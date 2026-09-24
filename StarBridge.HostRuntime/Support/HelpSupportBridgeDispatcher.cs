using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

/// <summary>Public support endpoints only. Never attaches credentials, player IDs,
/// logs, installation telemetry, or user-supplied URLs. Feedback is never retried.</summary>
public sealed class HelpSupportBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } =
        ["helpSupport.history", "helpSupport.stats", "helpSupport.feedback", "helpSupport.openScm"];
    private readonly Action _openScm;
    private readonly Uri? _origin;
    private readonly Func<long> _generation;
    private readonly HttpClient _client;
    private readonly SemaphoreSlim _sending = new(1, 1);
    private bool _disposed;

    public HelpSupportBridgeDispatcher(Uri? origin, Func<long> generation, HttpMessageHandler? handler = null,
        Action? openScm = null)
    {
        _origin = origin;
        _generation = generation;
        _openScm = openScm ?? (() => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "https://scm.flowcld.com/", UseShellExecute = true
        }));
        _client = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });
        _client.Timeout = TimeSpan.FromSeconds(15);
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        bool sending = false;
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(TimeSpan.FromSeconds(15));
            cancellationToken = deadline.Token;
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
            var feedback = request.Name == "helpSupport.feedback";
            var p = request.Payload;
            if (!Capabilities.Contains(request.Name) || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext is not null || p.ValueKind != JsonValueKind.Object ||
                p.EnumerateObject().Count() != (feedback ? 3 : 1) ||
                !p.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
                return Error(request, "invalid");
            if (request.Name == "helpSupport.openScm")
            {
                cancellationToken.ThrowIfCancellationRequested();
                _openScm();
                return Reply(request, new { schemaVersion = 1, opened = true });
            }
            if (request.Name == "helpSupport.history")
            {
                using var stream = typeof(HelpSupportBridgeDispatcher).Assembly.GetManifestResourceStream("StarBridge.ReleaseNotes.catalog.json")!;
                using var history = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
                if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
                return Reply(request, new { schemaVersion = 1, edition = "starbridge", entries = history.RootElement.GetProperty("entries").Clone() });
            }
            if (_origin is null) return Error(request, "unavailable");
            using var message = new HttpRequestMessage(feedback ? HttpMethod.Post : HttpMethod.Get,
                new Uri(_origin, feedback ? "api/feedback" : "api/app-stats"));
            if (feedback)
            {
                if (!p.TryGetProperty("contact", out var contact) || contact.ValueKind != JsonValueKind.String ||
                    !p.TryGetProperty("message", out var body) || body.ValueKind != JsonValueKind.String ||
                    contact.GetString()!.Length > 120 || string.IsNullOrWhiteSpace(body.GetString()) || body.GetString()!.Length > 2000)
                    return Error(request, "invalid");
                sending = await _sending.WaitAsync(0, cancellationToken);
                if (!sending) return Error(request, "busy");
                message.Content = JsonContent.Create(new { contact = contact.GetString()!.Trim(), message = body.GetString()!.Trim() });
            }
            using var response = await _client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (!response.IsSuccessStatusCode)
                return Error(request, response.StatusCode == System.Net.HttpStatusCode.TooManyRequests ? "rateLimited" : "rejected");
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unconfirmed");
            if (feedback) return Reply(request, new { schemaVersion = 1, sent = true });
            await response.Content.LoadIntoBufferAsync(16384).WaitAsync(cancellationToken);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            var data = json.RootElement;
            long Count(string key) => data.GetProperty(key).GetInt64() is var n && n >= 0 ? n : throw new JsonException();
            var updatedAt = data.GetProperty("updatedAt").GetDateTimeOffset();
            // Optional during Relay rollout. Missing or invalid is unknown, never zero.
            long? registeredAccountCount = data.TryGetProperty("registeredAccountCount", out var accounts)
                && accounts.ValueKind == JsonValueKind.Number && accounts.TryGetInt64(out var count) && count >= 0
                ? count : null;
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
            return Reply(request, new { schemaVersion = 1, downloadCount = Count("downloadCount"),
                onlineUserCount = Count("onlineUserCount"), fleetCount = Count("fleetCount"),
                overlayUsageSeconds = Count("overlayUsageSeconds"), registeredAccountCount, updatedAt });
        }
        catch { return Error(request, request.Name == "helpSupport.feedback" ? "unconfirmed" : "unavailable"); }
        finally { if (sending) _sending.Release(); }
    }
    private static BridgeDispatchBatch Reply(BridgeEnvelope request, object value) =>
        new(BridgeEnvelope.Response(request, value, preserveRequestAccountContext: false), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new BridgeError("helpSupport." + code, "Support operation could not be confirmed.")), []);
    public void Dispose() { _disposed = true; _client.Dispose(); }
}
