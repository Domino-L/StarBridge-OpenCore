namespace StarBridge.HostRuntime.Tools;

public sealed record ExecHangarGameOverlayState(int SchemaVersion, bool Pinned, string Position);
public sealed record ExecHangarGameOverlayFrame(DateTimeOffset Now, DateTimeOffset Boundary,
    bool Open, int Green, int Red, string Position)
{
    public bool Leaving => Open && Green == 0 && Red == 0;
}
public interface IExecHangarGameOverlaySink : IDisposable
{
    bool Available { get; }
    void Present(ExecHangarGameOverlayFrame frame, Func<bool> isCurrent);
    void Clear();
}

/// <summary>Session-only display grant. The existing hangar runtime owns calibration and reminders.</summary>
public sealed class ExecHangarGameOverlay : IDisposable
{
    public static readonly IReadOnlyList<string> Positions = ["topLeft", "topCenter", "topRight", "bottomRight", "bottomCenter", "bottomLeft"];
    private readonly object _gate = new();
    private readonly Func<CancellationToken, Task<ExecHangarSnapshot>> _read;
    private readonly IExecHangarGameOverlaySink _sink;
    private readonly Func<long> _generation;
    private bool _pinned, _disposed;
    private string _position = "topLeft";
    private long _owner, _epoch;
    public ExecHangarGameOverlay(Func<CancellationToken, Task<ExecHangarSnapshot>> read,
        IExecHangarGameOverlaySink sink, Func<long> generation)
    { _read = read; _sink = sink; _generation = generation; }

    public ExecHangarGameOverlayState Read()
    {
        lock (_gate) { RetireChangedOwner(); return new(1, _pinned, _position); }
    }
    public ExecHangarGameOverlayState Change(string? position, Func<bool> canCommit)
    {
        if (position is not null && !Positions.Contains(position)) throw new ArgumentException("Invalid overlay position.");
        lock (_gate)
        {
            RetireChangedOwner();
            if (_disposed || !canCommit()) throw new OperationCanceledException();
            if (position is not null && !_sink.Available) throw new InvalidOperationException("Overlay unavailable.");
            ++_epoch; _owner = _generation(); _pinned = position is not null;
            if (position is not null) _position = position;
            _sink.Clear();
            return new(1, _pinned, _position);
        }
    }
    private void RetireChangedOwner()
    {
        if (_pinned && _owner != _generation()) { _pinned = false; ++_epoch; _sink.Clear(); }
    }
    public async Task TickAsync(CancellationToken token = default)
    {
        long epoch, owner; string position;
        lock (_gate)
        {
            RetireChangedOwner(); if (_disposed || !_pinned) return;
            epoch = _epoch; owner = _owner; position = _position;
        }
        bool Current() { lock (_gate) return !_disposed && _pinned && _epoch == epoch && _owner == owner && _generation() == owner; }
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            var snapshot = await _read(timeout.Token);
            token.ThrowIfCancellationRequested();
            lock (_gate)
            {
                if (!Current()) return;
                var now = snapshot.Now;
                var phase = snapshot.Phases.FirstOrDefault(p => now >= p.Start && now < p.End);
                DateTimeOffset? boundary = phase is null ? null : phase.Open
                    ? snapshot.Windows.FirstOrDefault(w => now >= w.Open && now < w.Close)?.Close
                    : snapshot.Windows.FirstOrDefault(w => w.Open > now)?.Open;
                if (!snapshot.Reliable || snapshot.FetchedAt is not {} fetched || now < fetched ||
                    now - fetched > ExecHangarRuntime.MaxConfigAge || phase is null || boundary is null || boundary <= now ||
                    phase.GreenLights < 0 || phase.RedLights < 0 || phase.GreenLights + phase.RedLights > 5)
                { _sink.Clear(); return; }
                _sink.Present(new(now, boundary.Value, phase.Open, phase.GreenLights, phase.RedLights, position), Current);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch { lock (_gate) { if (Current()) _sink.Clear(); } }
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; _pinned = false; ++_epoch; _sink.Clear(); }
        _sink.Dispose();
    }
}

public sealed class ExecHangarGameOverlayDriver : IDisposable
{
    private readonly CancellationTokenSource _stop = new();
    private readonly Task _work;
    public ExecHangarGameOverlayDriver(ExecHangarGameOverlay overlay) => _work = Run(overlay);
    private async Task Run(ExecHangarGameOverlay overlay)
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
            while (await timer.WaitForNextTickAsync(_stop.Token)) await overlay.TickAsync(_stop.Token);
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }
    public void Dispose() { _stop.Cancel(); _ = _work.ContinueWith(_ => _stop.Dispose(), TaskScheduler.Default); }
}
