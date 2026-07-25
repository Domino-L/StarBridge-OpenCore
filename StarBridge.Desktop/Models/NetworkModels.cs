namespace StarBridge.Desktop;

public enum FleetInfoPanelKind
{
    Notice,
    CurrentTask,
    ActionPlan
}

public sealed record NetworkPlayerSnapshot(
    string Name,
    string? Callsign,
    string? Fleet,
    string? Squad,
    bool Online,
    string? Ship,
    string? ShipConfidence,
    string? Location,
    string? LocationConfidence,
    DateTimeOffset LastUpdated,
    string? AvatarImageData = null,
    NetworkOwnedShipSnapshot[]? OwnedShips = null,
    string? VisibilityScope = "Fleet",
    bool PersonalHangarSharedWithFleet = false,
    string? ServerShard = null,
    string? ServerRegion = null,
    string? LiveStatus = null,
    string? AccountId = null,
    int SharedEventTypes = (int)PlayerSharedEventTypes.All,
    NetworkPlayerSharedEventSnapshot[]? SharedEvents = null,
    bool FriendsCanViewPresence = true);

public sealed record PlayerPresenceHeartbeatRequest(
    bool Online,
    string? LiveStatus);

public sealed record NetworkPlayerSharedEventSnapshot(
    string Id,
    string Type,
    DateTimeOffset OccurredAt);

public sealed record NetworkOwnedShipSnapshot(
    string Code,
    string DisplayName,
    string Source,
    DateTimeOffset ImportedAt,
    DateTimeOffset SyncedAt = default,
    string? InstanceId = null,
    string? RoleCategory = null);

public sealed record NetworkFleetActivityWindowSnapshot(
    string[]? Days,
    string? StartTime,
    string? EndTime,
    bool EndsNextDay = false);

public sealed record NetworkFleetSnapshot(
    string Name,
    string Code,
    string? Commander,
    string? Description,
    string? Type,
    string? ActiveTime,
    string? JoinPolicy,
    string? LogoText,
    string? LogoImageData,
    NetworkSquadSnapshot[]? Squads,
    int OnlineMembers,
    int TotalMembers,
    string? NoticeTitle,
    string? NoticeContent,
    string? CurrentTaskTitle,
    string? CurrentTaskBrief,
    string? CurrentTaskParticipants,
    string? CurrentTaskRally,
    string? CurrentTaskShip,
    DateTime? CurrentTaskTime,
    NetworkActionPlanSnapshot[]? ActionPlans,
    DateTimeOffset LastUpdated,
    string? OwnerAccount = null,
    NetworkFleetMemberPermissionSnapshot[]? MemberPermissions = null,
    NetworkFleetMemberSnapshot[]? Members = null,
    NetworkFleetEventLogSnapshot[]? EventLog = null,
    int CurrentTaskNoticeRevision = 0,
    NetworkFleetShipSnapshot[]? Ships = null,
    NetworkFleetTaskHistorySnapshot[]? TaskHistory = null,
    NetworkFleetApplicationSnapshot[]? Applications = null,
    bool EmailNotificationsEnabled = true,
    string? BannerImageData = null,
    NetworkFleetActivityWindowSnapshot[]? ActivityWindows = null,
    string? ActiveDaysDescription = null,
    string? ActivityCadence = null,
    string? TimeZoneId = null,
    bool RecruitingEnabled = false,
    string? RecruitingTarget = null,
    string? RecruitingNote = null,
    NetworkFleetInviteSnapshot[]? Invites = null,
    NetworkFleetRoleGroupSnapshot[]? RoleGroups = null,
    bool PublicListingEnabled = true,
    string? PublicMemberScaleMode = null,
    string? PublicShipScaleMode = null,
    bool PublicProfileEnabled = true,
    bool PublicShowDescription = true,
    bool PublicShowTags = true,
    bool PublicShowActiveSystems = true,
    bool PublicShowActivityTime = true,
    bool PublicShowExternalContacts = false,
    string[]? ActiveSystemIds = null,
    string? Language = null,
    string? WebsiteUrl = null,
    NetworkFleetExternalContactSnapshot[]? ExternalContacts = null,
    int PublicShipCount = 0,
    string? PublicShipTypeSummary = null,
    long ProfileRevision = 0,
    DateTimeOffset? NoticePublishedAt = null,
    string? InviteCodeCreationPolicy = null,
    string? FleetInvitationCardPolicy = null);

public sealed record NetworkFleetExternalContactSnapshot(
    string Platform,
    string Value);

public sealed record NetworkFleetInviteSnapshot(
    string Id,
    string Code,
    string CreatedBy,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt,
    int MaxUses,
    int UsedCount,
    string Status,
    string AcceptMode,
    string? CreatedByAccount = null);

public sealed record NetworkFleetApplicationSnapshot(
    string Id,
    string ApplicantGameName,
    string? ApplicantCallsign,
    string? ApplicantAccount,
    string? Message,
    string Status,
    DateTimeOffset CreatedAt,
    string? AvatarImageData = null);

public sealed record NetworkFleetMemberPermissionSnapshot(
    string GameName,
    string? Callsign,
    string RoleTitle,
    bool PermissionEnabled,
    bool CanRemoveMembers,
    bool CanPublishTasks,
    bool CanPublishPlans,
    bool CanManageFleetInfo,
    DateTimeOffset UpdatedAt,
    string? RoleGroupKey = null,
    string[]? ExtraAllowedPermissions = null,
    string[]? ExtraDeniedPermissions = null,
    string? AccountId = null);

public sealed record NetworkFleetRoleGroupSnapshot(
    string Key,
    string DisplayName,
    string Description,
    string Color,
    int SortOrder,
    bool IsSystem,
    bool IsEnabled,
    int MemberCount,
    string[]? Permissions,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record NetworkFleetMemberSnapshot(
    string GameName,
    string? Callsign,
    string RoleTitle,
    string SquadName,
    bool Online,
    string? Ship,
    string? Location,
    DateTimeOffset LastUpdated,
    string? AvatarImageData = null,
    string? LocationConfidence = null,
    string? ServerShard = null,
    string? ServerRegion = null,
    string? LiveStatus = null,
    string? AccountId = null,
    DateTimeOffset JoinedAt = default);

public sealed record NetworkFleetShipSnapshot(
    string Code,
    string DisplayName,
    string OwnerGameName,
    string? OwnerCallsign,
    string? OwnerSquad,
    string? OwnerAvatarImageData,
    DateTimeOffset ImportedAt,
    DateTimeOffset HangarImportedAt = default,
    string? InstanceId = null,
    string? RoleCategory = null,
    string? OwnerAccountId = null);

public sealed record NetworkFleetEventLogSnapshot(
    string Id,
    DateTimeOffset Timestamp,
    string Type,
    string Title,
    string Detail,
    DateTimeOffset EndTimestamp = default,
    int OccurrenceCount = 1);

public sealed record NetworkFleetTaskHistorySnapshot(
    string Key,
    string Title,
    string Brief,
    string Status,
    string Participants,
    string Rally,
    string RequiredShip,
    string PublishedAtText);

public sealed record NetworkSquadSnapshot(
    string Name,
    string? Commander,
    string? Type,
    string? Description,
    string? Mission = null,
    string? RallyPoint = null,
    string? EmblemImageData = null,
    DateTimeOffset UpdatedAt = default,
    string? Id = null);

public sealed record FleetSquadMemberMutationRequest(
    string FleetCode,
    string SquadName,
    string TargetGameName,
    string? TargetCallsign = null);

public sealed record FleetSquadCommanderTransferRequest(
    string FleetCode,
    string SquadName,
    string TargetGameName,
    string? TargetCallsign = null);

public sealed record FleetSquadLeaveRequest(
    string FleetCode,
    string SquadName,
    string? SuccessorGameName = null,
    string? SuccessorCallsign = null);

public sealed record NetworkActionPlanSnapshot(
    string Id,
    string Title,
    string Content,
    DateTime StartTime,
    bool NotifyMembers,
    NetworkActionPlanParticipantSnapshot[]? Participants,
    string Status = "Published",
    DateTimeOffset? CanceledAt = null,
    string? CanceledBy = null,
    string? CancelReason = null,
    DateTimeOffset? ReachedAt = null,
    DateTimeOffset? CompletedAt = null,
    string? CompletedBy = null,
    string? CompletionMode = null,
    DateTimeOffset UpdatedAt = default,
    long Version = 1);

public sealed record NetworkActionPlanParticipantSnapshot(
    string Callsign,
    string GameName,
    string? AvatarPath,
    string Initials,
    string? AvatarImageData = null,
    bool ReminderRequested = false,
    DateTimeOffset? ReminderSentAt = null);

public sealed record AuthRequest(
    string UserName,
    string Password,
    string? GameName,
    string? Email = null,
    string? VerificationCode = null,
    string? Callsign = null);

public sealed record AuthResponse(
    string UserName,
    string? Email,
    string? Callsign,
    string? GameName,
    string Token,
    bool AllowEmailNotifications = true,
    string[]? Entitlements = null,
    TemporaryEntitlementGrant[]? TemporaryEntitlements = null,
    string? AvatarImageData = null,
    string? AccountId = null,
    DateTimeOffset? IdentityBindingConfirmedAt = null,
    DateTimeOffset? IdentityBindingUpdatedAt = null,
    bool? IdentityBindingRequired = null);

public sealed record IdentityBindingUpdateRequest(
    string? GameName,
    bool ReplaceExisting = false);

public sealed record FleetMembershipResponse(string? FleetCode);

public sealed record TemporaryEntitlementGrant(
    string Entitlement,
    DateTimeOffset ExpiresAt);

public sealed record TemporaryEntitlementRedeemRequest(string Code);

public sealed record EmailVerificationRequest(
    string Email);

public sealed record PasswordResetRequest(
    string Email,
    string VerificationCode,
    string NewPassword);

public sealed record ProfileUpdateRequest(
    string? Callsign,
    bool? AllowEmailNotifications = null,
    string? AvatarImageData = null);

public sealed record FeedbackRequest(
    string? Contact,
    string? GameName,
    string? Callsign,
    string Message);

public sealed record UpdateManifest(
    string Version,
    string? DownloadUrl,
    string? PackageUrl,
    string? Notes,
    bool Required = false,
    DateTimeOffset? PublishedAt = null,
    string? DownloadSha256 = null,
    string? PackageSha256 = null,
    string? SignatureKeyId = null,
    string? Signature = null);

public sealed record AppStatsSnapshot(
    long DownloadCount,
    int OnlineUserCount,
    int FleetCount,
    long OverlayUsageSeconds,
    DateTimeOffset UpdatedAt);

public sealed record AppStatsInstallRequest(
    string ClientId,
    string? Version,
    string? Channel = null);

public sealed record AppStatsHeartbeatRequest(
    string ClientId,
    string? Version,
    bool OverlayActive,
    long OverlayUsageSecondsDelta);

public sealed record FleetNotificationRequest(
    string FleetCode,
    string Subject,
    string Body);

public sealed record FleetNoticeUpdateRequest(
    string FleetCode,
    string? Title,
    string? Content,
    NetworkFleetEventLogSnapshot[]? EventLog = null);

public sealed record FleetTaskUpdateRequest(
    string FleetCode,
    string? Title,
    string? Brief,
    string? Participants,
    string? Rally,
    string? Ship,
    DateTime? Time,
    int NoticeRevision,
    NetworkFleetTaskHistorySnapshot[]? TaskHistory = null,
    NetworkFleetEventLogSnapshot[]? EventLog = null);

public sealed record FleetTaskResponseRequest(
    string FleetCode,
    string? TaskTitle,
    DateTime? TaskTime,
    string Response);

public sealed record FleetActionPlansUpdateRequest(
    string FleetCode,
    NetworkActionPlanSnapshot[]? ActionPlans,
    NetworkFleetEventLogSnapshot[]? EventLog = null);

public sealed record FleetActionPlanJoinRequest(
    string FleetCode,
    string PlanId,
    NetworkActionPlanParticipantSnapshot Participant);

public sealed record FleetActionPlanLeaveRequest(
    string FleetCode,
    string PlanId);

public sealed record FleetActionPlanCancelRequest(
    string FleetCode,
    string PlanId,
    long Version,
    string? Reason = null);

public sealed record FleetActionPlanCompleteRequest(
    string FleetCode,
    string PlanId,
    long Version);

public sealed record FleetJoinApplicationRequest(
    string FleetCode,
    string? Message = null);

public sealed record FleetJoinApplicationWithdrawRequest(
    string FleetCode);

public sealed record FleetJoinApplicationStatusResponse(
    string FleetCode,
    string ApplicationId,
    string Status);

public sealed record FleetApplicationDecisionRequest(
    string FleetCode,
    string ApplicationId,
    bool Approve);

public sealed record FleetInviteCreateRequest(
    string FleetCode,
    int ExpiresInDays = 7,
    int MaxUses = 1,
    string AcceptMode = "Direct",
    string Purpose = "code");

public sealed record FleetInviteRevokeRequest(
    string FleetCode,
    string InviteId);

public sealed record FleetInvitePreviewRequest(
    string InviteCode);

public sealed record FleetInviteAcceptRequest(
    string InviteCode);

public sealed record FleetInvitePreviewResponse(
    string FleetCode,
    string FleetName,
    string Commander,
    int TotalMembers,
    string JoinPolicy,
    DateTimeOffset ExpiresAt,
    int RemainingUses,
    string AcceptMode);

public sealed record FleetLeaveRequest(
    string FleetCode,
    string? TransferCommanderTo = null,
    bool ConfirmDisbandIfOwnerAlone = false);

public sealed record FleetMemberPermissionUpdateRequest(
    string FleetCode,
    NetworkFleetMemberPermissionSnapshot Permission,
    NetworkFleetEventLogSnapshot[]? EventLog = null);

public sealed record FleetInfoUpdateRequest(
    string FleetCode,
    string? Description,
    string? Type,
    string? ActiveTime,
    string? JoinPolicy,
    string? LogoText,
    string? LogoImageData,
    string? BannerImageData,
    NetworkFleetEventLogSnapshot[]? EventLog = null,
    bool? EmailNotificationsEnabled = null,
    NetworkFleetActivityWindowSnapshot[]? ActivityWindows = null,
    string? ActiveDaysDescription = null,
    string? ActivityCadence = null,
    string? TimeZoneId = null,
    bool? RecruitingEnabled = null,
    string? RecruitingTarget = null,
    string? RecruitingNote = null,
    NetworkFleetRoleGroupSnapshot[]? RoleGroups = null,
    bool? PublicListingEnabled = null,
    string? PublicMemberScaleMode = null,
    string? PublicShipScaleMode = null,
    bool? PublicProfileEnabled = null,
    bool? PublicShowDescription = null,
    bool? PublicShowTags = null,
    bool? PublicShowActiveSystems = null,
    bool? PublicShowActivityTime = null,
    bool? PublicShowExternalContacts = null,
    bool? ClearLogoImage = null,
    bool? ClearBannerImage = null,
    string[]? ActiveSystemIds = null,
    string? Language = null,
    string? WebsiteUrl = null,
    NetworkFleetExternalContactSnapshot[]? ExternalContacts = null,
    string[]? UpdatedSections = null,
    long? ExpectedProfileRevision = null,
    string? InviteCodeCreationPolicy = null,
    string? FleetInvitationCardPolicy = null);

public sealed record FleetLogDeleteRequest(
    string FleetCode,
    string LogId);

public sealed record FleetSquadsUpdateRequest(
    string FleetCode,
    NetworkSquadSnapshot[]? Squads,
    NetworkFleetEventLogSnapshot[]? EventLog = null);

public sealed record FleetDisbandRequest(
    string FleetCode,
    string Password);

public sealed record FleetMemberMutationRequest(
    string FleetCode,
    string TargetGameName);

public sealed record FleetCommanderTransferRequest(
    string FleetCode,
    string TargetGameName);
