namespace StarBridge.HostRuntime.Notifications;

using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;

public sealed partial class NotificationAudioBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        ["notificationAudio.read", "notificationAudio.save", "notificationAudio.preview", "notificationAudio.stop"];
    private readonly NotificationAudioSettingsStore _store;
    private readonly NotificationPolicyStore _policies;
    private readonly NotificationAudioCatalog? _catalog;
    private readonly INotificationAudioOutput _output;
    private readonly Func<long> _generation;
    private readonly object _gate = new();
    private bool _disposed;
    private readonly RoomAudioObserver _rooms;
    private readonly DirectMessageNotificationObserver _direct;
    private readonly FriendRequestNotificationObserver _friends = new();
    private readonly TimeProvider _time;
    private readonly Func<bool> _canNotify;
    private readonly Func<bool> _canPlaySocial;
    private readonly Func<bool> _menuVisible;
    private readonly Settings.MenuPreferencesStore _menuPreferences;
    private long? _lastPlayback;
    private bool _achievementSound;
    private bool AchievementPlaying => _celebration.IsActive;
    private readonly NotificationDeliveryJournal _delivery;
    private void Record(NotificationDeliveryStage stage) => _delivery.Record(NotificationDeliveryChannel.Audio, stage);
    internal NotificationAudioBridgeDispatcher(string dataRoot, NotificationAudioCatalog? catalog,
        INotificationAudioOutput output, Func<long> generation, Func<bool>? canNotify = null, TimeProvider? time = null, Func<bool>? canPlaySocial = null, Func<bool>? menuVisible = null,
        Achievements.AchievementCelebrationActivity? celebration = null)
    { _delivery = new(dataRoot); _store = new(dataRoot); _policies = new(dataRoot); _catalog = catalog; _output = output; _generation = generation; _canNotify = canNotify ?? (() => false);
        _canPlaySocial = canPlaySocial ?? _canNotify;
        _menuVisible = menuVisible ?? (() => false); _menuPreferences = new(dataRoot);
        _time = time ?? TimeProvider.System; _rooms = new(_time); _direct = new(_time);
        _celebration = celebration ?? Achievements.AchievementCelebrationActivity.Shared;
        _audioDrain = _time.CreateTimer(_ => DrainDeferred(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        _celebration.Changed += CelebrationChanged; }

    public static NotificationAudioBridgeDispatcher CreateDefault(string dataRoot, string assetRoot, Func<long> generation, Func<bool>? canNotify = null, Func<bool>? canPlaySocial = null, Func<bool>? menuVisible = null)
    {
        NotificationAudioCatalog? catalog = null;
        try { catalog = NotificationAudioCatalog.Load(assetRoot); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException) { }
        return new(dataRoot, catalog, new WindowsWaveAudioOutput(), generation, canNotify, canPlaySocial: canPlaySocial, menuVisible: menuVisible);
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        lock (_gate) {
            try {
                ObjectDisposedException.ThrowIf(_disposed, this);
                cancellationToken.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != _generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
                if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext != null || !AdvertisedCapabilities.Contains(request.Name))
                    return ReplyError(request, "invalid_request");
                var root = request.Payload;
                var fields = request.Name switch {
                    "notificationAudio.save" => new[] { "schemaVersion", "expectedRevision", "enabled", "volume" },
                    "notificationAudio.preview" => new[] { "schemaVersion", "cueId" },
                    _ => new[] { "schemaVersion" }
                };
                var names = root.EnumerateObject().Select(p => p.Name).ToArray();
                if (request.Name == "notificationAudio.save" && names.Contains("doNotDisturb")) fields = [.. fields, "doNotDisturb"];
                if (names.Length != fields.Length || names.Distinct().Count() != fields.Length || names.Except(fields).Any() || root.GetProperty("schemaVersion").GetInt32() != 1)
                    return ReplyError(request, "invalid_request");
                if (request.Name == "notificationAudio.stop") {
                    if (AchievementPlaying) return Reply(request, new { schemaVersion = 1, status = "deferred", played = false });
                    _output.Stop(); return Reply(request, new { schemaVersion = 1, status = "stopped", played = false });
                }
                if (request.Name == "notificationAudio.save") {
                    var value = _store.Save(root.GetProperty("expectedRevision").GetInt32(), root.GetProperty("enabled").GetBoolean(), root.GetProperty("volume").GetDouble(),
                        root.TryGetProperty("doNotDisturb", out var dnd) ? dnd.GetBoolean() : null);
                    if (!AchievementPlaying) _output.Stop(); // An ordinary preference action cannot cut the celebration.
                    return Reply(request, View(value));
                }
                var current = _store.Read();
                if (request.Name == "notificationAudio.read") return Reply(request, View(current));
                var cue = root.GetProperty("cueId").GetString();
                if (cue == null || !NotificationAudioCueIds.All.Contains(cue)) return ReplyError(request, "invalid_cue");
                if (!current.Enabled || current.Volume == 0) return Reply(request, new { schemaVersion = 1, status = "muted", played = false, cueId = cue });
                if (Defer(() => { _ = DispatchAsync(request, cancellationToken); return true; }))
                    return Reply(request, new { schemaVersion = 1, status = "queued", played = false, cueId = cue });
                var asset = _catalog?.Resolve(cue);
                if (asset == null) return ReplyError(request, "cue_unavailable");
                var wave = ReadVerifiedWave(asset, current.Volume);
                cancellationToken.ThrowIfCancellationRequested();
                if (request.SessionGeneration != _generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
                var played = _output.TryPlay(wave);
                if (played) AudioAccepted(wave);
                if (played) _lastPlayback = _time.GetTimestamp();
                return played
                    ? Reply(request, new { schemaVersion = 1, status = "played", played = true, cueId = cue, selectedTier = asset.Tier.ToString().ToLowerInvariant() })
                    : ReplyError(request, "output_unavailable");
            } catch (OperationCanceledException) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), [])); }
            catch (BridgeProtocolException e) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request, new BridgeError(e.Code, "Audio request rejected.")), [])); }
            catch (AudioConflictException) { return ReplyError(request, "write_conflict"); }
            catch (NotificationAudioCatalogException) { StopOrdinaryPlayback(); return ReplyError(request, "integrity_failed"); }
            catch (Exception e) when (e is InvalidOperationException or ArgumentException or KeyNotFoundException or FormatException or OverflowException) { return ReplyError(request, "invalid_request"); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) {
                return ReplyError(request, request.Name == "notificationAudio.save" ? "write_failed" : "read_failed");
            }
        }
    }
    private object View(AudioSettings value)
    {
        var available = false;
        try { available = _catalog?.Resolve(NotificationAudioCueIds.Soft) != null; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or NotificationAudioCatalogException) { }
        return new { value.SchemaVersion, value.Revision, value.Enabled, value.Volume, value.DoNotDisturb, previewAvailable = available };
    }
    // Device-local scheduled notice; reuses the verified cue, output and one global playback gain.
    // Authenticated achievement composition only, not a caller-controlled bypass.
    // DND is deliberately independent; explicit mute/volume and desktop ownership remain in force.
    public bool TryPlayAchievement(Func<bool> current)
    {
        lock (_gate)
        {
            try
            {
                if (_disposed || !current() || _achievementSound) return false;
                var settings = _store.Read();
                if (!settings.Enabled || settings.Volume == 0) return false;
                var asset = _catalog?.Resolve(NotificationAudioCueIds.Achievement);
                if (asset is null) return false;
                var wave = ReadVerifiedWave(asset, settings.Volume);
                if (!current()) return false;
                var played = _output.TryPlay(wave);
                if (played) { _achievementSound = true; _lastPlayback = _time.GetTimestamp(); }
                return played;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException)
            { return false; }
        }
    }
    public void StopAchievement()
    {
        lock (_gate)
        {
            try { if (!_disposed && _achievementSound) _output.Stop(); }
            finally { _achievementSound = false; }
        }
    }
    public bool TryPlayExecHangar(Func<bool> current, Func<bool>? environmentAllows = null)
    {
        lock (_gate) {
            // Separate this explicit reminder from message observations. A card
            // being submitted does not establish whether its sound was played.
            var trace = Guid.NewGuid().ToString("N");
            void RecordHangar(NotificationDeliveryStage stage, string? result = null) =>
                _delivery.Record(NotificationDeliveryChannel.ExecHangarAudio, stage, trace,
                    _output.DiagnosticTransport, result,
                    stage is NotificationDeliveryStage.NativeAccepted or NotificationDeliveryStage.NativeRejected
                        ? _output.DefaultEndpointSnapshot : null);
            try {
                var allowed = environmentAllows ?? _canPlaySocial;
                if (_disposed || !current()) { RecordHangar(NotificationDeliveryStage.Stale); return false; }
                if (!allowed()) { RecordHangar(NotificationDeliveryStage.EnvironmentSuppressed); return false; }
                var settings = _store.Read();
                if (!settings.Enabled || settings.Volume == 0) { RecordHangar(NotificationDeliveryStage.ChannelDisabled); return false; }
                if (Defer(() => TryPlayExecHangar(current, environmentAllows))) return false;
                if (AutomaticThrottled(1)) {
                    RecordHangar(NotificationDeliveryStage.Throttled); return false;
                }
                var asset = _catalog?.Resolve(NotificationAudioCueIds.Operation);
                if (asset == null) { RecordHangar(NotificationDeliveryStage.CueUnavailable); return false; }
                var wave = ReadVerifiedWave(asset, settings.Volume);
                if (!current()) { RecordHangar(NotificationDeliveryStage.Stale); return false; }
                if (!allowed()) { RecordHangar(NotificationDeliveryStage.EnvironmentSuppressed); return false; }
                var played = _output.TryPlay(wave);
                if (played) AudioAccepted(wave);
                RecordHangar(played ? NotificationDeliveryStage.NativeAccepted : NotificationDeliveryStage.NativeRejected,
                    played ? "acceptedUnverified" : "rejected");
                if (played) _lastPlayback = _time.GetTimestamp();
                return played;
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException) {
                RecordHangar(NotificationDeliveryStage.Failed);
                return false;
            }
        }
    }
    // The authenticated, continuously observed organization feed is the only
    // producer. Sound has its own channel setting; desktop delivery may be off.
    internal bool TryPlayCommunity(CommunityNotificationNotice notice)
    {
        lock (_gate) {
            try {
                if (_disposed || !notice.IsCurrent() ||
                    notice.Kind is not (NotificationEventKind.OrganizationManagement or NotificationEventKind.OrganizationChat) ||
                    string.IsNullOrWhiteSpace(notice.Source.PolicyKey) ||
                    (notice.Kind == NotificationEventKind.OrganizationManagement ? !notice.Source.ManagementAvailable : !notice.Source.ChatAvailable)) return false;
                var official = notice.Source.SourceKind == OrganizationNotificationSourceKind.OfficialFleet;
                if (!Enum.IsDefined(notice.Source.SourceKind) || official != NotificationPolicyStore.IsOfficialFleetKey(notice.Source.PolicyKey) ||
                    official && (notice.Source.ManagementAvailable || notice.Source.Tasks.Length != 0 || notice.Source.JoinedAt != null)) return false;
                if (!NotificationSourcePolicy.Allows(_policies.Read(notice.Owner).For(notice.Source.PolicyKey), notice.Kind)) return false;
                var settings = _store.Read();
                if (!settings.Enabled || settings.Volume == 0 || !_canPlaySocial() ||
                    _menuVisible() && !MenuSoundEnabled()) return false;
                if (Defer(() => TryPlayCommunity(notice), notice.Owner, notice.Source.PolicyKey)) return false;
                if (AutomaticThrottled(1)) return false;
                var asset = _catalog?.Resolve(NotificationAudioCueIds.Soft);
                if (asset == null) return false;
                var wave = ReadVerifiedWave(asset, settings.Volume);
                if (!notice.IsCurrent()) return false;
                var played = _output.TryPlay(wave);
                if (played) AudioAccepted(wave);
                if (played) _lastPlayback = _time.GetTimestamp();
                return played;
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException) {
                return false;
            }
        }
    }
    // Rally admission belongs to the settings observer, independently of source policies.
    internal bool TryPlayRally(Func<bool> current) =>
        PlayAdmitted(current, () => TryPlayRally(current), NotificationAudioCueIds.Rally, NotificationAudioCueIds.Action);
    // Order events have their own cue. Trade chat sounds like any other private message,
    // so a conversation does not stamp on every line.
    internal bool TryPlayTrade(bool chat, Func<bool> current) =>
        PlayAdmitted(current, () => TryPlayTrade(chat, current),
            chat ? NotificationAudioCueIds.Soft : NotificationAudioCueIds.Trade, NotificationAudioCueIds.Soft);
    private bool PlayAdmitted(Func<bool> current, Func<bool> retry, string cue, string fallback)
    {
        lock (_gate)
        {
            var trace = Guid.NewGuid().ToString("N");
            void RecordPlayback(NotificationDeliveryStage stage, string? result = null) =>
                _delivery.Record(NotificationDeliveryChannel.Audio, stage, trace, _output.DiagnosticTransport, result,
                    stage is NotificationDeliveryStage.NativeAccepted or NotificationDeliveryStage.NativeRejected
                        ? _output.DefaultEndpointSnapshot : null);
            try
            {
                if (_disposed || !current()) { RecordPlayback(NotificationDeliveryStage.Stale); return false; }
                var settings = _store.Read();
                if (!settings.Enabled || settings.Volume <= 0 || _menuVisible() && !MenuSoundEnabled())
                { RecordPlayback(NotificationDeliveryStage.ChannelDisabled); return false; }
                if (!_canPlaySocial()) { RecordPlayback(NotificationDeliveryStage.EnvironmentSuppressed); return false; }
                if (Defer(retry)) return false;
                if (AutomaticThrottled(1))
                { RecordPlayback(NotificationDeliveryStage.Throttled); return false; }
                var asset = _catalog?.Resolve(cue) ?? _catalog?.Resolve(fallback);
                if (asset == null) { RecordPlayback(NotificationDeliveryStage.CueUnavailable); return false; }
                var wave = ReadVerifiedWave(asset, settings.Volume);
                if (!current()) { RecordPlayback(NotificationDeliveryStage.Stale); return false; }
                var played = _output.TryPlay(wave);
                if (played) AudioAccepted(wave);
                RecordPlayback(played ? NotificationDeliveryStage.NativeAccepted : NotificationDeliveryStage.NativeRejected,
                    played ? "acceptedUnverified" : "rejected");
                if (played) _lastPlayback = _time.GetTimestamp();
                return played;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException)
            { RecordPlayback(NotificationDeliveryStage.Failed); return false; }
        }
    }
    internal void ResetAutomaticSession()
    {
        lock (_gate) { _rooms.Reset(); _direct.Reset(); _friends.Reset(); _deferredAudio.Clear();
            _audioAcceptedAt = null; _deferredPlayback = false; _audioDrain.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            if (!_disposed && !AchievementPlaying) _output.Stop(); }
    }

    // Only CompositeBridgeDispatcher can supply completed authenticated reads.
    // No externally callable 'play this event' command and no new network polling.
    internal void ObserveRoomRead(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        string? trace = null;
        void Record(NotificationDeliveryStage stage, string? result = null) =>
            _delivery.Record(NotificationDeliveryChannel.Audio, stage, trace, _output.DiagnosticTransport, result,
                stage is NotificationDeliveryStage.NativeAccepted or NotificationDeliveryStage.NativeRejected ? _output.DefaultEndpointSnapshot : null);
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested) { _rooms.Reset(); _direct.Reset(); _friends.Reset(); return; }
            var direct = request.Name == "directMessages.read";
            var friend = request.Name == "notificationInbox.read";
            if (!(friend ? _friends.Observe(request, response, _generation()) > 0 : direct ? _direct.Observe(request, response, _generation()) : _rooms.Observe(request, response, _generation()))) {
                if (direct && !request.Payload.TryGetProperty("targetRef", out _)) Record(_direct.LastStage);
                return;
            }
            trace = NotificationDeliveryJournal.TraceFor(request);
            Record(NotificationDeliveryStage.FreshEvent);
            PlayObservedRoom(request, token, direct, friend, trace);
        }
    }
    private void PlayObservedRoom(BridgeEnvelope request, CancellationToken token, bool direct, bool friend, string? trace)
    {
        void Record(NotificationDeliveryStage stage, string? result = null) =>
            _delivery.Record(NotificationDeliveryChannel.Audio, stage, trace, _output.DiagnosticTransport, result,
                stage is NotificationDeliveryStage.NativeAccepted or NotificationDeliveryStage.NativeRejected ? _output.DefaultEndpointSnapshot : null);
        if (_disposed || token.IsCancellationRequested || request.SessionGeneration != _generation()) return;
        try {
            if (request.AccountContext is null) return;
            var mode = _policies.Read(request.AccountContext).For(friend ? "friends" : direct ? "directMessages" : "room");
            if (direct ? !NotificationSourcePolicy.Allows(mode, NotificationEventKind.DirectMessage) : mode == NotificationSourceMode.DoNotDisturb) { Record(NotificationDeliveryStage.SourceMuted); return; }
            var settings = _store.Read();
            // DoNotDisturb is retained only for v1 compatibility; Enabled is the sole sound switch.
            var social = direct || friend;
            if (!settings.Enabled || settings.Volume == 0) { Record(NotificationDeliveryStage.ChannelDisabled); return; }
            if (social && _menuVisible() && !MenuSoundEnabled()) { Record(NotificationDeliveryStage.ChannelDisabled); return; }
            if (!(social ? _canPlaySocial() : _canNotify())) { Record(NotificationDeliveryStage.EnvironmentSuppressed); return; }
            if (Defer(() => { PlayObservedRoom(request, token, direct, friend, trace); return true; }, request.AccountContext,
                friend ? "friends" : direct ? "directMessages" : "room")) return;
            if (AutomaticThrottled(social ? 1 : 10)) { Record(NotificationDeliveryStage.Throttled); return; }
            var asset = _catalog?.Resolve(NotificationAudioCueIds.Soft);
            if (asset is null) { Record(NotificationDeliveryStage.CueUnavailable); return; }
            var wave = ReadVerifiedWave(asset, settings.Volume);
            if (token.IsCancellationRequested || request.SessionGeneration != _generation()) { Record(NotificationDeliveryStage.Stale); return; }
            var played = _output.TryPlay(wave);
            if (played) AudioAccepted(wave);
            Record(played ? NotificationDeliveryStage.NativeAccepted : NotificationDeliveryStage.NativeRejected,
                played ? "acceptedUnverified" : "rejected");
            if (played) _lastPlayback = _time.GetTimestamp();
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException) {
            StopOrdinaryPlayback(); // Ordinary failures cannot retire the achievement owner's output.
            Record(NotificationDeliveryStage.Failed);
        }
    }
    private void StopOrdinaryPlayback()
    {
        if (!_achievementSound && !AchievementPlaying) _output.Stop();
    }
    private bool MenuSoundEnabled()
    {
        var settings = _menuPreferences.Read().Settings;
        return settings.TryGetProperty("social", out var social) &&
            (!social.TryGetProperty("notifications", out var notices) || notices.GetBoolean()) &&
            social.TryGetProperty("sound", out var sound) && sound.GetBoolean();
    }

    private static ValueTask<BridgeDispatchBatch> Reply(BridgeEnvelope r, object value) =>
        ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(r, value, preserveRequestAccountContext: false), []));
    private static ValueTask<BridgeDispatchBatch> ReplyError(BridgeEnvelope r, string code) =>
        ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(r, new BridgeError("notificationAudio." + code, "Audio action could not be completed.")), []));
    public void Dispose() { lock (_gate) { if (_disposed) return; _disposed = true;
        _celebration.Changed -= CelebrationChanged; _audioDrain.Dispose(); _deferredAudio.Clear(); _output.Dispose(); } }

    private static byte[] ReadVerifiedWave(NotificationAudioAsset asset, double volume)
    {
        var bytes = File.ReadAllBytes(asset.FilePath);
        if (bytes.Length > 8 * 1024 * 1024 || !Convert.ToHexString(SHA256.HashData(bytes)).Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new NotificationAudioCatalogException("Audio checksum mismatch.");
        try { return NotificationWaveGain.Apply(bytes, volume,
            asset.CueId == NotificationAudioCueIds.Achievement ? 160 : 0); }
        catch (InvalidDataException) { throw new NotificationAudioCatalogException("Invalid PCM audio."); }
    }
}
