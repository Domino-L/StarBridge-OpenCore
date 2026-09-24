using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

namespace StarBridge.HostRuntime.PartyRooms;

internal sealed partial class PartyRoomReader
{
    internal async Task<InvitationDeliveryTarget> ResolveInvitationTargetAsync(string bearer, string roomId,
        string scope, Action current, CancellationToken token)
    {
        current();
        var directory = await ReadAsync(bearer, token);
        current();
        if (string.IsNullOrWhiteSpace(roomId) || directory.CurrentRoomId != roomId)
            throw new AccountBridgeHostException("party_rooms.not_member");
        var room = directory.Rooms.SingleOrDefault(room => room.RoomId == roomId)
            ?? throw new AccountBridgeHostException("party_rooms.not_member");
        return new("room", roomId, scope, _endpoint, room.Title)
        {
            RecipientAccountIds = room.Members.Select(member => member.AccountId)
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray()
        };
    }
}
