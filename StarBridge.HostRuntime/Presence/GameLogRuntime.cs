using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogRuntime : IDisposable, IAsyncDisposable
{
    private readonly object _sync = new();
    private readonly GameLogSettingsStore _store;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _current;
    private readonly Func<string?> _verifiedHandle;
    private readonly Func<bool> _recordingAllowed;
    private readonly Func<GameProcessSession> _probe;
    private readonly TimeProvider _time;
    private readonly GameLogSessionTracker _session;
    private readonly Support.GameLogJournalBatch? _journal;
    private readonly GameLogIdentityReader _reader;
    private readonly GameLogIdentityReader _recentReader = new();
    private readonly GameLogLocator _locator;
    private readonly Lifecycle.AsyncWorkRetirement _accountWork = new();
    private readonly Lifecycle.AsyncWorkRetirement _samplingWork = new();
    private bool AccountSlotBlocked => _samplingWork.IsClosed || _accountWork.IsClosed || _localSlot?.BlocksAccountSlot == true;
    private Onboarding.LocalGameLogRuntime? _localSlot;
    private bool _usingLocalSlot;
    // Internal composition seam, not a Bridge command or mode acknowledgement.
    // There is still only this runtime's one timer and one selected live reader.
    internal void AttachLocalSlot(Onboarding.LocalGameLogRuntime slot)
    {
        ArgumentNullException.ThrowIfNull(slot);
        lock (_sync)
        {
            lock (_samplingStopGate)
            {
                if (_disposed || _samplingStop is not null || _samplingWork.IsClosed ||
                    _localSlot is not null && !ReferenceEquals(_localSlot, slot))
                    throw new InvalidOperationException("The game log sampling slot is already owned.");
                _localSlot = slot;
            }
        }
    }
    private GameLogLocation _location = new("notFound");
    private DateTimeOffset? _lastDiscovery;
    private string? _processKey, _searchHint;
    private readonly Lifecycle.DeferredWorkTimer _timer;
    private (BridgeAccountContext? Context, long Generation) _owner;
    private GameLogSettingsStore.Lease? _lease;
    private GameLogSettings? _settings;
    private GameLogIdentityObservation _observation = new("notSelected");
    private DateTimeOffset _observedAt;
    private bool _disposed;
    private bool _stopped;
    private string? _error;
    private sealed record Published((BridgeAccountContext? Context, long Generation) Owner, string Handle,
        string Channel, DateTimeOffset At);
    private sealed record PublishedIdentityCheck(
        (BridgeAccountContext? Context, long Generation) Owner,
        LocalIdentityCheckState State);
    private sealed record PublishedSession(
        (BridgeAccountContext? Context, long Generation) Owner,
        GameLogSessionSnapshot Snapshot,
        DateTimeOffset At);
    private Published? _published;
    private Published? _recentPublished;
    private PublishedIdentityCheck? _publishedIdentityCheck;
    private PublishedSession? _publishedSession;
    internal event Action? PublicationChanged;
    internal event Action<Achievements.CityArrivalEvidence>? CityArrival;
    private readonly List<(string Handle, string City, string Evidence)> _cityArrivals = [];
    private sealed record PublicationState(Published? Identity, PublishedSession? Session, PublishedIdentityCheck? Check);
    private PublicationState _lastPublication = new(null, null, null);
    private void NotifyPublicationChanged()
    {
        var state = new PublicationState(_published is { } identity ? identity with { At = default } : null,
            _publishedSession is { } session ? session with { At = default } : null, _publishedIdentityCheck);
        if (state == _lastPublication) return;
        _lastPublication = state;
        // Consumers only schedule work; sampling never awaits remote publication.
        foreach (var handler in PublicationChanged?.GetInvocationList() ?? [])
            try { ((Action)handler)(); } catch { /* A wake must not invalidate log evidence. */ }
    }

    public GameLogRuntime(GameLogSettingsStore store,
        Func<(BridgeAccountContext? Context, long Generation)> current, Func<string?> verifiedHandle,
        Func<GameProcessSession>? probe = null, TimeProvider? time = null, bool startTimer = true,
        GameLogLocator? locator = null, Support.LocalGameEventJournal? journal = null,
        Func<bool>? recordingAllowed = null)
    {
        _store = store; _current = current; _verifiedHandle = verifiedHandle;
        _recordingAllowed = recordingAllowed ?? (() => true);
        _probe = probe ?? GameLogIdentityReader.Probe; _time = time ?? TimeProvider.System;
        _locator = locator ?? new();
        _journal = journal is null ? null : new(journal);
        _session = new(_journal);
        _session.CityArrived += AddCityArrival;
        _reader = new(_session, _journal);
        _reader.SourceReset += _cityArrivals.Clear;
        _timer = new(_time, () => { Sample(); return Task.CompletedTask; },
            TimeSpan.FromMilliseconds(500), TimeSpan.FromMilliseconds(500));
        if (startTimer) _timer.Start();
    }
    private void AddCityArrival(string handle, string city, string evidence)
    {
        var expected = _verifiedHandle();
        _cityArrivals.RemoveAll(candidate => !candidate.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase));
        // Retain the first arrival for each of the four known cities while identity is still reading.
        // Repeated arrivals cannot grow the list or evict another city's valid evidence.
        if (expected is not null && handle.Equals(expected, StringComparison.OrdinalIgnoreCase) &&
            Core.Achievements.JourneyAchievementPolicy.IsCity(city) &&
            !_cityArrivals.Any(candidate => candidate.City == city))
            _cityArrivals.Add((handle, city, evidence));
    }
    internal bool StartDeferredSampling() => !_disposed && !_samplingWork.IsClosed && _timer.Start();
    public string? DetectedHandle
    {
        get
        {
            if (AccountSlotBlocked) return null;
            // Account policy reads must not wait behind disk IO.
            var published = Volatile.Read(ref _published);
            var now = _time.GetUtcNow();
            return published is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10) &&
                !AccountSlotBlocked ? published.Handle : null;
        }
    }
    // Identity-only observation is separate from live process/session evidence.
    public string? RecentDetectedHandle
    {
        get {
            if (AccountSlotBlocked) return null;
            var value = Volatile.Read(ref _recentPublished);
            var now = _time.GetUtcNow();
            return value is not null && value.Owner == _current() && now >= value.At &&
                now - value.At < TimeSpan.FromSeconds(10) && !AccountSlotBlocked ? value.Handle : null;
        }
    }
    public string? ConfirmedVersion
    {
        get
        {
            if (AccountSlotBlocked) return null;
            var published = Volatile.Read(ref _published);
            var now = _time.GetUtcNow();
            var expected = _verifiedHandle();
            return published is not null && expected is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10) &&
                published.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase) && !AccountSlotBlocked
                ? published.Channel : null;
        }
    }
    public LocalIdentityCheckState IdentityPolicyState
    {
        get
        {
            if (AccountSlotBlocked) return LocalIdentityCheckState.NotObserved;
            var published = Volatile.Read(ref _publishedIdentityCheck);
            return published is not null && _current() == published.Owner && !AccountSlotBlocked
                ? published.State
                : LocalIdentityCheckState.NotObserved;
        }
    }
    public GameLogSessionSnapshot CurrentSession
    {
        get
        {
            if (AccountSlotBlocked) return GameLogSessionSnapshot.Empty;
            var published = Volatile.Read(ref _publishedSession);
            var now = _time.GetUtcNow();
            return published is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10) && !AccountSlotBlocked
                ? published.Snapshot
                : GameLogSessionSnapshot.Empty;
        }
    }
    public void Suspend()
    {
        Volatile.Write(ref _recentPublished, null);
        Volatile.Write(ref _published, null);
        Volatile.Write(ref _publishedIdentityCheck, null);
        Volatile.Write(ref _publishedSession, null);
        lock (_sync)
        {
            _lease?.Dispose(); _lease = null; _settings = null; _owner = default;
            _observation = new("notSelected"); _error = null; _stopped = false;
            _reader.Reset(); _recentReader.Reset();
            _location = new("notFound"); _lastDiscovery = null; _processKey = null; _searchHint = null;
            NotifyPublicationChanged();
        }
    }
    internal Achievements.FirstEntryEvidence? CaptureFirstEntry()
    {
        if (AccountSlotBlocked) return null;
        var identity = Volatile.Read(ref _published);
        var session = Volatile.Read(ref _publishedSession);
        var owner = _current(); var now = _time.GetUtcNow(); var expected = _verifiedHandle();
        var matched = identity is not null && session is not null && identity.Owner == owner && session.Owner == owner &&
            identity.At == session.At && now >= identity.At && now - identity.At < TimeSpan.FromSeconds(10) &&
            expected is not null && identity.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase);
        if (!Core.Achievements.FirstEntryAchievementPolicy.CanUnlock(owner.Context is not null, matched,
                identity?.Channel, session?.Snapshot.Server.State) || _current() != owner || AccountSlotBlocked) return null;
        return new(owner.Context!, owner.Generation,
            new(1, Achievements.FirstEntryObservation.HashHandle(identity!.Handle), identity.Channel));
    }
    // Diagnostics borrows the existing owner/selection, never a second store lease.
    internal string? SelectedPathForDiagnostics
    {
        get
        {
            lock (_sync)
            {
                if (AccountSlotBlocked) return null;
                if (_current().Context is null) return null;
                if (_disposed || _owner != _current() || _settings is null)
                    throw new InvalidOperationException("Game log selection is unavailable.");
                _lease?.ValidateOwner();
                if (AccountSlotBlocked) return null;
                return _settings.Selection == "automatic" && _settings.Enabled && !_stopped
                    ? _location.Path : _settings.Path;
            }
        }
    }

    // Borrow this account's existing binding; do not discover another installation or test channel.
    internal string? BoundLivePathForHistory
    {
        get
        {
            lock (_sync)
            {
                if (_disposed || !Resolve()) return null;
                var path = _settings!.Selection == "automatic" ? _location.Path : _settings.Path;
                return _settings.Channel == "LIVE" && GameLogLocator.ChannelOf(path) == "LIVE"
                    ? path : null;
            }
        }
    }

    private bool Resolve()
    {
        if (AccountSlotBlocked) return false;
        var owner = _current();
        if (_owner != owner) { Suspend(); _owner = owner; }
        if (owner.Context is null) return false;
        try { _lease?.ValidateOwner(); }
        catch
        {
            _lease?.Dispose(); _lease = null; _settings = null;
            throw;
        }
        if (_settings is null)
        {
            _lease ??= _store.Open(owner.Context);
            _settings = _lease.Read();
            PublishIdentityCheck();
        }
        return true;
    }
    public void Sample()
    {
        using var sampling = _samplingWork.Enter(default);
        if (sampling is null) return;
        // Timer ticks never queue behind an ongoing scan or command.
        if (!Monitor.TryEnter(_sync)) return;
        Lifecycle.AsyncWorkRetirement.Lease? work = null;
        try
        {
            if (_disposed || !sampling.IsCurrent) return;
            if (_localSlot?.BlocksAccountSlot == true)
            {
                if (!_usingLocalSlot) Suspend();
                _usingLocalSlot = true;
                _localSlot.Sample();
                return;
            }
            if (_usingLocalSlot) { _localSlot?.Suspend(); _usingLocalSlot = false; }
            work = _accountWork.Enter(default);
            if (work is null) return;
            if (!Resolve()) return;
            Observe(work.Token);
        }
        catch
        {
            _cityArrivals.Clear();
            _journal?.Reset();
            _error = "storage";
            _observation = new("unknown");
            Volatile.Write(ref _recentPublished, null);
            Volatile.Write(ref _published, null);
            Volatile.Write(ref _publishedSession, null);
            NotifyPublicationChanged();
        }
        finally { Monitor.Exit(_sync); work?.Dispose(); }
    }
    private void Observe(CancellationToken token = default, bool rediscover = false)
    {
        var settings = _settings!;
        GameLogIdentityObservation? recent = null;
        if (!settings.Enabled || _stopped)
        {
            _reader.Reset(); _recentReader.Reset(); _observation = new("stopped");
        }
        else
        {
            var process = _probe();
            if (token.IsCancellationRequested || !AccountSlotCurrent()) { _cityArrivals.Clear(); return; }
            var now = _time.GetUtcNow();
            var key = process.State + "|" + process.LogPath + "|" + process.SessionId;
            if (settings.Selection == "automatic" &&
                (rediscover || _lastDiscovery is null || key != _processKey ||
                 now < _lastDiscovery || now - _lastDiscovery >= TimeSpan.FromSeconds(30)))
            {
                Volatile.Write(ref _published, null);
                _location = _locator.Find(settings.Channel, process, _searchHint ?? settings.Path);
                _lastDiscovery = now; _processKey = key;
                if (_location.Path is not null) _searchHint = _location.Path;
                if (_location.Path is { } found && settings.Path != found)
                    settings = _settings = _lease!.Save(settings, settings with { Path = found },
                        () => !token.IsCancellationRequested && AccountSlotCurrent());
            }
            var path = settings.Selection == "automatic" ? _location.Path : settings.Path;
            var otherVersion = process.State == "running" && GameLogLocator.ChannelOf(process.LogPath) is { } running &&
                running != settings.Channel;
            if (otherVersion || path is null)
            {
                _reader.Reset(); _recentReader.Reset();
                _observation = new(otherVersion ? "otherVersion" : _location.State);
            }
            else {
                _observation = _reader.ReadCurrent(path, process, now);
                if (process.State == "notRunning") recent = _recentReader.ReadRecent(path, now);
                else {
                    _recentReader.Reset();
                    recent = _observation;
                }
            }
        }
        _observedAt = _time.GetUtcNow();
        Volatile.Write(ref _recentPublished, _error is null && recent is { State: "identified", Handle: not null } &&
            AccountSlotCurrent() ? new(_owner, recent.Handle, settings.Channel, _observedAt) : null);
        var expected = _verifiedHandle();
        if (_error is null && _observation.State == "identified" && _observation.Handle is not null &&
            expected is not null)
        {
            var before = _settings!;
            var matches = _observation.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase);
            var desired = before with {
                IdentityCheck = matches ? "match" : "mismatch",
                IdentityHandleHash = IdentityHash(expected),
                VerifiedChannels = matches
                    ? GameLogLocator.AddOptionalChannel(before.VerifiedChannels, before.Channel)
                    : before.VerifiedChannels
            };
            if (desired != before)
                _settings = _lease!.Save(before, desired,
                    () => !token.IsCancellationRequested && AccountSlotCurrent());
        }
        PublishIdentityCheck();
        _journal?.Complete(() => !token.IsCancellationRequested && !_disposed && _recordingAllowed() &&
            AccountSlotCurrent() && _owner.Context is not null &&
            _settings?.Enabled == true && !_stopped && _error is null &&
            expected is not null && string.Equals(expected, _verifiedHandle(), StringComparison.OrdinalIgnoreCase) &&
            (_observation.State == "reading" ||
             (_observation.State == "identified" && _observation.Handle is not null &&
              _observation.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase))),
            incomplete: _observation.State == "reading");
        var session = _error is null && _observation.State == "identified" &&
            _observation.Handle is not null && expected is not null &&
            _observation.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase) &&
            AccountSlotCurrent()
            ? _reader.SessionSnapshot(_observedAt)
            : GameLogSessionSnapshot.Empty;
        Volatile.Write(ref _publishedSession,
            session == GameLogSessionSnapshot.Empty
                ? null
                : new PublishedSession(_owner, session, _observedAt));
        Volatile.Write(ref _published, _error is null && _observation.State == "identified" &&
            _observation.Handle is not null && AccountSlotCurrent()
            ? new(_owner, _observation.Handle, _settings!.Channel, _observedAt) : null);
        var identity = Volatile.Read(ref _published);
        if (identity is not null && _owner.Context is not null && identity.Owner == _owner &&
            identity.At == _observedAt && expected is not null &&
            identity.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase))
            foreach (var candidate in _cityArrivals)
                if (candidate.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase) &&
                    !token.IsCancellationRequested && AccountSlotCurrent())
                    CityArrival?.Invoke(new(_owner.Context, _owner.Generation,
                        new(1, Achievements.FirstEntryObservation.HashHandle(identity.Handle), candidate.City, candidate.Evidence)));
        // A bounded read may consume live events before it can verify the whole identity.
        // Only the same account/source may carry them forward; Reset/Suspend clear them.
        if (_observation.State != "reading" || _reader.IdentityInvalidated || _error is not null ||
            token.IsCancellationRequested || !AccountSlotCurrent() || expected is null)
            _cityArrivals.Clear();
        else
            _cityArrivals.RemoveAll(candidate => !candidate.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase));
        NotifyPublicationChanged();
    }
    private void PublishIdentityCheck()
    {
        if (AccountSlotBlocked) { Volatile.Write(ref _publishedIdentityCheck, null); return; }
        var expected = _verifiedHandle();
        var state = LocalIdentityCheckState.NotObserved;
        if (_settings is not null && expected is not null &&
            _settings.IdentityHandleHash == IdentityHash(expected))
        {
            state = _settings.IdentityCheck switch
            {
                "match" => LocalIdentityCheckState.Match,
                "mismatch" => LocalIdentityCheckState.Mismatch,
                _ => LocalIdentityCheckState.NotObserved
            };
        }
        Volatile.Write(ref _publishedIdentityCheck,
            _owner.Context is null || AccountSlotBlocked ? null : new(_owner, state));
    }
    private bool AccountSlotCurrent() => !AccountSlotBlocked && _current() == _owner && !AccountSlotBlocked;

    private static string IdentityHash(string handle) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(handle.Trim().ToLowerInvariant())));

    public BridgeDispatchBatch Dispatch(BridgeEnvelope request, CancellationToken token = default)
    {
        using var sampling = _samplingWork.Enter(default);
        if (sampling is null) return Error(request, "localMode");
        using var work = _accountWork.Enter(default);
        if (work is null) return Error(request, "localMode");
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(token, work.Token);
        token = lifetime.Token;
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (AccountSlotBlocked) return Error(request, "localMode");
                var owner = _current();
                if (_disposed || owner.Context is null || request.MessageType != BridgeMessageTypes.Request ||
                    request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                    return Error(request, "accountChanged");
                var body = request.Payload;
                var select = request.Name == "gameLog.select";
                var addVersion = request.Name == "gameLog.addVersion";
                var removeVersion = request.Name == "gameLog.removeVersion";
                var configure = request.Name == "gameLog.configure";
                if (body.GetRawText().Length > 4096 || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                    request.Name is not ("gameLog.read" or "gameLog.select" or "gameLog.addVersion" or
                        "gameLog.removeVersion" or "gameLog.find" or "gameLog.stop" or "gameLog.retry" or
                        "gameLog.configure" or "gameLog.resume") ||
                    body.EnumerateObject().Any(p => p.Name != "schemaVersion" &&
                        !((select || addVersion) && p.Name == "path") &&
                        !((configure || removeVersion) && p.Name == "channel")) ||
                    (configure || removeVersion) && (!body.TryGetProperty("channel", out var configuredChannel) ||
                        !GameLogLocator.ValidChannel(GameLogLocator.NormalizeChannel(configuredChannel.GetString()))))
                    return Error(request, "invalid");
                Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
                token.ThrowIfCancellationRequested();
                if (!Resolve()) return Error(request, "accountChanged");
                if (request.Name == "gameLog.stop") {
                    _stopped = true; _observation = new("stopped"); _reader.Reset();
                    _recentReader.Reset(); Volatile.Write(ref _recentPublished, null);
                    Volatile.Write(ref _published, null);
                    Volatile.Write(ref _publishedSession, null);
                }
                var next = _settings!;
                if (select || addVersion)
                {
                    var path = body.GetProperty("path").GetString();
                    if (path is null) return Error(request, "notFound");
                    try { path = GameLogIdentityReader.ValidatePath(path); }
                    catch { return Error(request, "path"); }
                    var channel = GameLogLocator.ChannelOf(path);
                    if (channel is null) return Error(request, "path");
                    next = next with {
                        Path = path, Enabled = true,
                        Selection = addVersion ? "automatic" : "manual",
                        Channel = channel,
                        Channels = GameLogLocator.AddChannel(next.Channels, channel),
                        VerifiedChannels = GameLogLocator.RemoveChannelIfPresent(next.VerifiedChannels, channel)
                    };
                }
                else if (configure)
                {
                    var channel = GameLogLocator.NormalizeChannel(body.GetProperty("channel").GetString());
                    if (!GameLogLocator.ContainsChannel(next.Channels, channel))
                        return Error(request, "notFound");
                    next = next with { Channel = channel, Path = null, Selection = "automatic",
                        Channels = next.Channels };
                }
                else if (removeVersion)
                {
                    var channel = GameLogLocator.NormalizeChannel(body.GetProperty("channel").GetString());
                    if (channel == "LIVE") return Error(request, "requiredVersion");
                    if (!GameLogLocator.ContainsChannel(next.Channels, channel)) return Error(request, "notFound");
                    var removingActive = next.Channel == channel;
                    next = next with {
                        Channel = removingActive ? "LIVE" : next.Channel,
                        Path = removingActive ? null : next.Path,
                        Selection = removingActive ? "automatic" : next.Selection,
                        Channels = GameLogLocator.RemoveChannel(next.Channels, channel),
                        VerifiedChannels = GameLogLocator.RemoveChannelIfPresent(next.VerifiedChannels, channel)
                    };
                }
                else if (request.Name == "gameLog.find") next = next with { Selection = "automatic", Enabled = true };
                else if (request.Name == "gameLog.resume") next = next with { Enabled = true };
                else if (request.Name == "gameLog.stop") next = next with { Enabled = false };
                else if (request.Name == "gameLog.retry") { _settings = _lease!.Read(); next = _settings; }
                bool Current() => !token.IsCancellationRequested && !AccountSlotBlocked && _current() == owner &&
                    !AccountSlotBlocked;
                if (next != _settings)
                {
                    var hint = _settings?.Path;
                    Volatile.Write(ref _recentPublished, null); _recentReader.Reset();
                    Volatile.Write(ref _published, null);
                    Volatile.Write(ref _publishedSession, null);
                    _settings = _lease!.Save(_settings!, next, Current);
                    _stopped = !_settings.Enabled;
                    _reader.Reset(); _lastDiscovery = null;
                    _searchHint = configure || removeVersion ? hint : next.Path;
                }
                if (!Current()) return Error(request, "accountChanged");
                if (request.Name is "gameLog.select" or "gameLog.addVersion" or "gameLog.find" or "gameLog.resume")
                    _stopped = false;
                _error = null;
                Observe(token, request.Name is "gameLog.find" or "gameLog.retry");
                if (!Current()) { _observation = new("unknown"); return Error(request, "accountChanged"); }
                var expected = _verifiedHandle();
                var handle = DetectedHandle;
                var match = handle is null || expected is null ? "unknown" :
                    handle.Equals(expected, StringComparison.OrdinalIgnoreCase) ? "match" : "mismatch";
                var localSession = match == "match" && _observation.State == "identified"
                    ? CurrentSession
                    : GameLogSessionSnapshot.Empty;
                if (!Current()) return Error(request, "accountChanged");
                return new(BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, state = _observation.State,
                    observedAtUtc = _observedAt,
                    path = _settings!.Selection == "automatic" && _settings.Enabled && !_stopped ? _location.Path : _settings.Path,
                    enabled = _settings.Enabled && !_stopped, handle, recentHandle = RecentDetectedHandle,
                    expectedHandle = expected, match,
                    channel = _settings.Channel, selection = _settings.Selection,
                    channels = GameLogLocator.Channels(_settings.Channels),
                    verifiedChannels = GameLogLocator.Channels(_settings.VerifiedChannels),
                    session = new {
                        schemaVersion = 1,
                        state = match == "match" && _observation.State == "identified" ? "ready" : "unavailable",
                        server = new {
                            state = localSession.Server.State,
                            region = localSession.Server.Region,
                            shard = localSession.Server.Shard
                        },
                        location = new {
                            state = localSession.Location.State,
                            englishName = localSession.Location.EnglishName,
                            names = new {
                                zhHans = localSession.Location.ChineseName,
                                zhHant = (string?)null
                            }
                        },
                        ship = new {
                            state = localSession.Ship.State,
                            key = localSession.Ship.Key,
                            englishName = localSession.Ship.EnglishName,
                            names = new {
                                zhHans = localSession.Ship.ChineseName,
                                zhHant = localSession.Ship.TraditionalChineseName
                            }
                        }
                    }
                }), []);
            }
            catch (OperationCanceledException) { _cityArrivals.Clear(); return Error(request, "cancelled"); }
            catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
            { return Error(request, "invalid"); }
            catch
            {
                _cityArrivals.Clear();
                _error = "storage";
                _observation = new("unknown");
                Volatile.Write(ref _recentPublished, null);
                Volatile.Write(ref _published, null);
                Volatile.Write(ref _publishedSession, null);
                return Error(request, "storage");
            }
        }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new BridgeError("gameLog." + code, "Game recognition is unavailable.")), []);
    // Retire only the account slot. The single existing timer remains available
    // for an explicitly active local slot after composition completes the handoff.
    internal async Task RetireAccountAsync()
    {
        var drained = _accountWork.Close();
        await drained.ConfigureAwait(false);
        Suspend();
    }
}
