using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Notifications;

internal static class PlayerActivitySources
{
    private static readonly byte[] Salt = RandomNumberGenerator.GetBytes(32);
    internal static string Opaque(string scope, string value) =>
        Convert.ToHexString(HMACSHA256.HashData(Salt, Encoding.UTF8.GetBytes(scope + "\0" + value))).ToLowerInvariant();

    // Unknown or redacted is not offline. Do not use the permissive UI label fallback.
    internal static string Presence(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "online" or "apponline" or "app online" or "applicationonline" or "应用在线" or "應用在線" or "在线" or "在線" => "online",
        "ingame" or "in game" or "playing" or "游戏中" or "遊戲中" => "inGame",
        "away" or "idle" or "afk" or "暂离" or "暫離" => "away",
        "offline" or "离线" or "離線" => "offline",
        _ => "unknown"
    };

    internal static PlayerActivitySourceSnapshot Friends(FriendsView view) => new("friends", true,
        view.Friends.Where(member => member.Relationship == "friend").Select(member =>
            new PlayerActivitySourceMember(member.AccountId, member.Callsign, member.GameId,
                Presence(member.ObservedPresence), Presence(member.ObservedPresence) != "unknown", member.AvatarImageData)).ToArray());

    internal static PlayerActivitySourceSnapshot Room(RoomDirectoryView view)
    {
        var members = view.Rooms.SingleOrDefault(room => room.RoomId == view.CurrentRoomId)?.Members ?? [];
        return new("room", true, members.Where(member => !string.IsNullOrWhiteSpace(member.AccountId)).Select(member =>
        {
            // WPF may append a game-channel label after a middle dot.
            var presence = Presence(member.PresenceText.Split(['·', '•'], 2)[0]);
            return new PlayerActivitySourceMember(member.AccountId, member.Callsign, member.GameId,
                presence, presence != "unknown", member.AvatarImageData);
        }).ToArray());
    }

    internal static PlayerActivitySourceSnapshot Organization(JsonElement[] fleets, JsonElement players, string? viewerId = null)
    {
        if (players.ValueKind != JsonValueKind.Array || players.GetArrayLength() > 10000) throw new FormatException();
        var byId = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var player in players.EnumerateArray())
        {
            var id = Text(player, "accountId");
            if (id.Length > 0 && !byId.TryAdd(id, player)) throw new FormatException();
        }
        var members = new Dictionary<string, PlayerActivitySourceMember>(StringComparer.OrdinalIgnoreCase);
        foreach (var fleet in fleets)
        {
            var roster = fleet.GetProperty("members");
            if (roster.ValueKind != JsonValueKind.Array || roster.GetArrayLength() > 10000) throw new FormatException();
            var viewer = roster.EnumerateArray().Where(row => string.Equals(Text(row, "accountId"), viewerId, StringComparison.OrdinalIgnoreCase)).ToArray();
            string[] policy = viewerId != null && viewer.Length == 1 &&
                viewer[0].TryGetProperty("joinedAt", out var joined) && joined.TryGetDateTimeOffset(out var joinedAt) &&
                !string.IsNullOrWhiteSpace(Text(fleet, "code"))
                ? [NotificationPolicyStore.Organization(Text(fleet, "code"), joinedAt)] : [];
            var withinFleet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var organizations = policy.Select(key => new PlayerActivityOrganization(key, Text(fleet, "name")))
                .Where(row => !string.IsNullOrWhiteSpace(row.Name)).ToArray();
            foreach (var member in roster.EnumerateArray())
            {
                var id = Text(member, "accountId");
                if (id.Length == 0) continue; // Never substitute name, row number or expiring memberRef.
                if (!withinFleet.Add(id)) throw new FormatException();
                var presence = "unknown";
                var allowed = false;
                if (byId.TryGetValue(id, out var player))
                {
                    // Original WPF Presence event bit. The server removes this bit if events are not visible.
                    allowed = player.TryGetProperty("sharedEventTypes", out var events) && events.TryGetInt32(out var flags) && (flags & 1) != 0;
                    presence = Presence(Text(player, "liveStatus"));
                    if (!player.TryGetProperty("online", out var online) || online.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                        presence = "unknown";
                    else if (!online.GetBoolean() && presence != "offline") presence = "unknown";
                    // Redacted presence uses an empty timestamp in the original projection.
                    if (!player.TryGetProperty("lastUpdated", out var updated) || !updated.TryGetDateTimeOffset(out var at) || at == default)
                        presence = "unknown";
                }
                if (members.TryGetValue(id, out var existing)) {
                    members[id] = existing with {
                        PolicySources = (existing.PolicySources ?? []).Concat(policy).Distinct(StringComparer.Ordinal).ToArray(),
                        Organizations = (existing.Organizations ?? []).Concat(organizations).Distinct().ToArray()
                    };
                } else members.Add(id, new(id, Text(member, "callsign"), Text(member, "gameName"),
                    presence, allowed && presence != "unknown", RoomAvatarProjection.Normalize(Text(member, "avatarImageData", 1024 * 1024)), policy, organizations));
            }
        }
        return new("organization", true, members.Values.ToArray());
    }

    private static string Text(JsonElement row, string key, int max = 512)
    {
        if (!row.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null) return "";
        var text = value.GetString() ?? "";
        if (text.Length > max || text.Any(char.IsControl)) throw new FormatException();
        return text;
    }
}
