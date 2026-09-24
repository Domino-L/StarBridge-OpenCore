namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Overlay;

internal sealed record LocalNotificationSettings(int SchemaVersion = 1, int Revision = 0,
    bool InAppEnabled = true, string Position = "bottomRight", string Preview = "sourceOnly", bool WindowsEnabled = false,
    bool OverlayEnabled = true, bool DirectMessageWindowsEnabled = false);
internal sealed class NotificationSettingsConflictException : Exception;

// Device-local visual channels. No account/source policy or sound duplication.
public sealed partial class NotificationSettingsBridgeDispatcher(string dataRoot, Func<long> generation, Func<bool>? canNotifyDesktop = null,
    IInformationOverlayReminderSink? overlay = null, IDesktopNotificationSink? desktop = null,
    Func<long, object, BridgeEnvelope>? activationEvent = null) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["notificationSettings.read", "notificationSettings.save",
        "notificationSettings.presentDesktop", "notificationSettings.testDesktop", "notificationSettings.clearDesktop", "notificationSettings.consumeActivation"];
    private readonly string _path = Path.Combine(Path.GetFullPath(dataRoot), "notification-settings.v1.json");
    private readonly object _gate = new();
    private readonly RoomAudioObserver _rooms = new();
    private readonly DirectMessageNotificationObserver _direct = new();
    internal IReadOnlyList<string> DirectMessageCandidates { get { lock (_gate) return _direct.FreshKeys.ToArray(); } }
    private bool _disposed;
    private long _reminderEpoch;
    private string[] _activeIds = [];
    public event Action<BridgeEnvelope>? EventReady;
    internal void Reset() { lock (_gate) { Interlocked.Increment(ref _directEpoch); _rooms.Reset(); _direct.Reset(); InvalidateReminder(); } }
    private void InvalidateReminder() {
        Interlocked.Increment(ref _reminderEpoch);
        _activeIds = [];
        _desktopTicket = null;
        _activation = null;
        desktop?.ClearMessages();
        overlay?.ClearReminder();
    }
    private static string[] SettingFields(JsonElement root, string revision) =>
        ["schemaVersion", revision, "inAppEnabled", "position", "preview",
         .. root.TryGetProperty("windowsEnabled", out _) ? new[] { "windowsEnabled" } : [],
         .. root.TryGetProperty("overlayEnabled", out _) ? new[] { "overlayEnabled" } : [],
         .. root.TryGetProperty("directMessageWindowsEnabled", out _) ? new[] { "directMessageWindowsEnabled" } : []];
    private static bool Valid(LocalNotificationSettings value) => value.SchemaVersion == 1 && value.Revision >= 0 &&
        value.Position is "topLeft" or "topRight" or "bottomLeft" or "bottomRight" &&
        value.Preview is "fullContent" or "sourceOnly" or "hiddenDetails";
    private static void Fields(JsonElement root, params string[] fields) {
        var names = root.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Length != fields.Length || names.Distinct().Count() != fields.Length || names.Except(fields).Any())
            throw new InvalidDataException();
    }
    private LocalNotificationSettings Read() {
        if (!File.Exists(_path)) return new();
        var info = new FileInfo(_path);
        if (info.Length > 4096 || info.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidDataException();
        using var json = JsonDocument.Parse(File.ReadAllBytes(_path));
        Fields(json.RootElement, SettingFields(json.RootElement, "revision"));
        var value = json.RootElement.Deserialize<LocalNotificationSettings>(BridgeProtocol.JsonOptions);
        if (value == null || !Valid(value)) throw new InvalidDataException();
        return value;
    }
    private void Write(LocalNotificationSettings value) {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                JsonSerializer.Serialize(file, value, BridgeProtocol.JsonOptions); file.Flush(true);
            }
            File.Move(temp, _path, true);
        } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) {
        if (request.Name == "notificationSettings.consumeActivation") return ValueTask.FromResult(ConsumeActivation(request));
        if (request.Name is "notificationSettings.presentDesktop" or "notificationSettings.testDesktop" or "notificationSettings.clearDesktop")
            return DispatchDesktopAsync(request, cancellationToken);
        lock (_gate) {
            BridgeEnvelope Error(string code) => BridgeEnvelope.ErrorResponse(request, new BridgeError("notificationSettings." + code, "Notification preferences unavailable."));
            BridgeEnvelope response;
            try {
                ObjectDisposedException.ThrowIf(_disposed, this);
                cancellationToken.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.AccountContext != null || request.MessageType != BridgeMessageTypes.Request || !AdvertisedCapabilities.Contains(request.Name))
                    throw new ArgumentException();
                var save = request.Name == "notificationSettings.save";
                Fields(request.Payload, !save ? ["schemaVersion"] : SettingFields(request.Payload, "expectedRevision"));
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                var value = Read();
                if (save) {
                    if (request.Payload.GetProperty("expectedRevision").GetInt32() != value.Revision) throw new NotificationSettingsConflictException();
                    value = new(Revision: checked(value.Revision + 1), InAppEnabled: request.Payload.GetProperty("inAppEnabled").GetBoolean(),
                        Position: request.Payload.GetProperty("position").GetString()!, Preview: request.Payload.GetProperty("preview").GetString()!,
                        WindowsEnabled: request.Payload.TryGetProperty("windowsEnabled", out var windows) ? windows.GetBoolean() : value.WindowsEnabled,
                        OverlayEnabled: request.Payload.TryGetProperty("overlayEnabled", out var inGame) ? inGame.GetBoolean() : value.OverlayEnabled,
                        DirectMessageWindowsEnabled: request.Payload.TryGetProperty("directMessageWindowsEnabled", out var direct) ? direct.GetBoolean() : value.DirectMessageWindowsEnabled);
                    if (!Valid(value)) throw new ArgumentException();
                    cancellationToken.ThrowIfCancellationRequested();
                    if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                    Write(value);
                    Interlocked.Increment(ref _directEpoch);
                    InvalidateReminder();
                }
                var projection = JsonSerializer.SerializeToElement(value, BridgeProtocol.JsonOptions)
                    .Deserialize<Dictionary<string, JsonElement>>()!;
                if (overlay is null) projection.Remove("overlayEnabled");
                response = BridgeEnvelope.Response(request, projection, preserveRequestAccountContext: false);
            } catch (OperationCanceledException) { response = BridgeEnvelope.CancelledResponse(request); }
            catch (BridgeProtocolException e) { response = BridgeEnvelope.ErrorResponse(request, new BridgeError(e.Code, "Preferences request rejected.")); }
            catch (NotificationSettingsConflictException) { response = Error("write_conflict"); }
            catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException) { response = Error(request.Name.EndsWith("save") ? "write_failed" : "read_failed"); }
            catch (Exception e) when (e is ArgumentException or InvalidOperationException or OverflowException or FormatException or KeyNotFoundException) { response = Error("invalid_request"); }
            return ValueTask.FromResult(new BridgeDispatchBatch(response, []));
        }
    }
    internal async ValueTask<BridgeEnvelope> ObserveAsync(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token) {
        if (request.Name == "directMessages.read") return await ObserveDirectAsync(request, response, token).ConfigureAwait(false);
        LocalNotificationSettings settings;
        InformationOverlayReminder? reminder;
        int invitations, applications;
        long epoch;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || request.SessionGeneration != generation()) return response;
            // Warm and advance the inbox baseline even when delivery is disabled.
            // Desktop delivery will consume this source; no UI switch is advertised yet.
            var fresh = _rooms.Observe(request, response, generation());
            if (!_rooms.ContainsAll(_activeIds)) InvalidateReminder();
            if (!fresh) return response;
            try {
                settings = Read();
                if (request.AccountContext is null || _policies.Read(request.AccountContext).For("room") == NotificationSourceMode.DoNotDisturb) {
                    InvalidateReminder(); return response;
                }
                InvalidateReminder();
                epoch = Interlocked.Read(ref _reminderEpoch);
                if ((!settings.InAppEnabled && !settings.WindowsEnabled && !(settings.OverlayEnabled && overlay != null)) ||
                    request.SessionGeneration != generation()) return response;
                invitations = _rooms.FreshInvitations; applications = _rooms.FreshApplications;
                _activeIds = _rooms.FreshIds.ToArray();
                var started = System.Diagnostics.Stopwatch.GetTimestamp();
                var lifetime = _rooms.FreshLifetime;
                reminder = settings.OverlayEnabled && overlay != null
                    ? new(Guid.NewGuid(), invitations, applications, settings.Preview,
                        () => epoch == Interlocked.Read(ref _reminderEpoch) && request.SessionGeneration == generation() &&
                            System.Diagnostics.Stopwatch.GetElapsedTime(started) < lifetime) : null;
                if (settings.WindowsEnabled && desktop != null)
                    _desktopTicket = CreateDesktop(Guid.NewGuid(), false, invitations, applications, settings,
                        () => epoch == Interlocked.Read(ref _reminderEpoch) && request.SessionGeneration == generation() &&
                            System.Diagnostics.Stopwatch.GetElapsedTime(started) < lifetime);
            } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or InvalidOperationException or
                StarBridge.HostRuntime.Settings.ApplicationPreferencesException) { return response; }
        }
        var handled = false;
        if (reminder != null) {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            try { handled = await overlay!.TryPresentAsync(reminder, deadline.Token).ConfigureAwait(false); }
            // An uncertain native submission must not also pop on another visual channel.
            catch (OperationCanceledException) { handled = true; }
            catch (Exception) { handled = true; }
        }
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || epoch != Interlocked.Read(ref _reminderEpoch) ||
                request.SessionGeneration != generation()) return response;
            var payload = response.Payload.Deserialize<Dictionary<string, JsonElement>>()!;
            var metadata = new Dictionary<string, object> { ["schemaVersion"] = 1, ["revision"] = settings.Revision,
                ["invitations"] = invitations, ["applications"] = applications,
                ["desktopEligible"] = !handled && settings.WindowsEnabled && (canNotifyDesktop?.Invoke() ?? false) };
            if (handled) metadata["overlayHandled"] = true;
            if (handled) _desktopTicket = null;
            else if (_desktopTicket != null) metadata["desktopTicket"] = _desktopTicket.Id.ToString("N");
            payload["localReminder"] = BridgePayload.From(metadata);
            return response with { Payload = BridgePayload.From(payload) };
        }
    }
    public void Dispose() { lock (_gate) { _disposed = true; _rooms.Reset(); _direct.Reset(); InvalidateReminder(); } desktop?.Dispose(); }
}
