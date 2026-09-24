using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed class GameLogRuntime : IDisposable
{
    private readonly object _sync = new();
    private readonly GameLogSettingsStore _store;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _current;
    private readonly Func<string?> _verifiedHandle;
    private readonly Func<GameProcessSession> _probe;
    private readonly TimeProvider _time;
    private readonly GameLogSessionTracker _session;
    private readonly Support.GameLogJournalBatch? _journal;
    private readonly GameLogIdentityReader _reader;
    private readonly GameLogLocator _locator;
    private GameLogLocation _location = new("notFound");
    private DateTimeOffset? _lastDiscovery;
    private string? _processKey, _searchHint;
    private readonly ITimer? _timer;
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
    private PublishedIdentityCheck? _publishedIdentityCheck;
    private PublishedSession? _publishedSession;

    public GameLogRuntime(GameLogSettingsStore store,
        Func<(BridgeAccountContext? Context, long Generation)> current, Func<string?> verifiedHandle,
        Func<GameProcessSession>? probe = null, TimeProvider? time = null, bool startTimer = true,
        GameLogLocator? locator = null, Support.LocalGameEventJournal? journal = null)
    {
        _store = store; _current = current; _verifiedHandle = verifiedHandle;
        _probe = probe ?? GameLogIdentityReader.Probe; _time = time ?? TimeProvider.System;
        _locator = locator ?? new();
        _journal = journal is null ? null : new(journal);
        _session = new(_journal);
        _reader = new(_session, _journal);
        if (startTimer) _timer = _time.CreateTimer(_ => Sample(), null, TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(3));
    }
    public string? DetectedHandle
    {
        get
        {
            // Account policy reads must not wait behind disk IO.
            var published = Volatile.Read(ref _published);
            var now = _time.GetUtcNow();
            return published is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10) ? published.Handle : null;
        }
    }
    public string? ConfirmedVersion
    {
        get
        {
            var published = Volatile.Read(ref _published);
            var now = _time.GetUtcNow();
            var expected = _verifiedHandle();
            return published is not null && expected is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10) &&
                published.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase)
                ? published.Channel : null;
        }
    }
    public LocalIdentityCheckState IdentityPolicyState
    {
        get
        {
            var published = Volatile.Read(ref _publishedIdentityCheck);
            return published is not null && _current() == published.Owner
                ? published.State
                : LocalIdentityCheckState.NotObserved;
        }
    }
    public GameLogSessionSnapshot CurrentSession
    {
        get
        {
            var published = Volatile.Read(ref _publishedSession);
            var now = _time.GetUtcNow();
            return published is not null && _current() == published.Owner &&
                now >= published.At && now - published.At < TimeSpan.FromSeconds(10)
                ? published.Snapshot
                : GameLogSessionSnapshot.Empty;
        }
    }
    public void Suspend()
    {
        Volatile.Write(ref _published, null);
        Volatile.Write(ref _publishedIdentityCheck, null);
        Volatile.Write(ref _publishedSession, null);
        lock (_sync)
        {
            _lease?.Dispose(); _lease = null; _settings = null; _owner = default;
            _observation = new("notSelected"); _error = null; _stopped = false;
            _reader.Reset();
            _location = new("notFound"); _lastDiscovery = null; _processKey = null; _searchHint = null;
        }
    }
    // Diagnostics borrows the existing owner/selection, never a second store lease.
    internal string? SelectedPathForDiagnostics
    {
        get
        {
            lock (_sync)
            {
                if (_current().Context is null) return null;
                if (_disposed || _owner != _current() || _settings is null)
                    throw new InvalidOperationException("Game log selection is unavailable.");
                return _settings.Selection == "automatic" && _settings.Enabled && !_stopped
                    ? _location.Path : _settings.Path;
            }
        }
    }

    private bool Resolve()
    {
        var owner = _current();
        if (_owner != owner) { Suspend(); _owner = owner; }
        if (owner.Context is null) return false;
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
        // Timer ticks never queue behind an ongoing scan or command.
        if (!Monitor.TryEnter(_sync)) return;
        try
        {
            if (_disposed || !Resolve()) return;
            Observe();
        }
        catch
        {
            _journal?.Reset();
            _error = "storage";
            _observation = new("unknown");
            Volatile.Write(ref _published, null);
            Volatile.Write(ref _publishedSession, null);
        }
        finally { Monitor.Exit(_sync); }
    }
    private void Observe(CancellationToken token = default, bool rediscover = false)
    {
        var settings = _settings!;
        if (!settings.Enabled || _stopped)
        {
            _reader.Reset(); _observation = new("stopped");
        }
        else
        {
            var process = _probe();
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
                        () => !token.IsCancellationRequested && _current() == _owner);
            }
            var path = settings.Selection == "automatic" ? _location.Path : settings.Path;
            var otherVersion = process.State == "running" && GameLogLocator.ChannelOf(process.LogPath) is { } running &&
                running != settings.Channel;
            if (otherVersion || path is null)
            {
                _reader.Reset();
                _observation = new(otherVersion ? "otherVersion" : _location.State);
            }
            else _observation = _reader.ReadCurrent(path, process, now);
        }
        _observedAt = _time.GetUtcNow();
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
                    () => !token.IsCancellationRequested && _current() == _owner);
        }
        PublishIdentityCheck();
        _journal?.Complete(() => !token.IsCancellationRequested && !_disposed &&
            _current() == _owner && _owner.Context is not null &&
            _settings?.Enabled == true && !_stopped && _error is null &&
            expected is not null && string.Equals(expected, _verifiedHandle(), StringComparison.OrdinalIgnoreCase) &&
            (_observation.State == "reading" ||
             (_observation.State == "identified" && _observation.Handle is not null &&
              _observation.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase))),
            incomplete: _observation.State == "reading");
        var session = _error is null && _observation.State == "identified" &&
            _observation.Handle is not null && expected is not null &&
            _observation.Handle.Equals(expected, StringComparison.OrdinalIgnoreCase) &&
            _current() == _owner
            ? _reader.SessionSnapshot(_observedAt)
            : GameLogSessionSnapshot.Empty;
        Volatile.Write(ref _publishedSession,
            session == GameLogSessionSnapshot.Empty
                ? null
                : new PublishedSession(_owner, session, _observedAt));
        Volatile.Write(ref _published, _error is null && _observation.State == "identified" &&
            _observation.Handle is not null && _current() == _owner
            ? new(_owner, _observation.Handle, _settings!.Channel, _observedAt) : null);
    }
    private void PublishIdentityCheck()
    {
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
            _owner.Context is null ? null : new(_owner, state));
    }

    private static string IdentityHash(string handle) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(handle.Trim().ToLowerInvariant())));

    public BridgeDispatchBatch Dispatch(BridgeEnvelope request, CancellationToken token = default)
    {
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
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
                bool Current() => !token.IsCancellationRequested && _current() == owner;
                if (next != _settings)
                {
                    var hint = _settings?.Path;
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
                    enabled = _settings.Enabled && !_stopped, handle, expectedHandle = expected, match,
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
            catch (OperationCanceledException) { return Error(request, "cancelled"); }
            catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
            { return Error(request, "invalid"); }
            catch
            {
                _error = "storage";
                _observation = new("unknown");
                Volatile.Write(ref _published, null);
                Volatile.Write(ref _publishedSession, null);
                return Error(request, "storage");
            }
        }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new BridgeError("gameLog." + code, "Game recognition is unavailable.")), []);
    public void Dispose() { lock (_sync) { _disposed = true; _timer?.Dispose(); Suspend(); } }
}
