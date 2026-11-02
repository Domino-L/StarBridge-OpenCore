using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// Missing server data between refreshes is "unknown", not a transition. Field
/// report 2026-10-17: same-server, primary-server and fleet cards repeated at
/// random times because a briefly empty local shard or peer region was diffed
/// as a real leave/join.
/// </summary>
internal static class OverlayEventFlickerTests
{
    private const string Shard = "pub_use1_fixture_001";
    private const string OtherShard = "pub_euw1_fixture_002";

    internal static void RunAll()
    {
        LocalShardGapIsSilent();
        PeerServerGapIsSilent();
        PrimaryServerAnnouncesOncePerRealChange();
        RealTransitionsStillAnnounce();
        OnlineSummaryFollowsRealPresenceChanges();
        Console.WriteLine("PASS overlay server and fleet-online events ignore data gaps and announce real changes once");
    }

    private static void OnlineSummaryFollowsRealPresenceChanges()
    {
        var types = OverlayEventNotificationTypes.OnlineSummary;
        var full = Players(("A", Shard, null, false), ("B", Shard, null, false), ("C", Shard, null, false));
        var partial = full.Where(p => p.Name != "C").ToArray();
        var paused = full.Select(p => p.Name == "C" ? p with { LiveStatus = "Paused" } : p).ToArray();
        var offline = full.Select(p => p.Name == "C" ? p with { LiveStatus = "Offline", Status = "Offline" } : p).ToArray();
        Check(offline.Single(p => p.Name == "C").Presence != PlayerPresenceKind.InGame &&
              paused.Single(p => p.Name == "C").Presence != PlayerPresenceKind.InGame,
            "fixture: paused and offline rows must not count as in game");
        Run(types, full, Shard, (model, refresh) =>
        {
            for (var i = 0; i < 3; i++)
            {
                refresh(partial, Shard);
                refresh(full, Shard);
            }
            Check(Count(model) == 0, $"a refresh with an incomplete roster is not members going offline ({Describe(model)})");
            for (var i = 0; i < 3; i++)
            {
                refresh(paused, Shard);
                refresh(full, Shard);
            }
            Check(Count(model) == 0, $"pausing sync is not leaving the game for the fleet summary ({Describe(model)})");
            refresh(offline, Shard);
            Check(Count(model) == 1, $"a member really leaving the game updates the fleet summary once ({Describe(model)})");
            refresh(offline, Shard);
            refresh(full, Shard);
            Check(Count(model) == 2, $"the member really returning is announced once ({Describe(model)})");
        });
    }

    private static void LocalShardGapIsSilent()
    {
        var types = OverlayEventNotificationTypes.SameServer | OverlayEventNotificationTypes.MemberServer;
        var players = Players(("Self", Shard, null, true), ("Peer1", Shard, null, false), ("Peer2", Shard, null, false));
        Run(types, players, Shard, (model, refresh) =>
        {
            for (var i = 0; i < 3; i++)
            {
                refresh(players, "");
                refresh(players, Shard);
            }
            Check(Count(model) == 0, $"a briefly empty local shard must not announce same-server join/leave or the summary again ({Describe(model)})");
        });
    }

    private static void PeerServerGapIsSilent()
    {
        var types = OverlayEventNotificationTypes.SameServer | OverlayEventNotificationTypes.MemberServer |
                    OverlayEventNotificationTypes.PrimaryServer;
        var players = Players(("Self", Shard, null, true), ("Peer1", Shard, null, false), ("Peer2", Shard, null, false));
        var gap = players.Select(p => p.Name == "Peer1" ? p with { ServerShard = null, ServerRegion = null } : p).ToArray();
        Run(types, players, Shard, (model, refresh) =>
        {
            for (var i = 0; i < 3; i++)
            {
                refresh(gap, Shard);
                refresh(players, Shard);
            }
            Check(Count(model) == 0, $"an in-game peer whose server data is briefly missing must not leave and rejoin ({Describe(model)})");
        });
    }

    private static void PrimaryServerAnnouncesOncePerRealChange()
    {
        var types = OverlayEventNotificationTypes.PrimaryServer;
        var tie = Players(("A", null, "EU", false), ("B", null, "US", false));
        var usLead = Players(("A", null, "EU", false), ("B", null, "US", false), ("C", null, "US", false));
        var cGap = usLead.Select(p => p.Name == "C" ? p with { ServerRegion = null } : p).ToArray();
        var euLead = Players(("A", null, "EU", false), ("B", null, "US", false), ("D", null, "EU", false), ("E", null, "EU", false));
        Run(types, tie, "", (model, refresh) =>
        {
            refresh(usLead, "");
            Check(Count(model) == 1, $"a real lead change announces the primary server once ({Describe(model)})");
            refresh(cGap, "");
            refresh(usLead, "");
            refresh(cGap, "");
            Check(Count(model) == 1, $"a member's missing region must not flip the primary server back and forth ({Describe(model)})");
            refresh(tie, "");
            refresh(usLead, "");
            refresh(tie, "");
            Check(Count(model) == 1, $"a tie keeps the announced primary server instead of re-announcing ({Describe(model)})");
            refresh(euLead, "");
            Check(Count(model) == 2, $"a clear new lead is announced ({Describe(model)})");
            refresh(euLead, "");
            Check(Count(model) == 2, "an unchanged frame never repeats the announcement");
        });
    }

    private static void RealTransitionsStillAnnounce()
    {
        var types = OverlayEventNotificationTypes.SameServer;
        var apart = Players(("Self", Shard, null, true), ("Peer1", OtherShard, null, false));
        var together = Players(("Self", Shard, null, true), ("Peer1", Shard, null, false));
        Run(types, apart, Shard, (model, refresh) =>
        {
            refresh(together, Shard);
            Check(Count(model) == 1, $"a peer really joining your server is announced once ({Describe(model)})");
            refresh(together, Shard);
            Check(Count(model) == 1, "an unchanged frame never repeats the join");
            refresh(apart, Shard);
            Check(Count(model) == 2, $"a peer really leaving your server is announced ({Describe(model)})");
        });
        // Entering a server for the first time still produces one summary card.
        Run(types, together, "", (model, refresh) =>
        {
            refresh(together, Shard);
            var summaries = model.EventNotifications.Count(card => card.Title is "同服概况");
            refresh(together, Shard);
            refresh(together, "");
            refresh(together, Shard);
            Check(summaries == 1 && model.EventNotifications.Count(card => card.Title is "同服概况") == 1,
                $"the same-server summary appears once per server, not after each gap ({Describe(model)})");
        });
        // Organization members with event sharing off: their shard may be on screen, but no card is built from it.
        var silent = together.Select(p => p with { SharedEventTypes = 0 }).ToArray();
        Run(types, silent, "", (model, refresh) =>
        {
            refresh(silent, Shard);
            Check(model.EventNotifications.All(card => card.Title is not "同服概况"), $"no summary without event sharing ({Describe(model)})");
        });
    }

    private static PlayerRow[] Players(params (string Name, string? Shard, string? Region, bool Self)[] rows)
    {
        var content = new InformationOverlayCommunityContent("fixture", "Community",
            rows.Select(r => new InformationOverlayCommunityMember(r.Name, r.Name, "Member", "InGame", "", "", r.Region ?? "", r.Self))
                .ToArray());
        var source = NativeInformationOverlayRuntime.ProjectSource(null, content, OverlayScenePreference.Auto, "zh");
        var players = source.Scene.Players.Select(p =>
        {
            var row = rows.Single(r => r.Name == p.Name || r.Name == p.Callsign);
            // Peers who share per-player server events (room members or granted sharing).
            return p with { ServerShard = row.Shard, ServerRegion = row.Region, SharedEventTypes = (int)PlayerSharedEventTypes.All };
        }).ToArray();
        Check(players.Length == rows.Length, "every fixture row is projected");
        return players;
    }

    private static void Run(OverlayEventNotificationTypes types, PlayerRow[] baseline, string localShard,
        Action<OverlayViewModel, Action<PlayerRow[], string>> body)
    {
        var content = new InformationOverlayCommunityContent("fixture", "Community", []);
        var source = NativeInformationOverlayRuntime.ProjectSource(null, content, OverlayScenePreference.Auto, "zh");
        var settings = OverlayDisplaySettings.Default with
        {
            ShowEventNotifications = true,
            EventNotificationTypes = types,
            EventNotificationMaxVisibleCount = 5,
            AnimationFrameRate = OverlayAnimationFrameRate.Off
        };
        var model = new OverlayViewModel(new(baseline), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            source.Command, PlayerPresenceKind.InGame, localShard, source.Scene.Context);
        try
        {
            model.EventNotifications.Clear();
            body(model, (players, shard) => model.Refresh(new(players), settings, OverlayRosterSelectionSettings.Default,
                "zh", true, source.Command, PlayerPresenceKind.InGame, shard, source.Scene.Context));
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static int Count(OverlayViewModel model) =>
        model.EventNotifications.Count(card => card.EventType != OverlayEventNotificationTypes.None) +
        model.PendingEventNotificationCount;

    private static string Describe(OverlayViewModel model) =>
        string.Join(" | ", model.EventNotifications.Select(card => $"{card.Title}:{card.Detail}")) +
        $" (+{model.PendingEventNotificationCount} pending)";

    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
