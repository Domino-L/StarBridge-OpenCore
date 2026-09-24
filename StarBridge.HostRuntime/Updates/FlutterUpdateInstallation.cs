namespace StarBridge.HostRuntime.Updates;

public sealed record FlutterUpdatePrepared(string Ticket, string Version);
public sealed record FlutterUpdateProgress(string Phase, long ReceivedBytes, long? TotalBytes);

/// <summary>Host-owned installation ticket. Flutter never supplies a path or package.
/// Composition must supply a trusted helper handoff before advertising installation.</summary>
public sealed class FlutterUpdateInstallation
{
    private readonly Func<string, Action<FlutterUpdateProgress>?, CancellationToken, Task<string>> _stage;
    private readonly Func<string, CancellationToken, Task> _handoff;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private (string Ticket, string Version, string Path, Func<bool> Current)? _prepared;

    public FlutterUpdateInstallation(FlutterUpdateRuntime runtime, string ownedRoot,
        Func<string, CancellationToken, Task> trustedHandoff)
        : this((version, token) => runtime.StageAsync(ownedRoot, token, version), trustedHandoff) { }

    internal FlutterUpdateInstallation(Func<string, CancellationToken, Task<string>> stage,
        Func<string, CancellationToken, Task> handoff)
        : this((version, progress, token) => stage(version, token), handoff) { }

    internal FlutterUpdateInstallation(Func<string, Action<FlutterUpdateProgress>?, CancellationToken, Task<string>> stage,
        Func<string, CancellationToken, Task> handoff)
    { _stage = stage; _handoff = handoff; }

    public async Task<FlutterUpdatePrepared> PrepareAsync(string version, Func<bool> current,
        CancellationToken cancellation, Action<FlutterUpdateProgress>? progress = null)
    {
        if (!await _gate.WaitAsync(0, cancellation)) throw new InvalidOperationException("Update operation in progress.");
        try
        {
            _prepared = null;
            RequireCurrent(current, cancellation);
            var path = await _stage(version, progress, cancellation);
            RequireCurrent(current, cancellation);
            var ticket = Guid.NewGuid().ToString("N");
            _prepared = (ticket, version, path, current);
            return new(ticket, version);
        }
        finally { _gate.Release(); }
    }

    public async Task HandoffAsync(string ticket, Func<bool> current, CancellationToken cancellation)
    {
        if (!await _gate.WaitAsync(0, cancellation)) throw new InvalidOperationException("Update operation in progress.");
        try
        {
            RequireCurrent(current, cancellation);
            var prepared = _prepared;
            if (prepared is null || prepared.Value.Ticket != ticket) throw new InvalidOperationException("Unknown update ticket.");
            RequireCurrent(prepared.Value.Current, cancellation);
            // Never replay an uncertain handoff. A new explicit preparation is required.
            _prepared = null;
            await _handoff(prepared.Value.Path, cancellation);
            RequireCurrent(current, cancellation);
        }
        finally { _gate.Release(); }
    }

    private static void RequireCurrent(Func<bool> current, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!current()) throw new InvalidOperationException("Update session changed.");
    }
}
