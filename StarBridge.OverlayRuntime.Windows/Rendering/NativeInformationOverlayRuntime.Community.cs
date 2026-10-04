using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime
{
    internal static OverlayModulePresentation ProjectModules(InformationOverlayModuleFrame frame,
        string language, DateTimeOffset now,
        StarBridge.HostRuntime.Presence.GameLogSessionSnapshot? localSession = null,
        StarBridge.Core.Presence.PlayerPresenceKind? localPresence = null)
    {
        var contents = frame.ReadModules(now);
        var projected = new Dictionary<(OverlayResolvedSource, InformationOverlaySourceSnapshot?),
            (OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat)>();
        OverlayModuleScene Project(OverlaySourceModule module, InformationOverlayModuleContent? selected = null)
        {
            var content = selected ?? contents[module];
            var key = (content.Source, content.Snapshot);
            if (!projected.TryGetValue(key, out var scene))
            {
                var preference = content.Source.Mode == OverlaySourceMode.Room
                    ? OverlayScenePreference.PartyRoom : content.Source.Mode == OverlaySourceMode.Community
                    ? OverlayScenePreference.Auto : OverlayScenePreference.Fleet;
                // v2 identities come from Host authority, not WPF's historical
                // matching-handle fallback. In particular events cannot mistake
                // a peer with the same display identity for a local echo.
                var room = content.Snapshot?.Room;
                if (room is not null) room = room with
                { Members = room.Members.Select(member => member with { IsSelf = member.IsSelf == true }).ToArray() };
                scene = ProjectSource(room, content.Snapshot?.Community, preference,
                    language, content.Source.Mode == OverlaySourceMode.Community, localSession, localPresence, explicitSelf: true);
                // In particular, a missing explicit module remains empty: it must
                // not fall through to a room, another organization or local self.
                if (!content.Source.Available)
                    scene = (scene.Scene with { Players = [], HasContent = false }, scene.Command, []);
                projected.Add(key, scene);
            }
            var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            var traditional = language is "zh-Hant" or "zh-TW";
            var label = content.ShowSourceLabel ? content.Source.Mode switch
            {
                OverlaySourceMode.Room => zh ? "当前房间" : "Current room",
                OverlaySourceMode.Community => content.Snapshot?.Community?.Name ?? (zh ? "组织" : "Organization"),
                _ => zh ? "本地模式" : "Local"
            } : null;
            var identity = content.Source.Available
                ? $"{frame.OwnerKey}:{frame.Generation}:{content.Source.ResourceKey}:{content.Snapshot?.Room?.ContinuityId ?? content.Snapshot?.Community?.ContinuityId}"
                : null;
            var chatLabel = content.Source.Mode == OverlaySourceMode.Room
                ? $"{(traditional ? "房間" : zh ? "房间" : "Room")} · {content.Snapshot?.Room?.Title}"
                : $"{(traditional ? "組織" : zh ? "组织" : "Organization")} · {content.Snapshot?.Community?.Name}";
            return new(module is OverlaySourceModule.Notice or OverlaySourceModule.Chat ? scene.Scene with { Players = [] } : scene.Scene,
                module == OverlaySourceModule.Notice ? scene.Command : BuildCommandState(language) with { NoticeTitle = "", NoticeText = "" },
                module == OverlaySourceModule.Chat ? scene.Chat.Select(message => message with { SourceKey = identity, SourceLabel = chatLabel }).ToArray() : [], label, content.Source.Available, identity)
            { ResourceKey = content.Source.ResourceKey, EmptyMessage = OverlayModuleEmptyStates.Message(content.Source, language),
                ChatSourceKeys = module == OverlaySourceModule.Chat && identity is not null ? [identity] : [] };
        }
        var chat = Project(OverlaySourceModule.Chat);
        var chatContents = contents[OverlaySourceModule.Chat].ChatSources;
        if (chatContents is not null)
        {
            var parts = chatContents.Select(content => Project(OverlaySourceModule.Chat, content)).ToArray();
            var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            const string channel = "multi-chat";
            chat = chat with
            {
                Scene = new([], parts.Any(p => p.Available), new(OverlayScenePreference.Auto, OverlaySceneKind.Community,
                    zh ? "聊天" : "CHAT", false, ChatChannelId: channel, ChatChannelTitle: zh ? "聊天" : "CHAT")),
                Chat = parts.SelectMany(p => p.Chat).Select(message => message with { ChannelId = channel }).ToArray(),
                // Stable aggregate identity; individual membership incarnations
                // govern queued messages and watermarks, not the whole module.
                Identity = $"{frame.OwnerKey}:{frame.Generation}:multi-chat",
                Available = parts.Any(p => p.Available), SourceLabel = null, ResourceKey = null,
                ChatSourceKeys = parts.SelectMany(p => p.ChatSourceKeys ?? []).Distinct().Order(StringComparer.Ordinal).ToArray(),
                EmptyMessage = parts.Any(p => p.Available) ? null : language is "zh-Hant" or "zh-TW" ? "所選聊天來源暫不可用" : zh ? "所选聊天来源暂不可用" : "Selected chat sources unavailable"
            };
        }
        return new(Project(OverlaySourceModule.Notice), Project(OverlaySourceModule.Overview),
            Project(OverlaySourceModule.Members), chat, Project(OverlaySourceModule.Events),
            $"{frame.OwnerKey}:{frame.Generation}")
        {
            NextValidationAt = contents.Where(p => p.Value.Source.Available && p.Value.Snapshot is not null)
                .SelectMany(p => p.Key is OverlaySourceModule.Notice or OverlaySourceModule.Chat
                    ? new[] { p.Value.Snapshot!.CommunicationValidUntil }
                    : new[] { p.Value.Snapshot!.RealtimeValidUntil, p.Value.Snapshot!.Lease.ValidUntil })
                .Concat((chatContents ?? []).Where(c => c.Snapshot is not null && c.Source.Available)
                    .Select(c => c.Snapshot!.CommunicationValidUntil))
                .Where(deadline => deadline > now).Select(deadline => (DateTimeOffset?)deadline).Min()
        };
    }

    private string? SafeReadSourceMode() { try { return _sceneModeProvider(); } catch { return "unavailable"; } }
    private static OverlayScenePreference SourcePreference(string? mode, OverlayScenePreference legacy) => mode switch
    {
        null => legacy, "auto" or "community" => OverlayScenePreference.Auto,
        "room" => OverlayScenePreference.PartyRoom, _ => OverlayScenePreference.Fleet
    };
    private static Guid? SourceContinuity(OverlaySceneKind kind,
        InformationOverlayRoomContent? room, InformationOverlayCommunityContent? community) => kind switch
    {
        OverlaySceneKind.PartyRoom => room?.ContinuityId,
        OverlaySceneKind.Community => community?.ContinuityId,
        _ => null
    };
    private InformationOverlayCommunityContent? SafeReadCommunity()
    {
        try { return _communityProvider(); }
        catch { return null; }
    }

    internal static (OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat)
        ProjectSource(InformationOverlayRoomContent? room, InformationOverlayCommunityContent? community,
            OverlayScenePreference preference, string language, bool explicitCommunity = false,
            StarBridge.HostRuntime.Presence.GameLogSessionSnapshot? localSession = null,
            StarBridge.Core.Presence.PlayerPresenceKind? localPresence = null, bool explicitSelf = false)
    {
        var source = InformationOverlaySourcePolicy.Resolve(preference, room is not null,
            hasFleet: false, community is not null, explicitCommunity);
        if (source.Kind == InformationOverlaySourceKind.PartyRoom && source.IsAvailable)
        {
            var projected = ProjectRoom(room, preference, language, explicitSelf);
            return (ProjectLocalSelf(projected.Scene, localSession, localPresence, language), projected.Command, projected.Chat);
        }
        if (source.Kind != InformationOverlaySourceKind.Community || community is null)
        {
            if (source.Kind is InformationOverlaySourceKind.Community or InformationOverlaySourceKind.PartyRoom)
            {
                var kind = source.Kind == InformationOverlaySourceKind.Community ? OverlaySceneKind.Community : OverlaySceneKind.PartyRoom;
                var zhSource = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
                var sourceTitle = kind == OverlaySceneKind.Community ? zhSource ? "组织概况" : "ORGANIZATION OVERVIEW" : zhSource ? "房间概况" : "PARTY OVERVIEW";
                var unavailable = kind == OverlaySceneKind.Community ? zhSource ? "组织信息暂不可用" : "Organization information unavailable" : zhSource ? "房间信息暂不可用" : "Room information unavailable";
                return (new([], false, new(preference, kind, "", true)), BuildCommandState(language) with { NoticeTitle = sourceTitle, NoticeText = unavailable }, []);
            }
            return ProjectRoom(null, preference, language);
        }
        var players = community.Members.Select(member =>
            OverlaySceneResolver.CreateRoomPlayer(new(member.Callsign, member.GameId)
            {
                PresenceText = member.Presence, ShipText = member.Ship,
                LocationText = member.Location, ShardText = member.ServerRegion,
                LocationHiddenReason = member.LocationHiddenReason
            }, null, null) with
            {
                Role = member.Role,
                RawShip = member.Ship,
                SharedShip = member.Ship,
                AccountId = member.PreferenceKey,
                IsSelf = member.IsSelf,
                ShipConfidence = "Community",
                LocationConfidence = "Community",
                ArrivalPendingConfirmation = member.ArrivalPendingConfirmation,
                ArrivalTargetCode = member.ArrivalTargetCode,
                ShowMemberActions = false,
                SharedEventTypes = 0,
                RealtimeStateUnknown = member.Presence == "Unknown"
            }).ToArray();
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        var scene = new OverlaySceneSnapshot(players, true,
            new(preference, OverlaySceneKind.Community, community.Name, false,
                ChatChannelId: "organization:" + community.Code, ChatChannelTitle: community.Name));
        var command = BuildCommandState(language) with
        {
            NoticeTitle = community.AnnouncementTitle,
            NoticeText = community.AnnouncementText
        };
        var chat = community.Messages.Select(message => new OverlayChatMessage(message.Sequence,
            "organization:" + community.Code, message.SenderCallsign, message.SenderGameId,
            OverlayMessageText(message, language), message.CreatedAt, message.IsSystem,
            message.IsSelf == true, "")).ToArray();
        return (ProjectLocalSelf(scene, localSession, localPresence, language), command, chat);
    }
}
