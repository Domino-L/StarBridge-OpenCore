using System.Reflection;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

/// <summary>Member rotation: fixed pages, groups, hold while a row cues, jump to unseen relevant changes.</summary>
internal static class OverlayMemberPagingTests
{
    private const string Shard = "pub_use1_fixture_001";
    private const string OtherShard = "pub_euw1_fixture_002";
    // Header/padding 52 + six 35px rows.
    private const double SixRows = 52 + 6 * 35;

    internal static void RunAll()
    {
        FixedPagesCoverEveryMemberOnce();
        HoldWhileVisibleRowCues();
        JumpToPageWithUnseenRelevantChange();
        DataGapsAreNotChanges();
        ViewModelRotatesHoldsAndJumps();
        HostPreferencesSelectRotation();
        Console.WriteLine("PASS member rotation: fixed pages, groups, hold on change, jump to relevant change, gaps ignored");
    }

    private static void FixedPagesCoverEveryMemberOnce()
    {
        var roster = new OverlayAuthorizedRoster(Roster());
        var settings = Settings();
        var seen = new List<string>();
        for (var page = 0; page < 3; page++)
        {
            var plan = OverlayRosterPlanner.Project(roster, settings, new OverlayRosterViewport(SixRows, Shard, null, page));
            var ids = roster.Resolve(plan).Select(p => p.AccountId!).ToArray();
            Check(plan.PageCount == 3 && plan.PageIndex == page, $"12 automatic members over 4 slots are 3 pages (page {page})");
            Check(ids.Take(2).SequenceEqual(["pin-a", "pin-b"]), "pinned members stay at the top of every page");
            Check(plan.Groups.Take(2).All(g => g == OverlayRosterGroup.Pinned) &&
                  plan.Groups.Skip(2).All(g => g != OverlayRosterGroup.Pinned), "pinned rows are grouped apart");
            seen.AddRange(ids.Skip(2));
        }

        Check(seen.Count == 12 && seen.Distinct().Count() == 12, "every automatic member appears on exactly one page");
        var wrapped = OverlayRosterPlanner.Project(roster, settings, new OverlayRosterViewport(SixRows, Shard, null, 3));
        Check(wrapped.PageIndex == 0, "after the last page the rotation returns to the first");
        Check(wrapped.RotationPages.Count == 12 && wrapped.RotationPages.Values.Distinct().Order().SequenceEqual([0, 1, 2]),
            "every automatic member is mapped to its page");
        var first = OverlayRosterPlanner.Project(roster, settings, new OverlayRosterViewport(SixRows, Shard, null, 0));
        Check(first.Groups.Skip(2).First() == OverlayRosterGroup.SameServer, "same-server members lead the automatic pages");
    }

    private static void HoldWhileVisibleRowCues()
    {
        var tracker = new OverlayMemberPagingTracker();
        var now = DateTimeOffset.UtcNow;
        var players = Roster();
        var visible = Keys("pin-a", "pin-b", "m01", "m02", "m03", "m04");
        tracker.Observe(Classify(players), visible, true, now);
        var moved = players.Select(p => p.AccountId == "m02" ? p with { SharedLocation = "Lorville", RawLocation = "Lorville" } : p).ToArray();
        tracker.Observe(Classify(moved), visible, true, now.AddSeconds(1));
        Check(tracker.TryHold(["m01", "m02", "m03", "m04"], now.AddSeconds(2), out var wait) && wait > TimeSpan.Zero,
            "a visible row showing its change cue holds the page");
        Check(tracker.CueStartedAt("m02", now.AddSeconds(2)) is not null, "the changed visible row gets a cue");
        Check(!tracker.TryHold(["m01", "m02", "m03", "m04"], now.AddSeconds(4.5), out _), "the page flips once the cue has played");
    }

    private static void JumpToPageWithUnseenRelevantChange()
    {
        var tracker = new OverlayMemberPagingTracker();
        var now = DateTimeOffset.UtcNow;
        var players = Roster();
        var visible = Keys("pin-a", "pin-b", "m01", "m02", "m03", "m04");
        tracker.Observe(Classify(players), visible, true, now);
        // m09 is on another server; moving to the viewer's server matters to them.
        var joined = players.Select(p => p.AccountId == "m09" ? p with { ServerShard = Shard } : p).ToArray();
        tracker.Observe(Classify(joined), visible, true, now.AddSeconds(1));
        var pages = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase) { ["m09"] = 2, ["m05"] = 1 };
        Check(tracker.PendingPages(pages, 0).SequenceEqual([2]), "the page with the unseen change is marked");
        Check(tracker.TryTakeJump(pages, 0, now.AddSeconds(2), out var page) && page == 2, "the next flip goes to that page");
        Check(tracker.CueStartedAt("m09", now.AddSeconds(2.1)) is not null, "the changed row cues when its page shows");
        Check(!tracker.TryTakeJump(pages, 2, now.AddSeconds(3), out _), "a change is jumped to only once");
    }

    private static void DataGapsAreNotChanges()
    {
        var tracker = new OverlayMemberPagingTracker();
        var now = DateTimeOffset.UtcNow;
        var players = Roster();
        var visible = Keys("pin-a", "pin-b", "m01", "m02", "m03", "m04");
        tracker.Observe(Classify(players), visible, true, now);
        var gap = players.Select(p => p.AccountId is "m02" or "m09"
            ? p with { ServerShard = null, SharedLocation = null, RawLocation = "Unknown", Location = "Unknown" }
            : p).ToArray();
        for (var i = 1; i <= 3; i++)
        {
            tracker.Observe(Classify(gap), visible, true, now.AddSeconds(i * 2));
            tracker.Observe(Classify(players), visible, true, now.AddSeconds(i * 2 + 1));
        }

        var pages = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase) { ["m09"] = 2 };
        Check(tracker.CueStartedAt("m02", now.AddSeconds(7.5)) is null, "missing location or shard does not cue a visible row");
        Check(tracker.PendingPages(pages, 0).Count == 0, "missing data does not mark a hidden member as changed");
        // An unknown local shard cannot make anyone "join" the viewer's server.
        tracker.Observe(Classify(players, localShard: null), visible, false, now.AddSeconds(8));
        tracker.Observe(Classify(players), visible, true, now.AddSeconds(9));
        Check(tracker.PendingPages(pages, 0).Count == 0, "a local shard gap is not a same-server join");
    }

    private static void ViewModelRotatesHoldsAndJumps()
    {
        var content = new InformationOverlayCommunityContent("fixture", "Community", []);
        var source = NativeInformationOverlayRuntime.ProjectSource(null, content, OverlayScenePreference.Auto, "zh");
        var settings = OverlayDisplaySettings.Default with { AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var selection = Settings();
        var players = Roster();
        var model = new OverlayViewModel(new(players), settings, selection, "zh", true,
            source.Command, PlayerPresenceKind.InGame, Shard, source.Scene.Context);
        var advance = typeof(OverlayViewModel).GetMethod("AdvanceMemberPage", BindingFlags.NonPublic | BindingFlags.Instance)!;
        void Refresh(PlayerRow[] rows) => model.Refresh(new(rows), settings, selection, "zh", true,
            source.Command, PlayerPresenceKind.InGame, Shard, source.Scene.Context);
        try
        {
            model.ApplyMemberViewport(SixRows);
            Check(model.MemberPaging.PageCount == 3 && model.MemberPaging.PageIndex == 0, "the model exposes three pages");
            Check(model.Members.Take(2).All(row => row.Group == OverlayRosterGroup.Pinned), "pinned rows carry their group");
            var sequence = model.MemberPaging.FlipSequence;
            advance.Invoke(model, null);
            Check(model.MemberPaging.PageIndex == 1 && model.MemberPaging.FlipSequence == sequence + 1, "a tick flips to the next page");

            // A visible row changes: the next tick holds the page.
            var visibleKey = model.Members.Skip(2).First().Key!;
            Refresh(players.Select(p => p.AccountId == visibleKey ? p with { SharedShip = "Hornet", RawShip = "Hornet", Ship = "Hornet" } : p).ToArray());
            Check(model.Members.Single(row => row.Key == visibleKey).CueStartedAtUtc is not null, "the changed visible row carries a cue");
            advance.Invoke(model, null);
            Check(model.MemberPaging.PageIndex == 1, "rotation holds while a visible row shows its change");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void HostPreferencesSelectRotation()
    {
        var unset = OverlayRosterSelectionSettings.FromHostPreferences(InformationOverlayRosterPreferences.Empty);
        Check(unset.OverflowMode == OverlayRosterOverflowMode.Summary && unset.UserRowLimit == 0 &&
              unset.RotationIntervalSeconds == 10, "unset host preferences keep the summary overflow");
        var rotate = OverlayRosterSelectionSettings.FromHostPreferences(
            new InformationOverlayRosterPreferences(["pin-a"], ["m12"], "rotate", 4, 20));
        Check(rotate.OverflowMode == OverlayRosterOverflowMode.Rotate && rotate.UserRowLimit == 4 &&
              rotate.RotationIntervalSeconds == 20 && rotate.PinnedAccountIds!.Single() == "pin-a" &&
              rotate.ExcludedAccountIds!.Single() == "m12", "host display options reach the overlay roster settings");
        var truncate = OverlayRosterSelectionSettings.FromHostPreferences(
            new InformationOverlayRosterPreferences([], [], "truncate"));
        Check(truncate.OverflowMode == OverlayRosterOverflowMode.Truncate, "truncate maps through");
    }

    private static PlayerRow[] Roster()
    {
        var rows = new List<PlayerRow>
        {
            Player("pin-a", Shard, "Orison"),
            Player("pin-b", OtherShard, "New Babbage")
        };
        for (var i = 1; i <= 12; i++)
            rows.Add(Player($"m{i:00}", i <= 4 ? Shard : OtherShard, i <= 2 ? "Orison" : "Lorville"));
        return rows.ToArray();
    }

    private static PlayerRow Player(string id, string shard, string location) => new(
        id, "Online", "Carrack", "Ship: Carrack", location,
        Callsign: id, RawLocation: location, ServerShard: shard, LiveStatus: "InGame", AccountId: id,
        SharedOnlineStatus: "Online", SharedLiveStatus: "InGame", SharedShip: "Carrack", SharedLocation: location);

    private static OverlayRosterSelectionSettings Settings() => new(
        PinnedAccountIds: ["pin-a", "pin-b"], OverflowMode: OverlayRosterOverflowMode.Rotate);

    private static IReadOnlyList<(PlayerRow Player, bool SameServer, bool SameLocation, bool Online)> Classify(
        PlayerRow[] players, string? localShard = Shard) =>
        OverlayRosterPlanner.ClassifyMembers(new OverlayAuthorizedRoster(players), new OverlayRosterViewport(SixRows, localShard, "Orison"));

    private static HashSet<string> Keys(params string[] keys) => new(keys, StringComparer.OrdinalIgnoreCase);

    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
