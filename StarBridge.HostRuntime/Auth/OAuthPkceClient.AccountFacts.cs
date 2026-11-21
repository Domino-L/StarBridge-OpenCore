using System.Net;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<PersonalProfilePublicFacts?> LoadVisitorAccountFactsAsync(
        ScmOAuthSession session, string target, bool market, CancellationToken token)
    {
        // Read with the already authorized page session. Unlike a page read,
        // failure here must neither refresh authorization nor change page errors.
        var route = market ? "/scm-member/" + Uri.EscapeDataString(target) + "/account-facts"
            : "/account-facts/" + Uri.EscapeDataString(target);
        using var request = new HttpRequestMessage(HttpMethod.Get,
            new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + route));
        using var response = await scmHttpClient.SendAsync(request, session.AccessToken, token);
        if (!response.IsSuccessStatusCode) return null; // Includes market 429.
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 32 * 1024);
        return PersonalProfileAccountFacts.Parse(json.RootElement);
    }

    internal async Task<(PersonalProfilePublicFacts? Facts, ScmOAuthSession ActiveSession)> LoadOwnAccountFactsAsync(
        ScmOAuthSession session, CancellationToken token, Action current)
    {
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal))
            throw new ScmApiForbiddenException("Current authorization requires profile.read.");
        var identity = await LoadBusinessIdentityAsync(session, token, current);
        current();
        var endpoint = new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') +
            "/account-facts/" + Uri.EscapeDataString(identity.BusinessSubjectId));
        var unauthorized = false;
        try
        {
            var result = await SendResourceRequestWithRefreshAndSessionAsync<PersonalProfilePublicFacts?>(
                identity.ActiveSession, async (active, ct) =>
                {
                    current();
                    using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
                    using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
                    current();
                    unauthorized |= response.StatusCode == HttpStatusCode.Unauthorized;
                    await ScmHttpClient.EnsureSuccessAsync(response, "Read account facts", ct);
                    using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, ct, 32 * 1024);
                    current();
                    return PersonalProfileAccountFacts.Parse(json.RootElement);
                }, token, _ => current());
            current();
            return (result.Result, result.ActiveSession);
        }
        catch (ScmRefreshTemporarilyUnavailableException) when (unauthorized)
        {
            // The shared resource reader can wrap an unresolvable 401 as a
            // temporary restore failure. This optional endpoint must not swallow
            // that explicit authorization rejection as an unavailable feature.
            current();
            throw new ScmApiAuthenticationException("Account authorization is required.");
        }
    }
}
