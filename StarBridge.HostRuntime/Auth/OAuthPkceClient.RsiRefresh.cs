using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal sealed record RsiRefreshResult(int SchemaVersion, string State, long? RemainingMinutes = null);

    // Uses the existing SCM resource session, but never replays this mutation
    // after a rejected or uncertain response. No raw upstream message crosses Bridge.
    internal async Task<(RsiRefreshResult Result, ScmOAuthSession ActiveSession)> RefreshRsiDataAsync(
        ScmOAuthSession session, Func<bool> current, CancellationToken token)
    {
        var active = await EnsureActiveSessionAsync(session, token);
        if (!SameOwner(active, session) || !current()) throw new OperationCanceledException();
        using var request = new HttpRequestMessage(HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/member/user/refresh-rsi-data"));
        using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token,
            requestTimeout: ResourceRequestTimeout, completionOption: HttpCompletionOption.ResponseHeadersRead);
        if (!current()) throw new OperationCanceledException();
        if (response.StatusCode == HttpStatusCode.TooManyRequests) return (new(1, "globalBusy"), active);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            return (new(1, "signInRequired"), active);
        if (!response.IsSuccessStatusCode) return (new(1, "unavailable"), active);
        using var document = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 8 * 1024);
        return (ProjectRsiRefresh(document.RootElement), active);
    }

    internal static RsiRefreshResult ProjectRsiRefresh(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("code", out var code) ||
            code.ValueKind != JsonValueKind.Number || !code.TryGetInt32(out var number)) return new(1, "unavailable");
        if (number is 401 or 403) return new(1, "signInRequired");
        if (number == 429) return new(1, "globalBusy");
        if (number != 0 || !root.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object ||
            !data.TryGetProperty("success", out var success) || success.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            return new(1, "unavailable");
        if (success.GetBoolean())
        {
            if (data.TryGetProperty("fromCache", out var cache))
            {
                if (cache.ValueKind == JsonValueKind.True) return new(1, "cached");
                if (cache.ValueKind is not (JsonValueKind.False or JsonValueKind.Null)) return new(1, "unavailable");
            }
            return new(1, "requested");
        }
        if (data.TryGetProperty("remainingMinutes", out var remaining) && remaining.ValueKind != JsonValueKind.Null)
            return remaining.ValueKind == JsonValueKind.Number && remaining.TryGetInt64(out var minutes) && minutes >= 0
                ? new(1, "rateLimited", minutes) : new(1, "unavailable");
        var message = data.TryGetProperty("message", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() : null;
        return new(1, message switch {
            "请先完成账户验证" or "您的RSI账户状态异常（可能已改名），请重新进行账户验证" or
            "您的RSI账户状态异常（可能已改名或被其他人占用），请重新进行账户验证" => "verificationRequired",
            null or "" => "globalBusy", // Java globalRateLimitExceeded() returns no message or minutes.
            _ => "unavailable"
        });
    }
}
