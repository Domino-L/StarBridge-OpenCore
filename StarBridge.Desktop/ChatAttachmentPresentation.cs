using StarBridge.Core.Chat;
using System.Windows;

namespace StarBridge.Desktop;

internal static class ChatAttachmentPresentation
{
    public static Visibility AttachmentVisibility(ChatAttachmentContract? attachment) =>
        attachment is null ? Visibility.Collapsed : Visibility.Visible;

    public static Visibility TextVisibility(string? text) =>
        string.IsNullOrWhiteSpace(text) ? Visibility.Collapsed : Visibility.Visible;

    public static string ActionText(ChatAttachmentContract? attachment)
    {
        if (attachment?.Kind == ChatAttachmentKinds.PartyRoomInvitation)
        {
            if (attachment.ExpiresAt is { } expiresAt && expiresAt <= DateTimeOffset.UtcNow)
            {
                return "邀请已过期";
            }

            return string.Equals(attachment.RoomStatus, "closed", StringComparison.OrdinalIgnoreCase)
                ? "房间已结束"
                : "查看房间";
        }

        return attachment?.Kind switch
        {
            ChatAttachmentKinds.OverlayPreset => "查看预设",
            ChatAttachmentKinds.FleetInvitation => "查看舰队",
            _ => "查看"
        };
    }

    public static bool ActionEnabled(ChatAttachmentContract? attachment) =>
        attachment is not null &&
        !string.Equals(attachment.RoomStatus, "closed", StringComparison.OrdinalIgnoreCase) &&
        (attachment.ExpiresAt is null || attachment.ExpiresAt > DateTimeOffset.UtcNow);

    public static string TypeText(ChatAttachmentContract? attachment) => attachment?.Kind switch
    {
        ChatAttachmentKinds.OverlayPreset => "浮层预设",
        ChatAttachmentKinds.FleetInvitation => "舰队邀请",
        ChatAttachmentKinds.PartyRoomInvitation => "房间邀请",
        _ => "消息卡片"
    };

    public static Visibility StatusVisibility(ChatAttachmentContract? attachment) =>
        attachment?.Kind == ChatAttachmentKinds.PartyRoomInvitation
            ? Visibility.Visible
            : Visibility.Collapsed;

    public static string StatusText(ChatAttachmentContract? attachment)
    {
        if (attachment?.Kind != ChatAttachmentKinds.PartyRoomInvitation)
        {
            return "";
        }

        if (attachment.ExpiresAt is { } expiresAt && expiresAt <= DateTimeOffset.UtcNow)
        {
            return "已过期";
        }

        return attachment.RoomStatus?.Trim().ToLowerInvariant() switch
        {
            "closed" => "已结束",
            "full" => "已满员",
            "recruiting" => "开放中",
            _ => "邀请有效"
        };
    }

    public static string StatusBrush(ChatAttachmentContract? attachment) => StatusText(attachment) switch
    {
        "开放中" => "#49D98A",
        "已满员" => "#F0B84B",
        "邀请有效" => "#69CCFF",
        _ => "#8094A3"
    };

    public static string RoomActivityText(ChatAttachmentContract? attachment)
    {
        if (attachment?.Kind != ChatAttachmentKinds.PartyRoomInvitation)
        {
            return "";
        }

        var activities = (attachment.RoomGameplayTagNodeIds ?? [])
            .Select(PartyRoomTagCatalog.GetCompactGameplayText)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(2)
            .ToArray();
        return activities.Length == 0 ? "玩法未指定" : string.Join("   ", activities);
    }

    public static string RoomFactsText(ChatAttachmentContract? attachment)
    {
        if (attachment?.Kind != ChatAttachmentKinds.PartyRoomInvitation)
        {
            return "";
        }

        var parts = new List<string>();
        if (attachment.RoomCapacity is > 0)
        {
            parts.Add($"{Math.Max(0, attachment.RoomMemberCount ?? 0)}/{attachment.RoomCapacity} 人");
        }

        parts.Add(attachment.RoomAdmissionMode?.Trim().ToLowerInvariant() switch
        {
            "direct" => "直接加入",
            "approval" => "需房主审核",
            _ => "受邀加入"
        });
        parts.Add(attachment.RoomLanguage?.Trim().ToLowerInvariant() switch
        {
            "en" => "English",
            "bilingual" => "中英双语",
            _ => "中文"
        });
        var voice = attachment.RoomVoiceRequirement?.Trim().ToLowerInvariant() switch
        {
            "required" => "必须语音",
            "recommended" => "建议语音",
            _ => ""
        };
        if (voice.Length > 0)
        {
            parts.Add(voice);
        }

        if (attachment.ExpiresAt is { } expiresAt)
        {
            parts.Add($"有效至 {expiresAt.ToLocalTime():MM-dd HH:mm}");
        }

        return string.Join(" · ", parts);
    }

    public static Visibility RoomDetailsVisibility(ChatAttachmentContract? attachment) =>
        attachment?.Kind == ChatAttachmentKinds.PartyRoomInvitation
            ? Visibility.Visible
            : Visibility.Collapsed;
}
