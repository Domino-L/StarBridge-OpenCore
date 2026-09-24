using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Identity;

namespace StarBridge.HostRuntime.Account;

internal sealed record PasswordRecoveryResult(int SchemaVersion, string Outcome, int RetryAfterSeconds = 0);

// Anonymous WPF password-reset contract only. This client cannot log in, register,
// provision, save a credential or attach an SCM token to a request.
internal sealed class LegacyPasswordRecoveryClient : IDisposable
{
    private readonly Uri _baseUri;
    private readonly HttpClient _http;
    private readonly CancellationTokenSource _lifetime = new();
    private int _busy;
    internal LegacyPasswordRecoveryClient(Uri baseUri, HttpMessageHandler? handler = null)
    {
        if (!baseUri.IsAbsoluteUri || (baseUri.Scheme != "https" && !(baseUri.Scheme == "http" && baseUri.IsLoopback)) ||
            baseUri.UserInfo.Length != 0 || baseUri.Query.Length != 0 || baseUri.Fragment.Length != 0)
            throw new ArgumentException("Password recovery requires HTTPS or a loopback test endpoint.", nameof(baseUri));
        _baseUri = baseUri;
        _http = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(20) };
    }

    internal async Task<PasswordRecoveryResult> ExecuteAsync(string action, JsonElement payload, CancellationToken token)
    {
        var confirm = action == AccountBridgeRequestNames.ConfirmPasswordReset;
        if (!confirm && action != AccountBridgeRequestNames.SendPasswordResetCode)
            throw new AccountBridgeHostException("bridge.capability_unavailable");
        var allowed = confirm ? new[] { "schemaVersion", "email", "verificationCode", "newPassword" } : ["schemaVersion", "email"];
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Any(p => !allowed.Contains(p.Name)) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("bridge.invalid_envelope");
        var email = Text(payload, "email")?.Trim();
        if (email is null || email.Length > 320 || !System.Net.Mail.MailAddress.TryCreate(email, out var parsed) || parsed.Address != email)
            return new(1, "invalidEmail");
        var code = Text(payload, "verificationCode")?.Trim();
        var password = Text(payload, "newPassword");
        if (confirm && (code is null || code.Length != 6 || code.Any(c => c is < '0' or > '9')))
            return new(1, "invalidCode");
        if (confirm && !AccountPasswordPolicy.IsValidLength(password)) return new(1, "invalidPassword");
        if (Interlocked.Exchange(ref _busy, 1) != 0) return new(1, "busy");
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(20));
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_baseUri,
                confirm ? "api/auth/password-reset/confirm" : "api/auth/password-reset/send-code"))
            {
                Content = confirm ? JsonContent.Create(new { Email = email, VerificationCode = code, NewPassword = password }) : JsonContent.Create(new { Email = email })
            };
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            using var body = await ReadBoundedJsonAsync(response.Content, deadline.Token);
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                var retry = body.RootElement.TryGetProperty("retryAfterSeconds", out var value) && value.TryGetInt32(out var seconds) ? seconds : 60;
                return new(1, "throttled", Math.Clamp(retry, 1, 3600));
            }
            if (response.IsSuccessStatusCode)
            {
                if (!body.RootElement.TryGetProperty(confirm ? "reset" : "sent", out var accepted) || accepted.ValueKind != JsonValueKind.True)
                    return new(1, "unavailable");
                return new(1, confirm ? "reset" : "codeRequested", confirm ? 0 : 60);
            }
            // Only map known WPF contract errors. Never return server text or credentials.
            var error = Text(body.RootElement, "error");
            return new(1, error switch
            {
                "验证码错误或已过期。" => "invalidCode",
                "新密码需要 8 到 128 个字符。" => "invalidPassword",
                "该密码过于常见，请使用更长且独特的密码。" => "commonPassword",
                _ => "unavailable"
            });
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return new(1, "unavailable"); }
        finally { Interlocked.Exchange(ref _busy, 0); }
    }

    private static string? Text(JsonElement value, string key) =>
        value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
    internal static async Task<JsonDocument> ReadBoundedJsonAsync(HttpContent content, CancellationToken token, int limit = 16 * 1024,
        JsonValueKind expectedKind = JsonValueKind.Object)
    {
        await using var stream = await content.ReadAsStreamAsync(token);
        var buffer = new byte[limit + 1];
        var count = 0;
        while (count < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(count), token);
            if (read == 0) break;
            count += read;
        }
        if (count == buffer.Length) throw new JsonException("Password recovery response exceeds limit.");
        var document = JsonDocument.Parse(buffer.AsMemory(0, count));
        if (document.RootElement.ValueKind != expectedKind) { document.Dispose(); throw new JsonException("Invalid response shape."); }
        return document;
    }
    public void Dispose() { _lifetime.Cancel(); _http.Dispose(); }
}
