using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

// Internal only: neither credentials nor the raw AuthResponse cross the Bridge.
internal sealed record LegacyEntitlementResult(string Outcome, ScmOverlayEntitlementSnapshot? Snapshot = null);

internal sealed partial class LegacyPasswordLoginClient
{
    internal Task<LegacyEntitlementResult> ReadEntitlementsAsync(LegacyMigrationCredential credential, CancellationToken token) =>
        SendEntitlementsAsync(credential, null, token);

    internal Task<LegacyEntitlementResult> RedeemEntitlementsAsync(LegacyMigrationCredential credential, string code, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length > 4096 || code.Any(char.IsControl))
            return Task.FromResult(new LegacyEntitlementResult("invalidInput"));
        return SendEntitlementsAsync(credential, code.Trim(), token);
    }

    private async Task<LegacyEntitlementResult> SendEntitlementsAsync(
        LegacyMigrationCredential credential, string? code, CancellationToken token)
    {
        try
        {
            using var request = new HttpRequestMessage(code is null ? HttpMethod.Get : HttpMethod.Post,
                new Uri(_baseUri, code is null ? "api/auth/session" : "api/auth/entitlements/redeem"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
            if (code is not null) request.Content = JsonContent.Create(new { code });
            // Deliberately one send. A timeout is not permission to redeem again.
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                return new("reauthorizationRequired");
            if (response.StatusCode == HttpStatusCode.BadRequest) return new("rejected");
            if (response.StatusCode == HttpStatusCode.TooManyRequests) return new("throttled");
            if (!response.IsSuccessStatusCode) return new(code is null ? "unavailable" : "uncertain");
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 2 * 1024 * 1024);
            var snapshot = ParseLegacyEntitlements(json.RootElement, credential.AccountId);
            token.ThrowIfCancellationRequested();
            return new(code is null ? "ready" : "redeemed", snapshot);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return new(code is null ? "unavailable" : "uncertain"); }
    }

    internal static ScmOverlayEntitlementSnapshot ParseLegacyEntitlements(JsonElement value, string accountId)
    {
        StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore.RejectDuplicates(value);
        if (Text(value, "accountId") != accountId) throw new JsonException();
        var permanent = ReadArray(value, "entitlements").Select(item =>
            item.ValueKind == JsonValueKind.String ? ValidEntitlement(item.GetString()) : throw new JsonException()).ToArray();
        var temporary = ReadArray(value, "temporaryEntitlements").Select(item =>
        {
            if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("expiresAt", out var expires) ||
                expires.ValueKind != JsonValueKind.String || !expires.TryGetDateTimeOffset(out var date)) throw new JsonException();
            return new ScmTemporaryOverlayEntitlementGrant(ValidEntitlement(Text(item, "entitlement")), date);
        }).ToArray();
        return new("ready", accountId, permanent, temporary, DateTimeOffset.UtcNow);
    }

    private static JsonElement[] ReadArray(JsonElement value, string field)
    {
        // Older S2 accounts can omit optional grants; absence never grants access.
        if (!value.TryGetProperty(field, out var items) || items.ValueKind == JsonValueKind.Null) return [];
        if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() > 256) throw new JsonException();
        return items.EnumerateArray().ToArray();
    }

    private static string ValidEntitlement(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= 80 && !value.Any(char.IsControl)
            ? value.Trim() : throw new JsonException();
}
