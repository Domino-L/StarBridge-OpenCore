using StarBridge.NativeBridge;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Explicit local test workspace only; cannot forward SCM credentials or choose a remote URL.</summary>
public sealed class HangarSandboxDispatcher : IBridgeRequestDispatcher
{
    private readonly HttpClient _http;
    private readonly string _a, _b;
    private readonly Func<long> _generation;
    public HangarSandboxDispatcher(HttpClient http, string a, string b, Func<long> generation)
    {
        if (!System.Text.RegularExpressions.Regex.IsMatch(a, "^[a-f0-9]{64}$") ||
            !System.Text.RegularExpressions.Regex.IsMatch(b, "^[a-f0-9]{64}$") || a == b)
            throw new ArgumentException("Invalid sandbox credentials");
        _http = http; _a = a; _b = b; _generation = generation;
    }
    public static HangarSandboxDispatcher? FromEnvironment(Func<long> generation)
    {
        if (Environment.GetEnvironmentVariable("STARBRIDGE_HANGAR_SANDBOX") != "1") return null;
        const string path = @"G:\Development\tools\starbridge-profile-mysql\instance-hangar-20260903\client.dpapi";
        if (new FileInfo(path).Length > 16384) throw new InvalidOperationException("Invalid sandbox configuration");
        byte[] clear = ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser);
        try {
            using var document = JsonDocument.Parse(clear);
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
                root.GetProperty("endpoint").GetString() != "http://127.0.0.1:18083")
                throw new InvalidOperationException("Unexpected sandbox destination");
            return new(new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseProxy = false }) {
                Timeout = TimeSpan.FromSeconds(25)
            }, root.GetProperty("a").GetString()!, root.GetProperty("b").GetString()!, generation);
        } finally { CryptographicOperations.ZeroMemory(clear); }
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        if (request.AccountContext != null || request.SessionGeneration != _generation()) return Error(request, "accountChanged");
        if (request.Name == "hangarSandbox.status")
            return new(BridgeEnvelope.Response(request, new { enabled = true, environment = "sandbox", schemaVersion = 1 }), []);
        try {
            var input = request.Payload;
            string testAccount = input.GetProperty("testAccount").GetString()!;
            if (testAccount is not ("A" or "B")) return Error(request, "invalid");
            string method, path;
            object? payload = null;
            string[] fields;
            switch (request.Name) {
                case "hangarSandbox.read":
                    method = "GET"; path = "/hangar"; fields = ["testAccount"]; break;
                case "hangarSandbox.preview":
                    method = "POST"; path = "/sandbox/preview";
                    fields = ["testAccount","key","baseRevision","scenario"];
                    payload = new { key = input.GetProperty("key").GetString(), baseRevision = input.GetProperty("baseRevision").GetInt64(),
                        scenario = input.GetProperty("scenario").GetString() }; break;
                case "hangarSandbox.commit":
                    method = "PUT"; path = "/hangar/imports/" + Id(input) + "/commit";
                    fields = ["testAccount","key","expectedRevision","digest","confirmRemovalOfAll","importId"];
                    payload = new { key = input.GetProperty("key").GetString(), expectedRevision = input.GetProperty("expectedRevision").GetInt64(),
                        digest = input.GetProperty("digest").GetString(), confirmRemovalOfAll = input.GetProperty("confirmRemovalOfAll").GetBoolean() }; break;
                case "hangarSandbox.result":
                    method = "GET"; path = "/hangar/imports/" + Id(input); fields = ["testAccount","importId"]; break;
                default: return Error(request, "unavailable");
            }
            if (input.EnumerateObject().Any(p => !fields.Contains(p.Name)) || input.EnumerateObject().Count() != fields.Length)
                return Error(request, "invalid");
            using var message = new HttpRequestMessage(new HttpMethod(method), "http://127.0.0.1:18083" + path);
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", testAccount == "A" ? _a : _b);
            if (payload != null) message.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var response = await _http.SendAsync(message, cancellationToken);
            var text = await response.Content.ReadAsStringAsync(cancellationToken);
            if (request.SessionGeneration != _generation()) return Error(request, "accountChanged");
            if (text.Length > 1024 * 1024) return Error(request, "too_large");
            var node = JsonNode.Parse(text)!.AsObject();
            if (!response.IsSuccessStatusCode) return Error(request, node["code"]?.GetValue<string>() ?? "unavailable");
            Decorate(node);
            return new(BridgeEnvelope.Response(request, node), []);
        } catch (Exception error) when (error is HttpRequestException or TaskCanceledException or JsonException or
            KeyNotFoundException or InvalidOperationException or FormatException) {
            return Error(request, "unavailable");
        }
    }
    private static string Id(JsonElement input) =>
        Guid.TryParseExact(input.GetProperty("importId").GetString(), "D", out var id) ? id.ToString("D") : throw new FormatException();
    private static void Decorate(JsonObject node)
    {
        if (node["ships"] is JsonArray ships)
            foreach (var ship in ships.OfType<JsonObject>())
                ship["presentation"] = JsonSerializer.SerializeToNode(HangarShipNames.Present(ship["rawTitle"]!.GetValue<string>(),
                    ship["manufacturer"]?.GetValue<string>(), 0));
        if (node["preview"] is JsonObject preview) Decorate(preview);
        if (node["committed"] is JsonObject committed) Decorate(committed);
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new("hangar." + code, "Hangar request failed.", code is "unavailable" or "busy")), []);
    public void Dispose() => _http.Dispose();
}
