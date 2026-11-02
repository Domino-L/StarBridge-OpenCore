using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(long? Point, ScmOAuthSession ActiveSession)> ReadMarketplaceReputationAsync(
        ScmOAuthSession session, CancellationToken token)
    {
        var endpoint = new UriBuilder(options.ProfileEndpoint) { Query = "view=self" }.Uri;
        var (profile, active) = await ReadAccountResourceAsync<JsonElement>(session, endpoint,
            ScmAuthDiagnostics.NewCorrelationId(), "marketplace-reputation", token);
        if (!profile.TryGetProperty("subject", out var subject) || subject.GetString() != active.Subject)
            throw new ScmApiProtocolException("SCM reputation owner mismatch.");
        long? point = profile.TryGetProperty("reputation", out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number)
            ? number : null;
        return (point, active);
    }
}

