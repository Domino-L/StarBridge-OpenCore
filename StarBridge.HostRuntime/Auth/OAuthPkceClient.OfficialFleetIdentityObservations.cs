using System.Net.Http.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.OfficialFleet;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Narrow clock owner shared by V2 transport and the Host's final projection checks.
    private OfficialFleetServerClock _identityClock = new(TimeProvider.System);
    internal TimeProvider OfficialFleetIdentityObservationClock
    {
        get => _identityClock;
        init => _identityClock = new(value);
    }

    internal Task<(IReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation> Result, ScmOAuthSession ActiveSession)>
        ReadOfficialFleetMemberIdentityObservationsAsync(ScmOAuthSession session, string sourceRef,
            IReadOnlyCollection<long> memberIds, CancellationToken token, Action? current = null)
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
            for (var attempt = 0; ; attempt++)
            {
                var endpoint = new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/official-fleet/member-identities");
                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                { Content = JsonContent.Create(new { schemaVersion = 2, sourceRef, memberIds }) };
                request.Headers.Add("X-StarBridge-Member-Identity-Version", "2");
                request.Headers.CacheControl = new() { NoCache = true, NoStore = true };
                var started = _identityClock.Start();
                current?.Invoke();
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, budget.Token,
                    completionOption: HttpCompletionOption.ResponseHeadersRead);
                current?.Invoke();
                await ScmHttpClient.EnsureSuccessAsync(response, "读取舰队成员可见资料", budget.Token);
                using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, budget.Token, 512 * 1024);
                var result = OfficialFleetMemberIdentityObservation.Parse(json.RootElement, sourceRef, memberIds,
                    OfficialFleetIdentityObservationClock.GetUtcNow(), checkTime: false);
                // Only a successful, bounded, structurally valid response from this exact trusted resource route is a sample.
                _identityClock.Observe(started, response, json.RootElement, endpoint);
                try { OfficialFleetMemberIdentityObservation.EnsureCurrent(result.Values, _identityClock); return result; }
                catch (AccountBridgeHostException error) when (attempt == 0 && _identityClock.NeedsConfirmation &&
                    error.Code is "official_fleet.identity_time_invalid" or "official_fleet.identity_clock_skew")
                { /* One bounded repeat confirms a candidate, never extends the first proof's TTL. */ }
            }
        }, token);
    }
}
