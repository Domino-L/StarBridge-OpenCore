using System.Net.Http.Headers;
using System.Net.Http.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    // Still-live WPF identity contract, exclusively for the legacy session.
    // Unlike RestoreAsync this never deletes or promotes stored credentials.
    internal async Task<ScmGameIdentitySnapshot> ReadHandleAsync(LegacyMigrationCredential credential,
        Action requireCurrent, CancellationToken token) =>
        await SendHandleAsync(credential, null, requireCurrent, token);

    internal async Task<ScmGameIdentitySnapshot> WriteHandleAsync(LegacyMigrationCredential credential,
        string handle, Action requireCurrent, CancellationToken token) =>
        await SendHandleAsync(credential, handle, requireCurrent, token);

    private async Task<ScmGameIdentitySnapshot> SendHandleAsync(LegacyMigrationCredential credential,
        string? handle, Action requireCurrent, CancellationToken token)
    {
        requireCurrent();
        using var request = new HttpRequestMessage(handle is null ? HttpMethod.Get : HttpMethod.Put,
            new Uri(_baseUri, handle is null ? "api/auth/session" : "api/auth/identity-binding"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
        if (handle is not null) request.Content = JsonContent.Create(new { gameName = handle, replaceExisting = true });
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (handle is not null && response.StatusCode is System.Net.HttpStatusCode.BadRequest or
            System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden or System.Net.HttpStatusCode.Conflict)
            throw new AccountBridgeHostException("identity.change_rejected");
        response.EnsureSuccessStatusCode();
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 2 * 1024 * 1024);
        requireCurrent();
        if (Text(json.RootElement, "accountId") != credential.AccountId)
            throw new AccountBridgeHostException("identity.account_changed");
        var identity = Identity(json.RootElement);
        if (identity.Status != ScmGameIdentityStatus.Verified || !IdentityBindingPolicy.IsValidGameName(identity.Handle))
            throw new AccountBridgeHostException("identity.read_unavailable");
        return identity;
    }
}
