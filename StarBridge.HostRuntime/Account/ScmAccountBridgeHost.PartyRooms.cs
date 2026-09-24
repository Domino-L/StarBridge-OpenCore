namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly SemaphoreSlim _roomSessionGate = new(1, 1);
    private readonly RoomOverlaySession _roomOverlay = new();

    public StarBridge.HostRuntime.Overlay.InformationOverlayRoomContent? CurrentRoomOverlay =>
        _roomOverlay.Read(_disposed ? null : GameplayTimeContext, Generation);

    public async Task<RoomCommandView> ExecutePartyRoomAsync(BridgeAccountContext context,
        System.Text.Json.JsonElement payload, CancellationToken token)
    {
        await _roomSessionGate.WaitAsync(token);
        var generation = Generation;
        try
        {
            var result = await ExecutePartyRoomCoreAsync(context, payload, token);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            result = ProjectRoomChat(result, OverlayLocalHandle());
            result = result with {
                Chat = result.Chat is { } chat ? chat with {
                    Messages = chat.Messages.Select(m => ProjectRoomMessageAvatar(m, context, generation)).ToArray() } : null,
                Message = result.Message is { } message ? ProjectRoomMessageAvatar(message, context, generation) : null
            };
            if (result.Directory is { } avatarDirectory)
                result = result with { Directory = ProjectRoomAvatars(avatarDirectory, context, generation) };
            var directory = result.AuthorizedOverlayDirectory ?? result.Directory;
            if (directory is not null)
                _roomOverlay.ApplyDirectory(context, generation, directory, OverlayLocalHandle());
            else if (result.Status is not ("targets" or "resolved"))
                _roomOverlay.Clear();
            if (payload.TryGetProperty("data", out var data) && data.TryGetProperty("roomId", out var room))
                _roomOverlay.ApplyChat(room.GetString() ?? "", result.Chat, result.Message,
                    data.TryGetProperty("before", out var before) && before.GetInt64() > 0);
            return result;
        }
        catch { _roomOverlay.Clear(); throw; }
        finally { _roomSessionGate.Release(); }
    }

    private string OverlayLocalHandle() => HangarIdentity is { } identity
        ? StarBridge.Core.Hangar.RsiHangarIdentityPolicy.DisplayHandle(identity.Identity) ?? "" : "";

    internal static RoomCommandView ProjectRoomChat(RoomCommandView result, string verifiedHandle)
    {
        RoomChatMessageView Project(RoomChatMessageView message) => message with {
            // Only the authoritative RSI identity, never the editable callsign.
            IsSelf = message.Kind == "player" && !string.IsNullOrWhiteSpace(verifiedHandle) &&
                string.Equals(message.SenderGameId, verifiedHandle, StringComparison.OrdinalIgnoreCase)
        };
        return result with {
            Chat = result.Chat is { } page ? page with { Messages = page.Messages.Select(Project).ToArray() } : null,
            Message = result.Message is { } sent ? Project(sent) with { IsSelf = sent.Kind == "player" } : null
        };
    }

    private async Task<RoomCommandView> ExecutePartyRoomCoreAsync(BridgeAccountContext context,
        System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _partyRooms ?? throw new AccountBridgeHostException("party_rooms.command_unavailable");
        (RoomCommandView Result, RelayRequestSession ActiveSession) result;
        try
        {
            result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ExecuteAsync(active.AccessToken, payload, ct), token);
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        if (_disposed || generation != Generation)
            throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        _session = result.ActiveSession.Scm;
        return result.Result;
    }

    public async Task<RoomDirectoryView> GetPartyRoomsAsync(BridgeAccountContext context, CancellationToken token)
    {
        await _roomSessionGate.WaitAsync(token);
        var generation = Generation;
        try
        {
            var result = await GetPartyRoomsCoreAsync(context, token);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            _roomOverlay.ApplyDirectory(context, generation, result, OverlayLocalHandle());
            return ProjectRoomAvatars(result, context, generation);
        }
        catch { _roomOverlay.Clear(); throw; }
        finally { _roomSessionGate.Release(); }
    }

    private async Task<RoomDirectoryView> GetPartyRoomsCoreAsync(BridgeAccountContext context, CancellationToken token)
    {
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _partyRooms ?? throw new AccountBridgeHostException("party_rooms.read_unavailable");
        var sequence = Interlocked.Increment(ref _playerActivitySequence);
        try
        {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ReadAsync(active.AccessToken, ct), token);
            if (_disposed || generation != Generation)
                throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            PublishPlayerActivity(context, generation, sequence, Notifications.PlayerActivitySources.Room(result.Result));
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("party_rooms.read_unavailable", true); }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException)
        { throw new AccountBridgeHostException("party_rooms.read_unavailable", true); }
    }
}
