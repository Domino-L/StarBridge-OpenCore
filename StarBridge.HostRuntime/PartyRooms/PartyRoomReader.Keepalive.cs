using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.PartyRooms;

internal sealed partial class PartyRoomReader
{
    // Host-owned membership proof only. Never accepts Flutter payloads or publishes game state.
    internal async Task<bool> KeepaliveAsync(string bearer, RoomDirectoryView directory, CancellationToken token)
    {
        if (!directory.SupportsMembershipKeepalive || directory.CurrentRoomId is null ||
            !Guid.TryParseExact(directory.ViewerMembershipToken, "N", out _)) return false;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint, "/api/party-rooms/keepalive"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(new { roomId = directory.CurrentRoomId, membershipToken = directory.ViewerMembershipToken });
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.NoContent) return true;
            if (response.StatusCode == HttpStatusCode.Conflict) return false;
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException("party_rooms.forbidden");
            throw new AccountBridgeHostException("party_rooms.keepalive_unavailable", true);
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        { throw new AccountBridgeHostException("party_rooms.keepalive_unavailable", true); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("party_rooms.keepalive_unavailable", true); }
    }
}
