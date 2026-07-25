using System.Text.Json;

namespace StarBridge.Core.Chat;

public static class ChatAttachmentKinds
{
    public const string OverlayPreset = "overlay_preset";
    public const string FleetInvitation = "fleet_invitation";
    public const string PartyRoomInvitation = "party_room_invitation";
}

public sealed record ChatAttachmentContract(
    string Kind,
    string Title,
    string Summary,
    string? OverlayPresetPackage = null,
    string? FleetInviteCode = null,
    string? RoomId = null,
    string? RoomInvitationId = null,
    DateTimeOffset? ExpiresAt = null,
    string? RoomStatus = null,
    int? RoomMemberCount = null,
    int? RoomCapacity = null,
    string? RoomAdmissionMode = null,
    string? RoomLanguage = null,
    string? RoomVoiceRequirement = null,
    string[]? RoomGameplayTagNodeIds = null);

public static class ChatAttachmentPolicy
{
    public const int MaximumPresetPackageLength = 96 * 1024;

    public static bool TryNormalize(
        ChatAttachmentContract? value,
        out ChatAttachmentContract? normalized,
        out string? error)
    {
        normalized = null;
        error = null;
        if (value is null)
        {
            return true;
        }

        var kind = value.Kind?.Trim().ToLowerInvariant() ?? "";
        var title = NormalizeText(value.Title, 64);
        var summary = NormalizeText(value.Summary, 240);
        if (title.Length == 0 || summary.Length == 0)
        {
            error = "消息卡片缺少标题或说明。";
            return false;
        }

        switch (kind)
        {
            case ChatAttachmentKinds.OverlayPreset:
            {
                var package = value.OverlayPresetPackage?.Trim() ?? "";
                if (!IsValidOverlayPresetPackage(package))
                {
                    error = "浮层预设内容无效或超过大小限制。";
                    return false;
                }

                normalized = new ChatAttachmentContract(kind, title, summary, OverlayPresetPackage: package);
                return true;
            }
            case ChatAttachmentKinds.FleetInvitation:
            {
                var code = NormalizeToken(value.FleetInviteCode, 40).ToUpperInvariant();
                if (code.Length < 6)
                {
                    error = "舰队邀请码无效。";
                    return false;
                }

                normalized = new ChatAttachmentContract(
                    kind,
                    title,
                    summary,
                    FleetInviteCode: code,
                    ExpiresAt: value.ExpiresAt);
                return true;
            }
            case ChatAttachmentKinds.PartyRoomInvitation:
            {
                var roomId = NormalizeToken(value.RoomId, 80);
                var invitationId = NormalizeToken(value.RoomInvitationId, 80);
                if (roomId.Length < 8 || invitationId.Length < 8 || value.ExpiresAt is null)
                {
                    error = "房间邀请信息不完整。";
                    return false;
                }

                normalized = new ChatAttachmentContract(
                    kind,
                    title,
                    summary,
                    RoomId: roomId,
                    RoomInvitationId: invitationId,
                    ExpiresAt: value.ExpiresAt,
                    RoomStatus: NormalizeToken(value.RoomStatus, 24).ToLowerInvariant(),
                    RoomMemberCount: Math.Max(0, value.RoomMemberCount ?? 0),
                    RoomCapacity: Math.Clamp(value.RoomCapacity ?? 0, 0, 100),
                    RoomAdmissionMode: NormalizeToken(value.RoomAdmissionMode, 24).ToLowerInvariant(),
                    RoomLanguage: NormalizeToken(value.RoomLanguage, 24).ToLowerInvariant(),
                    RoomVoiceRequirement: NormalizeToken(value.RoomVoiceRequirement, 24).ToLowerInvariant(),
                    RoomGameplayTagNodeIds: (value.RoomGameplayTagNodeIds ?? [])
                        .Select(id => NormalizeToken(id, 80).ToLowerInvariant())
                        .Where(id => id.Length > 0)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .Take(6)
                        .ToArray());
                return true;
            }
            default:
                error = "不支持这种消息卡片。";
                return false;
        }
    }

    public static string BuildPreview(ChatAttachmentContract attachment) => attachment.Kind switch
    {
        ChatAttachmentKinds.OverlayPreset => $"[浮层预设] {attachment.Title}",
        ChatAttachmentKinds.FleetInvitation => $"[舰队邀请] {attachment.Title}",
        ChatAttachmentKinds.PartyRoomInvitation => $"[房间邀请] {attachment.Title}",
        _ => $"[消息卡片] {attachment.Title}"
    };

    private static bool IsValidOverlayPresetPackage(string package)
    {
        if (package.Length is < 16 or > MaximumPresetPackageLength)
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(package);
            var root = document.RootElement;
            return root.ValueKind == JsonValueKind.Object &&
                   TryGetProperty(root, "version", out var version) && version.TryGetInt32(out var versionValue) && versionValue == 1 &&
                   TryGetProperty(root, "name", out var name) && !string.IsNullOrWhiteSpace(name.GetString()) &&
                   TryGetProperty(root, "settings", out var settings) && !string.IsNullOrWhiteSpace(settings.GetString()) &&
                   TryGetProperty(root, "layout", out var layout) && !string.IsNullOrWhiteSpace(layout.GetString());
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        foreach (var property in element.EnumerateObject())
        {
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }

        value = default;
        return false;
    }

    private static string NormalizeText(string? value, int maximumLength)
    {
        var normalized = string.Join(' ', (value ?? "")
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
            .Trim();
        return normalized.Length <= maximumLength ? normalized : normalized[..maximumLength];
    }

    private static string NormalizeToken(string? value, int maximumLength)
    {
        var normalized = (value ?? "").Trim();
        if (normalized.Length > maximumLength || normalized.Any(char.IsControl))
        {
            return "";
        }

        return normalized;
    }
}
