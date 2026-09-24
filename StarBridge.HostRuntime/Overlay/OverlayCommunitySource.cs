using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>
/// Owns one bounded, independently refreshed display source. No publication or
/// authorization writes. A late response cannot revive a previous account,
/// selected organization, or revoked snapshot.
/// </summary>
internal sealed partial class OverlayCommunitySource : IDisposable
{
    private readonly Func<(BridgeAccountContext? Owner, long Generation)> _owner;
    private readonly IOverlayCommunityReader _reader;
    private readonly Func<DateTimeOffset> _now;
    private readonly object _sync = new();
    private readonly SemaphoreSlim _readGate = new(1, 1);
    private readonly CancellationTokenSource _stop = new();
    private readonly SemaphoreSlim _wake = new(0, 1);
    private readonly Task? _driver;
    private (BridgeAccountContext? Owner, long Generation) _scope;
    private InformationOverlayCommunityContent? _content;
    private DateTimeOffset _validUntil;
    private string? _explicitCode;
    private string? _automaticCode;
    private string? _pageCode;
    private long _revision;
    private bool _disposed;
    private DateTimeOffset? _lastDemand;
    internal Task Completion => _driver ?? Task.CompletedTask;

    internal OverlayCommunitySource(
        Func<(BridgeAccountContext? Owner, long Generation)> owner,
        IOverlayCommunityReader reader, bool startDriver = true,
        Func<DateTimeOffset>? now = null, OverlaySceneChoiceStore? choiceStore = null,
        Func<InformationOverlayRoomContent?>? room = null)
    {
        _owner = owner;
        _reader = reader;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _choiceStore = choiceStore;
        _room = room ?? (() => null);
        if (startDriver) _driver = DriveAsync();
    }

    internal InformationOverlayCommunityContent? Read()
    {
        lock (_sync)
        {
            CheckScope();
            if (_content is not null && _now() >= _validUntil) _content = null;
            return _disposed ? null : _content;
        }
    }

    internal InformationOverlayCommunityContent? ReadForDisplay()
    {
        lock (_sync)
        {
            if (_disposed) return null;
            var now = _now();
            var wake = _lastDemand is null || now - _lastDemand > TimeSpan.FromSeconds(20);
            _lastDemand = now;
            if (wake && _wake.CurrentCount == 0) _wake.Release();
            return Read();
        }
    }

    // Internal regression seam. Product changes use the revisioned account bridge;
    // selection must never be put in exported appearance/layout presets.
    internal void Select(string? code)
    {
        if (code is not null && (string.IsNullOrWhiteSpace(code) || code.Length > 256 || code.Any(char.IsControl)))
            throw new ArgumentException("Invalid organization target.", nameof(code));
        lock (_sync)
        {
            CheckScope();
            if (_explicitCode == code) return;
            _explicitCode = code;
            _choice = _choice with { Mode = code is null ? "auto" : "community", Code = code };
            _content = null;
            _revision++;
        }
    }

    internal async Task RefreshAsync(CancellationToken token = default)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        if (!await _readGate.WaitAsync(0, deadline.Token).ConfigureAwait(false)) return;
        (BridgeAccountContext? Owner, long Generation) scope = default;
        long revision = -1;
        string? selected;
        string? automatic;
        try
        {
            lock (_sync)
            {
                CheckScope();
                if (_disposed || _scope.Owner is null) return;
                scope = _scope; revision = _revision;
                selected = _explicitCode; automatic = _pageCode ?? _automaticCode;
            }
            var targets = await CatalogAsync(scope, false, deadline.Token).ConfigureAwait(false);
            var target = selected is not null
                ? targets.SingleOrDefault(x => x.Code == selected)
                : targets.FirstOrDefault(x => x.Code == automatic) ??
                  targets.OrderBy(x => x.Code, StringComparer.Ordinal).FirstOrDefault();
            lock (_sync)
            {
                if (!Current(scope, revision)) return;
                // A successful membership read revokes the old content before
                // fetching a replacement. Explicit targets never fall through.
                if (target is null || _content?.Code != target.Code) _content = null;
                if (target is null) { _automaticCode = null; return; }
            }
            var content = await _reader.ReadContentAsync(scope.Owner!, target, deadline.Token).ConfigureAwait(false);
            if (content.Code != target.Code) throw new InvalidDataException("Mismatched overlay source.");
            deadline.Token.ThrowIfCancellationRequested();
            lock (_sync)
            {
                if (!Current(scope, revision)) return;
                var previous = Read();
                var members = Array.AsReadOnly(content.Members.ToArray());
                _content = previous is not null && previous.Code == content.Code &&
                    previous.Name == content.Name && previous.Members.SequenceEqual(members)
                    ? previous
                    : content with { Members = members,
                        ContinuityId = previous?.ContinuityId ?? Guid.NewGuid() };
                _validUntil = _now().AddSeconds(40);
                if (selected is null) _automaticCode = target.Code;
            }
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { Read(); }
        catch (Account.AccountBridgeHostException error) when (error.Retryable) { Read(); }
        catch (Exception error) when (error is Account.AccountBridgeHostException or InvalidDataException)
        {
            // Permission/schema failures must not keep showing the old roster.
            lock (_sync) { if (Current(scope, revision)) { _content = null; _catalogAt = default; } }
        }
        finally { _readGate.Release(); }
    }

    private bool Current((BridgeAccountContext? Owner, long Generation) scope, long revision)
    {
        CheckScope();
        return !_disposed && _scope == scope && _revision == revision;
    }

    private void CheckScope()
    {
        var current = _owner();
        if (_scope == current && (!_choiceFailed || _now() < _choiceRetryAt)) return;
        _scope = current;
        _content = null;
        _explicitCode = null;
        _automaticCode = null;
        _pageCode = null;
        _catalog = [];
        _catalogAt = default;
        _choiceFailed = false;
        try { _choice = current.Owner is null ? new() : _choiceStore?.Read(current.Owner) ?? new(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        { _choice = new(0, "unavailable"); _choiceFailed = true; _choiceRetryAt = _now().AddSeconds(10); }
        _explicitCode = _choice.Code;
        _revision++;
    }

    private async Task DriveAsync()
    {
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                await _wake.WaitAsync(TimeSpan.FromSeconds(15), _stop.Token).ConfigureAwait(false);
                lock (_sync)
                {
                    // Closed overlays and room/fleet scenes do not continuously
                    // download unrelated organization rosters in the background.
                    if (_lastDemand is null || _now() - _lastDemand > TimeSpan.FromSeconds(20)) continue;
                }
                try { await RefreshAsync(_stop.Token).ConfigureAwait(false); }
                catch (Exception) when (!_stop.IsCancellationRequested)
                { lock (_sync) { _content = null; } }
            }
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }

    public void Dispose()
    {
        lock (_sync) { _disposed = true; _content = null; _revision++; }
        _stop.Cancel();
        // Cancellation may still be observed by an in-flight read. Do not
        // dispose the semaphore/token source underneath its finally block.
    }
}
