using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

internal sealed class AchievementIdeaClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly Uri _endpoint;
    internal AchievementIdeaClient(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)) throw new ArgumentException("Trusted Relay origin required.");
        _endpoint = new(origin, "/api/achievements/ideas");
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(45) };
    }
    internal async Task<object> Send(string bearer, JsonElement payload, CancellationToken token)
    {
        string[] fields = ["schemaVersion", "submissionId", "name", "condition", "imageData"];
        if (payload.ValueKind != JsonValueKind.Object) throw new AccountBridgeHostException("ideas.invalid_request");
        var keys = payload.EnumerateObject().Select(p => p.Name).ToArray();
        if (keys.Length != 5 || keys.Distinct().Count() != 5 || keys.Except(fields).Any() || payload.GetProperty("schemaVersion").GetInt32() != 1)
            throw new AccountBridgeHostException("ideas.invalid_request");
        var id = payload.GetProperty("submissionId").GetString(); var name = payload.GetProperty("name").GetString()?.Trim();
        var condition = payload.GetProperty("condition").GetString()?.Trim();
        var image = payload.GetProperty("imageData").ValueKind == JsonValueKind.Null ? null : payload.GetProperty("imageData").GetString();
        if (!Guid.TryParseExact(id, "N", out _) || name is not { Length: > 0 and <= 120 } || name.Any(char.IsControl) ||
            condition is not { Length: > 0 and <= 2000 } || image is not null && (image.Length > 700000 || !image.StartsWith("data:image/png;base64,", StringComparison.Ordinal)))
            throw new AccountBridgeHostException("ideas.invalid_request");
        using var request = new HttpRequestMessage(HttpMethod.Post, _endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(new { submissionId = id, name, condition, imageData = image });
        // Sending email is a write. Do not replay this request through OAuth retries.
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (!response.IsSuccessStatusCode)
            throw new AccountBridgeHostException(response.StatusCode switch {
                System.Net.HttpStatusCode.Unauthorized => "ideas.sign_in",
                System.Net.HttpStatusCode.Forbidden => "ideas.restricted",
                System.Net.HttpStatusCode.NotFound => "ideas.unavailable",
                System.Net.HttpStatusCode.TooManyRequests => "ideas.rate_limited",
                System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.RequestEntityTooLarge or System.Net.HttpStatusCode.Conflict => "ideas.invalid_request",
                _ => "ideas.unconfirmed" });
        using var stream = await response.Content.ReadAsStreamAsync(token);
        var bytes = new byte[1025]; var count = 0; int read;
        while ((read = await stream.ReadAsync(bytes.AsMemory(count), token)) > 0)
        { count += read; if (count > 1024) throw new AccountBridgeHostException("ideas.unconfirmed"); }
        using var json = JsonDocument.Parse(bytes.AsMemory(0, count));
        var value = json.RootElement;
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != 2 || value.GetProperty("schemaVersion").GetInt32() != 1 ||
            value.GetProperty("sent").ValueKind != JsonValueKind.True) throw new AccountBridgeHostException("ideas.unconfirmed");
        return new { schemaVersion = 1, sent = true };
    }
    public void Dispose() => _http.Dispose();
}
