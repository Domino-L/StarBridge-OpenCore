using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Rect = System.Windows.Rect;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// 11-14 (user, "甲 按推荐"): a member whose state is not known is "未知" on the visor, drawn like offline with its name
/// at full strength, never as in game. "实时状态未知" shows only when every member is unknown (the read went stale), on
/// the visor and the classic overview alike; one unknown member leaves the overview and the others' events running.
/// The classic list's own lines ("另有 N 人", "暂无可显示成员") stay out of the visor.
/// </summary>
internal static class OverlayVisorUnknownTests
{
    private const string Shard = "pub_use1_fixture_001";
    private const int W = 2560, H = 1440;
    private static readonly BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    private static int _failures;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) _failures++;
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "CHECK", Name = name, Status = value ? "PASS" : "FAIL", Evidence = evidence }));
    }

    private static object? Call(object target, string name, params object?[] values) =>
        target.GetType().GetMethods(All).Single(m => m.Name == name && m.GetParameters().Length == values.Length).Invoke(target, values);

    private static OverlayVisorScene Scene(OverlayCompositionHudWindow window) =>
        (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;

    private static PlayerRow Unknown(PlayerRow row) => row with { RealtimeStateUnknown = true };

    internal static void Run()
    {
        _failures = 0;
        OneUnknownMember();
        EveryMemberUnknown();
        PlaceholderRowsStayOut();
        ClassicOverviewAndEvents();
        StaleSourceWithLocalSelf();
        BatchedRecoveryStartsFresh();
        NeverKnownMemberStillCounted();
        if (_failures != 0) throw new InvalidOperationException($"Visor unknown-state failures: {_failures}");
        Console.WriteLine("PASS visor unknown state: 未知 drawn like offline, 实时状态未知 only when all are unknown, placeholder rows stay out");
    }

    private static void OneUnknownMember()
    {
        using var window = OverlayVisorTests.Window(3, W, H, row: i => i == 1 ? Unknown(OverlayVisorTests.Player(i)) : OverlayVisorTests.Player(i));
        var scene = Scene(window);
        var vega = scene.Members.SingleOrDefault(m => m.Name.EndsWith("Vega", StringComparison.Ordinal));
        Check(vega is { State: OverlayVisorMemberState.Unknown, Status: "未知", Ship: "", Place: "" },
            "one unknown member: 未知, no ship and no place, never in game", vega);
        // The fixture makes player 2 app-online, so compare with the same roster where nobody is unknown.
        using var known = OverlayVisorTests.Window(3, W, H, row: OverlayVisorTests.Player);
        var expected = Scene(known).Members.Where(m => !m.Name.EndsWith("Vega", StringComparison.Ordinal))
            .Select(m => $"{m.Name}:{m.State}").ToArray();
        var actual = scene.Members.Where(m => !ReferenceEquals(m, vega)).Select(m => $"{m.Name}:{m.State}").ToArray();
        Check(expected.Length == 2 && expected.SequenceEqual(actual),
            "one unknown member: the others keep their own state", new { expected, actual });
        Check(scene.RealtimeUnknown.Length == 0, "one unknown member: the counts stay, no 实时状态未知", scene.RealtimeUnknown);
        Check(scene.Online == 2, "one unknown member: an unknown member is not counted online", scene.Online);

        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        using var d3d = D3D11.D3D11CreateDevice(Vortice.Direct3D.DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var painter = new OverlayVisorPainter(dc, dw);
        var style = OverlayVisorStyle.FromPalette(new(0.3f, 0.7f, 1, 1), new(1, 1, 1, 1));
        var draw = new OverlayVisorDraw(painter, style, true, 0);
        OverlayVisorRun Run(object runs, string field) => (OverlayVisorRun)runs.GetType().GetField(field)!.GetValue(runs)!;
        object Runs(OverlayVisorMember m) => draw.GetType().GetMethod("RowRuns", All)!.Invoke(draw, [m])!;
        Color4 Dot(OverlayVisorMember m) => (Color4)draw.GetType().GetMethod("Dot", All)!.Invoke(draw, [m])!;
        var unknown = new OverlayVisorMember("Vega", "", "", "未知", OverlayVisorMemberState.Unknown, false, false);
        var offline = unknown with { Status = "离线", State = OverlayVisorMemberState.Offline };
        var (unknownRuns, offlineRuns) = (Runs(unknown), Runs(offline));
        Check(Run(unknownRuns, "Item2").Text == "未知" && Run(unknownRuns, "Item2").Color == Run(offlineRuns, "Item2").Color &&
              Run(unknownRuns, "Item3").Text == "—",
            "drawn: the ship line says 未知 in the offline tag's colour; the place is a dash, as offline",
            new { Ship = Run(unknownRuns, "Item2").Text, Place = Run(unknownRuns, "Item3").Text });
        Check(Run(unknownRuns, "Item1").Color != Run(offlineRuns, "Item1").Color,
            "drawn: an unknown member's name is not dimmed, unlike offline", new { Unknown = Run(unknownRuns, "Item1").Color, Offline = Run(offlineRuns, "Item1").Color });
        Check(Dot(unknown) == Dot(offline), "drawn: the diamond takes the offline colour (hollow like offline)", Dot(unknown));
    }

    private static void EveryMemberUnknown()
    {
        using var window = OverlayVisorTests.Window(3, W, H, row: i => Unknown(OverlayVisorTests.Player(i)));
        var scene = Scene(window);
        Check(scene.Members.Count == 3 && scene.Members.All(m => m.State == OverlayVisorMemberState.Unknown && m.Status == "未知"),
            "every member unknown: each is 未知", scene.Members.Select(m => $"{m.Name}:{m.State}"));
        Check(scene.RealtimeUnknown == "实时状态未知" && scene.Online == 0 && scene.InGame == 0,
            "every member unknown (the read went stale): 实时状态未知 in place of the counts", new { scene.RealtimeUnknown, scene.Online, scene.InGame });
    }

    private static void PlaceholderRowsStayOut()
    {
        using (var empty = OverlayVisorTests.Window(0, W, H))
        {
            var scene = Scene(empty);
            Check(scene.Members.Count == 0, "no members: the classic \"暂无可显示成员\" line is not drawn as a member", scene.Members.Select(m => m.Name));
        }

        var source = NativeInformationOverlayRuntime.ProjectSource(null, new InformationOverlayCommunityContent("visor", "示例组织", []), OverlayScenePreference.Auto, "zh");
        var settings = OverlayDisplaySettings.Default with { EnableStartupTransition = false, ShowEventNotifications = false, Skin = OverlaySkin.Visor };
        var summary = new OverlayRosterSelectionSettings(OverflowMode: OverlayRosterOverflowMode.Summary, UserRowLimit: 5);
        var layout = OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray();
        var rows = Enumerable.Range(0, 20).Select(OverlayVisorTests.Player).ToArray();
        using var window = new OverlayCompositionHudWindow(new(rows), [], layout, settings, summary, "zh", true, source.Command, PlayerPresenceKind.InGame, Shard,
            new Rect(0, 0, W, H), OverlayStartupTransitionContext.ForLanguage("zh"), source.Scene.Context);
        var members = Scene(window).Members;
        Check(members.Count > 0 && members.All(m => !m.Name.StartsWith("另有", StringComparison.Ordinal) && m.State == OverlayVisorMemberState.InGame),
            "overflow as a summary: the classic \"另有 N 人\" line is not drawn as a member", members.Select(m => $"{m.Name}:{m.State}"));
    }

    private static void ClassicOverviewAndEvents()
    {
        static PlayerRow P(int i, string shard) =>
            new($"P{i:00}", "Online", "Cutlass Black", "Ship: Cutlass Black", "Orison", Callsign: $"P{i:00}", RawLocation: "Orison", RawShip: "Cutlass Black",
                ServerShard: shard, LiveStatus: "InGame", AccountId: $"P{i:00}",
                SharedOnlineStatus: "Online", SharedLiveStatus: "InGame", SharedShip: "Cutlass Black", SharedLocation: "Orison");
        var settings = OverlayDisplaySettings.Default with
        {
            Skin = OverlaySkin.Visor, AnimationFrameRate = OverlayAnimationFrameRate.Off, ShowEventNotifications = true,
            EventNotificationTypes = OverlayEventNotificationTypes.All, EventNotificationMaxVisibleCount = 3,
        };
        var before = new[] { P(1, "pub_euw1_fixture_007"), P(2, "pub_euw1_fixture_007") };
        var model = new OverlayViewModel(new(before), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, Shard);
        void Refresh(IEnumerable<PlayerRow> rows) => model.Refresh(new(rows), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, Shard);
        IReadOnlyList<string> Lines() => model.EventNotifications.Select(row => $"{row.Title}｜{row.Detail}").ToArray();
        try
        {
            Refresh(before);
            model.EventNotifications.Clear();
            // one member the room does not know; the other changes server
            Refresh([Unknown(P(1, "pub_euw1_fixture_007")), P(2, "pub_euw1_fixture_009")]);
            Check(!model.RealtimeStatusUnknown && model.SquadStatusPrimaryName != "实时状态未知",
                "classic: one unknown member leaves the overview as usual", model.SquadStatusPrimaryName);
            var lines = Lines();
            Check(lines.Any(line => line.StartsWith("换服") && line.Contains("P02")), "events: the other member's change still reports", lines);
            Check(!lines.Any(line => line.Contains("P01")), "events: the unknown member fires nothing (no offline or leave from unknown)", lines);
            model.EventNotifications.Clear();
            Refresh([P(1, "pub_euw1_fixture_007"), P(2, "pub_euw1_fixture_009")]);
            Check(!Lines().Any(line => line.Contains("P01")), "events: known again with the same state, nothing fires", Lines());

            Refresh([Unknown(P(1, "pub_euw1_fixture_007")), Unknown(P(2, "pub_euw1_fixture_009"))]);
            Check(model.RealtimeStatusUnknown && model.SquadStatusPrimaryName == "实时状态未知",
                "classic: every member unknown (the read went stale) says 实时状态未知", model.SquadStatusPrimaryName);
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static PlayerRow Peer(int i, string shard) =>
        new($"P{i:00}", "Online", "Cutlass Black", "Ship: Cutlass Black", "Orison", Callsign: $"P{i:00}", RawLocation: "Orison", RawShip: "Cutlass Black",
            ServerShard: shard, LiveStatus: "InGame", AccountId: $"P{i:00}",
            SharedOnlineStatus: "Online", SharedLiveStatus: "InGame", SharedShip: "Cutlass Black", SharedLocation: "Orison");

    private static OverlayDisplaySettings EventSettings => OverlayDisplaySettings.Default with
    {
        Skin = OverlaySkin.Visor, AnimationFrameRate = OverlayAnimationFrameRate.Off, ShowEventNotifications = true,
        EventNotificationTypes = OverlayEventNotificationTypes.All, EventNotificationMaxVisibleCount = 3,
    };

    private static (OverlayViewModel Model, Action<PlayerRow[]> Refresh) EventModel(PlayerRow[] first)
    {
        var settings = EventSettings;
        var model = new OverlayViewModel(new(first), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, Shard);
        return (model, rows => model.Refresh(new(rows), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, Shard));
    }

    /// <summary>
    /// Review CX-VISOR-UNKNOWN-073-R1 (1): the stale read is decided from the source rows, before the local self row is
    /// filled in from the game log; a known self row does not hide "实时状态未知".
    /// </summary>
    private static void StaleSourceWithLocalSelf()
    {
        InformationOverlayCommunityMember Member(string name, string presence, bool self) => new(name, name, "Member", presence, "", "", "", self);
        var stale = NativeInformationOverlayRuntime.ProjectSource(null, new InformationOverlayCommunityContent("org", "示例组织",
            [Member("Self", "Unknown", true), Member("Peer", "Unknown", false)]), OverlayScenePreference.Auto, "zh").Scene;
        Check(stale.Context.RealtimeUnknown, "stale source: the scene says every member it sent is unknown", stale.Context.RealtimeUnknown);
        // what ProjectLocalSelf does to the own row when the game log is known
        var players = stale.Players.Select(row => row.IsSelf ? row with { RealtimeStateUnknown = false, LiveStatus = "InGame", SharedLiveStatus = "InGame" } : row).ToArray();
        var overview = OverlayOverviewProjection.Project(players, stale.Context, true, PlayerPresenceKind.InGame, Shard, "zh");
        Check(overview.RealtimeStatusUnknown && overview.Primary == "实时状态未知",
            "stale source with a known local self row: still 实时状态未知", new { overview.Primary, overview.RealtimeStatusUnknown });

        var mixed = NativeInformationOverlayRuntime.ProjectSource(null, new InformationOverlayCommunityContent("org", "示例组织",
            [Member("Self", "InGame", true), Member("Peer", "Unknown", false)]), OverlayScenePreference.Auto, "zh").Scene;
        var mixedOverview = OverlayOverviewProjection.Project(mixed.Players, mixed.Context, true, PlayerPresenceKind.InGame, Shard, "zh");
        Check(!mixed.Context.RealtimeUnknown && !mixedOverview.RealtimeStatusUnknown,
            "one member the source does not know: not a stale read", new { mixed.Context.RealtimeUnknown, mixedOverview.Primary });
    }

    /// <summary>
    /// Review CX-VISOR-UNKNOWN-073-R1 (2): after every member went unknown, members coming back one at a time start fresh;
    /// a member that changed while the read was stale reports nothing on return, and a repeat refresh is quiet.
    /// </summary>
    private static void BatchedRecoveryStartsFresh()
    {
        var (model, refresh) = EventModel([Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_007")]);
        IReadOnlyList<string> Lines() => model.EventNotifications.Select(row => $"{row.Title}｜{row.Detail}").ToArray();
        try
        {
            refresh([Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_007")]);
            model.EventNotifications.Clear();
            refresh([Unknown(Peer(1, "pub_euw1_fixture_007")), Unknown(Peer(2, "pub_euw1_fixture_007"))]);
            refresh([Peer(1, "pub_euw1_fixture_007"), Unknown(Peer(2, "pub_euw1_fixture_007"))]);
            refresh([Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_009")]);
            Check(!Lines().Any(line => line.Contains("P02")), "batched recovery: a member back after the stale read is not compared with its state from before it", Lines());
            model.EventNotifications.Clear();
            refresh([Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_009")]);
            Check(Lines().Count == 0, "batched recovery: the same refresh again fires nothing", Lines());
            refresh([Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_011")]);
            Check(Lines().Any(line => line.StartsWith("换服") && line.Contains("P02")), "batched recovery: a real change after that reports again", Lines());
        }
        finally { model.ClearAuthorizedContent(); }
    }

    /// <summary>
    /// Review CX-VISOR-UNKNOWN-073-R1 (3): a member whose state was never known still counts in the member total the
    /// summaries use.
    /// </summary>
    private static void NeverKnownMemberStillCounted()
    {
        var rows = new[] { Peer(1, "pub_euw1_fixture_007"), Peer(2, "pub_euw1_fixture_007"), Unknown(Peer(3, "pub_euw1_fixture_007")) };
        var (model, refresh) = EventModel(rows);
        try
        {
            refresh(rows);
            refresh(rows);
            var fleet = model.GetType().GetField("_gameEventFleetState", All)!.GetValue(model)!;
            var total = (int)fleet.GetType().GetProperty("MemberCount")!.GetValue(fleet)!;
            var online = (int)fleet.GetType().GetProperty("OnlineCount")!.GetValue(fleet)!;
            Check(total == 3 && online == 2, "a never-known member counts in the total, not as online", new { total, online });
        }
        finally { model.ClearAuthorizedContent(); }
    }
}
