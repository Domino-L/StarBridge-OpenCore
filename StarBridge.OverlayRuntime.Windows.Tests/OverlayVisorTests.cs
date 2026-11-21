using System.Collections;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Rect = System.Windows.Rect;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// The visor appearance on the real overlay state: the actual HUD window builds its frame state from
/// roster rows, the visor scene is taken from it, and the visor renderer draws off screen (no window shown).
/// Pass a backdrop picture path in STARBRIDGE_VISOR_BACKDROP to get preview images.
/// </summary>
internal static class OverlayVisorTests
{
    private const string Shard = "pub_use1_fixture_001";
    private static readonly BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    private static int _failures;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) _failures++;
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "CHECK", Name = name, Status = value ? "PASS" : "FAIL", Evidence = evidence }));
    }

    private static object? Call(object target, string name, params object?[] values) =>
        target.GetType().GetMethods(All).Single(m => m.Name == name && m.GetParameters().Length == values.Length).Invoke(target, values);

    private static object? Get(object target, string name) =>
        target.GetType().GetField(name, All)?.GetValue(target) ?? target.GetType().GetProperty(name, All)!.GetValue(target);

    private static readonly string[] Names = ["Aster", "Vega", "Lyra", "Draco", "Orion", "Raven", "Nova", "Talon", "Ember", "Rook", "Sable", "Comet", "Atlas", "Halcyon", "Mirage",
        "Quill", "Saber", "Tycho", "Umbra", "Vesper", "Wren", "Xenon", "Yarrow", "Zephyr", "Bolt", "Cinder", "Dusk", "Echo", "Flint", "Kestrel"];
    private static readonly string[] Ships = ["Cutlass Black", "Hornet Mk II", "Freelancer MAX", "Constellation", "Carrack"];
    private static readonly string[] Places = ["Orison", "Orison", "New Babbage", "Lorville", "CRU-L1"];

    internal static PlayerRow Player(int i)
    {
        var appOnly = i % 6 == 2;
        var ship = Ships[i % Ships.Length];
        var place = Places[i % Places.Length];
        var live = appOnly ? "AppOnline" : "InGame";
        return new PlayerRow(Names[i], "Online", ship, "Ship: " + ship, place, Callsign: Names[i], RawLocation: place,
            ServerShard: i % 5 < 2 ? Shard : "pub_euw1_fixture_007", LiveStatus: live, AccountId: Names[i],
            SharedOnlineStatus: "Online", SharedLiveStatus: live, SharedShip: ship, SharedLocation: place);
    }

    internal static OverlayCompositionHudWindow Window(int people, double width, double height, string? layoutPayload = null,
        Func<OverlayDisplaySettings, OverlayDisplaySettings>? tweak = null, Func<int, PlayerRow>? row = null, OverlayChatMessage[]? chat = null,
        int rowLimit = 11)
    {
        var source = NativeInformationOverlayRuntime.ProjectSource(null, new InformationOverlayCommunityContent("visor", "示例组织", []), OverlayScenePreference.Auto, "zh");
        var settings = OverlayDisplaySettings.Default with { EnableStartupTransition = false, ShowEventNotifications = false, Skin = OverlaySkin.Visor };
        if (tweak is not null) settings = tweak(settings);
        var selection = new OverlayRosterSelectionSettings(OverflowMode: OverlayRosterOverflowMode.Rotate, UserRowLimit: rowLimit);
        var layout = OverlayLayoutItem.ParseMany(layoutPayload ?? InformationOverlayDefaults.DefaultLayoutPayload).ToArray();
        var rows = Enumerable.Range(0, people).Select(row ?? Player).ToArray();
        var window = new OverlayCompositionHudWindow(new(rows), chat ?? [], layout, settings, selection, "zh", true, source.Command, PlayerPresenceKind.InGame, Shard,
            new Rect(0, 0, width, height), OverlayStartupTransitionContext.ForLanguage("zh"),
            // chat messages need a channel; this one only the tests use
            chat is null ? source.Scene.Context : source.Scene.Context with { ChatChannelId = "demo-fleet" });
        return window;
    }

    internal static void Run()
    {
        _failures = 0;
        var output = Path.Combine(AppContext.BaseDirectory, "visor");
        Directory.CreateDirectory(output);
        var backdrop = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_BACKDROP");

        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2560, H = 1440;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        using var renderer = new OverlayVisorRenderer(dc, dw);

        foreach (var people in new[] { 3, 30 })
        {
            using var window = Window(people, W, H);
            var state = Call(window, "BuildFrameState")!;
            Check(Get(state, "RenderKind")?.ToString() == "Visor", $"{people} people: frame state selects the visor appearance", Get(state, "RenderKind")?.ToString());
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", state)!;
            Check(scene.Members.Count > 0 && scene.Members.All(m => m.Name.Length > 0), $"{people} people: every member row reaches the visor", scene.Members.Count);
            Check(scene.Members.Where(m => m.State == OverlayVisorMemberState.InGame).All(m => m.Ship.Length > 0 && m.Place.Length > 0), $"{people} people: in-game rows carry ship and place",
                scene.Members.Select(m => $"{m.Name}:{m.Ship}@{m.Place}").Take(6));
            if (people == 30)
            {
                Check(scene.PageLabel.Length > 0, "30 people: rows are paged like the current overlay", scene.PageLabel);
                // 11-07: as many rows as the default members height holds ("小而精"); 11-10 "信息较多可以稍微密一点": nine at
                // the tighter spacing
                Check(scene.Members.Count == 9 && OverlayVisorDraw.RowsFor((float)OverlayDisplaySettings.DefaultVisorMembersHeight) == 9,
                    "30 people: the default members height gives the visor 9 rows per page", scene.Members.Count);
            }
            Check(scene.Spots[OverlayVisorLayout.Team].Slot == "R-mid" && scene.Spots[OverlayVisorLayout.Chat].Slot == "L-bottom" && scene.Spots[OverlayVisorLayout.Events].Slot == "R-top",
                $"{people} people: an untouched old layout gives the visor defaults", scene.Spots);

            // sample event, chat and rally so the picture shows every group (these normally arrive at runtime)
            var shown = scene with
            {
                ShowEvents = true, ShowChat = true,
                Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)],
                Chat = [new("Aster", "准备完成，正在前往集合点。", 1)],
                ShowNotice = people == 30, NoticeTitle = "舰队召集", NoticeBody = "今晚八点奥里森集合，带上货船", NoticeTimer = "剩余 27:30", NoticeHint = "Ctrl+Alt+Y 马上到　Ctrl+Alt+N 来不了", NoticeIsRally = true,
                DirectMessage = people == 30 ? "Vega 发来私信" : null,
            };
            renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, 10);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, 20); // the rally pulse has settled by now
            var before = renderer.Redraws;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, 30);
            Check(renderer.Redraws == before && !renderer.Animating(30), $"{people} people: an unchanged, settled scene redraws no group and asks for no frames", new { Redraws = renderer.Redraws - before });

            var layoutWidth = W / (H / 1080f);
            var hud = OverlayVisorLayout.GameHud(layoutWidth);
            var boxes = renderer.Sizes.Where(kv => renderer.Positions.ContainsKey(kv.Key))
                .Select(kv => (kv.Key, Box: new OverlayVisorRect(renderer.Positions[kv.Key].X, renderer.Positions[kv.Key].Y, kv.Value.W, kv.Value.H))).ToArray();
            var hits = boxes.SelectMany(b => hud.Where(z => b.Box.Hits(z.Area)).Select(z => $"{b.Key}/{z.Name}"))
                .Concat(boxes.SelectMany(a => boxes.Where(b => string.CompareOrdinal(a.Key, b.Key) < 0 && a.Box.Hits(b.Box)).Select(b => $"{a.Key}+{b.Key}"))).ToArray();
            Check(hits.Length == 0, $"{people} people: groups clear the game's HUD and each other", new { Hits = hits, Boxes = boxes.Select(b => $"{b.Key} {b.Box}") });

            if (backdrop is not null && File.Exists(backdrop)) Save(dc, overlay, backdrop, W, H, Path.Combine(output, $"visor-{people}.jpg"));
        }
        // 11-06: the rally at the bottom centre clears the game's speed readout and crosshair area at every size.
        foreach (var size in Enum.GetValues<OverlayVisorSize>())
        {
            using var low = Window(3, W, H, "Notice,0.34,0.945,0.32,0.055,Center,Bottom", s => s with { VisorSize = size });
            var scene = (OverlayVisorScene)Call(low, "BuildVisorScene", Call(low, "BuildFrameState")!)!;
            var rally = scene with { ShowNotice = true, NoticeTitle = "舰队召集", NoticeBody = "今晚八点奥里森集合", NoticeTimer = "剩余 27:30", NoticeIsRally = true };
            using var r = new OverlayVisorRenderer(dc, dw);
            r.Render(overlay, System.Numerics.Vector2.Zero, rally, W, H, 10);
            var g = OverlayVisorRenderer.Compact * scene.Style.SizeFactor;
            var (x, y) = r.Positions["top"];
            // the visible band: from the heading line (52 design units) to the closing rule (180)
            var band = new OverlayVisorRect(x, y + 52 * g, OverlayVisorDraw.TopWidth * g, 128 * g);
            var hits = OverlayVisorLayout.GameHud(W / (H / 1080f)).Where(z => band.Hits(z.Area)).Select(z => z.Name).ToArray();
            Check(scene.RallyBottom && hits.Length == 0, $"{size}: the rally at the bottom centre clears the game's HUD", new { band, hits });
        }

        // 0.7.3: a room invite is a card, never the top slot; the DM badge that marked it is gone (11-13).
        using (var invited = Window(3, W, H))
        {
            var model = (OverlayViewModel)Get(invited, "_viewModel")!;
            var shown = model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "房间提醒", "新邀请 1 · 新加入申请 0");
            var scene = (OverlayVisorScene)Call(invited, "BuildVisorScene", Call(invited, "BuildFrameState")!)!;
            Check(shown && !scene.ShowNotice && scene.DirectMessage is null,
                "room invite: no mark on the visor (no DM badge), the top slot stays free", new { shown, scene.ShowNotice, scene.DirectMessage });
        }

        // Block 3 picture: a wave of 27 teammate changes through flood control, newest three lines shown.
        using (var wave = Window(30, W, H))
        {
            var flood = new OverlayMemberChangeFlood();
            var lines = new List<OverlayMemberChangeLine>();
            var start = DateTimeOffset.Now;
            string[] places = ["罗威尔", "新巴贝奇", "十字军 L1", "奥里森"];
            for (var i = 0; i < 27; i++)
            {
                var kind = (OverlayMemberChangeKind)(i % 3);
                var name = Names[i];
                var value = kind switch { OverlayMemberChangeKind.Server => "欧服 #009", OverlayMemberChangeKind.Ship => "F8C 闪电", _ => places[i % places.Length] };
                var part = $"{OverlayMemberChangeFlood.KindTitle(kind, true)} {value}";
                var line = flood.Add(start.AddSeconds(i * 0.3), name, name, pinned: i == 20, sameServer: i % 5 < 2, kind, part, $"{name} {part}", zh: true);
                var at = lines.FindIndex(existing => existing.Key == line.Key);
                if (line.Update && at >= 0) lines[at] = line; else lines.Add(line);
            }
            var scene = (OverlayVisorScene)Call(wave, "BuildVisorScene", Call(wave, "BuildFrameState")!)!;
            var shown = scene with
            {
                ShowEvents = true,
                Events = lines.TakeLast(3).Reverse().Select(line => new OverlayVisorEvent(line.Title, line.Detail, "20:41", 1, 1)).ToArray(),
            };
            Check(lines.Count <= 11, "wave picture: 27 changes make at most 11 lines", lines.Count);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, 50);
            if (backdrop is not null && File.Exists(backdrop)) Save(dc, overlay, backdrop, W, H, Path.Combine(output, "visor-wave.jpg"));
        }

        // An old layout with members moved to the upper left and chat to the bottom centre.
        using (var moved = Window(8, W, H, "Notice,0.34,0,0.32,0.055;Squads,0,0.4211,0.1327,0.1042;Members,0.01,0.1,0.13,0.16,Left,Top;Chat,0.35,0.84,0.3,0.12,Center,Bottom"))
        {
            var before = OverlayLayoutItem.SerializeMany((IEnumerable<OverlayLayoutItem>)Get(moved, "_layout")!);
            var scene = (OverlayVisorScene)Call(moved, "BuildVisorScene", Call(moved, "BuildFrameState")!)!;
            // 11-06 free positions: a moved module sits exactly where it was saved.
            var team = scene.Spots[OverlayVisorLayout.Team];
            var chat = scene.Spots[OverlayVisorLayout.Chat];
            Check(team.Free && !team.Right && !team.Bottom && chat.Free && chat.Bottom, "moved old layout: members and chat sit where the user put them", new { scene.Spots, Saved = before });
            Check(before == OverlayLayoutItem.SerializeMany((IEnumerable<OverlayLayoutItem>)Get(moved, "_layout")!), "moved old layout: the saved layout is not rewritten");
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene with { ShowChat = true, Chat = [new("Aster", "收到。", 1)] }, W, H, 40);
            var layoutWidth = W / (H / 1080f);
            Check(MathF.Abs(renderer.Positions["team"].X - 0.01f * layoutWidth) < 1 && MathF.Abs(renderer.Positions["team"].Y - 108) < 1,
                "moved old layout: the member list's corner is the saved corner", renderer.Positions["team"]);
            var boxes = renderer.Sizes.Where(kv => kv.Key is "team" or "events" or "chat")
                .Select(kv => (kv.Key, Box: new OverlayVisorRect(renderer.Positions[kv.Key].X, renderer.Positions[kv.Key].Y, kv.Value.W, kv.Value.H))).ToArray();
            Check(boxes.All(b => b.Box.X >= 0 && b.Box.Y >= 0 && b.Box.Right <= layoutWidth && b.Box.Bottom <= 1080) &&
                !boxes.Any(a => boxes.Any(b => string.CompareOrdinal(a.Key, b.Key) < 0 && a.Box.Hits(b.Box))),
                "moved old layout: every group stays on screen and apart", boxes.Select(b => $"{b.Key} {b.Box}"));
            if (backdrop is not null && File.Exists(backdrop)) Save(dc, overlay, backdrop, W, H, Path.Combine(output, "visor-moved.jpg"));
        }
        Sharpness(dc, overlay, renderer, W, H);
        OneSpace(dc, overlay, dw, W, H);
        MemberLayout(dc, overlay, dw, W, H);
        QuietWhenSettled(dc, overlay, dw, W, H);
        MovedEvents(dc, overlay, dw, W, H);
        EventsAndChatSize(dc, overlay, dw, W, H);
        MembersSize(dc, overlay, dw, W, H);
        TwentyRows(dc, overlay, dw, W, H);
        Barrage(dc, d3d, dw, W, H);
        Looks(dc, overlay, dw, W, H);
        if (_failures != 0) throw new InvalidOperationException($"Visor appearance failures: {_failures}");
        Console.WriteLine("PASS visor appearance on the real overlay state");
    }

    /// <summary>
    /// 11-07 (user chose method E, and 立体程度 0-40 degrees with the viewing distance fixed at 1000): text sizes,
    /// the saved angle reaching the drawing, and an angle change redrawing once.
    /// </summary>
    private static void Sharpness(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, OverlayVisorRenderer renderer, int w, int h)
    {
        var medium1440 = 1440f / 1080f * OverlayVisorRenderer.Compact;
        Check(MathF.Abs(OverlayVisorPainter.DrawnSize(15) * medium1440 - 12) < 0.01f && MathF.Abs(OverlayVisorPainter.DrawnSize(16) * medium1440 - 13) < 0.01f,
            "method E: body text is 12 px and titles 13 px at 1440p medium",
            new { Body = OverlayVisorPainter.DrawnSize(15) * medium1440, Title = OverlayVisorPainter.DrawnSize(16) * medium1440 });
        Check(OverlayVisorRenderer.Supersample == 2 && OverlayVisorRenderer.ViewingDistance == 1000, "method E: groups are drawn at 2x; the viewing distance is 1000");
        using (var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>())
        using (var painter = new OverlayVisorPainter(dc, dw))
        {
            // the member row as drawn: name 13 px, ship and place 12 px
            var draw = new OverlayVisorDraw(painter, OverlayVisorStyle.FromPalette(new(0.3f, 0.7f, 1, 1), new(1, 1, 1, 1)), true, 0);
            var runs = draw.GetType().GetMethod("RowRuns", All)!.Invoke(draw, [new OverlayVisorMember("Aster", "Cutlass Black", "Orison", "", OverlayVisorMemberState.InGame, false, true)])!;
            float Px(string field) => OverlayVisorPainter.DrawnSize(((OverlayVisorRun)runs.GetType().GetField(field)!.GetValue(runs)!).Size) * medium1440;
            Check(MathF.Abs(Px("Item1") - 13) < 0.01f && MathF.Abs(Px("Item2") - 12) < 0.01f && MathF.Abs(Px("Item3") - 12) < 0.01f,
                "method E: member names are 13 px, ships and places 12 px", new { Name = Px("Item1"), Ship = Px("Item2"), Place = Px("Item3") });
        }
        Dictionary<string, (float X, float Y)>? flat = null;
        foreach (var tilt in new[] { 0.0, 15, 40, 55, 60, 75 })
        {
            using var window = Window(5, w, h, tweak: s => s with { VisorTilt = tilt });
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            var expected = (float)Math.Min(tilt, 60);
            Check(scene.Style.Tilt == expected, $"立体程度 {tilt}: the saved angle reaches the drawing as {expected} degrees", scene.Style.Tilt);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 60);
            flat ??= new(renderer.Positions);
            Check(renderer.Positions.All(kv => flat.TryGetValue(kv.Key, out var at) && at == kv.Value), $"立体程度 {tilt}: groups keep their place on screen", renderer.Positions);
            var before = renderer.Redraws;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 61);
            Check(renderer.Redraws == before, $"立体程度 {tilt}: after the change, an unchanged scene redraws nothing", renderer.Redraws - before);
        }
        // 11-11: the saved viewing distance reaches the drawing (600-3000 in steps of 50)
        foreach (var (saved, drawn) in new[] { (1650.0, 1650f), (1000, 1000f), (9000, 3000f) })
        {
            using var window = Window(5, w, h, tweak: s => s with { VisorViewingDistance = saved });
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            Check(scene.Style.Distance == drawn, $"视距 {saved}: the saved distance reaches the drawing as {drawn}", scene.Style.Distance);
        }
        // both layers of the members group hold their part: the frame layer its lines, the text layer its letters
        var layers = (IDictionary)Get(renderer, "_layers")!;
        var shapes = Lit(dc, (ID2D1Bitmap1)Get(layers["team"]!, "Shapes")!);
        var text = Lit(dc, (ID2D1Bitmap1)Get(layers["team"]!, "Text")!);
        Check(shapes > 500 && text > 2000 && Lit(dc, overlay, w, h) > 2000, "method E: the frame layer and the text layer each draw their part, and both reach the screen", new { Shapes = shapes, Text = text });
    }

    /// <summary>
    /// 11-07 one space: a single camera at the screen centre, each side folded about its screen edge. A point of a
    /// side group at distance u from the screen edge must land where SpacePoint puts it, on both sides, so the inner
    /// edge measured flat (0 degrees) predicts the inner edge at 30 degrees.
    /// </summary>
    private static void OneSpace(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        foreach (var size in new[] { OverlayVisorSize.Medium, OverlayVisorSize.Large }) OneSpace(dc, overlay, dw, w, h, size);
    }

    private static void OneSpace(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h, OverlayVisorSize size)
    {
        using var window = Window(5, w, h, tweak: s => s with { VisorSize = size });
        var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
        var only = new Dictionary<string, OverlayVisorScene>
        {
            ["team"] = scene with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null },
            ["chat"] = scene with { ShowTeam = false, ShowEvents = false, ShowNotice = false, DirectMessage = null, ShowChat = true, Chat = [new("Aster", "准备完成，正在前往集合点。", 1)] },
        };
        // 11-11 viewing distance (视距): the drawing follows it, near and far as well as the default 1000
        foreach (var viewing in new[] { OverlayVisorRenderer.ViewingDistance, 600f, 2500f })
        foreach (var (id, part) in only)
        {
            var right = id == "team";
            (int Min, int Max) Bounds(float tilt)
            {
                using var r = new OverlayVisorRenderer(dc, dw);
                r.Render(overlay, System.Numerics.Vector2.Zero, part with { Style = part.Style with { Tilt = tilt, Distance = viewing } }, w, h, 70);
                return LitColumns(dc, overlay, w, h);
            }
            var flat = Bounds(0);
            var folded = Bounds(30);
            // the camera does not move with the visor size: the viewing distance in design units of a 1080-high screen
            var distance = viewing * h / 1080f;
            var inner = right ? flat.Min : flat.Max;
            var u = right ? w - inner : inner;
            var expected = OverlayVisorRenderer.SpacePoint(right, u, h / 2f, 30, distance, w, h).X;
            var actual = right ? folded.Min : folded.Max;
            var outerU = right ? w - flat.Max : flat.Min;
            var expectedOuter = OverlayVisorRenderer.SpacePoint(right, outerU, h / 2f, 30, distance, w, h).X;
            var outer = right ? folded.Max : folded.Min;
            Check(MathF.Abs(actual - expected) <= 3 && MathF.Abs(outer - expectedOuter) <= 3,
                $"one space ({id}, {(right ? "right" : "left")} side, {size}, distance {viewing}): folded 30 degrees, both edges land where the single camera puts them",
                new { FlatMin = flat.Min, FlatMax = flat.Max, FoldedMin = folded.Min, FoldedMax = folded.Max, Expected = expected, ExpectedOuter = expectedOuter });
        }
    }

    // The longest names in the client data (11-07): ships from StarBridge.Desktop/Data/ship-names-zh.txt and
    // ship-catalog.tsv, places from location-names-zh.txt and starbridge_location_catalog.json, a 30-character handle.
    private static readonly (string Handle, string Ship, string Place)[] LongMembers =
    [
        ("Domino_StarBridge_Fleet07_Lead", "十字军 战神 星际战斗机 地狱火 维克洛战争特别版", "人民服务空间站 拉姆达"),
        ("Aster", "铁砧 F7C-R 大黄蜂 追踪者 Mk II", "尼克斯 - 卡斯塔 跳跃点"),
        ("LongestPossibleHandleExample_X", "Cutlass Black", "Orison"),
        ("Nova", "F7C-M Super Hornet Heartseeker Mk I", "Asteroid Cluster Base Pyro Encounter Region A"),
        ("Vega", "Cutlass Black", "Orison"),
        ("Raven", "十字军 大力神 A2 星际运输船 维克洛战争特别版", "焰联-监管控制站-3-5"),
    ];

    private static PlayerRow LongRow(int i)
    {
        var (handle, ship, place) = LongMembers[i % LongMembers.Length];
        return Player(i) with
        {
            Name = handle, Callsign = handle, AccountId = handle, Ship = ship, ShipInfo = "Ship: " + ship, SharedShip = ship,
            Location = place, RawLocation = place, SharedLocation = place, LiveStatus = "InGame", SharedLiveStatus = "InGame",
        };
    }

    /// <summary>
    /// 11-07 K1 with adaptive columns (user: "固定位置会导致空间浪费，随动又会上下对不齐", "最好还是能保证这个面板小而精的"):
    /// name over ship at the screen edge, the place toward the centre; each column as wide as its longest entry up to a
    /// tight cap, every row aligned to it; wider at once, narrower after the members settle; long text scrolls.
    /// </summary>
    private static void MemberLayout(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        ColumnDebounce();
        var k = h / 1080f * OverlayVisorRenderer.Compact;
        var caps = OverlayVisorDraw.MemberColumns.Select(c => c.Cap).ToArray();
        var widths = new Dictionary<string, (int W, int H)>();
        foreach (var (label, row) in new (string, Func<int, PlayerRow>?)[] { ("everyday names", null), ("longest names", LongRow) })
        {
            using var window = Window(6, w, h, row: row);
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            var team = scene with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null, Style = scene.Style with { Tilt = 0 } };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, team, w, h, 100);
            var (min, max) = LitColumns(dc, overlay, w, h);
            var (top, bottom) = LitRows(dc, overlay, w, h);
            widths[label] = (max - min, bottom - top);
            Console.WriteLine(JsonSerializer.Serialize(new { Kind = "SIZE", Set = label, WidthPx = max - min, HeightPx = bottom - top, renderer.TeamWidth, Columns = renderer.TeamColumns }));
            Check(renderer.TeamColumns.Select((c, i) => c <= caps[i] + 0.5f).All(x => x) && w - max < 70,
                $"K1 {label}: every column stays within its cap and the members hug the right edge", new { Columns = renderer.TeamColumns, Gap = w - max });
            if (row is null)
            {
                Check(renderer.TeamColumns.Select((c, i) => c < caps[i] - 1).All(x => x) && renderer.ScrollFields == 0 && !renderer.Animating(100),
                    "K1 everyday names: the columns are narrower than their caps, nothing scrolls, no frames are asked for", new { Columns = renderer.TeamColumns, renderer.ScrollFields });
                continue;
            }
            Check(renderer.TeamColumns.Select((c, i) => MathF.Abs(c - caps[i]) < 0.5f).All(x => x), "K1 longest names: the columns stop at their caps", renderer.TeamColumns);
            Check(renderer.ScrollFields >= 4 && renderer.Animating(100), "K1 longest names: entries longer than the cap scroll", renderer.ScrollFields);
            var layers = (IDictionary)Get(renderer, "_layers")!;
            var fields = (OverlayVisorDraw.ScrollField[])Get(layers["team"]!, "Scrolls")!;
            var places = fields.Where(f => f.Order == 2).Select(f => (f.X, f.W)).Distinct().ToArray();
            Check(places.Length == 1, "K1 longest names: every row's place column starts at the same spot with the same width", places.Select(p => $"{p.X},{p.W}"));
            var most = Enumerable.Range(0, 600).Max(t => OverlayVisorRenderer.ScrollOffsets(fields, t * 0.1).Count(o => o > 0));
            Check(most is > 0 and <= OverlayVisorRenderer.MaxScrolling, "K1 longest names: at most two fields move at the same time", most);
            var before = renderer.ScrollRedraws;
            for (var f = 1; f <= 120; f++) renderer.Render(overlay, System.Numerics.Vector2.Zero, team, w, h, 100 + f / 60.0);
            Check(renderer.ScrollRedraws - before <= 61, "K1 longest names: two seconds at 60 frames redraw the scrolling text at most 30 times a second", renderer.ScrollRedraws - before);
        }
        // the earlier K1 drew the members 480 x 0.825 design units wide (280 px at 1440p medium) with 44-unit rows
        var oldWidth = (int)MathF.Round(OverlayVisorRenderer.MaxSideWidthPx);
        Check(widths["everyday names"].W < oldWidth && widths["longest names"].W <= oldWidth,
            "K1: the members are narrower than the earlier fixed 280 px, also with the longest names", widths.Select(kv => $"{kv.Key}: {kv.Value.W} x {kv.Value.H}"));

        // A long-named member leaves: the columns keep their width for five seconds, then ease narrower in 0.3 s.
        using (var many = Window(6, w, h, row: i => i == 0 ? LongRow(0) : Player(i)))
        using (var few = Window(6, w, h))
        {
            OverlayVisorScene Team(OverlayCompositionHudWindow wnd)
            {
                var sc = (OverlayVisorScene)Call(wnd, "BuildVisorScene", Call(wnd, "BuildFrameState")!)!;
                return sc with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
            }
            var wide = Team(many); var narrow = Team(few);
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, wide, w, h, 200);
            var start = renderer.TeamWidth;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, narrow, w, h, 201);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, narrow, w, h, 205.9);
            var waiting = renderer.TeamWidth;
            var asks = renderer.Animating(205.9);
            var idle = new List<double>(); var narrowing = new List<double>();
            for (var f = 0; f <= 30; f++)
            {
                var t = 206.0 + f / 60.0;
                var before = renderer.Redraws;
                var clock = System.Diagnostics.Stopwatch.StartNew();
                renderer.Render(overlay, System.Numerics.Vector2.Zero, narrow, w, h, t);
                Finish(dc, overlay);
                (renderer.Redraws > before ? narrowing : idle).Add(clock.Elapsed.TotalMilliseconds);
            }
            var end = renderer.TeamWidth;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, narrow, w, h, 207);
            var settledRedraws = renderer.Redraws;
            for (var f = 0; f < 30; f++)
            {
                var clock = System.Diagnostics.Stopwatch.StartNew();
                renderer.Render(overlay, System.Numerics.Vector2.Zero, narrow, w, h, 207 + f / 60.0);
                Finish(dc, overlay);
                idle.Add(clock.Elapsed.TotalMilliseconds);
            }
            Check(MathF.Abs(waiting - start) < 0.5f && asks && end < start - 20 && renderer.Redraws == settledRedraws && !renderer.Animating(208),
                "K1: when the longest entry leaves, the members keep their width for five seconds, then narrow and settle",
                new { Start = start, Waiting = waiting, End = end });
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                Kind = "COST", NarrowingFrames = narrowing.Count, NarrowingMs = narrowing.DefaultIfEmpty(0).Average(), NarrowingMaxMs = narrowing.DefaultIfEmpty(0).Max(),
                IdleMs = idle.Average(),
            }));
            Check(narrowing.Count is >= 10 and <= 24, "K1: the narrowing redraws about 0.3 s of frames", narrowing.Count);
        }
    }

    /// <summary>
    /// Review R1: hiding the members while their columns wait to narrow asks for no more frames; a settled rally does not
    /// redraw while member text scrolls (only the scroll layer is redrawn).
    /// </summary>
    private static void QuietWhenSettled(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        using var many = Window(6, w, h, row: i => i == 0 ? LongRow(0) : Player(i));
        using var few = Window(6, w, h);
        OverlayVisorScene Team(OverlayCompositionHudWindow wnd) =>
            ((OverlayVisorScene)Call(wnd, "BuildVisorScene", Call(wnd, "BuildFrameState")!)!) with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Team(many), w, h, 300);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Team(few), w, h, 301);
            var waiting = renderer.Animating(301);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Team(few) with { ShowTeam = false }, w, h, 302);
            Check(waiting && !renderer.Animating(302) && !renderer.Animating(320),
                "K1: hiding the members while their columns wait to narrow stops asking for frames", new { waiting });
        }
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            var rally = Team(many) with { ShowNotice = true, NoticeTitle = "舰队召集", NoticeBody = "今晚八点奥里森集合", NoticeTimer = "剩余 27:30", NoticeIsRally = true };
            renderer.Render(overlay, System.Numerics.Vector2.Zero, rally, w, h, 400);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, rally, w, h, 410); // the rally's own motion is over
            var before = renderer.Redraws; var scrolls = renderer.ScrollRedraws;
            for (var f = 1; f <= 60; f++) renderer.Render(overlay, System.Numerics.Vector2.Zero, rally, w, h, 410 + f / 60.0);
            Check(renderer.Redraws == before && renderer.ScrollRedraws > scrolls && renderer.Animating(411),
                "a settled rally is not redrawn while member text scrolls; only the scroll layer is", new { Redraws = renderer.Redraws - before, Scrolls = renderer.ScrollRedraws - scrolls });
        }
    }

    /// <summary>
    /// 11-07 (user: "弹幕也要留着"): with the chat set to barrage, the visor leaves out its chat group and the overlay's own
    /// barrage is drawn over the visor's frame (with its settings); with the message list, the visor's chat group stays.
    /// </summary>
    private static void Barrage(ID2D1DeviceContext dc, ID3D11Device d3d, IDWriteFactory5 dw, int w, int h)
    {
        var now = DateTimeOffset.Now;
        OverlayChatMessage[] messages =
        [
            new(1, "demo-fleet", "Aster", "Aster", "准备完成，正在前往集合点。", now.AddSeconds(-2), false, false, "#53BEFF"),
            new(2, "demo-fleet", "Lyra", "Lyra", "收到，五分钟到。", now.AddSeconds(-1), false, false, "#53BEFF"),
        ];
        foreach (var mode in new[] { OverlayChatDisplayMode.MessageList, OverlayChatDisplayMode.FullScreenBarrage })
        {
            // messages already there when the chat loads are history; one that arrives afterwards runs as barrage
            var settings = OverlayDisplaySettings.Default with
            {
                EnableStartupTransition = false, ShowEventNotifications = false, Skin = OverlaySkin.Visor,
                ShowChat = true, ChatDisplayMode = mode, AnimationFrameRate = OverlayAnimationFrameRate.Off, ChatBarrageRegion = OverlayChatBarrageRegion.Upper,
            };
            var source = NativeInformationOverlayRuntime.ProjectSource(null, new InformationOverlayCommunityContent("visor", "示例组织", []), OverlayScenePreference.Auto, "zh");
            var context = source.Scene.Context with { ChatChannelId = "demo-fleet" };
            var selection = new OverlayRosterSelectionSettings(OverflowMode: OverlayRosterOverflowMode.Rotate, UserRowLimit: 11);
            var layout = OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray();
            var rows = Enumerable.Range(0, 3).Select(Player).ToArray();
            using var window = new OverlayCompositionHudWindow(new(rows), messages, layout, settings, selection, "zh", true, source.Command,
                PlayerPresenceKind.InGame, Shard, new Rect(0, 0, w, h), OverlayStartupTransitionContext.ForLanguage("zh"), context);
            OverlayChatMessage[] later = [.. messages, new(3, "demo-fleet", "Vega", "Vega", "货船已经停好，等你们。", DateTimeOffset.Now, false, false, "#53BEFF")];
            window.Refresh(new(rows), later, layout, settings, selection, "zh", true, source.Command,
                PlayerPresenceKind.InGame, Shard, new Rect(0, 0, w, h), OverlayStartupTransitionContext.ForLanguage("zh"), context);
            var state = Call(window, "BuildFrameState")!;
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", state)!;
            var barrage = (bool)typeof(OverlayCompositionHudWindow).GetMethod("VisorBarrage", All)!.Invoke(null, [state])!;
            if (mode == OverlayChatDisplayMode.MessageList)
            {
                Check(scene.ShowChat && !barrage, "chat as a message list: the visor draws its chat group, no barrage", new { scene.ShowChat, barrage });
                continue;
            }
            Check(!scene.ShowChat && barrage, "chat as barrage: the visor leaves out its chat group and the barrage takes over", new { scene.ShowChat, barrage });
            // draw the barrage the way the overlay window does: onto a DXGI surface, at the window's DPI
            using var texture = d3d.CreateTexture2D(new Texture2DDescription
            {
                Width = (uint)w, Height = (uint)h, MipLevels = 1, ArraySize = 1, Format = Format.B8G8R8A8_UNorm,
                SampleDescription = new SampleDescription(1, 0), Usage = ResourceUsage.Default, BindFlags = BindFlags.RenderTarget | BindFlags.ShaderResource,
            });
            using var surface = texture.QueryInterface<IDXGISurface>();
            // the visor's frame first, on a cleared surface (as TryDrawVisorFrame does), then the barrage over it
            var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
            using (var surfaceBitmap = dc.CreateBitmapFromDxgiSurface(surface, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target | BitmapOptions.CannotDraw)))
            using (var renderer = new OverlayVisorRenderer(dc, dw))
                renderer.Render(surfaceBitmap, System.Numerics.Vector2.Zero, scene, w, h, 600);
            int Count()
            {
                using var staging = d3d.CreateTexture2D(new Texture2DDescription
                {
                    Width = (uint)w, Height = (uint)h, MipLevels = 1, ArraySize = 1, Format = Format.B8G8R8A8_UNorm,
                    SampleDescription = new SampleDescription(1, 0), Usage = ResourceUsage.Staging, CPUAccessFlags = CpuAccessFlags.Read,
                });
                d3d.ImmediateContext.CopyResource(staging, texture);
                var mapped = d3d.ImmediateContext.Map(staging, 0, MapMode.Read);
                var count = 0;
                try
                {
                    var line = new byte[w * 4];
                    for (var y = 0; y < h; y++)
                    {
                        Marshal.Copy(mapped.DataPointer + y * (int)mapped.RowPitch, line, 0, line.Length);
                        for (var x = 3; x < line.Length; x += 4) if (line[x] > 128) count++;
                    }
                }
                finally { d3d.ImmediateContext.Unmap(staging, 0); }
                return count;
            }
            var visorOnly = Count();
            typeof(OverlayCompositionHudWindow).GetField("_renderDpiScaleX", All)!.SetValue(window, 1.0);
            typeof(OverlayCompositionHudWindow).GetField("_renderDpiScaleY", All)!.SetValue(window, 1.0);
            using var write = DWrite.DWriteCreateFactory<Vortice.DirectWrite.IDWriteFactory>(Vortice.DirectWrite.FactoryType.Shared);
            typeof(OverlayCompositionHudWindow).GetField("_writeFactory", All)!.SetValue(window, write);
            Call(window, "DrawVisorBarrage", dc, surface, state);
            typeof(OverlayCompositionHudWindow).GetField("_writeFactory", All)!.SetValue(window, null);
            using var staging = d3d.CreateTexture2D(new Texture2DDescription
            {
                Width = (uint)w, Height = (uint)h, MipLevels = 1, ArraySize = 1, Format = Format.B8G8R8A8_UNorm,
                SampleDescription = new SampleDescription(1, 0), Usage = ResourceUsage.Staging, CPUAccessFlags = CpuAccessFlags.Read,
            });
            d3d.ImmediateContext.CopyResource(staging, texture);
            var map = d3d.ImmediateContext.Map(staging, 0, MapMode.Read);
            var lit = 0;
            try
            {
                var row = new byte[w * 4];
                for (var y = 0; y < h; y++)
                {
                    Marshal.Copy(map.DataPointer + y * (int)map.RowPitch, row, 0, row.Length);
                    for (var x = 3; x < row.Length; x += 4) if (row[x] > 128) lit++;
                }
            }
            finally { d3d.ImmediateContext.Unmap(staging, 0); }
            Check(visorOnly > 1000 && lit > visorOnly + 300, "chat as barrage: the barrage lines are drawn over the visor's frame", new { VisorOnly = visorOnly, WithBarrage = lit });
        }
    }

    /// <summary>
    /// Twenty rows on the production off-screen renderer, with a synthetic PNG for review.
    /// </summary>
    private static void TwentyRows(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        Check(OverlayVisorDraw.RowsFor(874) == 20 && OverlayVisorDraw.RowsFor(554) == 12,
            "new maximum holds twenty; old maximum still holds twelve");
        Check(OverlayRosterPlanner.ResolveCapacity(2000) == 20 && OverlayRosterPlanner.ResolveCapacity(2000, 20) == 20 &&
            OverlayRosterPlanner.ResolveCapacity(52 + 6 * 35, 20) == 6 && OverlayRosterPlanner.ResolveCapacity(2000, 16) == 16,
            "classic capacity caps at twenty and still respects physical height");
        foreach (var people in new[] { 20, 25 })
        {
            using var window = Window(people, w, h, tweak: s => s with
                { VisorMembersHeight = 874, VisorSize = OverlayVisorSize.Medium, VisorTilt = 15 }, rowLimit: 20);
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            Check(window.VisorMemberViewport == 52 + 20 * 35 && scene.Members.Count == 20 &&
                (people == 20 || scene.PageLabel.Length > 0), "twenty-row viewport and twenty-five-member pagination");
            scene = scene with
            {
                ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null,
                TeamTitle = "示例舰队 · 20 人满页", YouAt = "示例地点", TeamCount = "20 位示例成员",
                Members = scene.Members.Select((m, i) => m with
                {
                    Name = $"示例成员 {i + 1:00}", Ship = $"示例舰船 {i + 1:00}", Place = $"示例地点 {i + 1:00}",
                    State = i % 4 == 2 ? OverlayVisorMemberState.AppOnly : i % 4 == 3 ? OverlayVisorMemberState.Away : OverlayVisorMemberState.InGame,
                    SameServer = i % 4 == 0, Status = "示例状态",
                }).ToArray(),
            };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 500);
            var layer = ((IDictionary)Get(renderer, "_layers")!)["team"]!;
            var rings = (OverlayVisorDraw.RingSpot[])Get(layer, "Rings")!;
            Check(rings.Length == 20 && rings.Select(r => r.Key).Distinct().Count() == 20 &&
                rings.All(r => r.Y - 27 >= OverlayVisorDraw.TeamHeader && r.Y + 7 < 874) &&
                rings.Zip(rings.Skip(1), (a, b) => b.Y - a.Y).All(gap => gap >= OverlayVisorDraw.DenseRowHeight) &&
                (float)Get(layer, "ContentH")! <= 874.5f && Lit(dc, overlay, w, h) > 1000,
                "renderer emits twenty distinct rows inside the panel without overlap");
            if (people == 20) Save(dc, overlay, null, w, h, Path.Combine(AppContext.BaseDirectory, "visor-20-rows.png"));
        }
    }

    /// <summary>Adaptive/fixed dimensions, paging and overflow at the configured panel size.</summary>
    private static void MembersSize(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        (OverlayVisorRenderer Renderer, OverlayVisorScene Scene) Draw(int people, Func<int, PlayerRow>? row, Func<OverlayDisplaySettings, OverlayDisplaySettings> tweak)
        {
            using var window = Window(people, w, h, tweak: tweak, row: row);
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            scene = scene with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
            var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 500);
            return (renderer, scene);
        }
        float ContentH(OverlayVisorRenderer r) => (float)Get(((IDictionary)Get(r, "_layers")!)["team"]!, "ContentH")!;
        float Inner(OverlayVisorRenderer r) => OverlayVisorDraw.TeamWidth([.. r.TeamColumns]);

        // width adaptive with a smaller maximum: the longest names stop at it, the columns share it
        var (narrowMax, _) = Draw(6, LongRow, s => s with { VisorMembersWidth = 260 });
        using (narrowMax)
            Check(narrowMax.TeamWidth <= 260 && MathF.Abs(Inner(narrowMax) - 260) <= 2 && narrowMax.ScrollFields > 0,
                "members width adaptive, maximum 260: the longest names stop at it and scroll", new { narrowMax.TeamWidth, Columns = narrowMax.TeamColumns });
        // width fixed: the group keeps the width with everyday names too
        var (fixedWidth, _) = Draw(6, null, s => s with { VisorMembersAutoWidth = false, VisorMembersWidth = 330 });
        using (fixedWidth)
            Check(fixedWidth.TeamWidth == 330 && MathF.Abs(Inner(fixedWidth) - 330) <= 2 && !fixedWidth.Animating(500),
                "members width fixed at 330: the group keeps it with everyday names", new { fixedWidth.TeamWidth, Columns = fixedWidth.TeamColumns });
        // 11-10 (user: "不希望模块上下自适应了，老是会变位置，就要固定上下高度"): the members keep the set height whatever
        // the number of rows, even with the old adaptive-height switch still saved on; the rows spread out when there are
        // few and tighten a little when there are many ("信息较少而空间较大可以宽松一些，如果信息较多可以稍微密一点")
        var (three, _) = Draw(3, null, s => s with { VisorMembersAutoHeight = true });
        var (six, _) = Draw(6, null, s => s);
        var defaultHeight = (float)OverlayDisplaySettings.DefaultVisorMembersHeight;
        using (three) using (six)
            Check(MathF.Abs(ContentH(three) - defaultHeight) < 0.5f && MathF.Abs(ContentH(six) - defaultHeight) < 0.5f && three.Positions["team"] == six.Positions["team"],
                "members height fixed: three or six members keep the default height and the same place, even with the old adaptive switch on",
                new { Three = ContentH(three), Six = ContentH(six), At3 = three.Positions["team"], At6 = six.Positions["team"] });
        float pitch3 = OverlayVisorDraw.RowPitch(defaultHeight, 3, false, false), pitch6 = OverlayVisorDraw.RowPitch(defaultHeight, 6, false, false),
            pitch8 = OverlayVisorDraw.RowPitch(defaultHeight, OverlayVisorDraw.RowsFor(defaultHeight), true, false), pitchFew = OverlayVisorDraw.RowPitch(defaultHeight, 1, false, false);
        Check(pitchFew == OverlayVisorDraw.LooseRowHeight && pitch3 >= pitch6 && pitch6 > OverlayVisorDraw.RowHeight && pitch8 < OverlayVisorDraw.RowHeight &&
              pitch8 >= OverlayVisorDraw.DenseRowHeight && OverlayVisorDraw.RowPitch(0, 3, false, false) == OverlayVisorDraw.RowHeight,
            "members row spacing: wider with few members (at most 60), a little tighter with a full page (at least 35), 40 when the height is not fixed",
            new { pitchFew, pitch3, pitch6, pitch8 });
        // height fixed: the group keeps the height with three members
        var (tall, _) = Draw(3, null, s => s with { VisorMembersAutoHeight = false, VisorMembersHeight = 540 });
        using (tall)
            Check(MathF.Abs(ContentH(tall) - 540) < 0.5f, "members height fixed at 540: the group keeps it with three members", ContentH(tall));
        // 11-07 (user: "youat可以"): "你在" is on the title line, so three members take one line less of header
        var (titled, titledScene) = Draw(3, null, s => s);
        using (titled)
            Check(titledScene.YouAt.Length > 0 && MathF.Abs(ContentH(titled) - defaultHeight) < 0.5f &&
                OverlayVisorDraw.TeamHeader == 51 && OverlayVisorDraw.RowsFor(defaultHeight) == 9,
                "members: \"你在\" sits on the title line (no line of its own); the default height holds nine rows at the tighter spacing",
                new { titledScene.YouAt, Height = ContentH(titled) });
        MembersSizeReviewR3(dc, overlay, dw, w, h, Draw, ContentH);
        // too many rows for the height turn pages (the old adaptive switch, if still saved, changes nothing)
        foreach (var auto in new[] { true, false })
        {
            var (paged, scene) = Draw(30, null, s => s with { VisorMembersAutoHeight = auto, VisorMembersHeight = 300 });
            using (paged)
                Check(scene.Members.Count == OverlayVisorDraw.RowsFor(300) && scene.PageLabel.Length > 0 && ContentH(paged) <= 300.5f,
                    $"members height 300 (old adaptive switch {(auto ? "on" : "off")}) with 30 people: pages of {OverlayVisorDraw.RowsFor(300)} rows with a page number, within the height",
                    new { Rows = scene.Members.Count, scene.PageLabel, Height = ContentH(paged) });
        }
        // both fixed, both adaptive at the defaults: the four combinations draw and settle
        foreach (var (autoW, autoH) in new[] { (true, true), (true, false), (false, true), (false, false) })
        {
            var (r, scene) = Draw(6, null, s => s with { VisorMembersAutoWidth = autoW, VisorMembersAutoHeight = autoH });
            using (r)
            {
                var before = r.Redraws;
                r.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 501);
                Check(Lit(dc, overlay, w, h) > 1000 && r.Redraws == before, $"members width {(autoW ? "adaptive" : "fixed")}, height {(autoH ? "adaptive" : "fixed")}: draws and settles");
            }
        }
    }

    /// <summary>
    /// Review R3: the tallest members height is the roster's twenty rows; the header stays inside a narrow width; a lower
    /// maximum width applies at once; the pinned gap is within the height; the tallest members keep their column.
    /// </summary>
    private static void MembersSizeReviewR3(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h,
        Func<int, Func<int, PlayerRow>?, Func<OverlayDisplaySettings, OverlayDisplaySettings>, (OverlayVisorRenderer, OverlayVisorScene)> draw,
        Func<OverlayVisorRenderer, float> contentH)
    {
        var tallest = (float)OverlayDisplaySettings.MaxVisorMembersHeight;
        var (twelve, twelveScene) = draw(30, null, s => s with { VisorMembersHeight = tallest });
        using (twelve)
        using (var window = Window(30, w, h, tweak: s => s with { VisorMembersHeight = tallest }))
        {
            // the overlay hands the roster room for twenty rows (its own page limit); this test window also sets the
            // user's row limit to 11, which still applies
            var viewport = (double)Get(window, "VisorMemberViewport")!;
            Check(OverlayVisorDraw.RowsFor(tallest) == 20 && Math.Abs(viewport - (52 + 20 * 35)) < 0.01 && twelveScene.Members.Count == 11 && contentH(twelve) <= tallest + 0.5f,
                "members height at its maximum: room for twenty rows (the roster's limit), the user's row limit still applies, within the height",
                new { Viewport = viewport, Rows = twelveScene.Members.Count, Height = contentH(twelve) });
        }

        // a narrow members width with a long place: the header stays inside it (the place scrolls)
        var k = h / 1080f * OverlayVisorRenderer.Compact;
        using (var window = Window(6, w, h, tweak: s => s with { VisorMembersAutoWidth = false, VisorMembersWidth = 220 }))
        {
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            scene = scene with
            {
                ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null, Style = scene.Style with { Tilt = 0 },
                YouAt = "派罗小行星群基地遭遇区 A · 美服 #001", TeamTitle = "非常长的组织名字示例舰队联盟", TeamCount = "共 30 人",
            };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 700);
            var (min, max) = LitColumns(dc, overlay, w, h);
            Check(max - min <= (220 + 32) * k + 4 && renderer.ScrollFields >= 1,
                "members width 220 with a long title and place: the header stays inside the width and scrolls", new { Width = max - min, Box = (220 + 32) * k, renderer.ScrollFields });
        }

        // a lower maximum width applies at once, not after the wait to narrow
        using (var wide = Window(6, w, h, row: LongRow))
        using (var narrow = Window(6, w, h, row: LongRow, tweak: s => s with { VisorMembersWidth = 240 }))
        {
            OverlayVisorScene Team(OverlayCompositionHudWindow window) =>
                ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!) with { ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Team(wide), w, h, 800);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Team(narrow), w, h, 801);
            var inner = OverlayVisorDraw.TeamWidth([.. renderer.TeamColumns]);
            Check(inner <= 240.5f && renderer.TeamWidth <= 240, "members: lowering the maximum width narrows the columns at once", new { inner, renderer.TeamWidth });
        }

        // pinned members, a full page and a page line: the gap after the pinned ones stays within the default height
        using (var window = Window(30, w, h))
        {
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            var members = scene.Members.Select((m, i) => m with { Pinned = i < 2 }).ToArray();
            scene = scene with { Members = members, ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 900);
            Check(members.Length == OverlayVisorDraw.RowsFor((float)OverlayDisplaySettings.DefaultVisorMembersHeight) && scene.PageLabel.Length > 0 && contentH(renderer) <= (float)OverlayDisplaySettings.DefaultVisorMembersHeight + 0.5f,
                "members: pinned and other members with a page line fit the default height", new { Rows = members.Length, Height = contentH(renderer) });
        }

        // The former maximum (554) at the large size keeps the right column, wherever many events show (review R4); the
        // layout editor computes the same top (overlay_visor_layout_test.dart). m102 (11-18 user: "往下延长", the members
        // are never pushed by the events): it keeps the middle slot's top, below the events' three-line box
        using (var window = Window(6, w, h, tweak: s => s with { VisorSize = OverlayVisorSize.Large, VisorMembersHeight = 554 }))
        {
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            OverlayVisorEvent[] all = [new("到达", "Vega 到达奥里森", "20:41", 1, 1), new("换船", "Lyra 换乘 Cutlass Black", "20:39", 1, 1), new("换服", "Draco 换到 欧服 #009", "20:37", 1, 1)];
            var layoutWidth = w / (h / 1080f);
            var g = OverlayVisorRenderer.Compact * scene.Style.SizeFactor;
            var expectedTop = OverlayVisorLayout.RightMidTop;
            Check(expectedTop > 150 + OverlayVisorDraw.EventsBoxHeight(3) * g + OverlayVisorLayout.Gap, "the middle slot's top is below the events' box at the large size");
            foreach (var count in new[] { 0, 1, 3 })
            {
                using var renderer = new OverlayVisorRenderer(dc, dw);
                renderer.Render(overlay, System.Numerics.Vector2.Zero,
                    scene with { ShowEvents = true, ShowChat = false, ShowNotice = false, DirectMessage = null, Events = all.Take(count).ToArray() }, w, h, 1000);
                var team = renderer.Positions["team"];
                Check(team.X > layoutWidth / 2 && MathF.Abs(team.Y - expectedTop) < 0.5f,
                    $"the tallest members at the large size with {count} events: right column, top at {expectedTop:F2} (under the events' three-line box)",
                    new { team.X, team.Y });
            }
        }
    }

    /// <summary>
    /// Review R5: moved events and moved members follow the same order as the layout editor (moved groups first, then
    /// members, events, chat), and a moved event height is Y x 990 in layout units. The editor test checks the same numbers
    /// (overlay_visor_layout_test.dart).
    /// </summary>
    private static void MovedEvents(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        var layoutWidth = w / (h / 1080f);
        var g = OverlayVisorRenderer.Compact;
        OverlayVisorEvent[] one = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)];
        // 1. members moved to the left at top 400, events on the left at 0.4: the members stay, the events move up
        var membersLayout = $"Members,{57.6 / layoutWidth:0.######},{400 / 1080.0:0.######},0.13,0.3,Left,Top";
        using (var window = Window(6, w, h, membersLayout, s => s with { EventNotificationSide = OverlayEventNotificationSide.Left, EventNotificationY = 0.4 }))
        {
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene with { ShowEvents = true, Events = one, ShowChat = false, ShowNotice = false, DirectMessage = null }, w, h, 1100);
            var expectedEvents = 400 - OverlayVisorLayout.Gap - OverlayVisorDraw.EventsBoxHeight(3) * g;
            Check(MathF.Abs(renderer.Positions["team"].Y - 400) < 0.5f && MathF.Abs(renderer.Positions["events"].Y - expectedEvents) < 0.5f,
                "moved members and moved events: the members keep their place, the events move just above them",
                new { Team = renderer.Positions["team"].Y, Events = renderer.Positions["events"].Y, ExpectedEvents = expectedEvents });
        }
        // 2. events on the right at 0.6 at 1440 high: their top is 0.6 x 990 = 594, just over the default members' bottom.
        // m102 (11-18 user: the events give way, never the members): the members keep their place, the events placed
        // below them move a gap below them
        using (var window = Window(6, w, h, tweak: s => s with { EventNotificationSide = OverlayEventNotificationSide.Right, EventNotificationY = 0.6 }))
        {
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene with { ShowEvents = true, Events = one, ShowChat = false, ShowNotice = false, DirectMessage = null }, w, h, 1200);
            var membersH = (float)OverlayDisplaySettings.DefaultVisorMembersHeight * g;
            var expectedTeam = OverlayVisorLayout.RightMidTop;
            var expectedEvents = expectedTeam + membersH + OverlayVisorLayout.Gap;
            Check(MathF.Abs(renderer.Positions["events"].Y - expectedEvents) < 0.5f && MathF.Abs(renderer.Positions["team"].Y - expectedTeam) < 0.5f,
                "events moved to 0.6 at 1440 high (top 594, over the members' bottom): the members stay, the events move just below them",
                new { Events = renderer.Positions["events"].Y, Team = renderer.Positions["team"].Y, ExpectedTeam = expectedTeam });
        }
    }

    /// <summary>
    /// 11-07 (user: "2放"): events and chat width adaptive or fixed like the members; the existing line counts apply and
    /// set the boxes they are placed by; long text scrolls inside the group (a long chat message used to run past it).
    /// </summary>
    private static void EventsAndChatSize(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        var k = h / 1080f * OverlayVisorRenderer.Compact;
        OverlayVisorScene Scene(Func<OverlayDisplaySettings, OverlayDisplaySettings> tweak)
        {
            using var window = Window(3, w, h, tweak: tweak);
            return (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
        }
        // the line counts reach the visor and size the boxes
        var counted = Scene(s => s with { EventNotificationMaxVisibleCount = 5, ChatMaxVisibleCount = 2 });
        Check(counted.EventsCount == 5 && counted.ChatCount == 2, "the existing event and chat line counts reach the visor", new { counted.EventsCount, counted.ChatCount });
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            var g = OverlayVisorRenderer.Compact * counted.Style.SizeFactor;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, counted with
            {
                ShowEvents = true, ShowChat = true, ShowTeam = false, ShowNotice = false, DirectMessage = null,
                Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)], Chat = [new("Aster", "收到。", 1)],
            }, w, h, 1300);
            Check(MathF.Abs(renderer.Sizes["events"].H - OverlayVisorDraw.EventsBoxHeight(5) * g) < 0.01f &&
                MathF.Abs(renderer.Sizes["chat"].H - MathF.Max(OverlayVisorLayout.ChatMinHeight, OverlayVisorDraw.ChatBoxHeight(2) * g)) < 0.01f,
                "events and chat are placed by the height of their most lines, whatever shows", renderer.Sizes);
        }
        // events width: adaptive follows short text, stops at the width with long text (which scrolls); fixed stays
        var shortEvent = new OverlayVisorEvent("到达", "Vega 到达奥里森", "20:41", 1, 1);
        var longEvent = new OverlayVisorEvent("换船", "Kestrel 换乘 十字军 大力神 A2 星际运输船 维克洛战争特别版，前往人民服务空间站 拉姆达", "20:39", 1, 1);
        float EventsWidth(Func<OverlayDisplaySettings, OverlayDisplaySettings> tweak, OverlayVisorEvent e, out int scrolls)
        {
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Scene(tweak) with
            {
                ShowEvents = true, Events = [e], ShowTeam = false, ShowChat = false, ShowNotice = false, DirectMessage = null,
            }, w, h, 1400);
            scrolls = renderer.ScrollFields;
            return renderer.GroupWidths["events"];
        }
        var narrow = EventsWidth(s => s, shortEvent, out var narrowScrolls);
        var capped = EventsWidth(s => s with { VisorEventsWidth = 300 }, longEvent, out var cappedScrolls);
        var fixedWidth = EventsWidth(s => s with { VisorEventsAutoWidth = false, VisorEventsWidth = 330 }, shortEvent, out _);
        Check(narrow < 300 && narrowScrolls == 0 && capped == 300 && cappedScrolls == 1 && fixedWidth == 330,
            "events width: adaptive follows short text, stops at its width with long text (which scrolls), fixed keeps the width",
            new { narrow, capped, cappedScrolls, fixedWidth });
        // review R7: five events and eight chat lines are drawn whole (the group bitmaps hold the most lines)
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            OverlayVisorEvent[] five = [.. Enumerable.Range(0, 5).Select(i => new OverlayVisorEvent("到达", $"成员 {i} 到达奥里森", "20:4" + i, 1, 1))];
            OverlayVisorChatLine[] eight = [.. Enumerable.Range(0, 8).Select(i => new OverlayVisorChatLine("Aster", $"第 {i} 条消息", 1))];
            renderer.Render(overlay, System.Numerics.Vector2.Zero, Scene(s => s with { EventNotificationMaxVisibleCount = 5, ChatMaxVisibleCount = 8 }) with
            {
                ShowEvents = true, Events = five, ShowChat = true, Chat = eight, ShowTeam = false, ShowNotice = false, DirectMessage = null,
            }, w, h, 1450);
            var layers = (IDictionary)Get(renderer, "_layers")!;
            var eventsH = (float)Get(layers["events"]!, "ContentH")!;
            var chatH = (float)Get(layers["chat"]!, "ContentH")!;
            Check(MathF.Abs(eventsH - OverlayVisorDraw.EventsBoxHeight(5)) < 0.5f && MathF.Abs(chatH - OverlayVisorDraw.ChatBoxHeight(8)) < 0.5f,
                "five events and eight chat lines are drawn whole", new { eventsH, chatH });
        }
        // review R7: at the large size, the tallest members and five events overflow the right column. m102 (11-18 user:
        // "成员不挪，事件让，让不开就重叠"): the members stay on the right at the middle slot's top, the events keep 150 and
        // overlap them (the editors warn; overlay_visor_layout_test.dart shows the same)
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            // 554 was the tallest members height before 20 rows (11-14); the 874 case below checks the new tallest
            var big = Scene(s => s with { VisorSize = OverlayVisorSize.Large, VisorMembersHeight = 554, EventNotificationMaxVisibleCount = 5 });
            renderer.Render(overlay, System.Numerics.Vector2.Zero, big with
            {
                ShowEvents = true, Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)], ShowChat = false, ShowNotice = false, DirectMessage = null,
            }, w, h, 1460);
            var team = renderer.Positions["team"];
            var events = renderer.Positions["events"];
            var layoutWidth = w / (h / 1080f);
            Check(team.X > layoutWidth / 2 && MathF.Abs(team.Y - OverlayVisorLayout.RightMidTop) < 0.5f && MathF.Abs(events.Y - 150) < 0.5f &&
                OverlayVisorLayout.EventsOverlap(renderer.Positions, renderer.Sizes) is not null,
                "an overflowing right column: the members stay on the right (386), the events stay at 150 and overlap them",
                new { team.X, team.Y, EventsY = events.Y });
        }
        // 11-14 twenty rows: the new tallest (874) at the large size also stays on the right (m102), lifts to fit above
        // the column's bottom (its own height, not the events), and stays on screen; the events keep 150 and overlap
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            var tallest = Scene(s => s with { VisorSize = OverlayVisorSize.Large, VisorMembersHeight = OverlayDisplaySettings.MaxVisorMembersHeight, EventNotificationMaxVisibleCount = 5 });
            renderer.Render(overlay, System.Numerics.Vector2.Zero, tallest with
            {
                ShowEvents = true, Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)], ShowChat = false, ShowNotice = false, DirectMessage = null,
            }, w, h, 1465);
            var team = renderer.Positions["team"];
            var events = renderer.Positions["events"];
            var layoutWidth = w / (h / 1080f);
            var teamH = renderer.Sizes["team"].H;
            Check(team.X > layoutWidth / 2 && team.Y >= 150 - 0.5f && team.Y < OverlayVisorLayout.RightMidTop && team.Y + teamH <= OverlayVisorLayout.RightBottom + 0.5f &&
                MathF.Abs(events.Y - 150) < 0.5f,
                "the tallest members (874) at the large size: they stay on the right, lift to fit the column, the events stay at 150",
                new { team.X, team.Y, teamH, EventsY = events.Y });
        }
        // a long chat message stays inside the chat group and scrolls; a fading line is cut instead
        var longChat = new OverlayVisorChatLine("Aster", "准备完成，正在前往集合点，大家记得带上货船和护航，十分钟后在奥里森上空集合出发。", 1);
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            var scene = Scene(s => s with { VisorChatAutoWidth = false, VisorChatWidth = 260 }) with
            {
                ShowChat = true, Chat = [longChat], ShowTeam = false, ShowEvents = false, ShowNotice = false, DirectMessage = null,
                Style = Scene(s => s).Style with { Tilt = 0 },
            };
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene, w, h, 1500);
            var (min, max) = LitColumns(dc, overlay, w, h);
            var scrolling = renderer.ScrollFields;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, scene with { Chat = [longChat with { Opacity = 0.5f }] }, w, h, 1501);
            Check(max - min <= (260 + 32) * k + 4 && scrolling == 1 && renderer.ScrollFields == 0,
                "a long chat message stays inside the chat width and scrolls; while it fades it is cut instead",
                new { Width = max - min, Box = (260 + 32) * k, scrolling, Fading = renderer.ScrollFields });
        }
    }

    /// <summary>The column debounce on its own: wider at once, narrower after five quiet seconds over 0.3 s.</summary>
    private static void ColumnDebounce()
    {
        var c = new OverlayVisorColumnWidths();
        c.Update([100, 80], 0);
        var wider = c.Update([140, 80], 1);
        Check(wider[0] == 140 && !c.Busy, "column widths: a column that needs more room widens at once", wider);
        c.Update([90, 80], 2);
        var held = c.Update([90, 80], 6.9)[0];
        c.Update([95, 80], 6.95); // a change while waiting starts the wait again
        var restarted = c.Update([95, 80], 11.9)[0];
        c.Update([95, 80], 12.0); // five quiet seconds: the narrowing starts
        var easing = c.Update([95, 80], 12.1)[0];
        var done = c.Update([95, 80], 12.4)[0];
        Check(held == 140 && restarted == 140 && easing < 140 && easing > 95 && MathF.Abs(done - 95) < 0.01f && !c.Busy,
            "column widths: narrower only after five quiet seconds, eased over 0.3 s; a change while waiting starts again",
            new { held, restarted, easing, done });
        c.Update([95, 60], 20);
        c.Update([95, 60], 25.05);
        c.Update([95, 60], 25.15);
        var grow = c.Update([200, 60], 25.2);
        Check(grow[0] == 200 && grow[1] < 80 && grow[1] > 60 && c.Waiting,
            "column widths: a column that widens mid-narrowing does so at once; the other stops where it is and waits again", grow);
    }

    /// <summary>Waits until the GPU has drawn the frame (reads one pixel back).</summary>
    private static void Finish(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(1, 1), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(new System.Drawing.Point(0, 0), overlay, new System.Drawing.Rectangle(0, 0, 1, 1));
        read.Map(MapOptions.Read);
        read.Unmap();
    }

    /// <summary>The top and bottom rows with a clearly visible pixel (alpha over a half).</summary>
    private static (int Min, int Max) LitRows(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, int w, int h)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(overlay);
        var map = read.Map(MapOptions.Read);
        var row = new byte[w * 4];
        int min = h, max = -1;
        try
        {
            for (var y = 0; y < h; y++)
            {
                Marshal.Copy(map.Bits + y * (int)map.Pitch, row, 0, row.Length);
                for (var x = 3; x < row.Length; x += 4) if (row[x] > 128) { min = Math.Min(min, y); max = Math.Max(max, y); break; }
            }
        }
        finally { read.Unmap(); }
        return (min, max);
    }

    /// <summary>
    /// 11-07 the look is settled ("参考游戏，渐隐", no grid or ticks): the chat plate is the one choice left, as a
    /// setting ("可选", on by default). Turning it off redraws the chat once, draws less of it, and keeps every place.
    /// </summary>
    private static void Looks(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, IDWriteFactory5 dw, int w, int h)
    {
        int Chat(bool plate, out int redraws)
        {
            using var window = Window(6, w, h, tweak: s => s with { VisorChatPlate = plate });
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            Check(scene.ChatPlate == plate, $"聊天底框 {(plate ? "on" : "off")}: the setting reaches the drawing", scene.ChatPlate);
            var chat = scene with { ShowTeam = false, ShowEvents = false, ShowNotice = false, DirectMessage = null, ShowChat = true, Chat = [new("Aster", "收到。", 1)] };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, chat, w, h, 80);
            var before = renderer.Redraws;
            renderer.Render(overlay, System.Numerics.Vector2.Zero, chat, w, h, 81);
            redraws = renderer.Redraws - before;
            return Visible(dc, overlay, w, h);
        }
        var with = Chat(true, out var idleWith);
        var without = Chat(false, out var idleWithout);
        Check(without < with && without > 0 && idleWith == 0 && idleWithout == 0,
            "聊天底框: without the plate the chat draws only its text (fewer visible pixels), and settles", new { With = with, Without = without });
        Check(OverlayDisplaySettings.Default.VisorChatPlate, "聊天底框: on by default");
    }

    /// <summary>How many pixels of the overlay are visible at all (alpha over 8).</summary>
    private static int Visible(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, int w, int h)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(overlay);
        var map = read.Map(MapOptions.Read);
        var row = new byte[w * 4];
        var count = 0;
        try
        {
            for (var y = 0; y < h; y++)
            {
                Marshal.Copy(map.Bits + y * (int)map.Pitch, row, 0, row.Length);
                for (var x = 3; x < row.Length; x += 4) if (row[x] > 8) count++;
            }
        }
        finally { read.Unmap(); }
        return count;
    }

    /// <summary>
    /// --visor-text-widths: drawn widths (design units) of every ship and place name in the client data at the member
    /// row sizes (ship and place 15 design units = 12 px, names 16 = 13 px at 1440p medium), with percentiles. Used to
    /// set the K1 column caps (user, 11-07: "小而精", caps that fit 80-90% of everyday names, longer ones scroll).
    /// </summary>
    internal static void TextWidths()
    {
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        using var p = new OverlayVisorPainter(dc, dw);
        var data = Path.Combine(FindRepositoryRoot(), "StarBridge.Desktop", "Data");
        static IEnumerable<(string Key, string Value)> Pairs(string path) => File.ReadLines(path)
            .Where(line => line.Length > 0 && line[0] != '#' && line.Contains('='))
            .Select(line => (line[..line.IndexOf('=')].Trim(), line[(line.IndexOf('=') + 1)..].Trim()))
            .Where(pair => pair.Item2.Length > 0);
        var ships = Pairs(Path.Combine(data, "ship-names-zh.txt")).Where(pair => pair.Key.StartsWith("vehicle_Name", StringComparison.OrdinalIgnoreCase)).ToArray();
        var sets = new (string Label, string[] Texts, bool Numeric, float Size)[]
        {
            ("ship (full)", ships.Where(pair => !pair.Key.EndsWith("_short", StringComparison.OrdinalIgnoreCase)).Select(pair => pair.Value).Distinct().ToArray(), false, 15),
            ("ship (short)", ships.Where(pair => pair.Key.EndsWith("_short", StringComparison.OrdinalIgnoreCase)).Select(pair => pair.Value).Distinct().ToArray(), false, 15),
            ("place", Pairs(Path.Combine(data, "location-names-zh.txt")).Select(pair => pair.Value).Distinct().ToArray(), false, 15),
            ("name (sample handles)", DailyHandles, true, 16),
        };
        var medium1440 = 1440f / 1080f * OverlayVisorRenderer.Compact;
        foreach (var (label, texts, numeric, size) in sets)
        {
            var widths = texts.Select(t => p.Measure(t, numeric, Vortice.DirectWrite.FontWeight.Medium, size)).OrderBy(x => x).ToArray();
            float At(double q) => widths[Math.Clamp((int)Math.Ceiling(q * widths.Length) - 1, 0, widths.Length - 1)];
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                Kind = "WIDTHS", Set = label, Count = widths.Length,
                P50 = At(0.5), P80 = At(0.8), P85 = At(0.85), P90 = At(0.9), Max = widths[^1],
                P85Px1440Medium = At(0.85) * medium1440,
                Longest = texts.OrderByDescending(t => p.Measure(t, numeric, Vortice.DirectWrite.FontWeight.Medium, size)).First(),
            }));
        }
    }

    // Typical RSI handles and call signs (no member list is kept in the repository; lengths 4-16 like everyday ones).
    internal static readonly string[] DailyHandles =
    [
        "Aster", "Vega", "Lyra", "Raven", "Nova", "Orion", "Kestrel", "多米诺", "夜航者", "NightOwl_7", "Domino_CN", "SilentFox",
        "Maverick88", "IronClad", "StarDust_01", "Wanderer", "老王", "星海小队长", "Phoenix_Rise", "BlueComet", "Hawkeye", "Specter_X",
        "QuantumLeap", "Drifter", "冷锋", "Kite", "RedBaron_CN", "Sabre", "TitanForge", "Nebula_Walker",
    ];

    private static string FindRepositoryRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "StarBridge.sln"))) dir = dir.Parent;
        return dir?.FullName ?? throw new InvalidOperationException("repository root");
    }

    /// <summary>The leftmost and rightmost columns with a clearly visible pixel (alpha over a half).</summary>
    private static (int Min, int Max) LitColumns(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, int w, int h)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(overlay);
        var map = read.Map(MapOptions.Read);
        var row = new byte[w * 4];
        int min = w, max = -1;
        try
        {
            for (var y = 0; y < h; y++)
            {
                Marshal.Copy(map.Bits + y * (int)map.Pitch, row, 0, row.Length);
                for (var x = 0; x < w; x++) if (row[x * 4 + 3] > 128) { min = Math.Min(min, x); max = Math.Max(max, x); }
            }
        }
        finally { read.Unmap(); }
        return (min, max);
    }

    /// <summary>How many pixels of a GPU bitmap are clearly visible (alpha over a half).</summary>
    private static int Lit(ID2D1DeviceContext dc, ID2D1Bitmap1 bitmap)
    {
        var size = bitmap.PixelSize;
        return Lit(dc, bitmap, (int)size.Width, (int)size.Height);
    }

    /// <summary>How many pixels of the overlay are clearly visible (alpha over a half).</summary>
    internal static int Lit(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, int w, int h)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(overlay);
        var map = read.Map(MapOptions.Read);
        var row = new byte[w * 4];
        var lit = 0;
        try
        {
            for (var y = 0; y < h; y++)
            {
                Marshal.Copy(map.Bits + y * (int)map.Pitch, row, 0, row.Length);
                for (var x = 3; x < row.Length; x += 4) if (row[x] > 128) lit++;
            }
        }
        finally { read.Unmap(); }
        return lit;
    }

    /// <summary>The overlay's pixels (BGRA, row by row), to compare two pictures exactly.</summary>
    internal static byte[] Pixels(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay)
    {
        var size = overlay.PixelSize;
        int w = (int)size.Width, h = (int)size.Height;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(overlay);
        var map = read.Map(MapOptions.Read);
        var all = new byte[w * h * 4];
        try
        {
            for (var y = 0; y < h; y++) Marshal.Copy(map.Bits + y * (int)map.Pitch, all, y * w * 4, w * 4);
        }
        finally { read.Unmap(); }
        return all;
    }

    /// <summary>
    /// Review pictures (11-06): the real HUD window builds the frame state, the production visor
    /// renderer draws it off screen at 2560x1440, laid over a real game screenshot. Events, chat,
    /// the DM line and the rally are sample content (at runtime they arrive from the network).
    /// STARBRIDGE_VISOR_PICTURES names the output folder; STARBRIDGE_VISOR_BACKDROP the screenshot.
    /// </summary>
    /// <summary>
    /// The visor's own open and close (user, 11-10) as numbered frames over a backdrop, for a preview video: 60 frames a
    /// second through opening, a pause, and closing. STARBRIDGE_VISOR_PICTURES is the output folder.
    /// </summary>
    internal static void IntroFrames()
    {
        var output = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_PICTURES") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_PICTURES");
        var backdrop = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_BACKDROP") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_BACKDROP");
        var people = int.TryParse(Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_PEOPLE"), out var n) ? n : 3;
        Directory.CreateDirectory(output);
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2560, H = 1440;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        using var window = Window(people, W, H);
        var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
        OverlayVisorEvent[] events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1), new("换服", "Draco 换到 欧服 #009", "20:37", 1, 1)];
        OverlayVisorChatLine[] chat = [new("Aster", "准备完成，正在前往集合点。", 1), new("Lyra", "收到，五分钟到。", 1)];
        const double openAt = 10, closeAt = 11.6;
        var shown = scene with { ShowEvents = true, ShowChat = true, Events = events, Chat = chat, DirectMessage = null, ShowNotice = false, OpenAt = openAt, CloseAt = closeAt };
        using var renderer = new OverlayVisorRenderer(dc, dw);
        var frame = 0;
        var watch = new System.Diagnostics.Stopwatch();
        var timed = new List<double>();
        {
            for (var t = openAt - 0.2; t <= closeAt + 0.7; t += 1 / 60.0, frame++)
            {
                watch.Restart();
                renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, t);
                // a read-back waits for the GPU, so the time covers the drawing itself (and the read-back)
                Lit(dc, overlay);
                if (renderer.Animating(t)) timed.Add(watch.Elapsed.TotalMilliseconds);
                Save(dc, overlay, backdrop, W, H, Path.Combine(output, $"f{frame:D4}.jpg"));
            }
        }
        timed.Sort();
        Console.WriteLine($"INTRO frames={frame} people={people} members={shown.Members.Count} animatedFrames={timed.Count} " +
            $"msMedian={(timed.Count > 0 ? timed[timed.Count / 2] : 0):F2} msMax={(timed.Count > 0 ? timed[^1] : 0):F2}");
    }

    /// <summary>
    /// The health ring (user, 11-10, style 1 of the four tried): the members panel with sample health on every row (full,
    /// 72%, 41%, 15%, downed, dead, not known), and with only the local player's own health (what 0.7.3 has).
    /// Prints where the panel is so the pictures can be cropped. STARBRIDGE_VISOR_PICTURES is the output folder.
    /// </summary>
    internal static void HealthRings()
    {
        var output = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_PICTURES") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_PICTURES");
        var backdrop = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_BACKDROP") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_BACKDROP");
        Directory.CreateDirectory(output);
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2560, H = 1440;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        using var window = Window(7, W, H);
        var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
        (OverlayVisorVitals, float)[] all = [(OverlayVisorVitals.Alive, 1), (OverlayVisorVitals.Alive, 0.72f), (OverlayVisorVitals.Alive, 0.41f),
            (OverlayVisorVitals.Alive, 0.15f), (OverlayVisorVitals.Downed, 0), (OverlayVisorVitals.Dead, 0), (OverlayVisorVitals.Unknown, 0)];
        {
            foreach (var (name, selfOnly) in new[] { ("ring", false), ("ring-self", true) })
            {
                var members = scene.Members.Select((m, i) => selfOnly
                    ? m with { Vitals = i == 0 ? OverlayVisorVitals.Alive : OverlayVisorVitals.Unknown, Health = i == 0 ? 0.86f : 0 }
                    : m with { Vitals = all[i % all.Length].Item1, Health = all[i % all.Length].Item2 }).ToArray();
                var shown = scene with { Members = members, ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null };
                using var renderer = new OverlayVisorRenderer(dc, dw);
                foreach (var t in new[] { 10.0, 20, 30 }) renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, t);
                Save(dc, overlay, backdrop, W, H, Path.Combine(output, name + ".jpg"));
                var scale = H / 1080f;
                var (x, y) = renderer.Positions["team"];
                var (w, h) = renderer.Sizes["team"];
                Console.WriteLine($"RING {name} crop={(int)(x * scale) - 60},{(int)(y * scale) - 40},{(int)(w * scale) + 120},{(int)(h * scale) + 80}");
            }
        }
    }

    /// <summary>
    /// The health ring in motion (user, 11-10, via the scheduler): the local player's own row through full, losses (each
    /// flashes once), low (breathing), downed (slow blink), dead (X), revived (grows from empty) and healing (grows back
    /// smoothly), 60 frames a second. Writes the frames and phases.txt (frame, phase) to STARBRIDGE_VISOR_PICTURES.
    /// </summary>
    internal static void HealthMotion()
    {
        var output = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_PICTURES") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_PICTURES");
        var backdrop = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_BACKDROP") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_BACKDROP");
        Directory.CreateDirectory(output);
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2560, H = 1440;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        using var window = Window(4, W, H);
        var scene = ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!) with
        {
            ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null,
        };
        // (from second, vitals, health, phase)
        (double At, OverlayVisorVitals Vitals, float Health, string Phase)[] script =
        [
            (0, OverlayVisorVitals.Alive, 0.42f, "一半以下（琥珀）"),
            (1.0, OverlayVisorVitals.Alive, 0.18f, "残血（红，静止）"),
            (3.4, OverlayVisorVitals.Downed, 0, "倒地（红色十字，慢闪）"),
            (8.0, OverlayVisorVitals.Dead, 0, "阵亡（X）"),
            (10.0, OverlayVisorVitals.Alive, 0.6f, "复活（从空长起，长满亮一下）"),
        ];
        const double end = 12.2;
        using var renderer = new OverlayVisorRenderer(dc, dw);
        var phases = new List<string>();
        var frame = 0;
        var busy = 0;
        for (var t = 0.0; t <= end; t += 1 / 60.0, frame++)
        {
            var now = script.Last(p => p.At <= t + 1e-9);
            var shown = scene with
            {
                Members = [.. scene.Members.Select((m, i) => i == 0 ? m with { Vitals = now.Vitals, Health = now.Health } : m with { Vitals = OverlayVisorVitals.Unknown, Health = 0 })],
            };
            renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, 100 + t);
            if (renderer.Animating(100 + t)) busy++;
            Save(dc, overlay, backdrop, W, H, Path.Combine(output, $"f{frame:D4}.jpg"));
            phases.Add($"{frame} {now.Phase}");
        }
        File.WriteAllLines(Path.Combine(output, "phases.txt"), phases);
        var scale = H / 1080f;
        var (x, y) = renderer.Positions["team"];
        var (w, h) = renderer.Sizes["team"];
        Console.WriteLine($"MOTION frames={frame} animating={busy} right={renderer.Positions["team"].X > W / scale / 2} crop={(int)(x * scale) - 40},{(int)(y * scale) - 30},{(int)(w * scale) + 80},{(int)(h * scale) + 60}");
    }

    internal static void Pictures()
    {
        var output = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_PICTURES") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_PICTURES");
        var backdrop = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_BACKDROP") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_BACKDROP");
        Directory.CreateDirectory(output);
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2560, H = 1440;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));

        OverlayVisorEvent[] events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1), new("换船", OverlayEventShipPresentation.FormatShipChange("Lyra", "Cutlass Black", zh: true), "20:39", 1, 1), new("换服", "Draco 换到 欧服 #009", "20:37", 1, 1)];
        OverlayVisorChatLine[] chat = [new("Aster", "准备完成，正在前往集合点。", 1), new("Lyra", "收到，五分钟到。", 1)];
        void Picture(string name, int people, Func<OverlayDisplaySettings, OverlayDisplaySettings>? tweak, bool rally, bool invite, Func<int, PlayerRow>? row = null)
        {
            using var window = Window(people, W, H, tweak: tweak, row: row);
            if (invite)
            {
                // the real room-invite path: a live reminder, which the visor shows as a mark beside the DM badge
                var model = (OverlayViewModel)Get(window, "_viewModel")!;
                model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "房间提醒", "新邀请 1 · 新加入申请 0");
            }
            var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
            var dm = invite ? (scene.DirectMessage is { Length: > 0 } mark ? "Vega 发来私信 · " + mark : "Vega 发来私信") : "Vega 发来私信";
            var shown = scene with
            {
                ShowEvents = true, ShowChat = true, Events = events, Chat = chat, DirectMessage = dm,
                ShowNotice = rally, NoticeTitle = rally ? "舰队召集" : scene.NoticeTitle, NoticeBody = rally ? "今晚八点奥里森集合，带上货船" : scene.NoticeBody,
                NoticeTimer = rally ? "剩余 27:30" : scene.NoticeTimer, NoticeHint = rally ? "Ctrl+Alt+Y 马上到　Ctrl+Alt+N 来不了" : scene.NoticeHint, NoticeIsRally = rally,
            };
            using var renderer = new OverlayVisorRenderer(dc, dw);
            foreach (var t in new[] { 10, 20, 30 }) renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, t);
            Save(dc, overlay, backdrop, W, H, Path.Combine(output, name + ".jpg"));
            Console.WriteLine($"PICTURE {name}: members={shown.Members.Count} dm=\"{shown.DirectMessage}\" spots={string.Join(",", shown.Spots.Select(kv => kv.Key + "=" + (kv.Value.Slot ?? "free")))}");
        }
        Picture("1-default-3", 3, null, rally: false, invite: true);
        Picture("2-default-30-rally", 30, null, rally: true, invite: false);
        foreach (var size in new[] { OverlayVisorSize.Medium, OverlayVisorSize.Large })
            Picture("4-size-" + size, 8, s => s with { VisorSize = size }, rally: false, invite: false);
        // 11-07 K1: the longest names in the client data scroll inside their own fields
        Picture("5-long-names", 6, null, rally: false, invite: false, row: LongRow);
        // 11-07 聊天底框 off: the chat shows only its text
        Picture("6-chat-text-only", 6, s => s with { VisorChatPlate = false }, rally: false, invite: false);
    }

    /// <summary>
    /// The appearance-center card picture (assets/overlay-appearances/Visor.png, 2000 x 760 like the other
    /// cards): the shipping visor renderer, off screen, with synthetic sample members, events, chat and a
    /// rally on the cards' neutral opaque backdrop. No account, game or saved data is read.
    /// </summary>
    internal static void Catalog()
    {
        var output = Environment.GetEnvironmentVariable("STARBRIDGE_VISOR_CATALOG") ?? throw new InvalidOperationException("STARBRIDGE_VISOR_CATALOG");
        Directory.CreateDirectory(output);
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Hardware, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 2000, H = 760;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        // the card is small: the large visor size on a narrower, taller screen with its empty top and bottom cut off
        const int SceneW = 1300, SceneH = 1060, Top = 30;
        using var window = Window(5, SceneW, SceneH, tweak: s => s with { VisorSize = OverlayVisorSize.Large });
        var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState")!)!;
        var shown = scene with
        {
            ShowEvents = true, ShowChat = true,
            Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1), new("换船", "Lyra 换乘 Cutlass Black", "20:39", 1, 1)],
            Chat = [new("Aster", "准备完成，正在前往集合点。", 1)],
            ShowNotice = true, NoticeTitle = "舰队召集", NoticeBody = "今晚八点奥里森集合", NoticeTimer = "剩余 27:30", NoticeHint = "", NoticeIsRally = true,
        };
        using var renderer = new OverlayVisorRenderer(dc, dw);
        foreach (var t in new[] { 10, 20, 30 }) renderer.Render(overlay, new System.Numerics.Vector2((W - SceneW) / 2f, -Top), shown, SceneW, SceneH, t);
        var path = Path.Combine(output, "Visor.png");
        Save(dc, overlay, null, W, H, path);
        Console.WriteLine($"CATALOG {path}");
    }

    /// <summary>Saves the overlay over a backdrop picture (JPEG), or over the cards' neutral colour (PNG) when there is none.</summary>
    private static void Save(ID2D1DeviceContext dc, ID2D1Bitmap1 overlay, string? backdrop, int w, int h, string path)
    {
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var final = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        dc.Target = final; dc.BeginDraw(); dc.Clear(backdrop is null ? new Color4(8 / 255f, 15 / 255f, 20 / 255f, 1) : new Color4(0, 0, 0, 1));
        if (backdrop is not null)
        {
            var source = new BitmapImage(new Uri(backdrop));
            var converted = new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
            var stride = converted.PixelWidth * 4;
            var bg = new byte[stride * converted.PixelHeight];
            converted.CopyPixels(bg, stride, 0);
            var pin = GCHandle.Alloc(bg, GCHandleType.Pinned);
            using var bgBitmap = dc.CreateBitmap(new SizeI(converted.PixelWidth, converted.PixelHeight), pin.AddrOfPinnedObject(), (uint)stride, new BitmapProperties1(pf, 96, 96, BitmapOptions.None));
            pin.Free();
            dc.DrawBitmap(bgBitmap, new Vortice.Mathematics.Rect(0, 0, w, h), 1f, Vortice.Direct2D1.BitmapInterpolationMode.Linear, null);
        }
        dc.DrawImage(overlay);
        dc.EndDraw().CheckError(); dc.Target = null;
        using var read = dc.CreateBitmap(new SizeI(w, h), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
        read.CopyFromBitmap(final);
        var map = read.Map(MapOptions.Read);
        var px = new byte[w * h * 4];
        try { for (var y = 0; y < h; y++) Marshal.Copy(map.Bits + y * (int)map.Pitch, px, y * w * 4, w * 4); }
        finally { read.Unmap(); }
        BitmapEncoder encoder = backdrop is null ? new PngBitmapEncoder() : new JpegBitmapEncoder { QualityLevel = 90 };
        encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(w, h, 96, 96, PixelFormats.Pbgra32, null, px, w * 4)));
        using var file = File.Create(path);
        encoder.Save(file);
    }
}
