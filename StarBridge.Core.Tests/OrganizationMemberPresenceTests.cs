using StarBridge.Core.Presence;

namespace StarBridge.Core.Tests;

internal static class OrganizationMemberPresenceTests
{
    private static readonly string?[] OfflineInputs =
    [
        "Offline", "ManualOffline", "manual-offline", "MANUAL_OFFLINE",
        " Invisible ", "iNvIsIbLe", "Paused", " pAuSeD ", "SyncPaused", "Stopped",
        "Suspended", "SyncStopped", null, "", "   ", "Unknown", " unknown ",
        "Unrecognized", "hidden", "notConnected", "FuturePresenceV2",
        // These are recognized by the general/owner policy, but are not the
        // existing Flutter public organization vocabulary.
        "Game", "Playing", "GameRunning", "Active", "游戏中", "In Game", "In-Game", "In_Game",
        "Idle", "AFK", "暂离", "ApplicationOnline", "应用在线", "在线", "App Online", "App-Online", "App_Online",
    ];

    internal static void RunAll()
    {
        ProjectionPrecedesRosterConsumers();
        foreach (var status in OfflineInputs)
        foreach (var online in new[] { false, true })
        {
            var reason = $"{status ?? "<null>"}/{online}";
            Check(OrganizationMemberPresence.Resolve(status, online) == PlayerPresenceKind.Offline,
                "Organization unavailable/private presence must be ordinary offline: " + reason);
            Check(OrganizationMemberPresence.IsOffline(status, online),
                "Organization offline predicate agrees with public projection: " + reason);
            Check(OrganizationMemberPresence.SortRank(status, online) == OrganizationMemberPresence.SortRank("Offline", false),
                "Organization unavailable/private presence cannot change pagination rank: " + reason);
        }

        foreach (var (status, expected) in new[]
        {
            ("InGame", PlayerPresenceKind.InGame), (" iNgAmE ", PlayerPresenceKind.InGame),
            ("AppOnline", PlayerPresenceKind.AppOnline), (" aPpOnLiNe ", PlayerPresenceKind.AppOnline),
            ("Online", PlayerPresenceKind.AppOnline), (" oNlInE ", PlayerPresenceKind.AppOnline),
            ("Away", PlayerPresenceKind.Away), (" aWaY ", PlayerPresenceKind.Away),
        })
        {
            Check(OrganizationMemberPresence.Resolve(status, true) == expected,
                "Explicit public organization status is preserved: " + status);
            Check(OrganizationMemberPresence.IsOffline(status, false),
                "Offline transport authority remains offline: " + status);
        }

        // The shared general policy still serves owner settings/friends and
        // intentionally retains broader aliases and its default behavior.
        Check(PlayerPresence.Normalize("Paused", true) == PlayerPresenceKind.Paused, "Owner pause policy unchanged");
        Check(PlayerPresence.Normalize("Unknown", true) == PlayerPresenceKind.AppOnline, "General default policy unchanged");
        Check(PlayerPresence.Normalize(null, true) == PlayerPresenceKind.AppOnline, "General missing-state policy unchanged");
        Check(PlayerPresence.Normalize("Game", true) == PlayerPresenceKind.InGame, "General game alias unchanged");
        Check(PlayerPresence.Normalize("Idle", true) == PlayerPresenceKind.Away, "General away alias unchanged");
        Check(PlayerPresence.Normalize("ApplicationOnline", true) == PlayerPresenceKind.AppOnline, "General online alias unchanged");
    }

    private static void ProjectionPrecedesRosterConsumers()
    {
        // Keep identity/source order identical while replacing only the subject's
        // raw presence. More than 20 records exercises a real page boundary.
        var tails = Enumerable.Range(0, 20).Select(i => new SourceMember($"tail-{i:00}", "Offline", false));
        var visible = new[]
        {
            new SourceMember("app", "AppOnline", true),
            new SourceMember("game", "InGame", true),
            new SourceMember("away", "Away", true),
        };
        var ordinary = new[] { new SourceMember("subject", "Offline", false) }.Concat(tails).Concat(visible).ToArray();
        var expected = Project(ordinary);
        var expectedOrder = new[] { "game", "app", "away", "subject" }
            .Concat(Enumerable.Range(0, 20).Select(i => $"tail-{i:00}")).ToArray();
        Check(OrderedIds(expected).SequenceEqual(expectedOrder), "Ordinary offline fixture has the expected stable roster order");
        Check(expected.Count(row => PlayerPresence.IsOnline(row.Presence)) == 3, "Ordinary fixture online count");
        Check(expected.Count(row => row.Presence == PlayerPresenceKind.InGame) == 1, "Ordinary fixture game count");

        foreach (var status in OfflineInputs)
        foreach (var online in new[] { false, true })
        {
            var raw = ordinary.ToArray();
            raw[0] = new SourceMember("subject", status, online);
            var projected = Project(raw);
            var reason = $"{status ?? "<null>"}/{online}";
            Check(OrderedIds(projected).SequenceEqual(expectedOrder),
                "Public projection precedes roster ordering: " + reason);
            Check(projected.Count(row => PlayerPresence.IsOnline(row.Presence)) == 3 &&
                  projected.Count(row => row.Presence == PlayerPresenceKind.InGame) == 1,
                "Public projection precedes online/game counts: " + reason);
            foreach (var filter in new[] { "all", "online", "inGame", "offline" })
            {
                var actualIds = FilteredIds(projected, filter);
                var expectedIds = FilteredIds(expected, filter);
                Check(actualIds.SequenceEqual(expectedIds), "Public projection precedes status filtering: " + filter + "/" + reason);
                for (var offset = 0; offset < expectedIds.Length; offset += 20)
                    Check(actualIds.Skip(offset).Take(20).SequenceEqual(expectedIds.Skip(offset).Take(20)),
                        $"Public projection precedes filtered 20-row pagination: {filter}/{offset}/{reason}");
            }
        }
    }

    private static PublicMember[] Project(IEnumerable<SourceMember> source) => source.Select((row, order) =>
        new PublicMember(row.Id, OrganizationMemberPresence.Resolve(row.Status, row.Online),
            OrganizationMemberPresence.SortRank(row.Status, row.Online), order)).ToArray();

    private static string[] OrderedIds(IEnumerable<PublicMember> source) =>
        source.OrderBy(row => row.Rank).ThenBy(row => row.SourceOrder).Select(row => row.Id).ToArray();

    private static string[] FilteredIds(IEnumerable<PublicMember> source, string filter) => OrderedIds(source.Where(row => filter switch
    {
        "online" => PlayerPresence.IsOnline(row.Presence),
        "inGame" => row.Presence == PlayerPresenceKind.InGame,
        "offline" => row.Presence == PlayerPresenceKind.Offline,
        _ => true,
    }));

    private readonly record struct SourceMember(string Id, string? Status, bool Online);
    private readonly record struct PublicMember(string Id, PlayerPresenceKind Presence, int Rank, int SourceOrder);

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
