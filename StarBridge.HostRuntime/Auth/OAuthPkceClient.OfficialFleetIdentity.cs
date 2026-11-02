using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.OfficialFleet;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal Task<(IReadOnlyDictionary<long, OfficialFleetMemberIdentity> Result, ScmOAuthSession ActiveSession)>
        ReadOfficialFleetMemberIdentitiesAsync(ScmOAuthSession session, string sourceRef,
            IReadOnlyCollection<long> memberIds, CancellationToken token)
    {
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal) ||
            !session.Capabilities.Contains("organizations.read", StringComparer.Ordinal) ||
            memberIds.Count is < 1 or > 100 || memberIds.Any(id => id <= 0) || memberIds.Distinct().Count() != memberIds.Count)
            throw OfficialFleetMemberIdentity.Invalid();
        return SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(ct);
            budget.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post,
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/official-fleet/member-identities"))
            {
                Content = JsonContent.Create(new { schemaVersion = 1, sourceRef, memberIds })
            };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, budget.Token,
                completionOption: HttpCompletionOption.ResponseHeadersRead);
            await ScmHttpClient.EnsureSuccessAsync(response, "读取舰队成员可见资料", budget.Token);
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, budget.Token, 512 * 1024);
            return OfficialFleetMemberIdentity.Parse(json.RootElement, sourceRef, memberIds);
        }, token);
    }
}
