using System.Net.Http;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Existing SCM core PermitAll routes. The resource server's OAuth token
    // never goes to this public contract; no new authentication scope.
    internal async Task<JsonDocument> ReadPublicOrganizationAsync(string query, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get,
            new Uri(options.AuthorizationServerBaseUri, "app-api/member/organization/" + query));
        using var response = await scmHttpClient.SendAsync(request, cancellationToken: deadline.Token,
            completionOption: HttpCompletionOption.ResponseHeadersRead);
        await ScmHttpClient.EnsureSuccessAsync(response, "舰队公开资料", deadline.Token);
        using var envelope = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, deadline.Token, 1024 * 1024);
        var body = envelope.RootElement;
        if (!body.TryGetProperty("code", out var code) || !code.TryGetInt32(out var number) || number != 0 ||
            !body.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object)
            throw OfficialFleet.OfficialFleetReadModel.Invalid();
        return JsonDocument.Parse(data.GetRawText());
    }
}
