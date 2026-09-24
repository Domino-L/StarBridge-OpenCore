using System.Text;
using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    internal async Task<ServerHangarMigrationRead> ReadHangarSnapshotAsync(
        LegacyMigrationCredential credential, MigrationOwner owner, CancellationToken token)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_baseUri, "api/profile/me/hangar-snapshot"));
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", credential.AuthToken);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode is System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            response.EnsureSuccessStatusCode();
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 4 * 1024 * 1024);
            token.ThrowIfCancellationRequested();
            return ServerHangarMigrationReader.Read(Encoding.UTF8.GetBytes(json.RootElement.GetRawText()), owner, credential.AccountId);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidDataException or JsonException or ArgumentException or OperationCanceledException)
        {
            throw new AccountBridgeHostException("hangar.migration_unavailable", retryable: true);
        }
    }
}
