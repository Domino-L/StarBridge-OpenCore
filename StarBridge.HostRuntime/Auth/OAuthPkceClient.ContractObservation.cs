using System.Net.Http.Json;
using StarBridge.HostRuntime.Achievements;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(ContractAchievementReceipt Result, ScmOAuthSession ActiveSession)> ObserveContractAsync(
        ScmOAuthSession session, ContractObservation observation, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        if (!observation.IsValid) throw new ArgumentException("Invalid contract evidence.");
        return await SendResourceRequestAsync(session, async (active, ct) => {
            using var request = new HttpRequestMessage(HttpMethod.Post,
                new Uri(options.AchievementsEndpoint.AbsoluteUri.TrimEnd('/') + "/observations/contract"))
                { Content = JsonContent.Create(observation) };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var receipt = await scmHttpClient.ReadJsonAsync<ContractAchievementReceipt>(response, "Contract observation", ct);
            receipt.Validate(); return receipt;
        }, token, sessionReady);
    }
}
