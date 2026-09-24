using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    // Existing WPF account-profile contract. Never send a local profile callsign
    // here: the account and local personal-page drafts have separate owners.
    internal async Task<string> UpdateAvatarAsync(LegacyMigrationCredential credential,
        string imageData, Action requireCurrent, CancellationToken token)
    {
        if (imageData.Length > 700000 || RoomAvatarProjection.Normalize(imageData, 512 * 1024) != imageData)
            throw new AccountBridgeHostException("account.avatar_invalid");
        async Task<JsonDocument> Send(HttpMethod method, object? body)
        {
            requireCurrent();
            using var request = new HttpRequestMessage(method, new Uri(_baseUri,
                method == HttpMethod.Get ? "api/auth/session" : "api/auth/profile"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
            if (body is not null) request.Content = JsonContent.Create(body);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 2 * 1024 * 1024);
            try
            {
                requireCurrent();
                if (Text(json.RootElement, "accountId") != credential.AccountId) throw new JsonException();
                return json;
            }
            catch { json.Dispose(); throw; }
        }
        try
        {
            using var current = await Send(HttpMethod.Get, null);
            // The existing endpoint replaces callsign; preserve the authoritative
            // value, and omit every other unrelated optional preference.
            using var updated = await Send(HttpMethod.Post, new {
                callsign = Text(current.RootElement, "callsign"), avatarImageData = imageData
            });
            if (Avatar(updated.RootElement) != imageData) throw new JsonException();
            return imageData;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { throw new AccountBridgeHostException("account.avatar_unavailable", retryable: true); }
    }
}
