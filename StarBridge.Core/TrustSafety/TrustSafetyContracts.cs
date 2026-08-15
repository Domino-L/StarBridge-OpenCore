namespace StarBridge.Core.TrustSafety;

public static class NotificationCategories
{
    public const string Social = "social";
    public const string Fleet = "fleet";
    public const string Room = "room";
    public const string System = "system";
    public const string Safety = "safety";
}

public static class NotificationPriorities
{
    public const string Normal = "normal";
    public const string Important = "important";
    public const string ActionRequired = "action_required";
}

public static class NotificationActionTargets
{
    public const string FriendRequests = "friend_requests";
    public const string FriendChat = "friend_chat";
    public const string FleetApplications = "fleet_applications";
    public const string RoomInvitations = "room_invitations";
    public const string RoomApplications = "room_applications";
    public const string MyReports = "my_reports";
    public const string AccountSafety = "account_safety";
    public const string OverlaySettings = "overlay_settings";
}

public sealed record NotificationItemContract(
    string NotificationId,
    string Category,
    string Priority,
    string Title,
    string Body,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ReadAt,
    string ActionLabel,
    string ActionTarget,
    string? ActionEntityId,
    string SourceType,
    string SourceId,
    bool IsAvailable = true,
    int GroupCount = 1);

public sealed record NotificationInboxContract(
    NotificationItemContract[] Items,
    int UnreadCount,
    int ActionRequiredCount,
    DateTimeOffset UpdatedAt);

public sealed record NotificationReadRequestContract(string[] NotificationIds);

public sealed record NotificationReadResponseContract(int UpdatedCount, DateTimeOffset ReadAt);

public static class ReportTargetTypes
{
    public const string User = "user";
    public const string Message = "message";
    public const string Fleet = "fleet";
    public const string Room = "room";
    public const string ShipImage = "ship_image";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        User or Message or Fleet or Room or ShipImage;
}

public static class TrustSafetyEntitlements
{
    public const string ModerateReports = "trust_safety.moderate_reports";
}

public static class ReportReasons
{
    public const string Harassment = "harassment";
    public const string Spam = "spam";
    public const string Impersonation = "impersonation";
    public const string HateOrThreat = "hate_or_threat";
    public const string InappropriateContent = "inappropriate_content";
    public const string FraudOrScam = "fraud_or_scam";
    public const string Privacy = "privacy";
    public const string Other = "other";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        Harassment or Spam or Impersonation or HateOrThreat or InappropriateContent or
        FraudOrScam or Privacy or Other;
}

public static class ReportStatuses
{
    public const string Submitted = "submitted";
    public const string Reviewing = "reviewing";
    public const string Actioned = "actioned";
    public const string NoViolation = "no_violation";

    // Legacy values remain readable so existing persisted reports can be migrated safely.
    public const string Resolved = "resolved";
    public const string Closed = "closed";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        Submitted or Reviewing or Actioned or NoViolation or Resolved or Closed;

    public static string Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        Reviewing => Reviewing,
        Actioned or Resolved => Actioned,
        NoViolation or Closed => NoViolation,
        _ => Submitted
    };
}

public sealed record ReportTargetSnapshotContract(
    string TargetType,
    string TargetId,
    string DisplayName,
    string? Callsign,
    string? GameName,
    DateTimeOffset CapturedAt,
    string? SubjectAccountId = null);

public static class ReportEvidenceCategories
{
    public const string Profile = "profile";
    public const string DirectMessage = "direct_message";
    public const string FleetChat = "fleet_chat";
    public const string RoomChat = "room_chat";
    public const string RoomContent = "room_content";
    public const string ShipImage = "ship_image";
}

public sealed record ReportEvidenceItemContract(
    string EvidenceId,
    string Category,
    string Label,
    string Content,
    DateTimeOffset CapturedAt,
    string? ContextId = null);

public sealed record ReportEvidenceSnapshotContract(
    DateTimeOffset CapturedAt,
    string ScopeExplanation,
    ReportEvidenceItemContract[] Items);

public sealed record ReportAuditEntryContract(
    string EntryId,
    string Actor,
    string FromStatus,
    string ToStatus,
    string InternalNote,
    DateTimeOffset CreatedAt,
    string? ClientRequestId = null,
    string? ContentAction = null);

public static class ReportContentActions
{
    public const string None = "none";
    public const string QuarantineShipImage = "quarantine_ship_image";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        None or QuarantineShipImage;

    public static string Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        QuarantineShipImage => QuarantineShipImage,
        _ => None
    };
}

public static class AccountSanctionTypes
{
    public const string Warning = "warning";
    public const string ChatMute = "chat_mute";
    public const string ProfileRestriction = "profile_restriction";
    public const string RoomCreationRestriction = "room_creation_restriction";
    public const string RoomParticipationRestriction = "room_participation_restriction";
    public const string FleetParticipationRestriction = "fleet_participation_restriction";
    public const string ShipMediaUploadRestriction = "ship_media_upload_restriction";
    public const string SocialRestriction = "social_restriction";
    public const string AccountRestriction = "account_restriction";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        Warning or ChatMute or ProfileRestriction or RoomCreationRestriction or
        RoomParticipationRestriction or FleetParticipationRestriction or
        ShipMediaUploadRestriction or SocialRestriction or AccountRestriction;

    public static string Normalize(string value) => value.Trim().ToLowerInvariant();
}

public sealed record AccountSanctionContract(
    string SanctionId,
    string Type,
    string ReportId,
    string Summary,
    DateTimeOffset IssuedAt,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset? RevokedAt = null);

public sealed record TrustSafetyAccountStatusContract(
    AccountSanctionContract[] ActiveSanctions,
    bool ChatRestricted,
    bool SocialRestricted,
    bool AccountRestricted,
    DateTimeOffset UpdatedAt,
    bool ProfileRestricted = false,
    bool RoomCreationRestricted = false,
    bool RoomParticipationRestricted = false,
    bool FleetParticipationRestricted = false,
    bool ShipMediaUploadRestricted = false);

public sealed record CreateReportRequestContract(
    string TargetType,
    string TargetId,
    string TargetDisplayName,
    string ContextType,
    string? ContextId,
    string Reason,
    string Details,
    string ClientRequestId);

public sealed record ReportRecordContract(
    string ReportId,
    string TargetType,
    string TargetId,
    string TargetDisplayName,
    string ContextType,
    string? ContextId,
    string Reason,
    string Details,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    string? OutcomeSummary = null,
    DateTimeOffset? ResolvedAt = null);

public sealed record MyReportsContract(ReportRecordContract[] Reports, DateTimeOffset UpdatedAt);

public sealed record AdminReportSummaryContract(
    ReportRecordContract Report,
    string ReporterAccountId,
    ReportTargetSnapshotContract TargetSnapshot,
    int AuditEntryCount);

public sealed record AdminReportDetailContract(
    ReportRecordContract Report,
    string ReporterAccountId,
    ReportTargetSnapshotContract TargetSnapshot,
    ReportAuditEntryContract[] AuditTrail,
    AccountSanctionContract[]? Sanctions = null,
    ReportEvidenceSnapshotContract? Evidence = null);

public sealed record AdminReportQueueContract(
    AdminReportSummaryContract[] Reports,
    string? StatusFilter,
    DateTimeOffset UpdatedAt);

public sealed record ReviewReportRequestContract(
    string Status,
    string Reviewer,
    string? InternalNote,
    string? OutcomeSummary,
    string? SanctionType = null,
    int? SanctionDurationHours = null,
    string? ClientRequestId = null,
    string? ContentAction = null);

public static class SanctionAppealStatuses
{
    public const string Submitted = "submitted";
    public const string Reviewing = "reviewing";
    public const string Accepted = "accepted";
    public const string Denied = "denied";

    public static bool IsSupported(string? value) => value?.Trim().ToLowerInvariant() is
        Submitted or Reviewing or Accepted or Denied;

    public static string Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        Reviewing => Reviewing,
        Accepted => Accepted,
        Denied => Denied,
        _ => Submitted
    };
}

public sealed record CreateSanctionAppealRequestContract(
    string SanctionId,
    string Details,
    string ClientRequestId);

public sealed record SanctionAppealRecordContract(
    string AppealId,
    string SanctionId,
    string SanctionType,
    string Details,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    string? OutcomeSummary = null,
    DateTimeOffset? ResolvedAt = null);

public sealed record MySanctionAppealsContract(
    SanctionAppealRecordContract[] Appeals,
    DateTimeOffset UpdatedAt);

public sealed record AdminSanctionAppealSummaryContract(
    SanctionAppealRecordContract Appeal,
    string AccountId,
    string SanctionSummary,
    int AuditEntryCount);

public sealed record AdminSanctionAppealDetailContract(
    SanctionAppealRecordContract Appeal,
    string AccountId,
    AccountSanctionContract Sanction,
    ReportAuditEntryContract[] AuditTrail);

public sealed record AdminSanctionAppealQueueContract(
    AdminSanctionAppealSummaryContract[] Appeals,
    string? StatusFilter,
    DateTimeOffset UpdatedAt);

public sealed record ReviewSanctionAppealRequestContract(
    string Status,
    string Reviewer,
    string? InternalNote,
    string? OutcomeSummary,
    string? ClientRequestId = null);

public static class ReportReviewValidation
{
    public const int MaximumReviewerLength = 80;
    public const int MaximumInternalNoteLength = 2000;
    public const int MaximumOutcomeSummaryLength = 500;

    public static string? Validate(ReviewReportRequestContract? request)
    {
        if (request is null)
        {
            return "审核内容不完整，请重新填写。";
        }

        if (!ReportStatuses.IsSupported(request.Status) ||
            ReportStatuses.Normalize(request.Status) == ReportStatuses.Submitted)
        {
            return "请选择有效的处理状态。";
        }

        if (string.IsNullOrWhiteSpace(request.Reviewer) ||
            request.Reviewer.Trim().Length > MaximumReviewerLength)
        {
            return "请填写有效的审核人名称。";
        }

        if (request.InternalNote?.Trim().Length > MaximumInternalNoteLength)
        {
            return $"内部备注最多可填写 {MaximumInternalNoteLength} 个字符。";
        }

        if (request.OutcomeSummary?.Trim().Length > MaximumOutcomeSummaryLength)
        {
            return $"用户可见说明最多可填写 {MaximumOutcomeSummaryLength} 个字符。";
        }

        var normalizedStatus = ReportStatuses.Normalize(request.Status);
        if (normalizedStatus is ReportStatuses.Actioned or ReportStatuses.NoViolation &&
            string.IsNullOrWhiteSpace(request.OutcomeSummary))
        {
            return "完成审核前，请填写用户可见的处理说明。";
        }

        if (!string.IsNullOrWhiteSpace(request.SanctionType))
        {
            if (normalizedStatus != ReportStatuses.Actioned ||
                !AccountSanctionTypes.IsSupported(request.SanctionType))
            {
                return "当前审核结果不能应用所选处置。";
            }

            var sanctionType = AccountSanctionTypes.Normalize(request.SanctionType);
            if (sanctionType == AccountSanctionTypes.Warning && request.SanctionDurationHours is not null)
            {
                return "警告不需要设置持续时间。";
            }

            if (sanctionType is not AccountSanctionTypes.Warning and not AccountSanctionTypes.AccountRestriction &&
                request.SanctionDurationHours is null)
            {
                return "请为限时处置设置持续时间。";
            }

            if (request.SanctionDurationHours is < 1 or > 87_600)
            {
                return "处置持续时间应在 1 小时到 10 年之间。";
            }
        }

        if (!string.IsNullOrWhiteSpace(request.ContentAction))
        {
            if (!ReportContentActions.IsSupported(request.ContentAction))
            {
                return "请选择有效的内容处理方式。";
            }

            if (ReportContentActions.Normalize(request.ContentAction) != ReportContentActions.None &&
                normalizedStatus != ReportStatuses.Actioned)
            {
                return "只有确认违规后才能下架相关内容。";
            }
        }

        if (request.ClientRequestId?.Trim().Length > ReportValidation.MaximumIdentifierLength)
        {
            return "本次保存请求无效，请重试。";
        }

        return null;
    }
}

public static class SanctionAppealValidation
{
    public const int MaximumDetailsLength = 2000;

    public static string? Validate(CreateSanctionAppealRequestContract? request)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.SanctionId) ||
            string.IsNullOrWhiteSpace(request.ClientRequestId))
        {
            return "申诉内容不完整，请重新填写。";
        }

        if (request.SanctionId.Trim().Length > ReportValidation.MaximumIdentifierLength ||
            request.ClientRequestId.Trim().Length > ReportValidation.MaximumIdentifierLength)
        {
            return "申诉对象无效，请返回后重试。";
        }

        if (string.IsNullOrWhiteSpace(request.Details))
        {
            return "请说明申诉理由。";
        }

        if (request.Details.Trim().Length > MaximumDetailsLength)
        {
            return $"申诉说明最多可填写 {MaximumDetailsLength} 个字符。";
        }

        return null;
    }

    public static string? ValidateReview(ReviewSanctionAppealRequestContract? request)
    {
        if (request is null || !SanctionAppealStatuses.IsSupported(request.Status) ||
            SanctionAppealStatuses.Normalize(request.Status) == SanctionAppealStatuses.Submitted)
        {
            return "请选择有效的申诉处理状态。";
        }

        if (string.IsNullOrWhiteSpace(request.Reviewer) ||
            request.Reviewer.Trim().Length > ReportReviewValidation.MaximumReviewerLength)
        {
            return "请填写有效的审核人名称。";
        }

        if (request.InternalNote?.Trim().Length > ReportReviewValidation.MaximumInternalNoteLength ||
            request.OutcomeSummary?.Trim().Length > ReportReviewValidation.MaximumOutcomeSummaryLength)
        {
            return "申诉处理说明过长，请精简后重试。";
        }

        var status = SanctionAppealStatuses.Normalize(request.Status);
        if ((status is SanctionAppealStatuses.Accepted or SanctionAppealStatuses.Denied) &&
            string.IsNullOrWhiteSpace(request.OutcomeSummary))
        {
            return "完成申诉审核前，请填写用户可见的处理说明。";
        }

        return null;
    }
}

public static class ReportValidation
{
    public const int MaximumDetailsLength = 1000;
    public const int MaximumIdentifierLength = 160;
    public const int MaximumDisplayNameLength = 100;

    public static string? Validate(CreateReportRequestContract? request)
    {
        if (request is null)
        {
            return "举报内容不完整，请重新填写。";
        }

        if (!ReportTargetTypes.IsSupported(request.TargetType))
        {
            return "暂不支持举报此类内容。";
        }

        if (!ReportReasons.IsSupported(request.Reason))
        {
            return "请选择举报原因。";
        }

        if (string.IsNullOrWhiteSpace(request.TargetId) || request.TargetId.Trim().Length > MaximumIdentifierLength ||
            string.IsNullOrWhiteSpace(request.ClientRequestId) || request.ClientRequestId.Trim().Length > MaximumIdentifierLength)
        {
            return "举报对象无效，请返回后重试。";
        }

        if (string.IsNullOrWhiteSpace(request.TargetDisplayName) ||
            request.TargetDisplayName.Trim().Length > MaximumDisplayNameLength)
        {
            return "举报对象名称无效，请返回后重试。";
        }

        if (request.Details?.Trim().Length > MaximumDetailsLength)
        {
            return $"补充说明最多可填写 {MaximumDetailsLength} 个字符。";
        }

        return null;
    }
}
