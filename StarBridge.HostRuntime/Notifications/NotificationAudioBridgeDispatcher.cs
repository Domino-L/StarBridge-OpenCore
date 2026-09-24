namespace StarBridge.HostRuntime.Notifications;

using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;

public sealed class NotificationAudioBridgeDispatcher : IBridgeRequestDispatcher
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
    private readonly TimeProvider _time;
    private readonly Func<bool> _canNotify;
    private long? _lastPlayback;
    internal NotificationAudioBridgeDispatcher(string dataRoot, NotificationAudioCatalog? catalog,
        INotificationAudioOutput output, Func<long> generation, Func<bool>? canNotify = null, TimeProvider? time = null)
    { _store = new(dataRoot); _policies = new(dataRoot); _catalog = catalog; _output = output; _generation = generation; _canNotify = canNotify ?? (() => false);
        _time = time ?? TimeProvider.System; _rooms = new(_time); }

    public static NotificationAudioBridgeDispatcher CreateDefault(string dataRoot, string assetRoot, Func<long> generation, Func<bool>? canNotify = null)
    {
        NotificationAudioCatalog? catalog = null;
        try { catalog = NotificationAudioCatalog.Load(assetRoot); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException) { }
        return new(dataRoot, catalog, new WindowsWaveAudioOutput(), generation, canNotify);
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
                    _output.Stop(); return Reply(request, new { schemaVersion = 1, status = "stopped", played = false });
                }
                if (request.Name == "notificationAudio.save") {
                    var value = _store.Save(root.GetProperty("expectedRevision").GetInt32(), root.GetProperty("enabled").GetBoolean(), root.GetProperty("volume").GetDouble(),
                        root.TryGetProperty("doNotDisturb", out var dnd) ? dnd.GetBoolean() : null);
                    _output.Stop(); // Never leave an old-volume preview sounding after a preference change.
                    return Reply(request, View(value));
                }
                var current = _store.Read();
                if (request.Name == "notificationAudio.read") return Reply(request, View(current));
                var cue = root.GetProperty("cueId").GetString();
                if (cue == null || !NotificationAudioCueIds.All.Contains(cue)) return ReplyError(request, "invalid_cue");
                if (!current.Enabled || current.Volume == 0) return Reply(request, new { schemaVersion = 1, status = "muted", played = false, cueId = cue });
                var asset = _catalog?.Resolve(cue);
                if (asset == null) return ReplyError(request, "cue_unavailable");
                var wave = ReadVerifiedWave(asset, current.Volume);
                cancellationToken.ThrowIfCancellationRequested();
                if (request.SessionGeneration != _generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
                var played = _output.TryPlay(wave);
                if (played) _lastPlayback = _time.GetTimestamp();
                return played
                    ? Reply(request, new { schemaVersion = 1, status = "played", played = true, cueId = cue, selectedTier = asset.Tier.ToString().ToLowerInvariant() })
                    : ReplyError(request, "output_unavailable");
            } catch (OperationCanceledException) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), [])); }
            catch (BridgeProtocolException e) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request, new BridgeError(e.Code, "Audio request rejected.")), [])); }
            catch (AudioConflictException) { return ReplyError(request, "write_conflict"); }
            catch (NotificationAudioCatalogException) { _output.Stop(); return ReplyError(request, "integrity_failed"); }
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
    internal void ResetAutomaticSession()
    {
        lock (_gate) { _rooms.Reset(); if (!_disposed) _output.Stop(); }
    }

    // Only CompositeBridgeDispatcher can supply a completed authenticated room read.
    // No externally callable 'play this event' command and no new network polling.
    internal void ObserveRoomRead(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested) { _rooms.Reset(); return; }
            if (!_rooms.Observe(request, response, _generation())) return;
            try {
                if (request.AccountContext is null || _policies.Read(request.AccountContext).For("room") == NotificationSourceMode.DoNotDisturb) return;
                var settings = _store.Read();
                // DoNotDisturb is retained only for v1 compatibility; Enabled is the sole sound switch.
                if (!settings.Enabled || settings.Volume == 0 || !_canNotify() ||
                    (_lastPlayback is { } last && _time.GetElapsedTime(last) < TimeSpan.FromSeconds(10))) return;
                var asset = _catalog?.Resolve(NotificationAudioCueIds.Soft);
                if (asset is null) return;
                var wave = ReadVerifiedWave(asset, settings.Volume);
                if (token.IsCancellationRequested || request.SessionGeneration != _generation()) return;
                if (_output.TryPlay(wave)) _lastPlayback = _time.GetTimestamp();
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotificationAudioCatalogException or InvalidOperationException) {
                _output.Stop(); // A local audio failure never changes the successful room result.
            }
        }
    }
    private static ValueTask<BridgeDispatchBatch> Reply(BridgeEnvelope r, object value) =>
        ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(r, value, preserveRequestAccountContext: false), []));
    private static ValueTask<BridgeDispatchBatch> ReplyError(BridgeEnvelope r, string code) =>
        ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(r, new BridgeError("notificationAudio." + code, "Audio action could not be completed.")), []));
    public void Dispose() { lock (_gate) { if (_disposed) return; _disposed = true; _output.Dispose(); } }

    private static byte[] ReadVerifiedWave(NotificationAudioAsset asset, double volume)
    {
        var bytes = File.ReadAllBytes(asset.FilePath);
        if (bytes.Length > 8 * 1024 * 1024 || !Convert.ToHexString(SHA256.HashData(bytes)).Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new NotificationAudioCatalogException("Audio checksum mismatch.");
        try { return NotificationWaveGain.Apply(bytes, volume); }
        catch (InvalidDataException) { throw new NotificationAudioCatalogException("Invalid PCM audio."); }
    }
}
