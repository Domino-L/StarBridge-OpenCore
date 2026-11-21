using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    /// <summary>The whole optional visitor facts read, zones included. The client
    /// gives the visitor request 15 seconds; a slow facts endpoint must leave the
    /// page enough of them (CX-OWNER-FACTS-073-R).</summary>
    internal static TimeSpan VisitorAccountFactsBudget = TimeSpan.FromSeconds(3);

    // Caller must first obtain the full visitor page, and must finish the usual
    // session/target rechecks after this read (including failures and zone waits).
    private async Task<PersonalProfilePublicFacts?> ReadVisitorAccountFactsAsync(
        ScmOAuthSession session, string target, bool market, CancellationToken token)
    {
        try
        {
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
            budget.CancelAfter(VisitorAccountFactsBudget);
            var facts = await _oauth.LoadVisitorAccountFactsAsync(session, target, market, budget.Token);
            return facts?.TimezoneId is not null
                ? WithFactOffset(facts, await PublicFactZonesAsync(budget.Token)) : facts;
        }
        catch (Exception)
        {
            // Optional decoration: no diagnostics, target identity, error-code
            // changes, session refresh, or retry. The page's final checks remain authoritative.
            return null;
        }
    }

    public async Task<object> ReadAccountFactsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        // There is deliberately no target parameter: the authenticated business
        // identity is resolved inside OAuthPkceClient for this session only.
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 1 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
            !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("profile.account_facts_invalid");
        var generation = Generation;
        var owner = RequireRelaySession(context);
        void Current()
        {
            if (_disposed || generation != Generation)
                throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(owner, RequireRelaySession(context));
        }
        object Project(PersonalProfilePublicFacts? facts) => new Dictionary<string, object?>
        { ["schemaVersion"] = 1, ["facts"] = facts?.ToPayload() };
        Current();
        if (owner.Scm is null) return Project(null);
        try
        {
            var result = await _oauth.LoadOwnAccountFactsAsync(owner.Scm, token, Current);
            Current();
            RequireSameSession(owner.Scm, result.ActiveSession);
            CommitSharingSession(owner, new RelayRequestSession(result.ActiveSession));
            var facts = result.Facts;
            if (facts?.TimezoneId is not null)
                facts = WithFactOffset(facts, await PublicFactZonesAsync(token));
            Current();
            return Project(facts);
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (Exception error) when (error is HttpRequestException or IOException or TimeoutException or
            OperationCanceledException or JsonException or InvalidOperationException or FormatException or KeyNotFoundException)
        {
            // No response body, path, subject or session is logged for this optional read.
            // Even a failed old request must not be delivered into a new account.
            Current();
            return Project(null);
        }
    }
}
