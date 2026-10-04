namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly SemaphoreSlim _roomSessionGate = new(1, 1);
    private readonly RoomOverlaySession _roomOverlay = new();

    internal event Action RoomOverlayContentChanged
    {
        add => _roomOverlay.ContentChanged += value;
        remove => _roomOverlay.ContentChanged -= value;
    }
    internal event Action<BridgeAccountContext, long, string?> RoomOverlayMembershipConfirmed
    {
        add => _roomOverlay.MembershipConfirmed += value;
        remove => _roomOverlay.MembershipConfirmed -= value;
    }

    public StarBridge.HostRuntime.Overlay.InformationOverlayRoomContent? CurrentRoomOverlay =>
        _roomOverlay.Read(_disposed ? null : GameplayTimeContext, Generation);

    internal (bool Known, string? Room) ReadOverlayPresetTrigger() =>
        _roomOverlay.ReadPresetTrigger(_disposed ? null : GameplayTimeContext, Generation);

    internal StarBridge.HostRuntime.Overlay.InformationOverlaySourceSnapshot? CurrentRoomOverlaySource =>
        _roomOverlay.ReadSource(_disposed ? null : GameplayTimeContext, Generation);

    internal (StarBridge.Core.Overlay.OverlaySourceLease Lease, object Stamp)? PeekRoomOverlayAuthority(BridgeAccountContext owner, long generation) =>
        _disposed || owner != GameplayTimeContext || generation != Generation ? null : _roomOverlay.PeekAuthority(owner, generation);

    internal bool IsRoomOverlaySourceCurrent(StarBridge.HostRuntime.Overlay.InformationOverlaySourceSnapshot snapshot) =>
        _roomOverlay.IsSourceCurrent(_disposed ? null : GameplayTimeContext, Generation, snapshot);

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
                _roomOverlay.ApplyDirectory(context, generation, ProjectRoomOverlayIdentity(directory, context), OverlayLocalHandle());
            else if (result.Status is not ("targets" or "resolved"))
                _roomOverlay.Clear();
            if (payload.TryGetProperty("data", out var data) && data.TryGetProperty("roomId", out var room))
                _roomOverlay.ApplyChat(room.GetString() ?? "", result.Chat, result.Message,
                    data.TryGetProperty("before", out var before) && before.GetInt64() > 0);
            return result;
        }
        catch (AccountBridgeHostException error) when (
            IsRoomChatRead(payload) &&
            CanRetainRoomOverlayAfterRead(error, context, generation)) { throw; }
        catch (OperationCanceledException) when (IsRoomChatRead(payload) && HasValidRoomOverlay(context, generation)) { throw; }
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
            _roomOverlay.ApplyDirectory(context, generation, ProjectRoomOverlayIdentity(result, context), OverlayLocalHandle());
            return ProjectRoomAvatars(result, context, generation);
        }
        catch (AccountBridgeHostException error) when (CanRetainRoomOverlayAfterRead(error, context, generation)) { throw; }
        catch (OperationCanceledException) when (HasValidRoomOverlay(context, generation)) { throw; }
        catch { _roomOverlay.Clear(); throw; }
        finally { _roomSessionGate.Release(); }
    }

    private bool CanRetainRoomOverlayAfterRead(AccountBridgeHostException error, BridgeAccountContext context, long generation) =>
        error.Code == "party_rooms.read_unavailable" && error.Retryable &&
        HasValidRoomOverlay(context, generation);

    private static bool IsRoomChatRead(System.Text.Json.JsonElement payload) =>
        payload.ValueKind == System.Text.Json.JsonValueKind.Object && payload.TryGetProperty("operation", out var operation) &&
        operation.ValueKind == System.Text.Json.JsonValueKind.String && operation.GetString() == "chatRead";

    private bool HasValidRoomOverlay(BridgeAccountContext context, long generation) =>
        !_disposed && generation == Generation && Equals(context, GameplayTimeContext) &&
        // A failed GET grants no new authority or time: keep only the original,
        // still-valid account/room lease. Read also revokes an expired lease.
        _roomOverlay.Read(context, generation) is not null;

    private RoomDirectoryView ProjectRoomOverlayIdentity(RoomDirectoryView directory, BridgeAccountContext context)
    {
        // Overlay reads (including chat preflight) may precede avatar/UI projection.
        // Bind self to the authenticated account, never a callsign or display handle.
        var viewer = RequireRelaySession(context).Legacy?.AccountId;
        return directory with { Rooms = directory.Rooms.Select(room => room with {
            Members = room.Members.Select(member => member with {
                IsSelf = !string.IsNullOrWhiteSpace(viewer) && !string.IsNullOrWhiteSpace(member.AccountId) &&
                    string.Equals(member.AccountId, viewer, StringComparison.Ordinal)
            }).ToArray()
        }).ToArray() };
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
