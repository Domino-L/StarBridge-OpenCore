using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Write-only envelope policy. GET projections retain their existing contracts.
    // The caller may supply a stable domain mapping; null means an unknown refusal.
    private async Task<JsonElement> ReadMarketplaceWriteEnvelopeAsync(
        HttpResponseMessage response, string operation, CancellationToken token,
        Func<long, JsonElement, string?>? knownRejection = null)
    {
        JsonElement envelope;
        if (response.StatusCode == HttpStatusCode.Forbidden)
        {
            try
            {
                using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
                envelope = document.RootElement.Clone();
            }
            catch (JsonException)
            {
                throw new AccountBridgeHostException(HasInsufficientScopeHeader(response)
                    ? "marketplace.reauthorize_required" : "marketplace.forbidden");
            }
        }
        else envelope = await scmHttpClient.ReadJsonAsync<JsonElement>(response, operation, token);

        var valid = envelope.ValueKind == JsonValueKind.Object && envelope.TryGetProperty("code", out var code)
            && code.ValueKind == JsonValueKind.Number && code.TryGetInt64(out _);
        if (valid)
        {
            var value = envelope.GetProperty("code").GetInt64();
            if (value is not (0 or 401 or 403))
                throw new AccountBridgeHostException(SpecificMarketplaceRejection(envelope)
                    ?? knownRejection?.Invoke(value, envelope) ?? "marketplace.trade_rejected");
        }
        if (InsufficientScope(envelope) || response.StatusCode == HttpStatusCode.Forbidden && HasInsufficientScopeHeader(response))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        if (!valid) throw new AccountBridgeHostException("marketplace.unavailable");
        var businessCode = envelope.GetProperty("code").GetInt64();
        if (businessCode == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
        if (businessCode == 403) throw new AccountBridgeHostException("marketplace.forbidden");
        return envelope;
    }

    private static bool HasInsufficientScopeHeader(HttpResponseMessage response) =>
        response.Headers.WwwAuthenticate.Any(header =>
            header.Scheme.Equals("Bearer", StringComparison.OrdinalIgnoreCase) &&
            Regex.Matches(header.Parameter ?? "",
                "(?:^|,)\\s*(?<name>[a-zA-Z_]+)\\s*=\\s*(?:\"(?<quoted>(?:\\\\.|[^\"])*)\"|(?<token>[^,\\s]+))")
                .Any(match => match.Groups["name"].Value.Equals("error", StringComparison.OrdinalIgnoreCase) &&
                    (match.Groups["quoted"].Success ? match.Groups["quoted"].Value : match.Groups["token"].Value) == "insufficient_scope"));

    // Only explicit OAuth insufficient_scope is an authorization-renewal signal.
    // Keep this policy local to the hall; other resource owners retain their error contracts.
    private async Task<JsonElement> ReadMarketplaceEnvelopeAsync(
        HttpResponseMessage response, string operation, CancellationToken token)
    {
        if (response.StatusCode == HttpStatusCode.Forbidden)
        {
            JsonElement body = default;
            try
            {
                using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
                body = document.RootElement.Clone();
            }
            catch (JsonException) { }
            // A concrete business refusal takes precedence over a generic authorization signal.
            if (SpecificMarketplaceRejection(body) is { } specific)
                throw new AccountBridgeHostException(specific);
            if (body.ValueKind == JsonValueKind.Object && body.TryGetProperty("code", out var code) &&
                code.ValueKind == JsonValueKind.Number && code.TryGetInt64(out var businessCode) &&
                businessCode is not (0 or 401 or 403))
                throw new AccountBridgeHostException("marketplace.trade_rejected");
            var scope = HasInsufficientScopeHeader(response);
            throw new AccountBridgeHostException(scope || InsufficientScope(body)
                ? "marketplace.reauthorize_required" : "marketplace.forbidden");
        }
        var envelope = await scmHttpClient.ReadJsonAsync<JsonElement>(response, operation, token);
        if (SpecificMarketplaceRejection(envelope) is { } rejection)
            throw new AccountBridgeHostException(rejection);
        if (InsufficientScope(envelope))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        return envelope;
    }

    private static bool InsufficientScope(JsonElement body) =>
        body.ValueKind == JsonValueKind.Object && body.TryGetProperty("error", out var error) &&
        error.ValueKind == JsonValueKind.String && error.GetString() == "insufficient_scope";

    private static string? SpecificMarketplaceRejection(JsonElement body)
    {
        // Preserve the existing stable business-code projection (ownership, bans, limits, etc.).
        var mapped = TradeRejection(body);
        return mapped == "marketplace.trade_rejected" ? null : mapped;
    }
}
