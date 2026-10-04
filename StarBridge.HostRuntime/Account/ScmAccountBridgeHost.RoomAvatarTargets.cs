using StarBridge.HostRuntime.PartyRooms;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _roomAvatarGate = new();
    private sealed record RoomAvatarTarget(string Id, string Scope, DateTimeOffset Expires,
        string? RoomId = null, string? ApplicationId = null);
    private readonly Dictionary<string, RoomAvatarTarget> _roomAvatarTargets = new();
    private readonly Dictionary<(string Id, string Scope, string? RoomId, string? ApplicationId), string> _roomAvatarReferences = new();
    private string RegisterRoomTarget(string id, string scope, string? roomId = null, string? applicationId = null)
    {
        var key = (id, scope, roomId, applicationId);
        if (_roomAvatarReferences.Count > 32000) _roomAvatarReferences.Clear();
        var reference = _roomAvatarReferences.TryGetValue(key, out var previous) && _roomAvatarTargets.ContainsKey(previous)
            ? previous : Guid.NewGuid().ToString("N");
        _roomAvatarReferences[key] = reference;
        _roomAvatarTargets[reference] = new(id, scope, DateTimeOffset.UtcNow.AddMinutes(5), roomId, applicationId);
        return reference;
    }
    private RoomDirectoryView ProjectRoomAvatars(RoomDirectoryView directory, BridgeAccountContext context, long generation)
    {
        var scope = FriendScope(context, generation);
        var viewer = RequireRelaySession(context).Legacy?.AccountId;
        lock (_roomAvatarGate)
        {
            foreach (var key in _roomAvatarTargets.Where(p => p.Value.Scope != scope || p.Value.Expires <= DateTimeOffset.UtcNow)
                         .Select(p => p.Key).ToArray()) _roomAvatarTargets.Remove(key);
            if (_roomAvatarTargets.Count > 32000) _roomAvatarTargets.Clear();
            foreach (var key in _roomAvatarTargets.Where(pair => pair.Value.RoomId is not null &&
                         !AuthorizesRoomTarget(directory, pair.Value)).Select(pair => pair.Key).ToArray())
                _roomAvatarTargets.Remove(key);
            return directory with { Rooms = directory.Rooms.Select(room => room with {
                PendingApplications = room.PendingApplications.Select(application => application with {
                    UserRef = string.IsNullOrWhiteSpace(application.AccountId) ? null :
                        RegisterRoomTarget(application.AccountId, scope, room.RoomId, application.ApplicationId)
                }).ToArray(),
                Members = room.Members.Select(member => {
                    if (string.IsNullOrWhiteSpace(member.AccountId)) return member;
                    var reference = RegisterRoomTarget(member.AccountId, scope,
                        directory.CurrentRoomId is null ? room.RoomId : null);
                    var isSelf = member.AccountId == viewer;
                    return member with {
                        UserRef = reference,
                        IsSelf = isSelf,
                        AvatarImageData = RoomAvatarProjection.PreferCurrentAccountAvatar(
                            _legacyAvatarImageData, member.AvatarImageData, isSelf)
                    };
                }).ToArray()
            }).ToArray() };
        }
    }
    private static bool AuthorizesRoomTarget(RoomDirectoryView directory, RoomAvatarTarget target)
    {
        var room = directory.Rooms.SingleOrDefault(room => room.RoomId == target.RoomId);
        if (room is null) return false;
        if (target.ApplicationId is not null)
            return directory.CurrentRoomId == room.RoomId && room.ViewerIsHost &&
                room.PendingApplications.Any(item => item.ApplicationId == target.ApplicationId && item.AccountId == target.Id);
        return directory.CurrentRoomId is null && room.CanPreviewMemberProfiles &&
            StarBridge.Core.PartyRooms.PartyRoomProfilePreviewPolicy.Allows(room.PasswordRequired, room.AdmissionMode, room.Eligibility) &&
            room.Members.Any(member => member.AccountId == target.Id);
    }
    private async Task<string> ResolveRoomAvatarAsync(string reference, string scope, RelayRequestSession session,
        BridgeAccountContext context, long generation, CancellationToken token)
    {
        RoomAvatarTarget target;
        lock (_roomAvatarGate)
        {
            if (!_roomAvatarTargets.TryGetValue(reference, out target!) || target.Scope != scope ||
                target.Expires <= DateTimeOffset.UtcNow) throw new AccountBridgeHostException("users.targetChanged");
        }
        if (target.RoomId is not null)
        {
            var reader = _partyRooms ?? throw new AccountBridgeHostException("users.targetChanged");
            var result = await SendRelayRequestAsync(session, (active, ct) => reader.ReadAsync(active.AccessToken, ct), token);
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(result.ActiveSession, RequireRelaySession(context));
            if (!AuthorizesRoomTarget(result.Result, target))
            {
                lock (_roomAvatarGate) _roomAvatarTargets.Remove(reference);
                throw new AccountBridgeHostException("users.targetChanged");
            }
        }
        return target.Id;
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
            var reference = RegisterRoomTarget(message.SenderAccountId, scope);
            return message with { UserRef = reference };
        }
    }
}
