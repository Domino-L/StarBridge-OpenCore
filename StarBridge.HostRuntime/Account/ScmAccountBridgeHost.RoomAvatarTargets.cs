using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _roomAvatarGate = new();
    private readonly Dictionary<string, (string Id, string Scope, DateTimeOffset Expires)> _roomAvatarTargets = new();
    private RoomDirectoryView ProjectRoomAvatars(RoomDirectoryView directory, BridgeAccountContext context, long generation)
    {
        var scope = FriendScope(context, generation);
        var viewer = RequireRelaySession(context).Legacy?.AccountId;
        lock (_roomAvatarGate)
        {
            foreach (var key in _roomAvatarTargets.Where(p => p.Value.Scope != scope || p.Value.Expires <= DateTimeOffset.UtcNow)
                         .Select(p => p.Key).ToArray()) _roomAvatarTargets.Remove(key);
            if (_roomAvatarTargets.Count > 32000) _roomAvatarTargets.Clear();
            return directory with { Rooms = directory.Rooms.Select(room => room with {
                Members = room.Members.Select(member => {
                    if (string.IsNullOrWhiteSpace(member.AccountId)) return member;
                    var reference = Guid.NewGuid().ToString("N");
                    _roomAvatarTargets[reference] = (member.AccountId, scope, DateTimeOffset.UtcNow.AddMinutes(5));
                    return member with { UserRef = reference, IsSelf = member.AccountId == viewer };
                }).ToArray()
            }).ToArray() };
        }
    }
    private string ResolveRoomAvatar(string reference, string scope)
    {
        lock (_roomAvatarGate)
        {
            if (_roomAvatarTargets.TryGetValue(reference, out var target) && target.Scope == scope &&
                target.Expires > DateTimeOffset.UtcNow) return target.Id;
        }
        throw new AccountBridgeHostException("users.targetChanged");
    }
    private RoomChatMessageView ProjectRoomMessageAvatar(RoomChatMessageView message, BridgeAccountContext context, long generation)
    {
        if (message.Kind != "player" || string.IsNullOrWhiteSpace(message.SenderAccountId)) return message;
        var scope = FriendScope(context, generation);
        lock (_roomAvatarGate)
        {
            foreach (var key in _roomAvatarTargets.Where(p => p.Value.Scope != scope || p.Value.Expires <= DateTimeOffset.UtcNow)
                         .Select(p => p.Key).ToArray()) _roomAvatarTargets.Remove(key);
            if (_roomAvatarTargets.Count > 32000) _roomAvatarTargets.Clear();
            var reference = Guid.NewGuid().ToString("N");
            _roomAvatarTargets[reference] = (message.SenderAccountId, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            return message with { UserRef = reference };
        }
    }
}
