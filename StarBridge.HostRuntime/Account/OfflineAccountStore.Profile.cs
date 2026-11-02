using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class OfflineAccountStore
{
    internal void ClearRemoteProfile(BridgeAccountContext owner, Func<bool> current) =>
        Write(old => old?.Owner == owner && old.OfflineRevision is null ? old with { Profile = null } : old, current);

    // Drops only the image; the saved profile text and its time stay.
    internal void ClearStoredAvatar(BridgeAccountContext owner, Func<bool> current) =>
        Write(old =>
        {
            if (old?.Owner != owner || old.OfflineRevision is not null || old.Profile is not { } saved ||
                Display(old).AvatarImageData is null) return old;
            var copy = JsonNode.Parse(saved.Payload.GetRawText())!.AsObject();
            copy["profile"]!["identity"]!["avatarAssetId"] = null;
            return old with { Profile = saved with { Payload = JsonSerializer.SerializeToElement(copy, Json) } };
        }, current);

    internal void ObserveAvatarProfile(BridgeAccountContext owner,
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile, Func<bool> current) =>
        ObserveProfile(owner, JsonSerializer.SerializeToElement(new { schemaVersion = 1, editable = true,
            profile = new { profile.Revision, profile.AvatarStyle, profile.WallpaperId, profile.Presentation,
                profile.GameplayStatistics, identity = new { callSign = profile.Identity.Callsign,
                    avatarAssetId = profile.Identity.AvatarAssetId }, content = profile.Content } }, Json), current);

    private static OfflineAccountDisplay Display(Document value)
    {
        var image = value.Profile is { } profile && profile.Payload.TryGetProperty("profile", out var data) &&
            data.ValueKind == JsonValueKind.Object && data.TryGetProperty("identity", out var identity) &&
            identity.ValueKind == JsonValueKind.Object && identity.TryGetProperty("avatarAssetId", out var avatar) &&
            avatar.ValueKind == JsonValueKind.String
            ? PartyRooms.RoomAvatarProjection.Normalize(avatar.GetString(), 512 * 1024) : null;
        return new(value.DisplayName, value.CachedAtUtc, image, image is null ? null : value.Profile!.CachedAtUtc);
    }

    internal void ObserveProfile(BridgeAccountContext owner, JsonElement payload, Func<bool> current)
    {
        if (payload.GetRawText().Length > 1024 * 1024 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.GetInt32() != 1 ||
            !payload.TryGetProperty("editable", out var editable) || editable.ValueKind != JsonValueKind.True ||
            !payload.TryGetProperty("profile", out var profile) || profile.ValueKind != JsonValueKind.Object ||
            !profile.TryGetProperty("identity", out var identity) || identity.ValueKind != JsonValueKind.Object ||
            !identity.TryGetProperty("callSign", out var name) || name.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(name.GetString()) || name.GetString()!.Length > 256 ||
            !profile.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Object) return;

        // Preserve authored presentation only. Cached identity, affiliation, presence
        // and privacy fields must not become live game/organization/write authority.
        var display = new JsonObject { ["isPublic"] = false, ["visibility"] = "private" };
        foreach (var key in new[] { "revision", "avatarStyle", "wallpaperId", "presentation", "gameplayStatistics" })
            if (profile.TryGetProperty(key, out var value)) display[key] = JsonNode.Parse(value.GetRawText());
        var avatar = identity.TryGetProperty("avatarAssetId", out var rawAvatar) && rawAvatar.ValueKind == JsonValueKind.String
            ? PartyRooms.RoomAvatarProjection.Normalize(rawAvatar.GetString(), 512 * 1024) : null;
        display["identity"] = new JsonObject { ["callSign"] = name.GetString(), ["gameHandle"] = "", ["avatarAssetId"] = avatar };
        var savedContent = JsonNode.Parse(content.GetRawText())!.AsObject();
        savedContent["presenceIntent"] = null;
        display["content"] = savedContent;
        var copy = JsonSerializer.SerializeToElement(new { schemaVersion = 1, editable = false, profile = display }, Json);
        Write(old => old?.Owner == owner && old.OfflineRevision is null
            ? old with { Profile = new(copy, DateTimeOffset.UtcNow) } : old, current);
    }

    internal OfflinePersonalProfileDisplay? ReadRemoteProfile(long revision)
    {
        var value = Read();
        return value?.OfflineRevision == revision ? value.Profile : null;
    }
}
