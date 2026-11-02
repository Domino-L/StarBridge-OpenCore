using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

/// <summary>Public support endpoints only. Never attaches credentials, player IDs,
/// logs, installation telemetry, or user-supplied URLs. Feedback is never retried.</summary>
public sealed class HelpSupportBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } =
        ["helpSupport.history", "helpSupport.stats", "helpSupport.feedback", "helpSupport.openScm", "helpSupport.openRsiOrganization",
         "helpSupport.openRsiProfileSettings"];
    internal static Uri ScmWebsiteRoot { get; } = new("https://scm.flowcld.com/");
    internal static void OpenBrowser(Uri uri) =>
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        { FileName = uri.AbsoluteUri, UseShellExecute = true });
    private readonly Action _openScm;
    private readonly Action<Uri> _openRsiOrganization;
    private readonly Uri? _origin;
    private readonly Func<long> _generation;
    private readonly HttpClient _client;
    private readonly SemaphoreSlim _sending = new(1, 1);
    private bool _disposed;
    private readonly AppStatsHeartbeatRuntime.RelayCapability? _appStatsCapability;
    private readonly Lifecycle.DeviceNetworkAdmission? _network;

    public HelpSupportBridgeDispatcher(Uri? origin, Func<long> generation, HttpMessageHandler? handler = null,
        Action? openScm = null, Lifecycle.DeviceNetworkAdmission? network = null, Action<Uri>? openRsiOrganization = null,
        AppStatsHeartbeatRuntime.RelayCapability? appStatsCapability = null)
    {
        _origin = origin;
        _appStatsCapability = appStatsCapability;
        _network = network;
        _generation = generation;
        _openScm = openScm ?? (() => OpenBrowser(ScmWebsiteRoot));
        _openRsiOrganization = openRsiOrganization ?? (uri => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        { FileName = uri.AbsoluteUri, UseShellExecute = true }));
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
            var rsi = request.Name == "helpSupport.openRsiOrganization";
            var p = request.Payload;
            if (!Capabilities.Contains(request.Name) || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext is not null || p.ValueKind != JsonValueKind.Object ||
                p.EnumerateObject().Count() != (feedback ? 3 : rsi ? 2 : 1) ||
                !p.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
                return Error(request, "invalid");
            if (rsi)
            {
                // RSI publishes SIDs as 1-10 uppercase ASCII alphanumeric characters.
                // Accept only that identifier, never a caller-provided URL or path.
                if (!p.TryGetProperty("sid", out var value) || value.ValueKind != JsonValueKind.String ||
                    value.GetString() is not { Length: >= 1 and <= 10 } sid ||
                    sid.Any(c => c is not (>= 'A' and <= 'Z') and not (>= '0' and <= '9')))
                    return Error(request, "invalid");
                using var linkWork = _network?.Enter(cancellationToken);
                if (_network is not null && linkWork is null) return Error(request, "offline");
                cancellationToken.ThrowIfCancellationRequested();
                linkWork?.RequireCurrent();
                if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
                _openRsiOrganization(new Uri("https://robertsspaceindustries.com/orgs/" + sid));
                return Reply(request, new { schemaVersion = 1, opened = true });
            }
            if (request.Name == "helpSupport.openRsiProfileSettings")
            {
                // SCM users change their avatar on RSI; fixed URL, nothing caller-supplied.
                using var linkWork = _network?.Enter(cancellationToken);
                if (_network is not null && linkWork is null) return Error(request, "offline");
                cancellationToken.ThrowIfCancellationRequested();
                linkWork?.RequireCurrent();
                if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
                _openRsiOrganization(new Uri(Account.RsiAvatarImage.ProfileSettingsUrl));
                return Reply(request, new { schemaVersion = 1, opened = true });
            }
            if (request.Name == "helpSupport.openScm")
            {
                using var linkWork = _network?.Enter(cancellationToken);
                if (_network is not null && linkWork is null) return Error(request, "offline");
                cancellationToken.ThrowIfCancellationRequested();
                linkWork?.RequireCurrent();
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
            using var networkWork = _network?.Enter(cancellationToken);
            if (_network is not null && networkWork is null) return Error(request, "offline");
            using var networkDeadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, networkWork?.Token ?? CancellationToken.None);
            cancellationToken = networkDeadline.Token;
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
            networkWork?.RequireCurrent();
            if (!response.IsSuccessStatusCode)
                return Error(request, response.StatusCode == System.Net.HttpStatusCode.TooManyRequests ? "rateLimited" : "rejected");
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unconfirmed");
            if (feedback) return Reply(request, new { schemaVersion = 1, sent = true });
            // Do not abandon an uncancellable content read via WaitAsync. The
            // device lease must own its actual read through physical exit.
            using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var bytes = new MemoryStream();
            var buffer = new byte[1024];
            int length;
            while ((length = await content.ReadAsync(buffer, cancellationToken)) != 0)
            {
                if (bytes.Length + length > 16384) return Error(request, "unavailable");
                bytes.Write(buffer, 0, length);
            }
            networkWork?.RequireCurrent();
            cancellationToken.ThrowIfCancellationRequested();
            using var json = JsonDocument.Parse(bytes.ToArray());
            var data = json.RootElement;
            long Count(string key) => data.GetProperty(key).GetInt64() is var n && n >= 0 ? n : throw new JsonException();
            var updatedAt = data.GetProperty("updatedAt").GetDateTimeOffset();
            // Optional during Relay rollout. Missing or invalid is unknown, never zero.
            long? registeredAccountCount = data.TryGetProperty("registeredAccountCount", out var accounts)
                && accounts.ValueKind == JsonValueKind.Number && accounts.TryGetInt64(out var count) && count >= 0
                ? count : null;
            if (_disposed || request.SessionGeneration != _generation()) return Error(request, "unavailable");
            networkWork?.RequireCurrent();
            _appStatsCapability?.Observe(data);
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
