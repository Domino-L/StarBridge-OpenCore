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
    private readonly Task? _changeDriver;
    private readonly Func<TimeSpan, CancellationToken, Task> _waitForWake;
    private readonly bool _prepareWhenIdle;
    private readonly Func<(bool Known, string? Room)> _presetRoomTrigger;
    private readonly Func<InformationOverlayModuleDemand?> _moduleDemand;
    private readonly Func<StarBridge.Core.Overlay.OverlaySourceLease?> _moduleRoomLease;
    private (BridgeAccountContext? Owner, long Generation) _scope;
    private InformationOverlayCommunityContent? _contentValue;
    internal event Action? ContentChanged;
    private InformationOverlayCommunityContent? _content
    {
        get => _contentValue;
        set
        {
            if (ReferenceEquals(_contentValue, value)) return;
            _contentValue = value;
            NotifyContentChanged();
        }
    }
    // Consumers schedule a coalesced refresh; no data is published by this event.
    private void NotifyContentChanged()
    {
        foreach (var handler in ContentChanged?.GetInvocationList() ?? [])
            try { ((Action)handler)(); } catch { }
    }
    private DateTimeOffset _validUntil;
    private DateTimeOffset _communicationValidUntil;
    private string? _explicitCode;
    private string? _automaticCode;
    private string? _pageCode;
    private long _revision;
    private long _communicationRevision;
    private bool _disposed;
    private bool _chatNeedsBaseline;
    private int _transientFailures;
    private long _authorityRejectionVersion;
    private DateTimeOffset? _lastDemand;
    private bool? _supportsPresenceChanges;
    private CancellationTokenSource? _changeReadCancellation;
    internal Task Completion => Task.WhenAll(_driver ?? Task.CompletedTask, _changeDriver ?? Task.CompletedTask);

    internal OverlayCommunitySource(
        Func<(BridgeAccountContext? Owner, long Generation)> owner,
        IOverlayCommunityReader reader, bool startDriver = true,
        Func<DateTimeOffset>? now = null, OverlaySceneChoiceStore? choiceStore = null,
        Func<InformationOverlayRoomContent?>? room = null,
        Func<TimeSpan, CancellationToken, Task>? waitForWake = null, bool prepareWhenIdle = false,
        Func<(bool Known, string? Room)>? presetRoomTrigger = null,
        Func<InformationOverlayModuleDemand?>? moduleDemand = null,
        Func<StarBridge.Core.Overlay.OverlaySourceLease?>? moduleRoomLease = null)
    {
        _owner = owner;
        _reader = reader;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _choiceStore = choiceStore;
        _prepareWhenIdle = prepareWhenIdle;
        _room = room ?? (() => null);
        _presetRoomTrigger = presetRoomTrigger ?? (() => (false, null));
        _moduleDemand = moduleDemand ?? (() => null);
        _moduleRoomLease = moduleRoomLease ?? (() => null);
        _waitForWake = waitForWake ?? (async (delay, token) =>
            { await _wake.WaitAsync(delay, token).ConfigureAwait(false); });
        if (startDriver)
        {
            _driver = DriveAsync();
            if (reader is IOverlayCommunityChangeReader changes) _changeDriver = FollowChangesAsync(changes);
        }
    }

    internal InformationOverlayCommunityContent? Read()
    {
        lock (_sync)
        {
            CheckScope();
            if (_content is null) AdoptWorkspace();
            if (_content is not null && _now() >= _validUntil)
            { TraceRead("expired", "roster-lease"); _content = null; }
            if (_content is not null && _now() >= _communicationValidUntil &&
                (_content.AnnouncementTitle.Length > 0 || _content.AnnouncementText.Length > 0 || _content.Messages.Count > 0))
            {
                _chatNeedsBaseline = true;
                _content = _content with { AnnouncementTitle = "", AnnouncementText = "", Messages = [] };
            }
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

    internal void SuspendDisplayDemand()
    {
        CancellationTokenSource? pending;
        lock (_sync)
        {
            CheckScope();
            _lastDemand = null;
            pending = KeepSourceReady() ? null : _changeReadCancellation;
            if (!KeepSourceReady()) _transientFailures = 0;
        }
        try { pending?.Cancel(); } catch (ObjectDisposedException) { }
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
            if (code is not null) _focusedModuleCommunity = code;
            _choice = _choice with { Mode = code is null ? "auto" : "community", Code = code };
            _content = null;
            _transientFailures = 0;
            InvalidateRead();
        }
    }

    internal async Task RefreshAsync(CancellationToken token = default, bool waitForGate = false, bool includeCommunication = true)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        if (waitForGate) await _readGate.WaitAsync(deadline.Token).ConfigureAwait(false);
        else if (!await _readGate.WaitAsync(0, deadline.Token).ConfigureAwait(false)) return;
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        var readStartedAt = _now();
        TraceRead("started", "none");
        (BridgeAccountContext? Owner, long Generation) scope = default;
        long revision = -1;
        long communicationRevision = -1;
        string? selected;
        string? automatic;
        try
        {
            lock (_sync)
            {
                CheckScope();
                if (_disposed || _scope.Owner is null) return;
                if (waitForGate && Read() is not null) return;
                scope = _scope; revision = _revision; communicationRevision = _communicationRevision;
                selected = _explicitCode; automatic = _pageCode ?? _automaticCode;
            }
            var targets = await CatalogAsync(scope, false, deadline.Token).ConfigureAwait(false);
            var target = selected is not null
                ? targets.SingleOrDefault(x => x.Code == selected)
                : targets.FirstOrDefault(x => x.Code == automatic) ??
                  targets.OrderBy(x => x.Code, StringComparer.Ordinal).FirstOrDefault();
            lock (_sync)
            {
                if (!CurrentCommunication(scope, communicationRevision)) return;
                // A successful membership read revokes the old content before
                // fetching a replacement. Explicit targets never fall through.
                if (target is null || _content?.Code != target.Code) _content = null;
                if (target is null) { RevokeWorkspace(selected ?? automatic); _automaticCode = null; _transientFailures = 0; return; }
            }
            DateTimeOffset? rosterAcceptedAt = null;
            void AcceptRoster(InformationOverlayCommunityContent roster)
            {
                deadline.Token.ThrowIfCancellationRequested();
                if (roster.Code != target.Code) throw new InvalidDataException("Mismatched overlay roster.");
                lock (_sync)
                {
                    if (!Current(scope, revision)) return;
                    var previous = Read();
                    var members = Array.AsReadOnly(roster.Members.ToArray());
                    rosterAcceptedAt = _now();
                    _latestRosterReadStartedAt = readStartedAt;
                    _validUntil = rosterAcceptedAt.Value.AddSeconds(40);
                    RenewModuleAuthority(roster.Code, _validUntil);
                    TraceRead("roster-accepted", "none", started);
                    _chatNeedsBaseline |= previous is null;
                    _content = previous is not null && previous.Code == roster.Code && previous.Name == roster.Name &&
                        previous.Members.SequenceEqual(members) ? previous : roster with
                        {
                            Members = members,
                            ContinuityId = previous?.ContinuityId ?? Guid.NewGuid(),
                            AnnouncementTitle = previous?.AnnouncementTitle ?? "",
                            AnnouncementText = previous?.AnnouncementText ?? "",
                            LatestChatSequence = previous?.LatestChatSequence ?? 0,
                            Messages = previous?.Messages ?? []
                        };
                }
            }
            if (!includeCommunication)
            {
                var roster = await _reader.ReadRosterAsync(scope.Owner!, target, deadline.Token).ConfigureAwait(false);
                AcceptRoster(roster);
                lock (_sync)
                    if (Current(scope, revision))
                    {
                        _transientFailures = 0;
                        if (selected is null) _automaticCode = target.Code;
                    }
                return;
            }
            var content = await _reader.ReadContentAsync(scope.Owner!, target, AcceptRoster, deadline.Token).ConfigureAwait(false);
            if (content.Code != target.Code) throw new InvalidDataException("Mismatched overlay source.");
            deadline.Token.ThrowIfCancellationRequested();
            lock (_sync)
            {
                if (!CurrentCommunication(scope, communicationRevision)) return;
                // A newer foreground roster does not invalidate an independently
                // authenticated chat read. Never overwrite that newer roster or
                // extend its permission lifetime with communication data.
                var newerRoster = !Current(scope, revision);
                if (newerRoster && (_content?.Code != content.Code || _now() >= _validUntil)) return;
                var previous = Read();
                var members = Array.AsReadOnly((newerRoster ? previous!.Members : content.Members).ToArray());
                if (newerRoster) content = content with { Name = previous!.Name };
                var resetSource = previous is null || content.LatestChatSequence < previous.LatestChatSequence;
                var resetChat = resetSource || _chatNeedsBaseline;
                var messages = resetChat ? Array.Empty<InformationOverlayRoomMessage>() :
                    previous!.Messages.Concat(content.Messages.Where(message => message.Sequence > previous.LatestChatSequence))
                        .GroupBy(message => message.Sequence).Select(group => group.First())
                        .OrderBy(message => message.Sequence).TakeLast(50).ToArray();
                // Communication cannot renew the earlier roster authorization.
                if (!newerRoster) _validUntil = (rosterAcceptedAt ?? _now()).AddSeconds(40);
                RenewModuleAuthority(content.Code, _validUntil);
                _communicationValidUntil = _now().AddSeconds(40);
                _content = !resetChat && previous is not null && previous.Code == content.Code &&
                    previous.Name == content.Name && previous.Members.SequenceEqual(members) &&
                    previous.AnnouncementTitle == content.AnnouncementTitle && previous.AnnouncementText == content.AnnouncementText &&
                    previous.LatestChatSequence == content.LatestChatSequence && previous.Messages.SequenceEqual(messages)
                    ? previous
                    : content with { Members = members,
                        Messages = Array.AsReadOnly(messages),
                        // A network gap rebases chat, not the still-authorized
                        // roster's identity. Native clears every module on a
                        // source identity change, not just chat history.
                        ContinuityId = resetSource ? Guid.NewGuid() : previous!.ContinuityId };
                _chatNeedsBaseline = false;
                _transientFailures = 0;
                if (selected is null) _automaticCode = target.Code;
                TraceRead("completed", "none", started);
            }
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested && !_stop.IsCancellationRequested)
        { TraceRead("transient", "timeout", started); RetainUntilOriginalExpiry(scope, revision); }
        catch (OperationCanceledException) { throw; }
        catch (Exception error) when (IsTransientReadFailure(error))
        { TraceRead("transient", error.GetType().Name, started); RetainUntilOriginalExpiry(scope, revision); }
        catch (Exception error)
        {
            // Permission/schema/unclassified failures fail closed. A failure
            // belonging to an old selection must not clear a newer snapshot.
            lock (_sync) { if (Current(scope, revision)) { _authorityRejectionVersion++; TraceRead("rejected", error.GetType().Name, started); RevokeWorkspace(); _content = null; _catalogAt = default; _transientFailures = 0; } }
        }
        finally { _readGate.Release(); SignalReadProgress(); }
    }

    private static bool IsTransientReadFailure(Exception error) => error switch
    {
        Account.AccountBridgeHostException host => host.Retryable,
        HttpRequestException http => http.StatusCode is null or System.Net.HttpStatusCode.RequestTimeout or
            System.Net.HttpStatusCode.TooManyRequests || (int)http.StatusCode.Value >= 500,
        TimeoutException => true,
        IOException => true,
        _ => false
    };

    private void RetainUntilOriginalExpiry((BridgeAccountContext? Owner, long Generation) scope, long revision)
    {
        lock (_sync)
        {
            if (!Current(scope, revision)) return;
            _chatNeedsBaseline = true;
            _transientFailures = Math.Min(4, _transientFailures + 1);
            Read(); // Enforce, never renew, the last successful authorization lease.
        }
    }

    private TimeSpan NextRefreshDelay()
    {
        lock (_sync)
        {
            if (_transientFailures > 0)
                return TimeSpan.FromSeconds(_transientFailures switch { 1 => 1, 2 => 3, 3 => 5, _ => 15 });
            var normal = TimeSpan.FromSeconds(HasDisplayDemand() && _supportsPresenceChanges == false ? 2 : 15);
            if (_content is null) return normal;
            // Reserve the 20-second read budget plus a small scheduling margin.
            // Communication may have consumed time after roster acceptance.
            var renewal = _validUntil - _now() - TimeSpan.FromSeconds(22);
            return TimeSpan.FromSeconds(Math.Clamp(renewal.TotalSeconds, 1, normal.TotalSeconds));
        }
    }

    private void TraceRead(string phase, string reason, long started = 0)
    {
        if (!OverlayCommunityDiagnostics.Log.IsEnabled()) return;
        lock (_sync)
            OverlayCommunityDiagnostics.Log.Read(phase, reason,
                started == 0 ? 0 : (long)System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds,
                _content is null ? 0 : (long)(_validUntil - _now()).TotalMilliseconds);
    }

    private bool Current((BridgeAccountContext? Owner, long Generation) scope, long revision)
    {
        CheckScope();
        return !_disposed && _scope == scope && _revision == revision;
    }

    private void InvalidateRead(bool rosterOnly = false)
    {
        _revision++;
        if (!rosterOnly) _communicationRevision++;
    }

    private bool CurrentCommunication((BridgeAccountContext? Owner, long Generation) scope, long revision)
    {
        CheckScope();
        return !_disposed && _scope == scope && _communicationRevision == revision;
    }

    private void CheckScope()
    {
        var current = _owner();
        if (_scope == current && (!_choiceFailed || _now() < _choiceRetryAt)) return;
        _scope = current;
        RevokeWorkspace();
        _latestRosterReadStartedAt = default;
        _rejectedWorkspaceSequence = 0;
        _workspaceRejectedAt = default;
        _workspaceSourceRejectedAt.Clear();
        _content = null;
        _transientFailures = 0;
        _supportsPresenceChanges = null;
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
        _focusedModuleCommunity = _choice.Code;
        if (KeepSourceReady() && _wake.CurrentCount == 0) _wake.Release();
        InvalidateRead();
    }

    private async Task DriveAsync()
    {
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                lock (_sync) CheckScope();
                await _waitForWake(NextRefreshDelay(), _stop.Token).ConfigureAwait(false);
                bool includeCommunication;
                lock (_sync)
                {
                    CheckScope();
                    includeCommunication = HasDisplayDemand();
                    // Keep only the selected organization ready while closed.
                    // Room scenes and signed-out accounts do not warm unrelated
                    // rosters. Idle reads never fetch chat or announcements.
                    if (!HasSourceDemand())
                    { _transientFailures = 0; continue; }
                }
                (BridgeAccountContext? Owner, long Generation) scope;
                long revision;
                lock (_sync) { CheckScope(); scope = _scope; revision = _revision; }
                bool HasDemand()
                {
                    lock (_sync) return Current(scope, revision) && HasSourceDemand();
                }
                try
                {
                    await OverlayDemandRead.RunAsync(async token =>
                    { await RefreshAsync(token, includeCommunication: includeCommunication).ConfigureAwait(false); return true; }, HasDemand, _stop.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { throw; }
                catch (OperationCanceledException) when (!HasDemand())
                {
                    lock (_sync)
                        if (_lastDemand is not null && _now() - _lastDemand <= TimeSpan.FromSeconds(20) && _wake.CurrentCount == 0)
                            _wake.Release();
                }
                catch (Exception) when (!_stop.IsCancellationRequested)
                { lock (_sync) { if (Current(scope, revision)) _content = null; } }
            }
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }

    private sealed record ChangeDemand((BridgeAccountContext? Owner, long Generation) Scope, object Identity, bool Modules);

    private ChangeDemand? CaptureChangeDemand()
    {
        try
        {
            // The runtime callback resolves shared scope/budget. Call outside
            // the source lock so resource and runtime lock ordering stays local.
            if (UsesModuleSources())
            {
                var scope = _owner();
                var identity = _moduleChangeDemand?.Invoke();
                return !_disposed && scope.Owner is not null && identity is not null && _owner() == scope
                    ? new(scope, identity, true) : null;
            }
            lock (_sync)
            {
                CheckScope();
                return !_disposed && _scope.Owner is not null && HasSourceDemand() ? new(_scope, _revision, false) : null;
            }
        }
        catch { return null; }
    }

    private async Task FollowChangesAsync(IOverlayCommunityChangeReader reader)
    {
        var after = new OverlayActivityCursor();
        ChangeDemand? previous = null;
        var failures = 0;
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                var demand = CaptureChangeDemand();
                if (demand is null)
                {
                    after = new(); failures = 0; previous = null;
                    await Task.Delay(250, _stop.Token).ConfigureAwait(false);
                    continue;
                }
                var scope = demand.Scope;
                if (previous != demand)
                {
                    after = new();
                    if (demand.Modules) InvalidateModuleSources(scope);
                    else lock (_sync) if (_wake.CurrentCount == 0) _wake.Release();
                }
                previous = demand;
                bool HasDemand() => CaptureChangeDemand() == demand;
                try
                {
                    using var pending = CancellationTokenSource.CreateLinkedTokenSource(_stop.Token);
                    if (!HasDemand()) continue;
                    lock (_sync)
                    {
                        _changeReadCancellation = pending;
                    }
                    var next = await OverlayDemandRead.RunAsync(token =>
                        reader.WaitForChangesAsync(scope.Owner!, scope.Generation, after, token), HasDemand, pending.Token).ConfigureAwait(false);
                    if (!HasDemand()) { after = new(); continue; }
                    var changed = next.Instance != after.Instance || next.Version != after.Version || !next.PresenceEvents;
                    if (demand.Modules)
                    { if (changed) InvalidateModuleSources(scope); }
                    else lock (_sync)
                    {
                        if (!Current(scope, (long)demand.Identity)) { after = new(); continue; }
                        _supportsPresenceChanges = next.PresenceEvents;
                        if (HasSourceDemand() && changed && _wake.CurrentCount == 0)
                            _wake.Release();
                    }
                    after = next; failures = 0;
                    // Old servers may return without holding a wait. Avoid a hot
                    // loop and retain the bounded foreground polling fallback.
                    await Task.Delay(next.PresenceEvents ? 250 : 2000, _stop.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { throw; }
                catch (OperationCanceledException) when (!HasDemand())
                {
                    // Display/account changes are not a transport failure and
                    // must not delay the new scope behind retry backoff.
                    after = new(); failures = 0;
                }
                catch
                {
                    // A notification failure supplies no new authority. Existing
                    // display reads retain their original revocation/lease rules.
                    if (!demand.Modules) lock (_sync)
                        if (Current(scope, (long)demand.Identity) && _supportsPresenceChanges is null) _supportsPresenceChanges = false;
                    failures = Math.Min(4, failures + 1);
                    await Task.Delay(TimeSpan.FromSeconds(failures switch { 1 => 1, 2 => 3, 3 => 5, _ => 15 }), _stop.Token).ConfigureAwait(false);
                    after = new();
                }
                finally { lock (_sync) _changeReadCancellation = null; }
            }
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            _disposed = true; _content = null; InvalidateRead();
            foreach (var code in _moduleSessions.Keys.ToArray()) RemoveModuleSession(code);
        }
        _stop.Cancel();
        // Cancellation may still be observed by an in-flight read. Do not
        // dispose the semaphore/token source underneath its finally block.
    }

    // Called under _sync. Visibility demand and source readiness are different:
    // closing the HWND must not leave an otherwise healthy account cold again.
    private bool HasDisplayDemand() => !UsesModuleSources() && _lastDemand is not null && _now() - _lastDemand <= TimeSpan.FromSeconds(20);
    private bool KeepSourceReady() => !UsesModuleSources() && _prepareWhenIdle && !_disposed && !_choiceFailed && _scope.Owner is not null &&
        (_choice.Mode == "community" || _choice.Mode == "auto" && _room() is null);
    private bool HasSourceDemand() => HasDisplayDemand() || KeepSourceReady();
}
