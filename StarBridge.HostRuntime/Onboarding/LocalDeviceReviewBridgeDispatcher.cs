using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// This capability exposes only device-choice review, never first-use eligibility,
// Native functional readiness, statistics consent or completion.
public sealed class LocalDeviceReviewBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.deviceReview.v1";
    public const string ReadRequest = "onboarding.deviceReview.read";
    public const string ConfirmRequest = "onboarding.deviceReview.confirm";
    private readonly LocalDeviceSetupReviewRuntime _runtime;
    private readonly Func<long> _generation;
    private volatile bool _disposed;
    internal LocalDeviceReviewBridgeDispatcher(LocalDeviceSetupReviewRuntime runtime, Func<long> generation)
    { _runtime = runtime; _generation = generation; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "firstUse.context_changed");
            var confirm = request.Name == ConfirmRequest;
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.Name is not (ReadRequest or ConfirmRequest) || request.Payload.ValueKind != JsonValueKind.Object)
                return Error(request, "firstUse.invalid_request");
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            string[] expected = confirm ? ["schemaVersion", "reviewKey", "reviewedSections"] : ["schemaVersion"];
            if (fields.Length != expected.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                fields.Except(expected, StringComparer.Ordinal).Any() ||
                !request.Payload.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1)
                return Error(request, "firstUse.invalid_request");
            if (confirm && (request.Payload.GetProperty("reviewKey").ValueKind != JsonValueKind.String ||
                request.Payload.GetProperty("reviewedSections").ValueKind != JsonValueKind.Array ||
                request.Payload.GetProperty("reviewedSections").GetArrayLength() != 4))
                return Error(request, "firstUse.invalid_request");
            var value = confirm ? await _runtime.ConfirmAsync(
                request.Payload.GetProperty("reviewKey").GetString()!,
                request.Payload.GetProperty("reviewedSections").EnumerateArray().Select(p => p.GetString()!).ToArray(), token)
                : await _runtime.ReadAsync(token);
            token.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "firstUse.context_changed");
            return new(BridgeEnvelope.Response(request, Project(value), preserveRequestAccountContext: false), []);
        }
        catch (LocalFirstUseException error) { return Error(request, error.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { return Error(request, "firstUse.invalid_request"); }
        catch { return Error(request, "firstUse.device_review_read_failed"); }
    }
    private static object Project(LocalDeviceReviewObservation value)
    {
        var app = value.Choices?.Application.Value; var hud = value.Choices?.Overlay.Value;
        var notices = value.Choices?.Notifications.Value; var reminder = value.Choices?.PlayReminder.Value;
        return new { schemaVersion = 1, state = value.State, reviewKey = value.ReviewKey,
            application = app is null ? null : new { app.LaunchAtStartup, app.KeepRunningInBackground, app.StartMinimized,
                app.StartupChoiceMade, app.CloseBehaviorChoiceMade },
            overlay = hud is null ? null : new { hud.RenderMode, hud.HotkeyBinding, hud.HotkeyEnabled, hud.Opacity,
                hud.AutoOpenOnGameStart, hud.AutoOpenOnGameForeground, hud.AutoCloseOnGameBackground, hud.ShowEventNotifications },
            notifications = notices is null ? null : new { notices.InAppEnabled, notices.WindowsEnabled, notices.OverlayEnabled,
                notices.DirectMessageWindowsEnabled, notices.Position, notices.Preview },
            playReminder = reminder is null ? null : new { reminder.Enabled, reminder.FirstReminderMinutes, reminder.RepeatReminderMinutes }
        };
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Device choices could not be confirmed.", true)), []);
    public void Dispose() { _disposed = true; _ = _runtime.RetireAsync(); }
}
