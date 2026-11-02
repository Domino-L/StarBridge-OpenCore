using System.Net.Http.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.OfficialFleet;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Narrow clock owner shared by V2 transport and the Host's final projection checks.
    // Production uses true UTC; tests may inject their unchanged wire fixture clock.
    internal TimeProvider OfficialFleetIdentityObservationClock { get; init; } = TimeProvider.System;

    internal Task<(IReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation> Result, ScmOAuthSession ActiveSession)>
        ReadOfficialFleetMemberIdentityObservationsAsync(ScmOAuthSession session, string sourceRef,
            IReadOnlyCollection<long> memberIds, CancellationToken token)
    {
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal) ||
            !session.Capabilities.Contains("organizations.read", StringComparer.Ordinal) ||
            !Regex.IsMatch(sourceRef, @"^officialFleet:[1-9][0-9]{0,18}\z") || !long.TryParse(sourceRef[14..], out _) ||
            memberIds.Count is < 1 or > 100 || memberIds.Any(id => id <= 0) || memberIds.Distinct().Count() != memberIds.Count)
            throw OfficialFleetMemberIdentity.Invalid();
        return SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(ct);
            budget.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post,
                new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/official-fleet/member-identities"))
            { Content = JsonContent.Create(new { schemaVersion = 2, sourceRef, memberIds }) };
            request.Headers.Add("X-StarBridge-Member-Identity-Version", "2");
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, budget.Token,
                completionOption: HttpCompletionOption.ResponseHeadersRead);
            await ScmHttpClient.EnsureSuccessAsync(response, "读取舰队成员可见资料", budget.Token);
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, budget.Token, 512 * 1024);
            var result = OfficialFleetMemberIdentityObservation.Parse(json.RootElement, sourceRef, memberIds,
                OfficialFleetIdentityObservationClock.GetUtcNow());
            OfficialFleetMemberIdentityObservation.EnsureCurrent(result.Values, OfficialFleetIdentityObservationClock.GetUtcNow());
            return result;
        }, token);
    }
}
