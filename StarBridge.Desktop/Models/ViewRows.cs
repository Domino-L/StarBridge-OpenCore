using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using StarBridge.Core.Presence;
using MediaBrush = System.Windows.Media.Brush;
using MediaColor = System.Windows.Media.Color;
using MediaSolidBrush = System.Windows.Media.SolidColorBrush;

namespace StarBridge.Desktop;

public sealed record PlayerRow(
    string Name,
    string Status,
    string Ship,
    string ShipInfo,
    string Location,
    string? Callsign = null,
    string? AvatarPath = null,
    string Initials = "?",
    string Role = "Member",
    MediaBrush? NameBrush = null,
    string RawShip = "Unknown",
    string ShipConfidence = "None",
    string LocationConfidence = "None",
    string RawLocation = "Unknown",
    bool IsSelf = false,
    bool ShowMemberActions = true,
    string? ServerShard = null,
    string? ServerRegion = null,
    string? LiveStatus = null,
    MediaBrush? RoleBrush = null,
    string? AccountId = null,
    string? SharedOnlineStatus = null,
    string? SharedLiveStatus = null,
    string? SharedShip = null,
    string? SharedLocation = null,
    int SharedEventTypes = (int)PlayerSharedEventTypes.All,
    bool? SharedHasServerSession = null,
    bool IsFleetCommander = false,
    MediaBrush? RoleColorBrush = null,
    bool HasFleetPosition = false)
{
    // Callsign 在无呼号时回落为游戏 ID（DisplayCallsign），此时两行会重复，故留空。
    public string GameId => string.Equals(Name, Callsign, StringComparison.OrdinalIgnoreCase)
        ? ""
        : Name;
    public PlayerPresenceKind Presence => PlayerPresencePresentation.Resolve(LiveStatus, Status);
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public MediaBrush StatusBrush => PlayerPresencePresentation.Brush(Presence);
    public string SharedOnlineStatusValue => SharedOnlineStatus ?? Status;
    public string? SharedLiveStatusValue => SharedLiveStatus ?? LiveStatus;
    public PlayerPresenceKind SharedPresence => PlayerPresencePresentation.ResolveShared(SharedLiveStatusValue, SharedOnlineStatusValue);
    public string SharedPresenceText => PlayerPresencePresentation.Format(SharedPresence);
    public MediaBrush SharedStatusBrush => PlayerPresencePresentation.Brush(SharedPresence);
    public string SharedShipText => SharedShip ?? Ship;
    public string SharedLocationText => SharedLocation ?? Location;
    public string SharedShipDisplayText => ShipDisplayNamePresentation.ResolveChinese(
        PlayerSessionStatePresentation.ResolveShip(
            SharedPresence,
            ResolveSharedServerSession(),
            SharedShipText),
        ShipDisplayNamePresentation.UnknownShip);
    public string SharedLocationDisplayText => PlayerSessionStatePresentation.ResolveLocation(
        SharedPresence,
        ResolveSharedServerSession(),
        SharedLocationText);
    internal FleetServerRelationshipKind? ResolvedServerRelationship { get; init; }
    // The legacy property name is retained for XAML compatibility. The member
    // table now presents a localized region, never a relationship label or a
    // concrete shard identifier.
    public string ServerRelationshipText => GameServerRegionPresentation.Resolve(
        SharedPresence,
        ServerRegion,
        ServerShard,
        zh: true);
    public string ServerShardDisplayText =>
        SharedPresence == PlayerPresenceKind.InGame &&
        PlayerSessionStatePresentation.HasRecognizedValue(ServerShard)
            ? ServerShard!.Trim()
            : "未进入游戏";
    internal bool MatchesFleetSearch(string? searchText) =>
        FleetRosterSearchPolicy.Matches(
            searchText,
            Name,
            Callsign,
            Role,
            ServerRelationshipText,
            SharedPresenceText,
            SharedShipDisplayText,
            SharedLocationDisplayText);
    internal bool AllowsSharedEvent(PlayerSharedEventTypes eventType) =>
        PlayerEventSharingSettings.FromWireValue(SharedEventTypes).HasFlag(eventType);
    public Visibility MemberActionVisibility => ShowMemberActions && !IsSelf ? Visibility.Visible : Visibility.Collapsed;

    private bool? ResolveSharedServerSession()
    {
        if (SharedPresence != PlayerPresenceKind.InGame)
        {
            return false;
        }

        if (SharedHasServerSession.HasValue)
        {
            return SharedHasServerSession.Value;
        }

        return PlayerSessionStatePresentation.HasRecognizedValue(ServerShard) ||
               PlayerSessionStatePresentation.HasRecognizedValue(ServerRegion)
            ? true
            : null;
    }
}

public sealed class SpecifiedVisibilityMemberRow : INotifyPropertyChanged
{
    private bool _isSelected;

    public required string AccountId { get; init; }
    public required string Callsign { get; init; }
    public required string GameId { get; init; }
    public string? AvatarPath { get; init; }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value)
            {
                return;
            }

            _isSelected = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsSelected)));
        }
    }

    public string IdentityLine => string.Equals(Callsign, GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} · {GameId}";

    public event PropertyChangedEventHandler? PropertyChanged;
}

public sealed record ManageFleetSystemOptionRow(
    string Id,
    string Name,
    string ChineseName,
    string ImagePath,
    string Detail,
    bool IsImageAvailable)
{
    public string DisplayTitle => string.IsNullOrWhiteSpace(ChineseName) ? Name : $"{Name} / {ChineseName}";
    public Visibility ImageVisibility => IsImageAvailable ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PlaceholderVisibility => IsImageAvailable ? Visibility.Collapsed : Visibility.Visible;
    public string AvailabilityText => IsImageAvailable ? "本地素材已就绪" : $"等待本地文件：{ImagePath}";
}

public sealed record FleetTimeZoneOptionRow(
    string Id,
    string DisplayName)
{
    public override string ToString() => DisplayName;
}

public sealed class FleetExternalContactRow
{
    public FleetExternalContactRow(string platform = "QQ", string value = "")
    {
        Platform = string.IsNullOrWhiteSpace(platform) ? "QQ" : platform.Trim();
        Value = value ?? "";
    }

    public string Platform { get; set; }

    public string Value { get; set; }

    public Visibility CommunicationVisibility =>
        !string.IsNullOrWhiteSpace(Platform) && !string.IsNullOrWhiteSpace(Value)
            ? Visibility.Visible
            : Visibility.Collapsed;
}

internal static class StatusPalette
{
    public static MediaBrush InfoBrush { get; } = Brush(0x52, 0xB7, 0xF5);
    public static MediaBrush SuccessBrush { get; } = Brush(0x43, 0xD8, 0x7A);
    public static MediaBrush WarningBrush { get; } = Brush(0xD9, 0xA4, 0x41);
    public static MediaBrush DangerBrush { get; } = Brush(0xD2, 0x68, 0x5E);
    public static MediaBrush DisabledBrush { get; } = Brush(0x46, 0x54, 0x5D);

    public static MediaBrush ForOnlineState(string? status)
    {
        return PlayerPresencePresentation.Brush(PlayerPresencePresentation.ResolveShared(status, status));
    }

    public static MediaBrush ForTaskStatus(string? status)
    {
        var value = status ?? "";
        if (value.Contains("删除", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("取消", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("失败", StringComparison.OrdinalIgnoreCase))
        {
            return DangerBrush;
        }

        if (value.Contains("完成", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("成功", StringComparison.OrdinalIgnoreCase))
        {
            return SuccessBrush;
        }

        if (value.Contains("进行", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("待", StringComparison.OrdinalIgnoreCase))
        {
            return WarningBrush;
        }

        return InfoBrush;
    }

    public static MediaBrush ForEvent(string? type, string? title)
    {
        var text = $"{type} {title}";
        if (text.Contains("删除", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("取消", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("关闭", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("移除", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("解散", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("失败", StringComparison.OrdinalIgnoreCase))
        {
            return DangerBrush;
        }

        if (text.Contains("完成", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("加入", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("创建", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("启用", StringComparison.OrdinalIgnoreCase))
        {
            return SuccessBrush;
        }

        if (text.Contains("任务", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("计划", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("待", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("再次通知", StringComparison.OrdinalIgnoreCase))
        {
            return WarningBrush;
        }

        return InfoBrush;
    }

    public static MediaBrush? TryBrushFromHex(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex))
        {
            return null;
        }

        try
        {
            var color = (MediaColor)System.Windows.Media.ColorConverter.ConvertFromString(hex.Trim());
            var brush = new MediaSolidBrush(color);
            brush.Freeze();
            return brush;
        }
        catch
        {
            return null;
        }
    }

    public static MediaBrush BrushFromHex(string? hex, MediaBrush fallback) =>
        TryBrushFromHex(hex) ?? fallback;

    private static MediaBrush Brush(byte red, byte green, byte blue)
    {
        var brush = new MediaSolidBrush(MediaColor.FromRgb(red, green, blue));
        brush.Freeze();
        return brush;
    }

}

public static class FleetShipSpecPalette
{
    public const string Capital = "#C99CFF";
    public const string Large = "#8FCBFF";
    public const string Medium = "#75C9D6";
    public const string Small = "#7EDBA0";
    public const string Unknown = "#9DAAB3";

    public static string Resolve(string shipSpec) => shipSpec switch
    {
        "旗舰级" => Capital,
        "大型" => Large,
        "中型" => Medium,
        "小型" => Small,
        _ => Unknown
    };
}

public sealed record FleetShipInventoryRow(
    int Number,
    string ShipName,
    string ShipCode,
    string OwnerDisplay,
    string OwnerCallsign,
    string OwnerGameId,
    string? OwnerAvatarPath,
    string OwnerInitials,
    string ImportedAtText,
    string FleetSharedAtText,
    string ShipSpec,
    string ShipRole,
    string ShipStatus,
    string ShipPrice,
    string ShipImagePath = "",
    string? ShipInstanceId = null,
    string ShipRoleColorHex = "#9DAAB3",
    string? OwnerAccountId = null,
    string? CustomImageMediaId = null,
    bool CanReportCustomImage = false,
    double CustomImageCropFocusX = 0.5,
    double CustomImageCropFocusY = 0.5,
    double CustomImageCropZoom = 1.0,
    string OwnerOnlineStatus = "Offline",
    string? OwnerLiveStatus = null)
{
    private BadgePalette RoleBadgePalette { get; } = CreateSoftBadgePalette(ShipRoleColorHex);

    public IReadOnlyList<FleetShipInventoryRow> LoanerRows { get; init; } = [];
    public bool HasLoaners => LoanerRows.Count > 0;
    public bool HasCustomImage => !string.IsNullOrWhiteSpace(CustomImageMediaId);
    public Visibility ShipImageReportVisibility => CanReportCustomImage ? Visibility.Visible : Visibility.Collapsed;
    public PlayerPresenceKind OwnerPresence => PlayerPresencePresentation.ResolveShared(OwnerLiveStatus, OwnerOnlineStatus);
    public string OwnerPresenceText => PlayerPresencePresentation.Format(OwnerPresence);
    public MediaBrush OwnerPresenceBrush => PlayerPresencePresentation.Brush(OwnerPresence);
    public string ShipDetailImagePath => BuildShipDetailImagePath(ShipImagePath);
    public string ShipMetaLine => $"{ShipSpec} / {ShipStatus} / {ShipPrice}";
    public string ShipRoleTag => string.IsNullOrWhiteSpace(ShipRole) ? "待补充" : ShipRole;
    public string ShipPriceTag => string.IsNullOrWhiteSpace(ShipPrice) ? "未公布" : ShipPrice;
    public string ImportedAtCompactText => FormatImportedAtCompactText(ImportedAtText);
    public string FleetSharedAtCompactText => FormatImportedAtCompactText(FleetSharedAtText);
    public decimal? ShipPriceValue => TryReadPrice(ShipPrice, out var price) ? price : null;
    public MediaBrush ShipSpecBrush => ShipSpec switch
    {
        "旗舰级" => CapitalShipBrush,
        "大型" => LargeShipBrush,
        "中型" => MediumShipBrush,
        "小型" => SmallShipBrush,
        _ => NeutralShipBrush
    };
    public MediaBrush ShipSpecBadgeBackgroundBrush => SelectSpecBadgePalette().Background;
    public MediaBrush ShipSpecBadgeBorderBrush => SelectSpecBadgePalette().Border;
    public MediaBrush ShipSpecBadgeTextBrush => SelectSpecBadgePalette().Text;

    public MediaBrush ShipStatusBrush => ShipStatus == "可飞" ? FlyableShipBrush : ConceptShipBrush;
    public MediaBrush ShipStatusBadgeBackgroundBrush => SelectStatusBadgePalette().Background;
    public MediaBrush ShipStatusBadgeBorderBrush => SelectStatusBadgePalette().Border;
    public MediaBrush ShipStatusBadgeTextBrush => SelectStatusBadgePalette().Text;
    public MediaBrush ShipStatusLineBrush
    {
        get
        {
            if (ShipStatus.Equals("可飞", StringComparison.OrdinalIgnoreCase) ||
                ShipStatus.Equals("Flyable", StringComparison.OrdinalIgnoreCase))
            {
                return FlyableShipBrush;
            }

            if (ShipStatus.Contains("概念", StringComparison.OrdinalIgnoreCase) ||
                ShipStatus.Contains("Concept", StringComparison.OrdinalIgnoreCase))
            {
                return ConceptLineShipBrush;
            }

            if (ShipStatus.Contains("不可", StringComparison.OrdinalIgnoreCase) ||
                ShipStatus.Contains("unflyable", StringComparison.OrdinalIgnoreCase))
            {
                return UnflyableShipBrush;
            }

            if (ShipStatus.Contains("未知", StringComparison.OrdinalIgnoreCase) ||
                ShipStatus.Contains("unknown", StringComparison.OrdinalIgnoreCase))
            {
                return UnknownShipBrush;
            }

            return DefaultShipLineBrush;
        }
    }

    public MediaBrush ShipPriceBrush
    {
        get
        {
            if (!TryReadPrice(ShipPrice, out var price))
            {
                return NeutralShipBrush;
            }

            return price switch
            {
                <= 120 => PriceTierOneShipBrush,
                <= 300 => PriceTierTwoShipBrush,
                <= 600 => PriceTierThreeShipBrush,
                <= 999 => PriceTierFourShipBrush,
                <= 4999 => PriceTierFiveShipBrush,
                _ => PriceTierSixShipBrush
            };
        }
    }
    public MediaBrush ShipPriceBadgeBackgroundBrush => SelectPriceBadgePalette().Background;
    public MediaBrush ShipPriceBadgeBorderBrush => SelectPriceBadgePalette().Border;
    public MediaBrush ShipPriceBadgeTextBrush => SelectPriceBadgePalette().Text;

    public MediaBrush ShipRoleBrush => RoleBadgePalette.Text;
    public MediaBrush ShipRoleBadgeBackgroundBrush => RoleBadgePalette.Background;
    public MediaBrush ShipRoleBadgeBorderBrush => RoleBadgePalette.Border;
    public MediaBrush ShipRoleBadgeTextBrush => RoleBadgePalette.Text;

    private BadgePalette SelectSpecBadgePalette() => ShipSpec switch
    {
        "旗舰级" => CapitalSpecBadgePalette,
        "大型" => LargeSpecBadgePalette,
        "中型" => MediumSpecBadgePalette,
        "小型" => SmallSpecBadgePalette,
        _ => UnknownSpecBadgePalette
    };

    private BadgePalette SelectStatusBadgePalette()
    {
        if (ShipStatus.Equals("可飞", StringComparison.OrdinalIgnoreCase) ||
            ShipStatus.Equals("Flyable", StringComparison.OrdinalIgnoreCase))
        {
            return FlyableStatusBadgePalette;
        }

        if (ContainsAny(ShipStatus, "概念", "concept"))
        {
            return ConceptStatusBadgePalette;
        }

        if (ContainsAny(ShipStatus, "不可", "unflyable"))
        {
            return UnflyableStatusBadgePalette;
        }

        return UnknownStatusBadgePalette;
    }

    private BadgePalette SelectPriceBadgePalette()
    {
        if (!TryReadPrice(ShipPrice, out var price))
        {
            return UnknownPriceBadgePalette;
        }

        return price switch
        {
            <= 120 => PriceTierOneBadgePalette,
            <= 300 => PriceTierTwoBadgePalette,
            <= 600 => PriceTierThreeBadgePalette,
            <= 999 => PriceTierFourBadgePalette,
            <= 4999 => PriceTierFiveBadgePalette,
            _ => PriceTierSixBadgePalette
        };
    }

    private static BadgePalette CreateSoftBadgePalette(string colorHex)
    {
        MediaColor color;
        try
        {
            color = (MediaColor)System.Windows.Media.ColorConverter.ConvertFromString(colorHex);
        }
        catch (FormatException)
        {
            color = MediaColor.FromRgb(157, 170, 179);
        }

        return CreateSoftBadgePalette(color);
    }

    private static BadgePalette CreateSoftBadgePalette(byte red, byte green, byte blue) =>
        CreateSoftBadgePalette(MediaColor.FromRgb(red, green, blue));

    private static BadgePalette CreateSoftBadgePalette(MediaColor color) =>
        new(
            Brush(MediaColor.FromArgb(41, color.R, color.G, color.B)),
            Brush(color),
            Brush(color));

    private static bool ContainsAny(string value, params string[] tokens)
    {
        foreach (var token in tokens)
        {
            if (value.Contains(token, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryReadPrice(string value, out decimal price)
    {
        var normalized = value.Replace("$", "", StringComparison.Ordinal).Replace(",", "", StringComparison.Ordinal).Trim();
        return decimal.TryParse(normalized, out price);
    }

    private static string FormatImportedAtCompactText(string value)
    {
        var trimmed = value.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return "";
        }

        if (DateTime.TryParse(trimmed, out var timestamp))
        {
            return $"{timestamp:yyyy-MM-dd}";
        }

        var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length >= 2 && parts[0].Contains('-', StringComparison.Ordinal))
        {
            return parts[0];
        }

        return trimmed;
    }

    private static string BuildShipDetailImagePath(string imagePath)
    {
        if (string.IsNullOrWhiteSpace(imagePath))
        {
            return "";
        }

        return imagePath
            .Replace(@"Data\ShipImages\", @"Data\ShipDetailImages\", StringComparison.OrdinalIgnoreCase)
            .Replace("Data/ShipImages/", "Data/ShipDetailImages/", StringComparison.OrdinalIgnoreCase);
    }

    private static MediaBrush Brush(byte red, byte green, byte blue)
    {
        var brush = new MediaSolidBrush(MediaColor.FromRgb(red, green, blue));
        brush.Freeze();
        return brush;
    }

    private static MediaBrush Brush(MediaColor color)
    {
        var brush = new MediaSolidBrush(color);
        brush.Freeze();
        return brush;
    }

    private readonly record struct BadgePalette(MediaBrush Background, MediaBrush Border, MediaBrush Text);

    private static readonly MediaBrush CapitalShipBrush = Brush(170, 110, 255);
    private static readonly MediaBrush LargeShipBrush = Brush(77, 190, 255);
    private static readonly MediaBrush MediumShipBrush = Brush(77, 255, 213);
    private static readonly MediaBrush SmallShipBrush = Brush(141, 220, 105);
    private static readonly MediaBrush FlyableShipBrush = Brush(103, 255, 164);
    private static readonly MediaBrush ConceptShipBrush = Brush(255, 196, 87);
    private static readonly MediaBrush ConceptLineShipBrush = Brush(154, 112, 232);
    private static readonly MediaBrush UnflyableShipBrush = Brush(241, 91, 101);
    private static readonly MediaBrush UnknownShipBrush = Brush(217, 162, 59);
    private static readonly MediaBrush DefaultShipLineBrush = Brush(41, 175, 255);
    private static readonly MediaBrush PriceTierOneShipBrush = Brush(139, 188, 190);
    private static readonly MediaBrush PriceTierTwoShipBrush = Brush(117, 210, 255);
    private static readonly MediaBrush PriceTierThreeShipBrush = Brush(217, 216, 137);
    private static readonly MediaBrush PriceTierFourShipBrush = Brush(240, 191, 115);
    private static readonly MediaBrush PriceTierFiveShipBrush = Brush(216, 167, 255);
    private static readonly MediaBrush PriceTierSixShipBrush = Brush(255, 158, 178);
    private static readonly MediaBrush NeutralShipBrush = Brush(156, 183, 208);

    private static readonly BadgePalette CapitalSpecBadgePalette = CreateSoftBadgePalette(FleetShipSpecPalette.Capital);
    private static readonly BadgePalette LargeSpecBadgePalette = CreateSoftBadgePalette(FleetShipSpecPalette.Large);
    private static readonly BadgePalette MediumSpecBadgePalette = CreateSoftBadgePalette(FleetShipSpecPalette.Medium);
    private static readonly BadgePalette SmallSpecBadgePalette = CreateSoftBadgePalette(FleetShipSpecPalette.Small);
    private static readonly BadgePalette UnknownSpecBadgePalette = CreateSoftBadgePalette(FleetShipSpecPalette.Unknown);

    private static readonly BadgePalette FlyableStatusBadgePalette = CreateSoftBadgePalette(66, 207, 124);
    private static readonly BadgePalette ConceptStatusBadgePalette = CreateSoftBadgePalette(188, 166, 232);
    private static readonly BadgePalette UnflyableStatusBadgePalette = CreateSoftBadgePalette(241, 91, 101);
    private static readonly BadgePalette UnknownStatusBadgePalette = CreateSoftBadgePalette(157, 170, 179);

    private static readonly BadgePalette PriceTierOneBadgePalette = CreateSoftBadgePalette(139, 188, 190);
    private static readonly BadgePalette PriceTierTwoBadgePalette = CreateSoftBadgePalette(117, 210, 255);
    private static readonly BadgePalette PriceTierThreeBadgePalette = CreateSoftBadgePalette(217, 216, 137);
    private static readonly BadgePalette PriceTierFourBadgePalette = CreateSoftBadgePalette(240, 191, 115);
    private static readonly BadgePalette PriceTierFiveBadgePalette = CreateSoftBadgePalette(216, 167, 255);
    private static readonly BadgePalette PriceTierSixBadgePalette = CreateSoftBadgePalette(255, 158, 178);
    private static readonly BadgePalette UnknownPriceBadgePalette = CreateSoftBadgePalette(154, 174, 187);

}

public sealed record FleetTaskHistoryRow(
    string Key,
    string Title,
    string Brief,
    string Status,
    string Participants,
    string Rally,
    string RequiredShip,
    string PublishedAtText)
{
    public MediaBrush StatusBrush => StatusPalette.ForTaskStatus(Status);
}

public sealed record FleetEventLogRow(
    string Id,
    DateTimeOffset Timestamp,
    string Type,
    string Title,
    string Detail,
    bool CanDelete = false,
    DateTimeOffset EndTimestamp = default,
    int OccurrenceCount = 1)
{
    public DateTimeOffset EffectiveEndTimestamp => EndTimestamp == default ? Timestamp : EndTimestamp;
    public string TimestampText
    {
        get
        {
            var start = Timestamp.ToLocalTime();
            var end = EffectiveEndTimestamp.ToLocalTime();
            if (OccurrenceCount <= 1 || end <= start)
            {
                return start.ToString("yyyy-MM-dd HH:mm");
            }

            return start.Date == end.Date
                ? $"{start:MM-dd HH:mm}–{end:HH:mm}\n{OccurrenceCount} 次"
                : $"{start:MM-dd HH:mm}\n→ {end:MM-dd HH:mm} · {OccurrenceCount} 次";
        }
    }
    public MediaBrush AccentBrush => StatusPalette.ForEvent(Type, Title);
}

public sealed record FleetEventActionPlanRow(
    string Id,
    string Title,
    string Summary,
    string TimeText,
    string ParticipantText,
    string StatusText,
    string ActionText,
    bool CanAct,
    MediaBrush AccentBrush);

public sealed record FleetNotificationCenterItemRow(
    string Kind,
    string Title,
    string Detail,
    string TimeText,
    string ActionText,
    string ActionKey,
    MediaBrush? AccentBrush);

public sealed class FleetRoleGroupRow : INotifyPropertyChanged
{
    private bool _isSelected;
    private string _displayName = "";
    private string _description = "";
    private string _color = "#29AFFF";
    private bool _isEnabled = true;
    private int _memberCount;

    public string Key { get; init; } = "";
    public bool IsSystem { get; init; }
    public int SortOrder { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public ObservableCollection<FleetPermissionGroupRow> PermissionGroups { get; } = [];
    public HashSet<string> HiddenPermissionIds { get; } = new(StringComparer.OrdinalIgnoreCase);
    public bool IsCommanderSeat => Key.Equals("fleet_commander", StringComparison.OrdinalIgnoreCase);
    public string InternalTypeText => IsCommanderSeat ? "特殊身份" : IsSystem ? "系统默认" : "自定义身份组";
    public string DeleteHint => IsCommanderSeat ? "组织负责人是唯一席位，不能删除或复制" : IsSystem ? "系统默认身份组不可删除" : "自定义身份组可删除";
    public string MemberCountText => $"{MemberCount} 人";
    public string UpdatedText => UpdatedAt == default ? "尚未修改" : UpdatedAt.ToLocalTime().ToString("MM-dd HH:mm");
    public string PermissionSummary => BuildPermissionSummary();
    public string PermissionEditorHint => IsCommanderSeat
        ? "组织负责人不是普通身份组，而是唯一特殊身份。该席位默认拥有全部权限，权限矩阵不可调整；需要更换时请使用成员列表中的“转移管理权”。"
        : "权限只控制管理、编辑、审核和导出操作。成员基础查看能力默认开放，不在这里配置。";
    public bool CanCopyRole => !IsCommanderSeat;
    public bool CanAssignMembers => !IsCommanderSeat;
    public bool CanRenameRole => !IsCommanderSeat;
    public bool CanDeleteRole => !IsSystem;
    public MediaBrush AccentBrush => StatusPalette.BrushFromHex(Color, StatusPalette.InfoBrush);
    public MediaBrush CardBackgroundBrush => IsSelected
        ? StatusPalette.BrushFromHex("#12354A", StatusPalette.InfoBrush)
        : StatusPalette.BrushFromHex("#0A1823", StatusPalette.DisabledBrush);
    public MediaBrush CardBorderBrush => IsSelected
        ? StatusPalette.InfoBrush
        : StatusPalette.BrushFromHex("#173447", StatusPalette.DisabledBrush);
    public string SelectedBadge => IsSelected ? IsCommanderSeat ? "唯一席位" : "当前选中" : InternalTypeText;

    public string DisplayName
    {
        get => _displayName;
        set
        {
            var normalized = string.IsNullOrWhiteSpace(value) ? "未命名身份组" : value.Trim();
            if (_displayName == normalized)
            {
                return;
            }

            _displayName = normalized;
            Touch();
            OnChanged(nameof(DisplayName));
        }
    }

    public string Description
    {
        get => _description;
        set
        {
            var normalized = value?.Trim() ?? "";
            if (_description == normalized)
            {
                return;
            }

            _description = normalized;
            Touch();
            OnChanged(nameof(Description));
        }
    }

    public string Color
    {
        get => _color;
        set
        {
            var normalized = string.IsNullOrWhiteSpace(value) ? "#29AFFF" : value.Trim();
            if (_color == normalized)
            {
                return;
            }

            _color = normalized;
            Touch();
            OnChanged(nameof(Color));
            OnChanged(nameof(AccentBrush));
        }
    }

    public bool IsEnabled
    {
        get => _isEnabled;
        set
        {
            if (_isEnabled == value)
            {
                return;
            }

            _isEnabled = value;
            Touch();
            OnChanged(nameof(IsEnabled));
        }
    }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value)
            {
                return;
            }

            _isSelected = value;
            OnChanged(nameof(IsSelected));
            OnChanged(nameof(CardBackgroundBrush));
            OnChanged(nameof(CardBorderBrush));
            OnChanged(nameof(SelectedBadge));
        }
    }

    public int MemberCount
    {
        get => _memberCount;
        set
        {
            if (_memberCount == value)
            {
                return;
            }

            _memberCount = Math.Max(0, value);
            OnChanged(nameof(MemberCount));
            OnChanged(nameof(MemberCountText));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void RefreshDerived()
    {
        OnChanged(nameof(PermissionSummary));
        OnChanged(nameof(UpdatedText));
    }

    private string BuildPermissionSummary()
    {
        if (IsCommanderSeat)
        {
            return "特殊身份 / 全部权限";
        }

        var allowed = PermissionGroups
            .SelectMany(group => group.Items)
            .Where(item => item.IsAllowed)
            .Select(item => item.ShortModule)
            .Distinct()
            .Take(3)
            .ToArray();

        return allowed.Length == 0 ? "无管理权限" : string.Join(" / ", allowed);
    }

    private void Touch()
    {
        UpdatedAt = DateTimeOffset.UtcNow;
        OnChanged(nameof(UpdatedText));
    }

    private void OnChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed record FleetPermissionGroupRow(
    string Title,
    string Description,
    ObservableCollection<FleetPermissionItemRow> Items)
{
    public int AllowedCount => Items.Count(item => item.IsAllowed && !item.IsDevelopment);
    public int EditableCount => Items.Count(item => item.IsEditable);
    public string GroupBadgeText => IsDevelopment ? "开发中" : IsDangerous ? "高危" : $"{AllowedCount}/{Items.Count}";
    public MediaBrush GroupBadgeBrush => IsDevelopment
        ? StatusPalette.DisabledBrush
        : IsDangerous
            ? StatusPalette.WarningBrush
            : StatusPalette.InfoBrush;
    public bool IsDevelopment => Items.Any(item => item.IsDevelopment);
    public bool IsDangerous => Items.Any(item => item.IsDangerous);
    public string ProductHint => IsDevelopment
        ? "该模块尚未开放，暂不支持配置。"
        : IsDangerous
            ? "这些权限会影响舰队结构或关键数据，修改前需要二次确认。"
            : EditableCount == 0
                ? "当前没有可配置权限项。"
                : "按职责开启需要的权限，避免给身份组过大的管理范围。";
}

public sealed class FleetPermissionItemRow : INotifyPropertyChanged
{
    private bool _isAllowed;

    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Description { get; init; } = "";
    public string ShortModule { get; init; } = "";
    public bool IsDangerous { get; init; }
    public bool IsLocked { get; init; }
    public bool IsDevelopment => ShortModule.Equals("开发中", StringComparison.OrdinalIgnoreCase);
    public string StatusText => IsDevelopment ? "开发中" : IsLocked ? "系统锁定" : IsAllowed ? "允许" : "禁止";
    public MediaBrush StatusBrush => IsDevelopment
        ? StatusPalette.DisabledBrush
        : IsLocked
        ? StatusPalette.DisabledBrush
        : IsAllowed
            ? StatusPalette.SuccessBrush
            : StatusPalette.DisabledBrush;
    public MediaBrush TitleBrush => IsDangerous ? StatusPalette.WarningBrush : StatusPalette.InfoBrush;
    public bool IsEditable => !IsLocked && !IsDevelopment;

    public bool IsAllowed
    {
        get => _isAllowed;
        set
        {
            if (_isAllowed == value)
            {
                return;
            }

            _isAllowed = value;
            OnChanged(nameof(IsAllowed));
            OnChanged(nameof(StatusText));
            OnChanged(nameof(StatusBrush));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed class FleetMemberManagementRow : INotifyPropertyChanged
{
    private string _roleTitle = "成员";
    private bool _permissionEnabled;
    private bool _canRemoveMembers;
    private bool _canPublishTasks;
    private bool _canPublishPlans;
    private bool _canManageFleetInfo;

    public string GameName { get; init; } = "";
    public string GameId => GameName;
    public string Callsign { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Initials { get; init; } = "?";
    public string? AvatarPath { get; init; }
    public string? AccountId { get; init; }
    public string OnlineStatus { get; init; } = "Offline";
    public string? LiveStatus { get; init; }
    public bool IsSelf { get; init; }
    public bool IsCommander { get; init; }
    public bool CanCurrentUserEditPermissions { get; init; }
    public bool CanCurrentUserRemove { get; init; }
    public bool CanCurrentUserTransferCommand { get; init; }
    public MediaBrush? RoleBrush { get; init; }
    public PlayerPresenceKind Presence => PlayerPresencePresentation.ResolveShared(LiveStatus, OnlineStatus);
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public MediaBrush OnlineStatusBrush => PlayerPresencePresentation.Brush(Presence);
    public string HeaderLine => PresenceText;
    public bool CanEditPermissions => CanCurrentUserEditPermissions && !IsCommander;
    public bool ShowPermissionControls => IsCommander || PermissionEnabled;
    public bool ShowRoleEditor => CanEditPermissions;
    public bool ShowRoleSummary => IsCommander || PermissionEnabled;
    public bool ShowSavePermissions => CanEditPermissions;
    public bool CanTransferCommander => CanCurrentUserTransferCommand && !IsSelf && !IsCommander;
    public bool CanRemoveFromFleet => CanCurrentUserRemove && !IsSelf && !IsCommander;
    public string RoleSourceText => IsCommander ? "内部标识：fleet_commander" : PermissionEnabled ? "来自主要身份组" : "基础成员权限";
    public string ExceptionSummary => BuildExceptionSummary();
    public string EffectivePermissionSummary => IsCommander
        ? "最终权限：舰队最高管理权限"
        : PermissionEnabled
            ? $"最终权限：{BuildExceptionSummary()}"
            : "最终权限：基础查看与参与";

    public string RoleTitle
    {
        get => _roleTitle;
        set
        {
            if (_roleTitle == value)
            {
                return;
            }

            _roleTitle = value;
            OnChanged(nameof(RoleTitle));
            OnChanged(nameof(RoleSourceText));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    public bool PermissionEnabled
    {
        get => _permissionEnabled;
        set
        {
            if (_permissionEnabled == value)
            {
                return;
            }

            _permissionEnabled = value;
            OnChanged(nameof(PermissionEnabled));
            OnChanged(nameof(ShowPermissionControls));
            OnChanged(nameof(ShowRoleEditor));
            OnChanged(nameof(ShowRoleSummary));
            OnChanged(nameof(ShowSavePermissions));
            OnChanged(nameof(CanEditPermissions));
            OnChanged(nameof(CanTransferCommander));
            OnChanged(nameof(CanRemoveFromFleet));
            OnChanged(nameof(RoleSourceText));
            OnChanged(nameof(ExceptionSummary));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    public bool CanRemoveMembers
    {
        get => _canRemoveMembers;
        set
        {
            if (_canRemoveMembers == value)
            {
                return;
            }

            _canRemoveMembers = value;
            OnChanged(nameof(CanRemoveMembers));
            OnChanged(nameof(ExceptionSummary));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    public bool CanPublishTasks
    {
        get => _canPublishTasks;
        set
        {
            if (_canPublishTasks == value)
            {
                return;
            }

            _canPublishTasks = value;
            OnChanged(nameof(CanPublishTasks));
            OnChanged(nameof(ExceptionSummary));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    public bool CanPublishPlans
    {
        get => _canPublishPlans;
        set
        {
            if (_canPublishPlans == value)
            {
                return;
            }

            _canPublishPlans = value;
            OnChanged(nameof(CanPublishPlans));
            OnChanged(nameof(ExceptionSummary));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    public bool CanManageFleetInfo
    {
        get => _canManageFleetInfo;
        set
        {
            if (_canManageFleetInfo == value)
            {
                return;
            }

            _canManageFleetInfo = value;
            OnChanged(nameof(CanManageFleetInfo));
            OnChanged(nameof(ExceptionSummary));
            OnChanged(nameof(EffectivePermissionSummary));
        }
    }

    private string BuildExceptionSummary()
    {
        var allowed = new List<string>();
        if (CanManageFleetInfo)
        {
            allowed.Add("组织资料");
        }

        if (CanRemoveMembers)
        {
            allowed.Add("移除成员");
        }

        if (CanPublishTasks)
        {
            allowed.Add("发布行动");
        }

        if (CanPublishPlans)
        {
            allowed.Add("创建预约");
        }

        return allowed.Count == 0 ? "无成员例外" : string.Join(" / ", allowed);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed class FleetActionPlanRow : INotifyPropertyChanged
{
    public FleetActionPlanRow(
        string id,
        string title,
        string content,
        DateTime startTime,
        bool notifyMembers,
        string status = "Published",
        DateTimeOffset? canceledAt = null,
        string? canceledBy = null,
        string? cancelReason = null,
        DateTimeOffset? reachedAt = null,
        DateTimeOffset? completedAt = null,
        string? completedBy = null,
        string? completionMode = null,
        DateTimeOffset updatedAt = default,
        long version = 1)
    {
        Id = id;
        Title = title;
        Content = content;
        StartTime = startTime;
        NotifyMembers = notifyMembers;
        Status = NormalizeStatus(status);
        CanceledAt = canceledAt;
        CanceledBy = canceledBy;
        CancelReason = cancelReason;
        ReachedAt = reachedAt;
        CompletedAt = completedAt;
        CompletedBy = completedBy;
        CompletionMode = NormalizeCompletionMode(completionMode);
        UpdatedAt = updatedAt == default ? DateTimeOffset.UtcNow : updatedAt;
        Version = Math.Max(1, version);
        RefreshParticipantSummary();
    }

    public string Id { get; }
    public string Title { get; private set; }
    public string Content { get; private set; }
    public DateTime StartTime { get; private set; }
    public bool NotifyMembers { get; private set; }
    public string Status { get; private set; }
    public DateTimeOffset? CanceledAt { get; private set; }
    public string? CanceledBy { get; private set; }
    public string? CancelReason { get; private set; }
    public DateTimeOffset? ReachedAt { get; private set; }
    public DateTimeOffset? CompletedAt { get; private set; }
    public string? CompletedBy { get; private set; }
    public string? CompletionMode { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }
    public long Version { get; private set; }
    public ObservableCollection<ActionPlanParticipantRow> Participants { get; } = [];
    public string StartTimeText => $"行动时间 / {StartTime:yyyy-MM-dd HH:mm}";
    public string NotifyText => NotifyMembers ? "通知 / 启用" : "通知 / 未启用";
    public string ParticipantCountText => $"参与 / {Participants.Count}";
    public string EffectiveStatus
    {
        get
        {
            if (Status.Equals("Canceled", StringComparison.OrdinalIgnoreCase) ||
                Status.Equals("Completed", StringComparison.OrdinalIgnoreCase))
            {
                return Status;
            }

            var now = DateTime.Now;
            if (now >= StartTime.AddHours(6))
            {
                return "Completed";
            }

            return now >= StartTime ? "Reached" : "Published";
        }
    }

    public bool IsCanceled => EffectiveStatus.Equals("Canceled", StringComparison.OrdinalIgnoreCase);
    public bool IsReached => EffectiveStatus.Equals("Reached", StringComparison.OrdinalIgnoreCase);
    public bool IsCompleted => EffectiveStatus.Equals("Completed", StringComparison.OrdinalIgnoreCase);
    public bool IsPublished => EffectiveStatus.Equals("Published", StringComparison.OrdinalIgnoreCase);
    public bool IsJoinable => IsPublished;
    public bool CanEdit => IsPublished;
    public bool CanCancel => IsPublished || IsReached;
    public bool CanComplete => IsReached;
    public bool IsOpen => IsPublished || IsReached;
    public string StatusText => EffectiveStatus switch
    {
        "Canceled" => string.IsNullOrWhiteSpace(CancelReason) ? "状态 / 已取消" : $"状态 / 已取消：{CancelReason}",
        "Completed" => string.Equals(CompletionMode, "Automatic", StringComparison.OrdinalIgnoreCase)
            ? "状态 / 自动完成"
            : "状态 / 已完成",
        "Reached" => "状态 / 已到时",
        _ => "状态 / 已发布"
    };

    public MediaBrush StatusBrush => EffectiveStatus switch
    {
        "Canceled" => StatusPalette.DangerBrush,
        "Completed" => StatusPalette.SuccessBrush,
        "Reached" => StatusPalette.WarningBrush,
        _ => StatusPalette.InfoBrush
    };

    public MediaBrush TimeBrush => IsCanceled || IsCompleted
        ? StatusPalette.DisabledBrush
        : IsReached
            ? StatusPalette.WarningBrush
            : StatusPalette.InfoBrush;
    public MediaBrush NotifyBrush => NotifyMembers ? StatusPalette.WarningBrush : StatusPalette.DisabledBrush;
    public event PropertyChangedEventHandler? PropertyChanged;

    public void UpdatePlan(string title, string content, DateTime startTime, bool notifyMembers)
    {
        var startChanged = !StartTime.Equals(startTime);
        Title = title;
        Content = content;
        StartTime = startTime;
        NotifyMembers = notifyMembers;
        Status = "Published";
        ReachedAt = null;
        CompletedAt = null;
        CompletedBy = null;
        CompletionMode = null;
        UpdatedAt = DateTimeOffset.UtcNow;
        Version++;
        if (startChanged)
        {
            for (var index = 0; index < Participants.Count; index++)
            {
                Participants[index] = Participants[index] with { ReminderSentAt = null };
            }
        }

        OnChanged(nameof(Title));
        OnChanged(nameof(Content));
        OnChanged(nameof(StartTime));
        OnChanged(nameof(StartTimeText));
        OnChanged(nameof(NotifyMembers));
        OnChanged(nameof(NotifyText));
        OnChanged(nameof(NotifyBrush));
        RaiseLifecycleChanged();
    }

    public void Cancel(string? reason, string? canceledBy = null)
    {
        Status = "Canceled";
        CanceledAt = DateTimeOffset.UtcNow;
        CanceledBy = canceledBy;
        CancelReason = reason;
        ReachedAt = null;
        CompletedAt = null;
        CompletedBy = null;
        CompletionMode = null;
        UpdatedAt = CanceledAt.Value;
        Version++;
        RaiseLifecycleChanged();
    }

    public void Complete(string? completedBy = null)
    {
        Status = "Completed";
        ReachedAt ??= ToLocalOffset(StartTime);
        CompletedAt = DateTimeOffset.UtcNow;
        CompletedBy = completedBy;
        CompletionMode = "Manual";
        UpdatedAt = CompletedAt.Value;
        Version++;
        RaiseLifecycleChanged();
    }

    public void RefreshParticipantSummary()
    {
        OnChanged(nameof(ParticipantCountText));
        RaiseLifecycleChanged();
    }

    private static string NormalizeStatus(string? status)
    {
        if (string.Equals(status, "Canceled", StringComparison.OrdinalIgnoreCase))
        {
            return "Canceled";
        }

        if (string.Equals(status, "Completed", StringComparison.OrdinalIgnoreCase))
        {
            return "Completed";
        }

        if (string.Equals(status, "Reached", StringComparison.OrdinalIgnoreCase))
        {
            return "Reached";
        }

        return "Published";
    }

    private static string? NormalizeCompletionMode(string? mode)
    {
        if (string.Equals(mode, "Manual", StringComparison.OrdinalIgnoreCase))
        {
            return "Manual";
        }

        return string.Equals(mode, "Automatic", StringComparison.OrdinalIgnoreCase) ? "Automatic" : null;
    }

    private static DateTimeOffset ToLocalOffset(DateTime value)
    {
        return value.Kind switch
        {
            DateTimeKind.Utc => new DateTimeOffset(value, TimeSpan.Zero),
            DateTimeKind.Local => new DateTimeOffset(value),
            _ => new DateTimeOffset(value, TimeZoneInfo.Local.GetUtcOffset(value))
        };
    }

    private void RaiseLifecycleChanged()
    {
        OnChanged(nameof(Status));
        OnChanged(nameof(EffectiveStatus));
        OnChanged(nameof(StatusText));
        OnChanged(nameof(StatusBrush));
        OnChanged(nameof(TimeBrush));
        OnChanged(nameof(IsCanceled));
        OnChanged(nameof(IsReached));
        OnChanged(nameof(IsCompleted));
        OnChanged(nameof(IsPublished));
        OnChanged(nameof(IsJoinable));
        OnChanged(nameof(CanEdit));
        OnChanged(nameof(CanCancel));
        OnChanged(nameof(CanComplete));
        OnChanged(nameof(IsOpen));
    }

    private void OnChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed record ActionPlanParticipantRow(
    string Callsign,
    string GameName,
    string? AvatarPath,
    string Initials,
    bool ReminderRequested = false,
    DateTimeOffset? ReminderSentAt = null);

public sealed record FleetApplicationRow(
    string Id,
    string DisplayName,
    string GameName,
    string Callsign,
    string? Account,
    string Message,
    string Status,
    string CreatedAtText,
    string Initials,
    string? AvatarPath);

public sealed record FleetInviteRow(
    string Id,
    string Code,
    string CreatedBy,
    string CreatorInitials,
    string? CreatorAvatarPath,
    string CreatedAtText,
    string ExpiresAtText,
    string UsesText,
    string StatusText,
    MediaBrush StatusBrush,
    bool CanRevoke)
{
    public Visibility ActiveActionVisibility => CanRevoke ? Visibility.Visible : Visibility.Collapsed;
    public Visibility InactiveTagVisibility => CanRevoke ? Visibility.Collapsed : Visibility.Visible;
    public Visibility RevokeVisibility => ActiveActionVisibility;
    public Visibility CreatorAvatarVisibility => string.IsNullOrWhiteSpace(CreatorAvatarPath) ? Visibility.Collapsed : Visibility.Visible;
    public Visibility CreatorInitialsVisibility => string.IsNullOrWhiteSpace(CreatorAvatarPath) ? Visibility.Visible : Visibility.Collapsed;
}

public sealed record FleetDirectoryTagChip(
    string Name,
    string CategoryName,
    string Description,
    MediaBrush AccentBrush,
    MediaBrush BorderBrush,
    MediaBrush BackgroundBrush,
    string TooltipText);

public sealed record NetworkFleetCard(
    NetworkFleetSnapshot Snapshot,
    string Name,
    string LogoText,
    string? LogoImageData,
    string? BannerImageData,
    Visibility LogoTextVisibility,
    string CodeLine,
    string CommanderLine,
    string JoinPolicyLine,
    string RecruitingLine,
    string ApplicationStatusLine,
    Visibility ApplicationStatusVisibility,
    string Description,
    string TypeLine,
    string ActiveTimeLine,
    string MembersLine,
    bool RequiresApplication,
    bool HasPendingApplication,
    bool CanJoin,
    string JoinButtonText,
    IReadOnlyList<FleetDirectoryTagChip> TagChips,
    int SearchScore = 1)
{
    public IReadOnlyList<FleetDirectoryTagChip> SystemRecommendationChips { get; init; } = [];
    public Visibility TagChipsVisibility => TagChips.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility SystemRecommendationVisibility => SystemRecommendationChips.Count > 0
        ? Visibility.Visible
        : Visibility.Collapsed;
    public Visibility TagFallbackVisibility => TagChips.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
    public Visibility JoinActionVisibility => CanJoin ? Visibility.Visible : Visibility.Collapsed;
    public string FleetCodeText => string.IsNullOrWhiteSpace(Snapshot.Code) ? "N/A" : Snapshot.Code.Trim();
    public string CommanderText => string.IsNullOrWhiteSpace(Snapshot.Commander) ? "未指定" : Snapshot.Commander!.Trim();
    public string RecruitingStatusText => Snapshot.RecruitingEnabled ? "正在招募" : "暂停招募";
    public string RelationText => HasPendingApplication
        ? "申请处理中"
        : IsInviteOnly ? "需要邀请码"
        : CanJoin ? (RequiresApplication ? "可申请" : "可加入") : "已加入";
    public string MainSystemLine => Snapshot.PublicShowActiveSystems
        ? $"主要活跃星系 / {BuildActiveSystemText(Snapshot.ActiveSystemIds)}"
        : "主要活跃星系 / 未公开";
    public string ActiveSystemText => Snapshot.PublicShowActiveSystems
        ? BuildActiveSystemText(Snapshot.ActiveSystemIds)
        : "未公开";
    public string LanguageLine => $"语言 / {(string.IsNullOrWhiteSpace(Snapshot.Language) ? "未公开" : Snapshot.Language.Trim())}";
    public string WebsiteLine => string.IsNullOrWhiteSpace(Snapshot.WebsiteUrl)
        ? ""
        : Snapshot.WebsiteUrl.Trim();
    public string PublicContactText
    {
        get
        {
            var values = new List<string>();
            if (!string.IsNullOrWhiteSpace(Snapshot.WebsiteUrl))
            {
                values.Add($"舰队网站：{Snapshot.WebsiteUrl.Trim()}");
            }

            values.AddRange((Snapshot.ExternalContacts ?? [])
                .Where(contact => !string.IsNullOrWhiteSpace(contact.Platform) && !string.IsNullOrWhiteSpace(contact.Value))
                .Take(5)
                .Select(contact => $"{contact.Platform.Trim()}：{contact.Value.Trim()}"));
            return values.Count == 0 ? "未公开联系方式" : string.Join(Environment.NewLine, values);
        }
    }
    public string LastUpdatedLine => Snapshot.LastUpdated == default
        ? "最近更新 / 未知"
        : $"最近更新 / {Snapshot.LastUpdated.ToLocalTime():MM-dd HH:mm}";
    public string PublicDescriptionLine => string.IsNullOrWhiteSpace(Description)
        ? "简介 / 暂无公开介绍"
        : $"简介 / {Description.Trim()}";
    public string PublicDescriptionText => !Snapshot.PublicShowDescription
        ? "舰队介绍未公开"
        : string.IsNullOrWhiteSpace(Snapshot.Description)
            ? "未提供舰队介绍"
            : Snapshot.Description.Trim();
    public string PublicShipScaleLine => BuildPublicShipScaleLine(Snapshot);
    public string ActiveTimeValueText => ExtractDirectoryValue(ActiveTimeLine);
    public string LocalActiveTimeLine => BuildLocalActivityTimeLine(
        Snapshot,
        !Snapshot.PublicShowActivityTime
            ? $"活动时间 / {FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.HiddenByPublisher)}"
            : string.IsNullOrWhiteSpace(Snapshot.ActiveTime)
                ? $"活动时间 / {FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.MissingInput)}"
                : ActiveTimeLine);
    public string LocalActiveTimeValueText => ExtractDirectoryValue(LocalActiveTimeLine);
    public string FleetDefaultTimeText => BuildFleetDefaultTimeText(
        Snapshot.TimeZoneId,
        Snapshot.PublicShowActivityTime);
    public string FleetTimeZoneText => BuildFleetTimeZoneSummaryText(
        Snapshot.TimeZoneId,
        Snapshot.PublicShowActivityTime);
    public string PublicShipScaleValueText => ExtractDirectoryValue(PublicShipScaleLine);
    public string PublicShipTotalValueText
    {
        get
        {
            if (string.Equals(Snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase))
            {
                return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.HiddenByPublisher);
            }

            var count = Math.Max(Snapshot.PublicShipCount, Snapshot.Ships?.Length ?? 0);
            return count > 0
                ? $"{count} 艘"
                : FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.EmptyStatistic);
        }
    }
    public string PublicShipDetailText => BuildPublicShipDetailText(Snapshot);
    public string FleetScaleLine => $"舰队规模 / {BuildMemberScaleBucket(Snapshot.TotalMembers)}";
    public string MemberScaleOnlyLine => $"成员 / {BuildPublicMemberScaleOnlyLine(Snapshot)}";
    public string MemberScaleOnlyValueText => ExtractDirectoryValue(MemberScaleOnlyLine);
    public string JoinPolicyValueText => ExtractDirectoryValue(JoinPolicyLine);
    public bool IsInviteOnly => IsInviteOnlyJoinPolicy(Snapshot.JoinPolicy);
    public string InviteRequirementLine => RequiresApplication
        ? "该舰队需要提交申请，由舰队管理者审核。"
        : IsInviteOnly ? "该舰队需要邀请码才能加入。"
        : "该舰队允许直接加入。";
    public string DetailActionHint => HasPendingApplication
        ? "你已经提交申请，可在这里撤回。"
        : IsInviteOnly ? "需要邀请码时，请从目录顶部的“邀请码加入”进入。"
        : CanJoin ? (RequiresApplication ? "确认适合后可以提交申请。" : "确认适合后可以直接加入。") : "你已经在该舰队中。";

    private static string ExtractDirectoryValue(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "未公开";
        }

        var separator = value.IndexOf('/');
        return separator >= 0 && separator + 1 < value.Length
            ? value[(separator + 1)..].Trim()
            : value.Trim();
    }

    private static string BuildLocalActivityTimeLine(NetworkFleetSnapshot snapshot, string fallbackLine)
    {
        if (!snapshot.PublicShowActivityTime ||
            string.IsNullOrWhiteSpace(snapshot.ActiveTime) ||
            snapshot.ActivityWindows is not { Length: > 0 } ||
            string.IsNullOrWhiteSpace(snapshot.TimeZoneId))
        {
            return fallbackLine;
        }

        try
        {
            var fleetZone = TimeZoneInfo.FindSystemTimeZoneById(snapshot.TimeZoneId);
            var fleetNow = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, fleetZone).Date;
            var daysSinceMonday = ((int)fleetNow.DayOfWeek + 6) % 7;
            var fleetMonday = DateTime.SpecifyKind(fleetNow.AddDays(-daysSinceMonday), DateTimeKind.Unspecified);
            var converted = new List<(int DayIndex, string DayId, string Start, string End, bool EndsNextDay)>();

            foreach (var window in snapshot.ActivityWindows)
            {
                if (!TryParseActivityClock(window.StartTime, out var startClock) ||
                    !TryParseActivityClock(window.EndTime, out var endClock))
                {
                    continue;
                }

                foreach (var sourceDayId in NormalizeActivityDayIds(window.Days))
                {
                    var sourceDayIndex = ActivityDayIndex(sourceDayId);
                    if (sourceDayIndex < 0)
                    {
                        continue;
                    }

                    var sourceStart = fleetMonday.AddDays(sourceDayIndex).Add(startClock);
                    var sourceEnd = fleetMonday.AddDays(sourceDayIndex).Add(endClock);
                    if (window.EndsNextDay || sourceEnd <= sourceStart)
                    {
                        sourceEnd = sourceEnd.AddDays(1);
                    }

                    var localStart = TimeZoneInfo.ConvertTime(sourceStart, fleetZone, TimeZoneInfo.Local);
                    var localEnd = TimeZoneInfo.ConvertTime(sourceEnd, fleetZone, TimeZoneInfo.Local);
                    var localDayIndex = ((int)localStart.DayOfWeek + 6) % 7;
                    converted.Add((
                        localDayIndex,
                        ActivityDayId(localDayIndex),
                        FormatClock(localStart),
                        FormatClock(localEnd),
                        localEnd.Date > localStart.Date));
                }
            }

            if (converted.Count == 0)
            {
                return fallbackLine;
            }

            var groups = converted
                .GroupBy(item => new { item.Start, item.End, item.EndsNextDay })
                .OrderBy(group => group.Min(item => item.DayIndex))
                .ThenBy(group => group.Key.Start, StringComparer.CurrentCulture)
                .Select(group =>
                {
                    var days = group
                        .OrderBy(item => item.DayIndex)
                        .Select(item => item.DayId)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToArray();
                    var endPrefix = group.Key.EndsNextDay ? "次日 " : string.Empty;
                    return $"{FormatActivityDays(days)} {group.Key.Start}-{endPrefix}{group.Key.End}";
                });

            return $"活动时间 / {string.Join("；", groups)}";
        }
        catch (TimeZoneNotFoundException)
        {
            return fallbackLine;
        }
        catch (InvalidTimeZoneException)
        {
            return fallbackLine;
        }
    }

    private static string[] NormalizeActivityDayIds(string[]? days)
    {
        return (days is { Length: > 0 } ? days : ["mon", "tue", "wed", "thu", "fri", "sat", "sun"])
            .Where(day => ActivityDayIndex(day) >= 0)
            .Select(day => day.Trim().ToLowerInvariant())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static int ActivityDayIndex(string? dayId) => dayId?.Trim().ToLowerInvariant() switch
    {
        "mon" => 0,
        "tue" => 1,
        "wed" => 2,
        "thu" => 3,
        "fri" => 4,
        "sat" => 5,
        "sun" => 6,
        _ => -1
    };

    private static string ActivityDayId(int dayIndex) => dayIndex switch
    {
        0 => "mon",
        1 => "tue",
        2 => "wed",
        3 => "thu",
        4 => "fri",
        5 => "sat",
        6 => "sun",
        _ => ""
    };

    private static string FormatActivityDays(string[] days)
    {
        var ordered = days
            .Where(day => ActivityDayIndex(day) >= 0)
            .OrderBy(ActivityDayIndex)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (ordered.Length == 7)
        {
            return "每日";
        }

        if (ordered.SequenceEqual(["mon", "tue", "wed", "thu", "fri"]))
        {
            return "工作日";
        }

        if (ordered.SequenceEqual(["sat", "sun"]))
        {
            return "周末";
        }

        return string.Join("、", ordered.Select(day => day switch
        {
            "mon" => "周一",
            "tue" => "周二",
            "wed" => "周三",
            "thu" => "周四",
            "fri" => "周五",
            "sat" => "周六",
            "sun" => "周日",
            _ => day
        }));
    }

    private static bool TryParseActivityClock(string? value, out TimeSpan clock)
    {
        return TimeSpan.TryParseExact(
            value?.Trim(),
            @"hh\:mm",
            CultureInfo.InvariantCulture,
            out clock) && clock >= TimeSpan.Zero && clock < TimeSpan.FromDays(1);
    }

    private static string BuildFleetDefaultTimeText(string? timeZoneId, bool isPublic)
    {
        if (!isPublic)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.HiddenByPublisher);
        }

        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.MissingInput);
        }

        try
        {
            var fleetZone = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);
            var fleetNow = TimeZoneInfo.ConvertTime(DateTimeOffset.Now, fleetZone);
            var offset = fleetZone.GetUtcOffset(fleetNow);
            var sign = offset < TimeSpan.Zero ? "-" : "+";
            var absoluteOffset = offset.Duration();
            return $"{FormatClock(fleetNow.DateTime)} · UTC{sign}{absoluteOffset:hh\\:mm} · {BuildFleetTimeZoneRegionText(fleetZone)}";
        }
        catch (TimeZoneNotFoundException)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.UnrecognizedInput);
        }
        catch (InvalidTimeZoneException)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.UnrecognizedInput);
        }
    }

    private static string BuildFleetTimeZoneSummaryText(string? timeZoneId, bool isPublic)
    {
        if (!isPublic)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.HiddenByPublisher);
        }

        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.MissingInput);
        }

        try
        {
            var fleetZone = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);
            var offset = fleetZone.GetUtcOffset(DateTimeOffset.Now);
            var sign = offset < TimeSpan.Zero ? "-" : "+";
            var absoluteOffset = offset.Duration();
            return $"UTC{sign}{absoluteOffset:hh\\:mm} · {BuildFleetTimeZoneRegionText(fleetZone)}";
        }
        catch (TimeZoneNotFoundException)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.UnrecognizedInput);
        }
        catch (InvalidTimeZoneException)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.UnrecognizedInput);
        }
    }

    private static string BuildFleetTimeZoneRegionText(TimeZoneInfo timeZone)
    {
        if (timeZone.Id.Equals("China Standard Time", StringComparison.OrdinalIgnoreCase))
        {
            return "中国标准时间 / 北京时间";
        }

        if (timeZone.Id.Equals("UTC", StringComparison.OrdinalIgnoreCase))
        {
            return "UTC";
        }

        var displayName = timeZone.DisplayName?.Trim();
        if (string.IsNullOrWhiteSpace(displayName))
        {
            return timeZone.StandardName;
        }

        var closingParenthesis = displayName.IndexOf(')');
        return closingParenthesis >= 0 && closingParenthesis + 1 < displayName.Length
            ? displayName[(closingParenthesis + 1)..].Trim()
            : displayName;
    }

    private static string FormatClock(DateTime value)
    {
        return UsesTwentyFourHourClock()
            ? value.ToString("HH:mm", CultureInfo.CurrentCulture)
            : value.ToString("h:mm tt", CultureInfo.CurrentCulture);
    }

    private static bool UsesTwentyFourHourClock()
    {
        return CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern.Contains('H');
    }

    public static NetworkFleetCard FromSnapshot(
        NetworkFleetSnapshot snapshot,
        string currentFleetName,
        string currentFleetCode,
        bool hasFleet,
        ISet<string>? pendingApplicationFleetCodes = null)
    {
        var code = string.IsNullOrWhiteSpace(snapshot.Code) ? "N/A" : snapshot.Code;
        var commander = string.IsNullOrWhiteSpace(snapshot.Commander) ? "Unassigned" : snapshot.Commander;
        var joinPolicy = string.IsNullOrWhiteSpace(snapshot.JoinPolicy) ? "Open" : snapshot.JoinPolicy;
        var recruitingTarget = string.IsNullOrWhiteSpace(snapshot.RecruitingTarget)
            ? "所有玩家"
            : snapshot.RecruitingTarget!.Trim();
        var recruitingLine = snapshot.RecruitingEnabled
            ? $"正在招募 / {recruitingTarget}"
            : "";
        var isCurrentFleet = hasFleet &&
                             (snapshot.Name.Equals(currentFleetName, StringComparison.OrdinalIgnoreCase) ||
                              code.Equals(currentFleetCode, StringComparison.OrdinalIgnoreCase));
        var hasLogoImage = !string.IsNullOrWhiteSpace(snapshot.LogoImageData);
        var requiresApplication =
            joinPolicy.Contains("申请", StringComparison.OrdinalIgnoreCase) ||
            joinPolicy.Contains("审核", StringComparison.OrdinalIgnoreCase) ||
            joinPolicy.Contains("Application", StringComparison.OrdinalIgnoreCase) ||
            joinPolicy.Contains("Apply", StringComparison.OrdinalIgnoreCase) ||
            joinPolicy.Contains("Request", StringComparison.OrdinalIgnoreCase);
        var requiresInvite = IsInviteOnlyJoinPolicy(joinPolicy);
        var hasPendingApplication = !isCurrentFleet &&
                                    pendingApplicationFleetCodes?.Contains(code) == true;
        const bool profileVisible = true;
        var description = profileVisible && snapshot.PublicShowDescription && !string.IsNullOrWhiteSpace(snapshot.Description)
            ? snapshot.Description
            : profileVisible ? "暂无舰队介绍。" : "该舰队未公开资料。";
        var type = profileVisible && snapshot.PublicShowTags && !string.IsNullOrWhiteSpace(snapshot.Type)
            ? snapshot.Type
            : "未公开";
        var activeTime = profileVisible && snapshot.PublicShowActivityTime && !string.IsNullOrWhiteSpace(snapshot.ActiveTime)
            ? snapshot.ActiveTime
            : "未公开";
        var membersLine = BuildPublicMembersLine(snapshot);
        return new NetworkFleetCard(
            snapshot,
            snapshot.Name,
            string.IsNullOrWhiteSpace(snapshot.LogoText) ? code : snapshot.LogoText!,
            snapshot.LogoImageData,
            snapshot.BannerImageData,
            hasLogoImage ? Visibility.Collapsed : Visibility.Visible,
            $"识别码 / {code}",
            $"指挥官 / {commander}",
            requiresInvite
                ? "加入 / 邀请码"
                : requiresApplication
                ? "加入 / 需要申请"
                : "加入 / 无门槛",
            recruitingLine,
            hasPendingApplication ? "申请状态 / 待审核" : "",
            hasPendingApplication ? Visibility.Visible : Visibility.Collapsed,
            description!,
            $"类型 / {type}",
            $"活动时间 / {activeTime}",
            membersLine,
            requiresApplication,
            hasPendingApplication,
            !isCurrentFleet && !requiresInvite,
            isCurrentFleet
                ? "已加入"
                : requiresInvite
                    ? "需要邀请码"
                : hasPendingApplication
                    ? "撤回申请"
                    : requiresApplication ? "申请加入" : hasFleet ? "切换舰队" : "加入",
            Array.Empty<FleetDirectoryTagChip>());
    }

    private static string BuildPublicMembersLine(NetworkFleetSnapshot snapshot)
    {
        if (string.Equals(snapshot.PublicMemberScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase))
        {
            return "成员规模 / 未公开";
        }

        if (string.Equals(snapshot.PublicMemberScaleMode, "Approx", StringComparison.OrdinalIgnoreCase))
        {
            return $"成员规模 / {BuildMemberScaleBucket(snapshot.TotalMembers)}";
        }

        return $"成员规模 / {snapshot.TotalMembers} 成员";
    }

    private static string BuildPublicMemberScaleOnlyLine(NetworkFleetSnapshot snapshot)
    {
        if (string.Equals(snapshot.PublicMemberScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase))
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.HiddenByPublisher);
        }

        if (snapshot.TotalMembers <= 0)
        {
            return FleetDirectoryValueText.Format(FleetDirectoryMissingValueKind.EmptyStatistic);
        }

        if (string.Equals(snapshot.PublicMemberScaleMode, "Approx", StringComparison.OrdinalIgnoreCase))
        {
            return BuildMemberScaleBucket(snapshot.TotalMembers);
        }

        return $"{snapshot.TotalMembers} 成员";
    }

    private static string BuildMemberScaleBucket(int totalMembers)
    {
        return FleetDirectoryMemberScale.Format(
            FleetDirectoryMemberScale.Classify(totalMembers));
    }

    private static bool IsInviteOnlyJoinPolicy(string? joinPolicy)
    {
        if (string.IsNullOrWhiteSpace(joinPolicy))
        {
            return false;
        }

        return joinPolicy.Contains("邀请", StringComparison.OrdinalIgnoreCase) ||
               joinPolicy.Contains("邀请码", StringComparison.OrdinalIgnoreCase) ||
               joinPolicy.Contains("Invite", StringComparison.OrdinalIgnoreCase) ||
               joinPolicy.Contains("Code", StringComparison.OrdinalIgnoreCase);
    }

    private static string BuildPublicShipScaleLine(NetworkFleetSnapshot snapshot)
    {
        if (string.Equals(snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase))
        {
            return "舰船展示 / 未公开";
        }

        var count = Math.Max(snapshot.PublicShipCount, snapshot.Ships?.Length ?? 0);
        if (count <= 0)
        {
            return "舰船展示 / 暂无公开数据";
        }

        if (string.Equals(snapshot.PublicShipScaleMode, "TotalOnly", StringComparison.OrdinalIgnoreCase))
        {
            return $"舰船展示 / {count} 艘";
        }

        var summary = FormatPublicShipTypeSummary(ResolvePublicShipTypeSummary(snapshot), 2);
        return string.IsNullOrWhiteSpace(summary)
            ? $"舰船展示 / {count} 艘公开"
            : $"舰船展示 / {count} 艘 · {summary}";
    }

    private static string BuildPublicShipDetailText(NetworkFleetSnapshot snapshot)
    {
        if (string.Equals(snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase))
        {
            return "该舰队未公开舰船资源。";
        }

        var count = Math.Max(snapshot.PublicShipCount, snapshot.Ships?.Length ?? 0);
        if (count <= 0)
        {
            return "暂无可公开的舰船规模数据。";
        }

        if (string.Equals(snapshot.PublicShipScaleMode, "TotalOnly", StringComparison.OrdinalIgnoreCase))
        {
            return $"公开舰船总数：{count} 艘。";
        }

        var summary = FormatPublicShipTypeSummary(ResolvePublicShipTypeSummary(snapshot), 6);
        return string.IsNullOrWhiteSpace(summary)
            ? $"公开舰船规模：{count} 艘。"
            : $"公开舰船规模：{count} 艘；{summary}。";
    }

    private static string FormatPublicShipTypeSummary(string? value, int maxItems)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Combat"] = "战斗",
            ["Transport"] = "运输",
            ["Industrial"] = "工业",
            ["Exploration"] = "探索",
            ["Support"] = "支援",
            ["Utility"] = "其他"
        };

        return string.Join(
            " · ",
            value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(item => item.Split('=', 2, StringSplitOptions.TrimEntries))
                .Where(parts => parts.Length == 2 && int.TryParse(parts[1], out var count) && count > 0)
                .Select(parts => $"{names.GetValueOrDefault(parts[0], parts[0])} {parts[1]}")
                .Take(Math.Max(1, maxItems)));
    }

    private static string? ResolvePublicShipTypeSummary(NetworkFleetSnapshot snapshot)
    {
        if (!string.IsNullOrWhiteSpace(snapshot.PublicShipTypeSummary))
        {
            return snapshot.PublicShipTypeSummary;
        }

        if (snapshot.Ships is not { Length: > 0 })
        {
            return null;
        }

        return string.Join(
            ';',
            snapshot.Ships
                .GroupBy(ResolvePublicShipRoleCategory, StringComparer.OrdinalIgnoreCase)
                .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
                .Select(group => $"{group.Key}={group.Count()}"));
    }

    private static string ResolvePublicShipRoleCategory(NetworkFleetShipSnapshot ship)
    {
        var storedCategory = NormalizePublicShipRoleCategory(ship.RoleCategory);
        if (!storedCategory.Equals("Utility", StringComparison.OrdinalIgnoreCase))
        {
            return storedCategory;
        }

        var catalogRole = ShipCatalog.Find(ship.Code, ship.DisplayName)?.Role;
        return ClassifyPublicShipCatalogRole(catalogRole);
    }

    private static string ClassifyPublicShipCatalogRole(string? role)
    {
        var value = role ?? "";
        if (ContainsPublicShipRoleToken(value, "escort", "interceptor", "interception", "interdiction", "patrol", "combat", "fighter", "gunship", "bomber", "attack", "frigate", "destroyer", "corvette", "carrier"))
        {
            return "Combat";
        }

        if (ContainsPublicShipRoleToken(value, "cargo", "freight", "freighter", "transport", "trade", "trading", "hauler", "courier", "passenger"))
        {
            return "Transport";
        }

        if (ContainsPublicShipRoleToken(value, "mining", "industrial", "salvage", "construction", "refinery"))
        {
            return "Industrial";
        }

        if (ContainsPublicShipRoleToken(value, "exploration", "explorer", "scanning", "pathfinder", "scout", "recon", "reconnaissance", "expedition", "science", "research"))
        {
            return "Exploration";
        }

        if (ContainsPublicShipRoleToken(value, "medical", "ambulance", "rescue", "repair", "refuel", "refueling", "support", "recovery"))
        {
            return "Support";
        }

        return "Utility";
    }

    private static bool ContainsPublicShipRoleToken(string value, params string[] tokens)
    {
        return tokens.Any(token => value.Contains(token, StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizePublicShipRoleCategory(string? value)
    {
        return value?.Trim().ToLowerInvariant() switch
        {
            "combat" => "Combat",
            "transport" => "Transport",
            "industrial" => "Industrial",
            "exploration" => "Exploration",
            "support" => "Support",
            _ => "Utility"
        };
    }

    private static string BuildActiveSystemText(IEnumerable<string>? systemIds)
    {
        var names = (systemIds ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim().ToLowerInvariant() switch
            {
                "stanton" => "斯坦顿",
                "pyro" => "派罗",
                "nyx" => "尼克斯",
                var other => other
            })
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(3)
            .ToArray();
        return names.Length == 0 ? "未公开" : string.Join(" · ", names);
    }
}
