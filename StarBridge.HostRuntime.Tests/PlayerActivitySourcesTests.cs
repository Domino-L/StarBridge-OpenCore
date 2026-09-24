using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.PartyRooms;

internal static class PlayerActivitySourcesTests
{
    internal static async Task Verify()
    {
        var friends = FriendsReader.Parse(FriendsReaderTests.Directory(), observePresence: true);
        var observed = PlayerActivitySources.Friends(friends);
        Check(observed.IsComplete && observed.Members.Single().Presence == "inGame", "opted-in accepted friend has authoritative state");
        Check(!JsonSerializer.Serialize(friends).Contains("ObservedPresence") && !JsonSerializer.Serialize(friends).Contains("InGame"), "friend observation does not extend the UI wire contract");
        Check(!PlayerActivitySources.Friends(FriendsReader.Parse(FriendsReaderTests.Directory())).Members.Single().AllowsPresenceEvents, "ordinary friend reads never collect presence");
        var unknownFriend = friends with { Friends = [friends.Friends[0] with { Relationship = "unknown" }] };
        Check(PlayerActivitySources.Friends(unknownFriend).Members.Length == 0, "unknown friendship never grants event eligibility");
        foreach (var text in new[] { "", "paused", "hidden", "future-value" })
            Check(PlayerActivitySources.Presence(text) == "unknown", "unknown is not offline");
        var fleets = new[] { E(new { members = new[] {
            new { accountId = "one", callsign = "Same", gameName = "" },
            new { accountId = "two", callsign = "Same", gameName = "" },
            new { accountId = "", callsign = "Anonymous", gameName = "Guess" }
        } }) };
        var players = E(new[] {
            new { accountId = "one", liveStatus = "Offline", online = false, sharedEventTypes = 1, lastUpdated = DateTimeOffset.UtcNow },
            new { accountId = "unrelated", liveStatus = "InGame", online = true, sharedEventTypes = 1, lastUpdated = DateTimeOffset.UtcNow }
        });
        var roster = PlayerActivitySources.Organization(fleets, players);
        Check(roster.Members.Length == 2 && roster.Members[0].Presence == "offline" && roster.Members[0].AllowsPresenceEvents,
            "only stable roster IDs intersect visible players; explicit offline is observed");
        Check(roster.Members[1].Presence == "unknown" && !roster.Members[1].AllowsPresenceEvents,
            "missing player is not a synthetic offline event");
        Check(PlayerActivitySources.Opaque("a", "one") == PlayerActivitySources.Opaque("a", "one") &&
            PlayerActivitySources.Opaque("b", "one") != PlayerActivitySources.Opaque("a", "one"), "stable within scope, different between accounts");
        var room = new RoomView("r", "Room", "", 2, false, "", "", false, "", "", DateTimeOffset.UtcNow.AddHours(1), null, false,
            [new("Pilot", "", false, "游戏中 · LIVE", "", "", "") { AccountId = "one" }]);
        var directory = new RoomDirectoryView(null, DateTimeOffset.UtcNow, [room]);
        Check(PlayerActivitySources.Room(directory).Members.Length == 0, "discovery rooms never count as current-room audience");
        Check(PlayerActivitySources.Room(directory with { CurrentRoomId = "r" }).Members.Single().Presence == "inGame", "current-room complete roster is observed");
        var joined = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        object Fleet(string code) => new { code, name = "Organization " + code, members = new[] {
            new { accountId = "viewer", callsign = "Viewer", joinedAt = joined },
            new { accountId = "one", callsign = "Pilot", joinedAt = joined }
        } };
        var overlap = PlayerActivitySources.Organization([E(Fleet("A")), E(Fleet("B"))], players, "viewer");
        Check(overlap.Members.Single(m => m.AccountId == "one").Organizations!.Select(o => o.Name)
            .SequenceEqual(new[] { "Organization A", "Organization B" }), "authorized organization names are retained per policy path");
        Check(PlayerActivitySources.Organization([E(Fleet("A"))], players, "outsider").Members.All(m => m.Organizations!.Length == 0),
            "organization labels require a verified viewer membership");
        Check(overlap.Members.Single(m => m.AccountId == "one").PolicySources!.Order().SequenceEqual(new[] {
            NotificationPolicyStore.Organization("A", joined), NotificationPolicyStore.Organization("B", joined)
        }.Order()), "overlapping organizations preserve both policy paths without duplicate players");
        await PlayerActivityPolicyTests.Run();
    }
    private static JsonElement E(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool condition, string reason) { if (!condition) throw new InvalidOperationException(reason); }
}
