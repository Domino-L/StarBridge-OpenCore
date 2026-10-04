namespace StarBridge.HostRuntime.Settings;

using StarBridge.NativeBridge;
using System.Text.Json;

// Receives current-account intents only. The renderer never chooses a filename
// or owner; the existing authenticated account runtime supplies both scope facts.
public sealed class MenuBrowserResumeBridgeDispatcher(
    string root, Func<(string? OwnerKey, long Generation)> scope) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } =
        ["menuBrowserResume.read", "menuBrowserResume.update", "menuBrowserResume.remember"];
    private readonly MenuBrowserResumeStore _store = new(root);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        bool entered = false;
        try
        {
            await _gate.WaitAsync(cancellationToken); entered = true;
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var lease = scope();
            bool Current() => !_disposed && !cancellationToken.IsCancellationRequested && scope() == lease;
            if (_disposed || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext is not null || !Capabilities.Contains(request.Name) ||
                !MenuBrowserResumeStore.ValidOwner(lease.OwnerKey) || request.SessionGeneration != lease.Generation)
                throw new BridgeProtocolException(BridgeErrorCodes.StaleGeneration, "Browser account scope unavailable");
            var keys = request.Name switch
            {
                "menuBrowserResume.read" => new[] { "schemaVersion" },
                "menuBrowserResume.update" => ["schemaVersion", "expectedRevision", "enabled"],
                _ => ["schemaVersion", "expectedRevision", "url"]
            };
            Validate(request.Payload, keys);
            MenuBrowserResumeStore.Snapshot value;
            if (request.Name == "menuBrowserResume.read") value = _store.Read(lease.OwnerKey!);
            else
            {
                var rawRevision = request.Payload.GetProperty("expectedRevision");
                if (rawRevision.ValueKind != JsonValueKind.Number || !rawRevision.TryGetInt64(out var revision) || revision < 0)
                    throw new ArgumentException("Invalid browser revision");
                if (request.Name == "menuBrowserResume.update")
                {
                    var enabled = request.Payload.GetProperty("enabled");
                    if (enabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid browser option");
                    value = _store.SetConsent(lease.OwnerKey!, revision, enabled.GetBoolean(), Current);
                }
                else
                {
                    var url = request.Payload.GetProperty("url");
                    if (url.ValueKind != JsonValueKind.String) throw new ArgumentException("Invalid browser address");
                    value = _store.Remember(lease.OwnerKey!, revision, url.GetString()!, Current);
                }
            }
            if (!Current()) throw new OperationCanceledException();
            // The shared envelope serializer omits nullable object properties.
            // Keep a stable four-field reply, including explicit null address.
            var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, revision = value.Revision,
                enabled = value.Enabled, url = value.Url });
            return new(BridgeEnvelope.Response(request, payload, preserveRequestAccountContext: false), []);
        }
        catch (ApplicationPreferencesException error) { return Error(request, error.Code, error.Retryable); }
        catch (BridgeProtocolException error) { return Error(request, error.Code); }
        catch (ArgumentException) { return Error(request, "menuBrowserResume.invalid_value"); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (OperationCanceledException) { return Error(request, BridgeErrorCodes.StaleGeneration); }
        catch (Exception) { return Error(request, "menuBrowserResume.unavailable", true); }
        finally { if (entered) _gate.Release(); }
    }
    private static void Validate(JsonElement payload, string[] keys)
    {
        if (payload.ValueKind != JsonValueKind.Object) throw new ArgumentException("Invalid browser payload");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in payload.EnumerateObject())
            if (!keys.Contains(field.Name) || !seen.Add(field.Name)) throw new ArgumentException("Invalid browser payload");
        if (seen.Count != keys.Length || payload.GetProperty("schemaVersion").ValueKind != JsonValueKind.Number ||
            !payload.GetProperty("schemaVersion").TryGetInt32(out var version) || version != 1)
            throw new ArgumentException("Invalid browser payload");
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code, bool retryable = false) =>
        new(BridgeEnvelope.ErrorResponse(request, new BridgeError(code, "Browser preference could not be applied", retryable)), []);
    public void Dispose() { _disposed = true; }
}
