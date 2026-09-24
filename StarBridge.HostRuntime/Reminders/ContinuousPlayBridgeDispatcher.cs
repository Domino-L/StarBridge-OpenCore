using StarBridge.NativeBridge;
using System.Text.Json;
namespace StarBridge.HostRuntime.Reminders;

public sealed class ContinuousPlayBridgeDispatcher(ContinuousPlayReminderRuntime runtime, Func<long> generation) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["playReminder.read", "playReminder.save"];
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.SessionGeneration != generation()) return Error(request, "stale_generation");
            if (request.AccountContext != null || request.MessageType != "request" || !AdvertisedCapabilities.Contains(request.Name))
                return Error(request, "invalid_request");
            var save = request.Name == "playReminder.save";
            string[] expected = save ? ["schemaVersion", "expectedRevision", "enabled", "firstReminderMinutes", "repeatReminderMinutes"] : ["schemaVersion"];
            var body = request.Payload;
            var names = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != expected.Length || names.Distinct().Count() != expected.Length || names.Except(expected).Any() ||
                body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalid_request");
            var settings = save ? await runtime.SaveAsync(new(body.GetProperty("enabled").GetBoolean(),
                body.GetProperty("firstReminderMinutes").GetInt32(), body.GetProperty("repeatReminderMinutes").GetInt32()),
                body.GetProperty("expectedRevision").GetInt32(), cancellationToken,
                () => request.SessionGeneration == generation()) : await runtime.ReadAsync(cancellationToken);
            if (request.SessionGeneration != generation()) return Error(request, "stale_generation");
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, settings.Enabled, settings.FirstReminderMinutes,
                settings.RepeatReminderMinutes, settings.Revision }, preserveRequestAccountContext: false), []);
        }
        catch (ContinuousPlayConflictException) { return Error(request, "conflict"); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or OverflowException)
        { return Error(request, "invalid_request"); }
        catch { return Error(request, "storage_unavailable"); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string suffix) =>
        new(BridgeEnvelope.ErrorResponse(request, new("playReminder." + suffix, "Play reminder settings unavailable.", true)), []);
    public void Dispose() { } // Runtime belongs to the Host lifecycle, not this borrowed settings adapter.
}
