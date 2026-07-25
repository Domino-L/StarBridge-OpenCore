using StarBridge.Core.Chat;

namespace StarBridge.Core.PartyRooms;

public sealed record PartyRoomMemberStateRequest(
    string? PresenceText,
    string? LocationText,
    string? ShipText,
    string? ShardText);

public sealed record PartyRoomCreateRequest(
    string Title,
    string? Goal,
    string[]? GameplayTagNodeIds,
    string[]? ContextTagIds,
    int Capacity,
    bool IsPublic,
    string? Eligibility,
    string? AdmissionMode,
    bool PasswordEnabled,
    string? Password,
    string? VoiceRequirement,
    string? Language,
    int? RecruitmentDurationMinutes,
    int AutoDisbandHours,
    PartyRoomMemberStateRequest? HostState)
{
    public int TagCatalogVersion { get; init; } = 1;
}

public sealed record PartyRoomResolveCodeRequest(string RoomCode);

public sealed record PartyRoomJoinRequest(
    string RoomId,
    string? Password,
    PartyRoomMemberStateRequest? MemberState)
{
    public string? InvitationId { get; init; }
}

public sealed record PartyRoomInviteCreateRequest(
    string RoomId,
    string TargetAccountId);

public sealed record PartyRoomInvitePreviewRequest(
    string RoomId,
    string InvitationId);

public sealed record PartyRoomInviteActionRequest(
    string RoomId,
    string InvitationId,
    string Action);

public sealed record PartyRoomLeaveRequest(string RoomId);

public sealed record PartyRoomApplicationDecisionRequest(
    string RoomId,
    string ApplicationId,
    bool Approve);

public sealed record PartyRoomUpdateRequest(
    string RoomId,
    string Title,
    string? Goal,
    string[]? GameplayTagNodeIds,
    string[]? ContextTagIds,
    int Capacity,
    bool IsPublic,
    string? Eligibility,
    string? AdmissionMode,
    string? PasswordMode,
    string? Password,
    string? VoiceRequirement,
    string? Language,
    int? RecruitmentDurationMinutes,
    int AutoDisbandHours)
{
    public int TagCatalogVersion { get; init; } = 1;
}

public sealed record PartyRoomChatSendRequest(
    string RoomId,
    string Text,
    ChatAttachmentContract? Attachment = null);

public sealed record PartyRoomChatMessageSnapshot(
    long Sequence,
    string MessageId,
    string Kind,
    string SenderCallsign,
    string SenderGameId,
    string Text,
    DateTimeOffset CreatedAt,
    ChatAttachmentContract? Attachment = null)
{
    public string SenderColor { get; init; } = "#69CCFF";

    public string? SenderAccountId { get; init; }

    public string? SenderAvatarImageData { get; init; }
}

public sealed record PartyRoomChatResponse(
    PartyRoomChatMessageSnapshot[] Messages,
    long LatestSequence,
    DateTimeOffset ServerTime,
    string? Error = null,
    bool HasOlder = false,
    long OldestSequence = 0);

public sealed record PartyRoomChatMutationResponse(
    PartyRoomChatMessageSnapshot? Message,
    string? Error = null);

public sealed record PartyRoomJoinApplicationSnapshot(
    string ApplicationId,
    string Callsign,
    string GameId,
    string? AvatarImageData,
    DateTimeOffset CreatedAt)
{
    public string? AccountId { get; init; }
}

public sealed record PartyRoomMemberSnapshot(
    string AccountId,
    string Callsign,
    string GameId,
    string? AvatarImageData,
    bool IsHost,
    string PresenceText,
    string LocationText,
    string ShipText,
    string ShardText,
    DateTimeOffset LastSeenAt)
{
    public string ChatColor { get; init; } = "#69CCFF";

    public string? PublicProfileId { get; init; }
}

public sealed record PartyRoomSnapshot(
    string RoomId,
    string RoomCode,
    string OwnerAccountId,
    string Title,
    string Goal,
    string[] GameplayTagNodeIds,
    string[] ContextTagIds,
    int Capacity,
    bool IsPublic,
    string Eligibility,
    string AdmissionMode,
    bool PasswordRequired,
    string VoiceRequirement,
    string Language,
    DateTimeOffset? RecruitmentClosesAt,
    DateTimeOffset ExpiresAt,
    PartyRoomMemberSnapshot[] Members,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    int TagCatalogVersion = 1)
{
    public bool ViewerIsHost { get; init; }

    public PartyRoomJoinApplicationSnapshot[] PendingApplications { get; init; } = [];
}

public sealed record PartyRoomDirectoryResponse(
    PartyRoomSnapshot[] Rooms,
    string? CurrentRoomId,
    DateTimeOffset ServerTime)
{
    public PartyRoomInvitationSnapshot[] ReceivedInvitations { get; init; } = [];

    public PartyRoomInvitationSnapshot[] SentInvitations { get; init; } = [];
}

public sealed record PartyRoomInvitationSnapshot(
    string InvitationId,
    string RoomId,
    string RoomTitle,
    string InviterAccountId,
    string InviterCallsign,
    string InviterGameId,
    string? InviterAvatarImageData,
    string RecipientAccountId,
    string RecipientCallsign,
    string RecipientGameId,
    string? RecipientAvatarImageData,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

public sealed record PartyRoomInvitationMutationResponse(
    PartyRoomInvitationSnapshot? Invitation,
    string? Error = null,
    string? Status = null);

public sealed record PartyRoomCloseRequest(string RoomId);

public sealed record PartyRoomMutationResponse(
    PartyRoomSnapshot? Room,
    string? Error = null,
    string? Status = null);
