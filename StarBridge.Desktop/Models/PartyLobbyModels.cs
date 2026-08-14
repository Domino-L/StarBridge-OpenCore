namespace StarBridge.Desktop;

using StarBridge.Core.Chat;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;

public enum PartyLobbyVoiceRequirement
{
    None,
    Recommended,
    Required
}

public enum PartyLobbyAdmissionMode
{
    Direct,
    HostApproval
}

public sealed record PartyLobbyMemberPreview(
    string Callsign,
    string GameId,
    string? AvatarImageData = null,
    bool IsHost = false,
    string? AccountId = null)
{
    public string PresenceText { get; init; } = "在线";

    public string PresenceBrush { get; init; } = "#42CF7C";

    public string LocationText { get; init; } = "等待位置同步";

    public string ShipText { get; init; } = "等待舰船同步";

    public string ShardText { get; init; } = "等待服务器同步";
}

public sealed record PartyLobbyJoinApplicationView(
    string ApplicationId,
    string Callsign,
    string GameId,
    string? AvatarImageData,
    DateTimeOffset CreatedAt)
{
    public string? AccountId { get; init; }

    public string DisplayName => string.IsNullOrWhiteSpace(GameId) ||
                                 Callsign.Equals(GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} ({GameId})";

    public string SubmittedAtText => $"{CreatedAt.ToLocalTime():HH:mm} 提交";
}

public sealed record PartyRoomInvitationActionRow(
    string AccountId,
    string Callsign,
    string GameId,
    string? AvatarImageData,
    string DetailText,
    string PrimaryText,
    string PrimaryAction,
    bool PrimaryEnabled,
    string SecondaryText,
    string SecondaryAction,
    string? RoomId = null,
    string? InvitationId = null)
{
    public string DisplayName => string.IsNullOrWhiteSpace(GameId) ||
                                 Callsign.Equals(GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} ({GameId})";

    public System.Windows.Visibility SecondaryVisibility =>
        string.IsNullOrWhiteSpace(SecondaryAction)
            ? System.Windows.Visibility.Collapsed
            : System.Windows.Visibility.Visible;
}

public sealed record PartyRoomChatMessageView(
    long Sequence,
    string MessageId,
    string Kind,
    string SenderCallsign,
    string SenderGameId,
    string Text,
    DateTimeOffset CreatedAt,
    ChatAttachmentContract? Attachment,
    WpfBrush SenderRoleBrush,
    WpfBrush AttachmentStatusBrush) : System.ComponentModel.INotifyPropertyChanged
{
    private string _timeText = CommunicationTimeFormatter.Format(CreatedAt);
    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
    public string SenderColor { get; init; } = "";

    public string? SenderAccountId { get; init; }

    public string? SenderAvatarImageData { get; init; }

    public bool IsLocal { get; init; }

    public bool IsSystem => Kind.Equals("system", StringComparison.OrdinalIgnoreCase);

    public bool IsSelf => IsLocal;

    public string? AccountId => SenderAccountId;

    public string SenderRoleTitle => "";

    public System.Windows.Visibility RoleVisibility => System.Windows.Visibility.Collapsed;

    public string SenderGameIdText => IsSystem || string.IsNullOrWhiteSpace(SenderGameId) ||
                                      SenderGameId.Equals(SenderCallsign, StringComparison.OrdinalIgnoreCase)
        ? ""
        : $"@ {SenderGameId}";

    public string Initials => GetInitials(string.IsNullOrWhiteSpace(SenderCallsign) ? SenderGameId : SenderCallsign);

    public string SenderDisplay => IsSystem
        ? "系统"
        : string.IsNullOrWhiteSpace(SenderGameId) ||
          SenderCallsign.Equals(SenderGameId, StringComparison.OrdinalIgnoreCase)
            ? SenderCallsign
            : $"{SenderCallsign}（{SenderGameId}）";

    public string TimeText => _timeText;
    public System.Windows.Visibility TextVisibility => ChatAttachmentPresentation.TextVisibility(Text);
    public System.Windows.Visibility AttachmentVisibility => ChatAttachmentPresentation.AttachmentVisibility(Attachment);
    public string AttachmentTitle => Attachment?.Title ?? "";
    public string AttachmentSummary => Attachment?.Summary ?? "";
    public string AttachmentActionText => ChatAttachmentPresentation.ActionText(Attachment);
    public bool AttachmentActionEnabled => ChatAttachmentPresentation.ActionEnabled(Attachment);
    public string AttachmentTypeText => ChatAttachmentPresentation.TypeText(Attachment);
    public string AttachmentStatusText => ChatAttachmentPresentation.StatusText(Attachment);
    public System.Windows.Visibility AttachmentStatusVisibility => ChatAttachmentPresentation.StatusVisibility(Attachment);
    public string AttachmentRoomActivityText => ChatAttachmentPresentation.RoomActivityText(Attachment);
    public string AttachmentRoomFactsText => ChatAttachmentPresentation.RoomFactsText(Attachment);
    public System.Windows.Visibility AttachmentRoomDetailsVisibility => ChatAttachmentPresentation.RoomDetailsVisibility(Attachment);

    public void RefreshTime(DateTimeOffset now)
    {
        var next = CommunicationTimeFormatter.Format(CreatedAt, now);
        if (string.Equals(_timeText, next, StringComparison.Ordinal))
        {
            return;
        }

        _timeText = next;
        PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(TimeText)));
    }

    private static string GetInitials(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return "?";
        }

        var parts = trimmed.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2
            ? string.Concat(parts[0][0], parts[1][0]).ToUpperInvariant()
            : trimmed[..Math.Min(2, trimmed.Length)].ToUpperInvariant();
    }
}

public sealed record PartyLobbyRoomCard(
    string RoomId,
    string Title,
    string Goal,
    string HostDisplay,
    string Activity,
    string[] Tags,
    int MemberCount,
    int Capacity,
    PartyLobbyVoiceRequirement VoiceRequirement,
    PartyLobbyAdmissionMode AdmissionMode,
    bool IsPublic,
    bool PasswordRequired,
    PartyLobbyMemberPreview[] Members,
    DateTimeOffset UpdatedAt)
{
    public string RoomCode { get; init; } = "";

    public PartyRoomEligibility Eligibility { get; init; } = PartyRoomEligibility.Everyone;

    public PartyRoomLanguage Language { get; init; } = PartyRoomLanguage.Chinese;

    public DateTimeOffset? RecruitmentClosesAt { get; init; }

    public DateTimeOffset ExpiresAt { get; init; }

    public string[] GameplayTagNodeIds { get; init; } = [];

    public string[] ContextTagIds { get; init; } = [];

    public int TagCatalogVersion { get; init; }

    public IReadOnlyList<PartyRoomDisplayTag> DisplayTags =>
        PartyRoomTagPresentation.Create(GameplayTagNodeIds, ContextTagIds);

    public bool ViewerIsHost { get; init; }

    public PartyLobbyJoinApplicationView[] PendingApplications { get; init; } = [];

    public bool HasPendingApplications => PendingApplications.Length > 0;

    public string PendingApplicationCountText => $"{PendingApplications.Length} 条待处理";

    public string MemberCountText => $"{MemberCount} / {Capacity}";

    public string GoalDisplay => string.IsNullOrWhiteSpace(Goal) ? "房主未填写目标" : Goal;

    public string VoiceRequirementText => VoiceRequirement switch
    {
        PartyLobbyVoiceRequirement.Required => "语音必须",
        PartyLobbyVoiceRequirement.Recommended => "建议语音",
        _ => "不要求语音"
    };

    public string AdmissionText => AdmissionMode == PartyLobbyAdmissionMode.HostApproval
        ? "需要批准"
        : "直接加入";

    public string VisibilityText => IsPublic ? "公开" : "仅房间码";

    public string PasswordText => PasswordRequired ? "需要密码" : "无需密码";

    public string EligibilityText => Eligibility switch
    {
        PartyRoomEligibility.HostFriends => "仅房主好友",
        PartyRoomEligibility.SameFleet => "仅同舰队成员",
        PartyRoomEligibility.InviteOnly => "仅受邀玩家",
        _ => "所有玩家"
    };

    public string LanguageText => Language switch
    {
        PartyRoomLanguage.English => "English",
        PartyRoomLanguage.Bilingual => "中英双语",
        _ => "中文"
    };

    public string RecruitmentText => RecruitmentClosesAt.HasValue
        ? $"招募至 {RecruitmentClosesAt.Value.ToLocalTime():HH:mm}"
        : "招募不限时";

    public string ExpiresAtText => ExpiresAt == default
        ? "自动解散时间未设置"
        : $"{ExpiresAt.ToLocalTime():MM-dd HH:mm} 自动解散";

    public string AccessSummary => $"{VisibilityText} · {EligibilityText} · {AdmissionText} · {VoiceRequirementText}";

    public string BeaconBrush => MemberCount >= Capacity
        ? "#D9A23B"
        : AdmissionMode == PartyLobbyAdmissionMode.HostApproval
            ? "#69CCFF"
            : "#42CF7C";
}

public sealed record PartyLobbyFilter(
    string SearchText,
    string Activity,
    PartyLobbyVoiceRequirement? VoiceRequirement,
    PartyLobbyAdmissionMode? AdmissionMode)
{
    public bool Matches(PartyLobbyRoomCard room)
    {
        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            var query = SearchText.Trim();
            var matchesText = room.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                              room.Goal.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                              room.HostDisplay.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                              room.Activity.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                              room.Tags.Any(tag => tag.Contains(query, StringComparison.OrdinalIgnoreCase)) ||
                              room.GameplayTagNodeIds.Any(id =>
                                  PartyRoomTagCatalog.GetGameplayPathText(id).Contains(query, StringComparison.OrdinalIgnoreCase));
            if (!matchesText)
            {
                return false;
            }
        }

        if (!string.IsNullOrWhiteSpace(Activity))
        {
            var matchesTree = PartyRoomTagCatalog.TryGetGameplayNode(Activity, out _) &&
                              room.GameplayTagNodeIds.Any(id => PartyRoomTagCatalog.IsNodeOrDescendantOf(id, Activity));
            var matchesLegacy = room.Activity.Equals(Activity, StringComparison.OrdinalIgnoreCase) ||
                                room.Tags.Any(tag => tag.Equals(Activity, StringComparison.OrdinalIgnoreCase));
            if (!matchesTree && !matchesLegacy)
            {
                return false;
            }
        }

        return (!VoiceRequirement.HasValue || room.VoiceRequirement == VoiceRequirement.Value) &&
               (!AdmissionMode.HasValue || room.AdmissionMode == AdmissionMode.Value);
    }
}
