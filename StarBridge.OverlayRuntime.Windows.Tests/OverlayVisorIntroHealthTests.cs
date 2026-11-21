using System.Diagnostics;
using System.Reflection;
using SharpGen.Runtime;
using StarBridge.Core.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// 11-10 user requests on the visor: its own open and close ("转场动画应该做专属的"; "头盔上线", closing "反着收回") and a
/// health ring under each member's status mark ("在线状态方块下面放圆环…从上方顶点顺时针扣血"; downed and dead colour
/// only; the local player's own health in 0.7.3, "连自己的血量一起做").
/// </summary>
internal static class OverlayVisorIntroHealthTests
{
    private static readonly BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) throw new InvalidOperationException($"FAIL {name} {evidence}");
        Console.WriteLine($"PASS {name} {evidence}");
    }

    private static object? Call(object target, string name, params object?[] values) =>
        target.GetType().GetMethods(All).Single(m => m.Name == name && m.GetParameters().Length == values.Length).Invoke(target, values);

    private static object? Field(object target, string name) => target.GetType().GetField(name, All)!.GetValue(target);

    internal static void Run()
    {
        Phases();
        MembersStayWhenEventsAndChatComeAndGo();
        EventsOpenFromTheEdge();
        RingMotion();
        Offscreen();
        LocalVitals();
        CrosshairOverTheVisor();
        ShipPalette();
        OverallOpacity();
        RealBackgroundOpacity();
        // the app's own order (m86, 调度总控): another overlay HUD in this process is shown and closed first, then the visor
        OtherHudShownAndClosed();
        HudOpensAndClosesWithItsOwnMotion();
    }

    private static void Phases()
    {
        var lockAt = OverlayVisorRenderer.BracketLock;
        var (open, close) = OverlayVisorRenderer.Durations;
        Check(lockAt > 0 && open > lockAt && close > 0 && close < open, "visor open and close: the brackets lock inside the opening, closing is quicker",
            new { lockAt, open, close });
        // the rally band and DM badge on the brackets' beat ("乙 只对齐节奏"): nothing before the lock, text with the flash at the lock
        var fx = typeof(OverlayVisorRenderer).GetMethod("CentreGroupFx", All)!;
        OverlayVisorRenderer.Fx At(double t, double c) => (OverlayVisorRenderer.Fx)fx.Invoke(null, [t, c])!;
        var early = At(lockAt - 0.1, double.NegativeInfinity);
        var flash = At(lockAt + 0.06, double.NegativeInfinity);
        var settled = At(open, double.NegativeInfinity);
        var closing = At(open, 0.06);
        var gone = At(open, close);
        Check(early.Panel == 0 && early.Text == 0 && flash.Text > 0.5f && flash.Flash > 0 && settled == OverlayVisorRenderer.Fx.Shown &&
              closing.Text == 0 && closing.Panel > 0 && gone.Panel == 0 && gone.Text == 0,
            "visor panels on the beat: nothing before the lock, text with the flash at the lock, settled after; closing takes the text first",
            new { early, flash, closing });
        Check(OverlayVisorRenderer.IntroBusy(10, double.PositiveInfinity, 10.4) && !OverlayVisorRenderer.IntroBusy(10, double.PositiveInfinity, 10 + open + 0.2) &&
              OverlayVisorRenderer.IntroBusy(double.NegativeInfinity, 20, 20.1) && !OverlayVisorRenderer.IntroBusy(double.NegativeInfinity, 20, 20 + close + 0.2) &&
              !OverlayVisorRenderer.IntroBusy(double.NegativeInfinity, 20, 19.9) && !OverlayVisorRenderer.IntroBusy(double.NegativeInfinity, double.PositiveInfinity, 5),
            "visor open and close ask for frames only while they run");
    }

    /// <summary>
    /// Build 86, user: "事件出现时会把成员往下挤，这个是不行的". With events and chat switched on, the members keep the
    /// same place and size whether there are events or chat lines right now or not; the events and the chat keep their
    /// own places too. Through the real HUD scene, so the places come from the settings as in the app.
    /// </summary>
    private static void MembersStayWhenEventsAndChatComeAndGo()
    {
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 1920, H = 1080;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        // the default settings; the tallest members with the most events; and the user's own layout from build 86 (members
        // moved to the right edge low down, events on the right at 0.291, members 554 high, three events), where it happened
        const string userLayout = "Notice,0.34,0,0.32,0.055,Center,Top,0,1,0.5,1;Squads,0,0.4211,0.1327,0.1042,Left,Middle,0,1,0.5,1;" +
            "Members,0.8889,0.3889,0.0938,0.2719,Right,Bottom,0,1,0.5,1;Chat,0,0.681,0.1327,0.1069,Center,Bottom,0,1,1,1";
        // and events moved down to 0.6 on the right, which moves the default members out of their way
        foreach (var (people, tall, user, low) in new[] { (3, false, false, false), (12, false, false, false), (12, true, false, false), (5, false, true, false),
                     (12, true, true, false), (6, false, false, true) })
        {
            using var window = OverlayVisorTests.Window(people, W, H, layoutPayload: user ? userLayout : null, tweak: st => st with
            {
                ShowEventNotifications = true, ShowChat = true,
                VisorMembersHeight = tall || user ? OverlayDisplaySettings.MaxVisorMembersHeight : st.VisorMembersHeight,
                EventNotificationMaxVisibleCount = tall ? OverlayDisplaySettings.MaxEventNotificationCount : st.EventNotificationMaxVisibleCount,
                EventNotificationSide = low ? OverlayEventNotificationSide.Right : st.EventNotificationSide,
                EventNotificationY = user ? 0.291 : low ? 0.6 : st.EventNotificationY,
            });
            // nothing to show right now: in the app the events and the chat are then not shown at all (their content is empty)
            var quiet = ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!) with { ShowEvents = false, Events = [], ShowChat = false, Chat = [] };
            OverlayVisorEvent[] events = [.. Enumerable.Range(0, quiet.EventsCount).Select(i => new OverlayVisorEvent("到达", $"成员{i} 到达奥里森", "20:41", 1, 1))];
            OverlayVisorChatLine[] chat = [new("Aster", "准备完成，正在前往集合点。", 1), new("Lyra", "收到，五分钟到。", 1)];
            var busy = quiet with { ShowEvents = true, Events = events, ShowChat = true, Chat = chat };
            var onlyEvents = quiet with { ShowEvents = true, Events = events };
            Check(quiet.EventsPlaced == true && quiet.ChatPlaced == true, "visor places: events and chat switched on in settings keep their places", new { quiet.EventsPlaced, quiet.ChatPlaced });

            (Dictionary<string, (float X, float Y)> At, Dictionary<string, (float W, float H)> Size) Place(params OverlayVisorScene[] frames)
            {
                using var renderer = new OverlayVisorRenderer(dc, dw);
                var t = 50.0;
                foreach (var f in frames) renderer.Render(overlay, System.Numerics.Vector2.Zero, f, W, H, t += 1);
                return (new(renderer.Positions), new(renderer.Sizes));
            }
            var a = Place(quiet);
            var b = Place(quiet, busy);
            var c = Place(quiet, busy, quiet);
            var d = Place(quiet, onlyEvents);
            Check(a.At["team"] == b.At["team"] && b.At["team"] == c.At["team"] && d.At["team"] == a.At["team"] && a.Size["team"] == b.Size["team"],
                "visor places: the members do not move or resize when events and chat come and go", new { people, quiet = a.At["team"], busy = b.At["team"], back = c.At["team"] });
            Check(b.At["events"] == d.At["events"] && a.At.TryGetValue("events", out var reserved) && reserved == b.At["events"],
                "visor places: the events keep one place, kept for them even with nothing to show", new { people, events = b.At["events"] });

            // the old rule (places by what shows now) moved the members in this layout; this test would have caught it
            var oldQuiet = quiet with { EventsPlaced = null, ChatPlaced = null };
            var oldBusy = busy with { EventsPlaced = null, ChatPlaced = null };
            var moved = Place(oldQuiet).At["team"] != Place(oldQuiet, oldBusy).At["team"];
            Console.WriteLine($"INFO visor places: placing by what shows now would have moved the members ({people} people, tall={tall}, user={user}, low={low}): {moved}");
            // the default layout with the tallest members and the most events: before m102 the old rule moved the members
            // here (the right column overflowed once the events showed and the members went to the other side). Since m102
            // (11-18 user: "成员不挪，事件让，让不开就重叠") they keep their side, so even this placing leaves them
            if (tall && !user) Check(!moved, "visor places: an overflowing column keeps the members, even placing by what shows now", new { people, tall, low });
            // events moved low: before m102 the old rule moved the members out of their way; since m102 (11-18 user:
            // "事件…应该自己向上避开 而不是向下挤压成员") the events give way, so even placing by what shows now leaves the members
            if (low) Check(!moved, "visor places: events moved low give way, so even placing by what shows now leaves the members", new { people, tall, low });
        }
    }

    /// <summary>
    /// Build 86 (user: "不要标记 从贴边处展开", "只展开，不加别的", "可以"): an event opens from the screen edge with a
    /// bright line and closes back to it, then the row closes up; on the right edge it opens leftward, on the left edge
    /// rightward. No markers, no typing, no interference.
    /// </summary>
    private static void EventsOpenFromTheEdge()
    {
        OverlayVisorEvent At(float reveal, float leave = 0) => new("到达", "Vega 到达奥里森", "20:41", reveal, 1, leave);
        var start = OverlayVisorDraw.EventOpening(At(0));
        var half = OverlayVisorDraw.EventOpening(At(0.4f));
        var open = OverlayVisorDraw.EventOpening(At(1));
        var back = OverlayVisorDraw.EventOpening(At(1, 0.4f));
        var closed = OverlayVisorDraw.EventOpening(At(1, 0.75f));
        var gone = OverlayVisorDraw.EventOpening(At(1, 1));
        // leaving part way through opening: it closes from where it got to, never first jumping open
        var early = OverlayVisorDraw.EventOpening(At(0.2f));
        var earlyLeave = OverlayVisorDraw.EventOpening(At(1, 0.01f) with { LeaveFrom = 0.2f });
        Check(earlyLeave.Open <= early.Open + 0.001f && earlyLeave.Room <= early.Room + 0.001f && earlyLeave.Open > 0,
            "visor events: an event leaving before it has fully opened closes from where it got to", new { early, earlyLeave });
        // the same through the real HUD: an event row entering (30% in), then leaving (review CX-VISOR-B86-R1)
        {
            using var window = OverlayVisorTests.Window(3, 1920, 1080, tweak: st => st with { ShowEventNotifications = true });
            var hud = window.GetType();
            var rowType = hud.GetNestedType("OverlayCompositionEventRow", All)!;
            var colorType = hud.GetNestedType("HudColor", All)!;
            // two events that read the same, told apart by their own view-model rows (Source)
            object a = new(), b = new();
            object Row(object source, float progress, bool entering, bool exiting, float opacity)
            {
                var row = rowType.GetConstructors(All).Single(c => c.GetParameters().Length == 13).Invoke(["倒地", "Vega 在奥里森倒地", "20:41", 0f, opacity, progress, entering, exiting,
                    DateTimeOffset.UnixEpoch, 0.0, 0, false, Activator.CreateInstance(colorType)!]);
                rowType.GetProperty("Source")!.SetValue(row, source);
                return row;
            }
            OverlayVisorEvent[] Built(params object[] rows)
            {
                var state = Call(window, "BuildFrameState")!;
                var copy = state.GetType().GetMethod("<Clone>$")!.Invoke(state, null)!;
                var list = (System.Collections.IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(rowType))!;
                foreach (var row in rows) list.Add(row);
                copy.GetType().GetProperty("EventRows")!.SetValue(copy, list);
                copy.GetType().GetProperty("ShowEvents")!.SetValue(copy, true);
                return [.. ((OverlayVisorScene)Call(window, "BuildVisorScene", copy)!).Events];
            }
            var entering = Built(Row(a, 0.3f, true, false, 0.3f), Row(b, 0.8f, true, false, 0.8f));
            // a leaves on the very frame its leaving starts (progress 0); b, reading the same, keeps opening
            var first = Built(Row(a, 0f, false, true, 0.3f), Row(b, 0.9f, true, false, 0.9f));
            var later = Built(Row(a, 0.3f, false, true, 0.2f), Row(b, 1f, false, false, 1f));
            var was = OverlayVisorDraw.EventOpening(entering[0]);
            var shut0 = OverlayVisorDraw.EventOpening(first[0]);
            var shut1 = OverlayVisorDraw.EventOpening(later[0]);
            Check(Math.Abs(first[0].LeaveFrom - 0.3f) < 0.001f && Math.Abs(later[0].LeaveFrom - 0.3f) < 0.001f &&
                  shut0.Open <= was.Open + 0.001f && shut0.Room <= was.Room + 0.001f && shut1.Open <= shut0.Open + 0.001f &&
                  entering.All(e => e.Opacity == 1) && first.All(e => e.Opacity == 1),
                "visor HUD events: leaving part way through opening starts from where it got to, from its first frame, at full strength",
                new { was, shut0, shut1, first0 = first[0].LeaveFrom });
            Check(first[1].Leave == 0 && Math.Abs(first[1].Reveal - 0.9f) < 0.001f,
                "visor HUD events: two events that read the same keep their own state");
        }
        Check(start.Open == 0 && start.Room == 0 && start.Line == 1 && half.Open is > 0 and < 1 && half.Line == 1 && open == (1, 1, 0) &&
              back.Open is > 0 and < 1 && back.Room == 1 && back.Line == 1 && closed.Open == 0 && closed.Room == 1 && gone == (0, 0, 0),
            "visor events: open from the edge with the line, settle without it; leaving, the line goes back to the edge, then the row closes up",
            new { half, back, closed });

        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 1920, H = 1080;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        foreach (var side in new[] { OverlayEventNotificationSide.Right, OverlayEventNotificationSide.Left })
        {
            // flat (no tilt), so the box's halves on screen are the halves of its layout box (review CX-VISOR-B86-R1)
            using var window = OverlayVisorTests.Window(3, W, H, tweak: st => st with { ShowEventNotifications = true, EventNotificationSide = side, VisorTilt = 0 });
            var scene = ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!) with { ShowChat = false, ShowTeam = false, ShowNotice = false, DirectMessage = null };
            // lit pixels in the half of the events box toward the screen edge, and in the half toward the centre
            (int Edge, int Centre) Halves(float reveal)
            {
                using var renderer = new OverlayVisorRenderer(dc, dw);
                // a detail as wide as the box, so both halves have text once open
                OverlayVisorEvent wide = new("倒地", "Vega 在奥里森倒地，等待救援，最近的成员 Draco", "20:41", reveal, 1);
                renderer.Render(overlay, System.Numerics.Vector2.Zero, scene with { ShowEvents = true, Events = [wide] }, W, H, 80);
                var px = OverlayVisorTests.Pixels(dc, overlay);
                var k = H / 1080f;
                var (x, y) = renderer.Positions["events"];
                var (w, h) = renderer.Sizes["events"];
                int x0 = (int)(x * k), x1 = (int)((x + w) * k), mid = (x0 + x1) / 2, y0 = (int)(y * k), y1 = (int)((y + h) * k);
                int left = 0, rightLit = 0;
                for (var yy = Math.Max(0, y0); yy < Math.Min(H, y1); yy++)
                    for (var xx = Math.Max(0, x0); xx < Math.Min(W, x1); xx++)
                        if (px[(yy * W + xx) * 4 + 3] > 128) { if (xx < mid) left++; else rightLit++; }
                return side == OverlayEventNotificationSide.Right ? (rightLit, left) : (left, rightLit);
            }
            var opening = Halves(0.08f); // about a fifth open (eased)
            var full = Halves(1);
            Check(opening.Edge > opening.Centre * 3 && full.Centre > opening.Centre * 2,
                "visor events: part way through opening, what shows is on the screen-edge side; the centre side comes later",
                new { side, opening, full });
        }
    }

    /// <summary>
    /// The ring over time (user, 11-10, via the scheduler): a loss flashes once, low breathes, downed blinks, dead is still,
    /// revived grows from empty, healing grows back smoothly; frames are asked for only while it moves.
    /// </summary>
    private static void RingMotion()
    {
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        using var renderer = new OverlayVisorRenderer(dc, dw);
        var step = typeof(OverlayVisorRenderer).GetMethod("StepRing", All)!;
        var member = new OverlayVisorMember("Aster", "", "", "", OverlayVisorMemberState.InGame, false, false);
        (OverlayVisorDraw.HealthLook Look, bool Busy) At(OverlayVisorVitals v, float health, double t)
        {
            var r = ((OverlayVisorDraw.HealthLook, bool))step.Invoke(renderer, ["Aster", member with { Vitals = v, Health = health }, t])!;
            return r;
        }
        var first = At(OverlayVisorVitals.Alive, 1, 0);
        var loss = At(OverlayVisorVitals.Alive, 0.5f, 1);
        var after = At(OverlayVisorVitals.Alive, 0.5f, 1 + OverlayVisorRenderer.RingFlash + 0.05);
        Check(!first.Busy && first.Look.Fraction == 1 && loss.Busy && loss.Look.Fraction == 0.5f && loss.Look.Flash > 0.9f && !after.Busy && after.Look.Flash == 0,
            "health ring: still when nothing changes; a loss goes down at once with one flash, then settles", new { loss = loss.Look });
        At(OverlayVisorVitals.Alive, 0.1f, 2);
        var lowLater = At(OverlayVisorVitals.Alive, 0.1f, 2 + OverlayVisorRenderer.RingFlash + 0.05);
        var lowMuchLater = At(OverlayVisorVitals.Alive, 0.1f, 4);
        Check(!lowLater.Busy && !lowMuchLater.Busy && lowLater.Look.Alpha == 1 && lowMuchLater.Look.Fraction == 0.1f,
            "health ring: below a quarter it stays still (\"低血量不闪\"), after the loss's one flash", new { lowLater.Look });
        var downed0 = At(OverlayVisorVitals.Downed, 0, 20);
        var downedHalf = At(OverlayVisorVitals.Downed, 0, 20 + OverlayVisorRenderer.RingBlink / 2);
        var dead = At(OverlayVisorVitals.Dead, 0, 25);
        var deadLater = At(OverlayVisorVitals.Dead, 0, 26);
        Check(downed0.Busy && downed0.Look.Alpha > 0.95f && downedHalf.Look.Alpha < 0.4f && !dead.Busy && !deadLater.Busy && dead.Look.Vitals == OverlayVisorVitals.Dead,
            "health ring: downed blinks slowly; dead is still (the X)", new { downedHalf = downedHalf.Look.Alpha });
        var revived = At(OverlayVisorVitals.Alive, 0.4f, 30);
        var growing = At(OverlayVisorVitals.Alive, 0.4f, 30.15);
        // every step runs (a lazy Last() over Range would only run the last one)
        var grown = Enumerable.Range(1, 120).Select(i => At(OverlayVisorVitals.Alive, 0.4f, 30.15 + i / 60.0)).ToArray()[^1];
        Check(revived.Look.Fraction == 0 && revived.Busy && growing.Look.Fraction is > 0 and < 0.4f && growing.Look.Glow == 0 &&
              grown.Look.Fraction == 0.4f,
            "health ring: back from dead it grows from empty to the health", new { growing = growing.Look.Fraction });
        // in one run of time: growth, then the glow, frames asked for without a gap until the glow is over (review R4)
        At(OverlayVisorVitals.Dead, 0, 35);
        var run = new List<(double T, OverlayVisorDraw.HealthLook Look, bool Busy)>();
        for (var t = 36.0; t < 39; t += 1 / 60.0) { var (look, busy) = At(OverlayVisorVitals.Alive, 0.4f, t); run.Add((t, look, busy)); }
        var lastBusy = run.FindLastIndex(x => x.Busy);
        var glowAt = run.FindIndex(x => x.Look.Glow > 0);
        Check(run.Take(lastBusy + 1).All(x => x.Busy) && glowAt > 0 && run.Max(x => x.Look.Glow) > 0.9f && run[lastBusy].Look.Fraction == 0.4f &&
              run.Skip(lastBusy + 1).All(x => x.Look is { Glow: 0, Fraction: 0.4f }) && run.Skip(lastBusy + 1).Any(),
            "health ring: from revival to the end of the glow every frame is asked for, then it settles",
            new { glowFrom = run[glowAt].T, busyUntil = run[lastBusy].T });
        var heal = new List<float>();
        for (var t = 40.0; t < 42; t += 1 / 60.0) heal.Add(At(OverlayVisorVitals.Alive, 1, t).Look.Fraction);
        var flashes = Enumerable.Range(0, 60).Select(i => At(OverlayVisorVitals.Alive, 1, 42 + i / 60.0).Look.Flash).ToArray().Max();
        Check(heal[0] < 0.5f && heal.Zip(heal.Skip(1)).All(p => p.Second >= p.First && p.Second - p.First < 0.12f) && heal[^1] == 1 && flashes == 0,
            "health ring: healing grows back smoothly, without a flash", new { first = heal[0], last = heal[^1] });
    }

    /// <summary>Off screen on a WARP device: what is drawn through the opening and closing, and the health ring states.</summary>
    private static void Offscreen()
    {
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        dc.SetDpi(96, 96);
        const int W = 1920, H = 1080;
        var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
        using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
        using var window = OverlayVisorTests.Window(5, W, H);
        var scene = ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!) with
        {
            ShowEvents = false, ShowChat = false, ShowNotice = false, DirectMessage = null,
        };

        int Lit(OverlayVisorScene s, double now)
        {
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, s, W, H, now);
            return OverlayVisorTests.Lit(dc, overlay, W, H);
        }

        var opening = scene with { OpenAt = 10, CloseAt = 12 };
        var (openSeconds, closeSeconds) = OverlayVisorRenderer.Durations;
        int atStart = Lit(opening, 10), midway = Lit(opening, 10 + OverlayVisorRenderer.BracketLock / 2), full = Lit(opening, 10 + openSeconds + 0.15),
            closed = Lit(opening, 12 + closeSeconds + 0.05);
        // midway the full-screen frame is closing in, so more of the screen is lit than once it has faded
        Check(atStart < full / 20 && midway > full / 4 && full > 0 && closed == 0,
            "visor opening and closing drawn: almost nothing at the start, the frame and panels coming in midway, the panels alone when open, nothing once closed",
            new { atStart, midway, full, closed });
        byte[] Picture(params (OverlayVisorScene Scene, double Now)[] frames)
        {
            using var renderer = new OverlayVisorRenderer(dc, dw);
            foreach (var (s, now) in frames) renderer.Render(overlay, System.Numerics.Vector2.Zero, s, W, H, now);
            return OverlayVisorTests.Pixels(dc, overlay);
        }
        var after = Picture((opening, 10.2), (opening, 10 + openSeconds + 0.15));
        var plainLook = Picture((scene, 10 + openSeconds + 0.15));
        Check(after.AsSpan().SequenceEqual(plainLook), "visor opening: once over, exactly the plain picture (pixel for pixel)");

        // a member leaving while the panel opens: the live layer does not keep their old ring (review CX-VISOR-INTRO-R3)
        var empty = opening with { Members = [] };
        var withRing = opening with { Members = [.. scene.Members.Select(m => m with { Vitals = OverlayVisorVitals.Alive, Health = 0.6f })] };
        Check(Picture((withRing, 10.5), (empty, 10.6)).AsSpan().SequenceEqual(Picture((empty, 10.5), (empty, 10.6))),
            "health ring: once the members are gone, the opening shows no ring left over from them");

        // healing across a colour threshold inside one step of the live layer's key ends in the new colour, exactly as if it
        // had been there all along (review R4: 0.499 -> 0.501 and 0.249 -> 0.251 share the quantised share)
        OverlayVisorScene Self(float health) => scene with { Members = [.. scene.Members.Select((m, i) => i == 0 ? m with { Vitals = OverlayVisorVitals.Alive, Health = health } : m)] };
        foreach (var (from, to) in new[] { (0.499f, 0.501f), (0.249f, 0.251f) })
        {
            var healed = Picture([(Self(from), 40), .. Enumerable.Range(1, 120).Select(i => (Self(to), 40 + i / 60.0))]);
            Check(healed.AsSpan().SequenceEqual(Picture((Self(to), 40))), "health ring: healing across a colour threshold ends in the new colour", new { from, to });
        }
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            var self = scene with { Members = [.. scene.Members.Select((m, i) => i == 0 ? m with { Vitals = OverlayVisorVitals.Alive, Health = 1 } : m)] };
            renderer.Render(overlay, System.Numerics.Vector2.Zero, self, W, H, 50);
            var redraws = renderer.Redraws;
            foreach (var (h, t) in new[] { (0.6f, 51.0), (0.2f, 52), (0.9f, 53) })
                renderer.Render(overlay, System.Numerics.Vector2.Zero, self with { Members = [.. self.Members.Select((m, i) => i == 0 ? m with { Health = h } : m)] }, W, H, t);
            Check(renderer.Redraws == redraws && renderer.ScrollRedraws >= 3, "health ring: a health change redraws only the small live layer, not the members panel",
                new { redraws = renderer.Redraws - redraws, renderer.ScrollRedraws });
        }
        using (var renderer = new OverlayVisorRenderer(dc, dw))
        {
            renderer.Render(overlay, System.Numerics.Vector2.Zero, opening, W, H, 10.3);
            var busy = renderer.Animating(10.3);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, opening, W, H, 10 + openSeconds + 0.2);
            Check(busy && !renderer.Animating(10 + openSeconds + 0.2), "visor renderer keeps frames coming through the opening only");
        }

        // the ring: nothing known (a faint track), half, full; downed and dead are a whole ring in red or grey
        OverlayVisorScene With(OverlayVisorVitals vitals, float health) =>
            scene with { Members = [.. scene.Members.Select(m => m with { Vitals = vitals, Health = health })] };
        int unknown = Lit(With(OverlayVisorVitals.Unknown, 0), 30), half = Lit(With(OverlayVisorVitals.Alive, 0.5f), 30),
            whole = Lit(With(OverlayVisorVitals.Alive, 1), 30), downed = Lit(With(OverlayVisorVitals.Downed, 0), 30), dead = Lit(With(OverlayVisorVitals.Dead, 0), 30);
        // no health known (reading off): exactly the panel without any ring (user, 11-10: no ring for someone not reading)
        var noRing = Lit(scene with { Members = [.. scene.Members.Select(m => m with { Vitals = OverlayVisorVitals.Unknown, Health = 0 })] }, 30);
        var unknownPixels = Pixels(With(OverlayVisorVitals.Unknown, 0));
        var aliveZero = Pixels(With(OverlayVisorVitals.Alive, 0));
        Check(unknown == noRing && unknown < half && half < whole && Math.Abs(downed - whole) <= whole / 50 && dead > unknown && !unknownPixels.AsSpan().SequenceEqual(aliveZero),
            "health ring: no health known draws no ring at all; half a ring less than a whole one; downed is a whole ring; dead adds the X",
            new { unknown, half, whole, downed, dead });

        byte[] Pixels(OverlayVisorScene sc)
        {
            using var renderer = new OverlayVisorRenderer(dc, dw);
            renderer.Render(overlay, System.Numerics.Vector2.Zero, sc, W, H, 30);
            return OverlayVisorTests.Pixels(dc, overlay);
        }

        // each group's own text / background / decoration opacity (user, 11-10: "分模块都让面罩用上")
        long Alpha(OverlayVisorScene sc) { long sum = 0; var px = Pixels(sc); for (var i = 3; i < px.Length; i += 4) sum += px[i]; return sum; }
        OverlayVisorScene Team(float text, float back, float deco) => scene with
        {
            ModuleOpacity = new Dictionary<string, OverlayVisorModuleOpacity> { ["team"] = new(text, back, deco) },
        };
        long all = Alpha(Team(1, 1, 1)), noText = Alpha(Team(0, 1, 1)), noBack = Alpha(Team(1, 0, 1)), noDeco = Alpha(Team(1, 1, 0)), none = Alpha(Team(0, 0, 0));
        Check(noText < all && noBack < all && noDeco < all && none < noText && none < noBack && none < noDeco && none * 20 < all,
            "visor module opacity: the members' text, background and decoration opacity each take their part; all at 0 leaves almost nothing",
            new { all, noText, noBack, noDeco, none });
    }

    /// <summary>
    /// The crosshair over the visor (user, 11-10: "给面罩补上准星", "甲 原样叠加"): the visor HUD draws the overlay's own
    /// crosshair in the screen centre after the visor itself.
    /// </summary>
    private static void CrosshairOverTheVisor()
    {
        const int W = 480, H = 320;
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var texture = d3d.CreateTexture2D(new Texture2DDescription
        {
            Width = W, Height = H, MipLevels = 1, ArraySize = 1, Format = Format.B8G8R8A8_UNorm, SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Default, BindFlags = BindFlags.RenderTarget | BindFlags.ShaderResource,
        });
        using var surface = texture.QueryInterface<IDXGISurface>();
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        int Centre(bool crosshair)
        {
            using var window = OverlayVisorTests.Window(3, W, H, tweak: st => st with { ShowCrosshair = crosshair });
            var hud = window.GetType();
            hud.GetField("_renderDpiScaleX", All)!.SetValue(window, 1.0);
            hud.GetField("_renderDpiScaleY", All)!.SetValue(window, 1.0);
            var state = Call(window, "BuildFrameState")!;
            // clear the surface, then the crosshair pass the visor frame runs after the visor
            var props = new BitmapProperties1(new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied), 96, 96, BitmapOptions.Target | BitmapOptions.CannotDraw);
            using (var target = dc.CreateBitmapFromDxgiSurface(surface, props)) { dc.Target = target; dc.BeginDraw(); dc.Clear(new Color4(0, 0, 0, 0)); dc.EndDraw(); dc.Target = null; }
            if ((bool)state.GetType().GetProperty("ShowCrosshair")!.GetValue(state)!) Call(window, "DrawVisorCrosshair", dc, surface, state);
            using var read = dc.CreateBitmapFromDxgiSurface(surface, new BitmapProperties1(new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied), 96, 96, BitmapOptions.Target));
            var px = OverlayVisorTests.Pixels(dc, read);
            var lit = 0;
            for (var y = H / 2 - 40; y < H / 2 + 40; y++)
                for (var x = W / 2 - 40; x < W / 2 + 40; x++)
                    if (px[(y * W + x) * 4 + 3] > 100) lit++;
            return lit;
        }
        int on = Centre(true), off = Centre(false);
        Check(on > 20 && off == 0, "visor crosshair: the visor HUD draws the overlay's crosshair in the screen centre (and nothing when it is off)", new { on, off });
    }

    /// <summary>
    /// The current ship's palette (user, 11-10: "浮层应该保留船厂颜色/根据当前飞船自动切换颜色"): with the switch on, the
    /// palette follows the ship the game log identifies; off, the chosen one stays; nothing known is the default. Until now
    /// only the old main window did this; the native overlay runtime never did.
    /// </summary>
    private static void ShipPalette()
    {
        Check(OverlaySkinCatalog.ThemeForShip("ANVL_Hornet_F7C_Mk2") == OverlayVisualTheme.Anvil &&
              OverlaySkinCatalog.ThemeForShip("DRAK_Cutlass_Black") == OverlayVisualTheme.Drake &&
              OverlaySkinCatalog.ThemeForShip("MISC_Razor") == OverlayVisualTheme.Mirai &&
              OverlaySkinCatalog.ThemeForShip("MISC_Freelancer") == OverlayVisualTheme.Musashi &&
              OverlaySkinCatalog.ThemeForShip(null) == OverlayVisualTheme.Default &&
              OverlaySkinCatalog.ThemeForShip("nothing like a ship") == OverlayVisualTheme.Default,
            "ship palette: a ship's maker picks its palette; an unknown ship is the default");
        var on = OverlayDisplaySettings.Default with { Skin = OverlaySkin.Visor, AutoThemeByShip = true, Theme = OverlayVisualTheme.Rsi };
        var off = on with { AutoThemeByShip = false };
        Check(OverlaySkinCatalog.WithShipTheme(on, "DRAK_Cutlass_Black").Theme == OverlayVisualTheme.Drake &&
              OverlaySkinCatalog.WithShipTheme(on, null).Theme == OverlayVisualTheme.Default &&
              OverlaySkinCatalog.WithShipTheme(off, "DRAK_Cutlass_Black").Theme == OverlayVisualTheme.Rsi,
            "ship palette: on, the palette follows the ship (default when none is known); off, the chosen palette stays");
        StarBridge.HostRuntime.Presence.GameLogSessionSnapshot Session(string state, string? key) => new(new("unknown"), new("unknown"), new(state, key));
        Check(NativeInformationOverlayRuntime.CurrentShip(Session("confirmed", "ANVL_Arrow")) == "ANVL_Arrow" &&
              NativeInformationOverlayRuntime.CurrentShip(Session("possible", "ANVL_Arrow")) == "ANVL_Arrow" &&
              NativeInformationOverlayRuntime.CurrentShip(Session("unknown", "ANVL_Arrow")) is null &&
              NativeInformationOverlayRuntime.CurrentShip(null) is null,
            "ship palette: the current ship is the one the game log identifies (confirmed, likely or possible)");
        // the visor's decoration really changes with the palette; its status colours and text never do (11-12: "颜色应该影响
        // 背景，不应该影响状态色")
        OverlayVisorStyle Style(OverlayVisualTheme theme)
        {
            using var window = OverlayVisorTests.Window(3, 1920, 1080, tweak: st => st with { Theme = theme });
            return ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!).Style;
        }
        OverlayVisorStyle drake = Style(OverlayVisualTheme.Drake), anvil = Style(OverlayVisualTheme.Anvil), plain = Style(OverlayVisualTheme.Default);
        Check(drake.Deco != anvil.Deco && drake.Deco != plain.Deco, "ship palette: the visor's decoration follows the palette",
            new { drake = drake.Deco, anvil = anvil.Deco, plain = plain.Deco });
        Check(new[] { drake, anvil, plain }.All(s => s.Accent == OverlayVisorStyle.StatusAccent && s.Ink == OverlayVisorStyle.StatusInk &&
              s.Ok == plain.Ok && s.Warn == plain.Warn && s.Bad == plain.Bad),
            "ship palette: status colours and text stay fixed whatever the palette", new { drake = drake.Accent, anvil = anvil.Accent });
        // event titles by kind: a loss red, a gain green, a server change violet, a ship change the status cyan
        Check(OverlayCompositionHudWindow.EventTone(OverlayEventNotificationTypes.DeathAndRespawn, negative: true) == OverlayVisorEventTone.Bad &&
              OverlayCompositionHudWindow.EventTone(OverlayEventNotificationTypes.DeathAndRespawn, negative: false) == OverlayVisorEventTone.Good &&
              OverlayCompositionHudWindow.EventTone(OverlayEventNotificationTypes.MemberServer, false) == OverlayVisorEventTone.Server &&
              OverlayCompositionHudWindow.EventTone(OverlayEventNotificationTypes.None, false) == OverlayVisorEventTone.None &&
              plain.Tone(OverlayVisorEventTone.Bad) == plain.Bad && plain.Tone(OverlayVisorEventTone.Ship) == OverlayVisorStyle.StatusAccent &&
              anvil.Tone(OverlayVisorEventTone.Server) == plain.Tone(OverlayVisorEventTone.Server),
            "event titles: coloured by kind, the same under every palette");
    }

    /// <summary>
    /// The overall opacity is retired (user 11-12: "全局里的整体透明度应该去掉，这是之前遗留的废弃项"): the value is still
    /// saved and read (format unchanged), but the overlay is always drawn full, so an old low value never fades it.
    /// </summary>
    /// <summary>11-13 user ("不透明拉满还是有些透明" / "背景可以"): 100% background is a solid plate; 15% is the old look.</summary>
    private static void RealBackgroundOpacity()
    {
        var full = OverlayVisorRenderer.Plate(1);
        var old = OverlayVisorRenderer.Plate(0.15f);
        var none = OverlayVisorRenderer.Plate(0);
        Check(full.Dark == 1 && old.Dark == 0 && MathF.Abs(old.Tint - 0.13f) < 1e-4f && none.Dark == 0 && none.Tint == 0,
            "background: 100% is a solid plate, 15% the faint plate the visor always had, 0% none", new { full, old, none });
        Check(MathF.Abs(OverlayVisorRenderer.TopHaze(0.5f, 0.15f) - 0.5f) < 1e-4f && OverlayVisorRenderer.TopHaze(0.5f, 1) == 1 &&
              OverlayVisorRenderer.TopHaze(0.5f, 0) == 0,
            "the rally haze: its old strength at 15%, solid at 100%");
        // m102b (11-18 user: "保持主题色不脏"): the solid plate is the theme's own dark, so a warm theme stays warm and the
        // default blue stays where it was
        static (float H, float S) Hs(Color4 c)
        {
            var max = MathF.Max(c.R, MathF.Max(c.G, c.B)); var min = MathF.Min(c.R, MathF.Min(c.G, c.B));
            var d = max - min;
            var h = d == 0 ? 0 : max == c.R ? 60 * (((c.G - c.B) / d + 6) % 6) : max == c.G ? 60 * ((c.B - c.R) / d + 2) : 60 * ((c.R - c.G) / d + 4);
            return (h, max == 0 ? 0 : d / max);
        }
        var drake = new Color4(255 / 255f, 178 / 255f, 48 / 255f, 1);
        var blue = OverlayVisorStyle.StatusAccent;
        var warm = OverlayVisorRenderer.PlateColor(drake);
        var cool = OverlayVisorRenderer.PlateColor(blue);
        Check(MathF.Abs(Hs(warm).H - Hs(drake).H) < 1 && MathF.Abs(Hs(warm).S - Hs(drake).S) < 0.01f && warm.A == 1 &&
              MathF.Max(warm.R, MathF.Max(warm.G, warm.B)) < 0.1f,
            "background plate: a warm theme's plate is its own dark (same hue and saturation), not a cool near-black", new { warm });
        Check(MathF.Abs(cool.R - 0.02f) < 0.015f && MathF.Abs(cool.G - 0.035f) < 0.04f && MathF.Abs(cool.B - 0.05f) < 0.045f,
            "background plate: the default blue's plate stays close to the old dark", new { cool });
        Console.WriteLine("PASS visor background opacity is real");
    }

    private static void OverallOpacity()
    {
        var legacy = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { Opacity = 0.85 }).Serialize()).Opacity;
        var chosen = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize()).Opacity;
        // a saved value reads as saved; the old defaults are moved once by the workspace store (HostRuntime tests)
        Check(OverlayDisplaySettings.Default.Opacity == 1 && Math.Abs(legacy - 0.85) < 0.001 && Math.Abs(chosen - 0.6) < 0.001,
            "overall opacity: the default is full; a saved value reads as saved (the store moves old defaults once)", new { legacy, chosen });
        double Frame(double opacity, out float visor)
        {
            using var window = OverlayVisorTests.Window(3, 1920, 1080, tweak: st => st with { Opacity = opacity });
            var state = Call(window, "BuildFrameState")!;
            visor = ((OverlayVisorScene)Call(window, "BuildVisorScene", state)!).Opacity;
            return (double)state.GetType().GetProperty("Opacity")!.GetValue(state)!;
        }
        double half = Frame(0.5, out var visorHalf), full = Frame(1, out var visorFull);
        Check(half == 1 && full == 1 && visorHalf == 1 && visorFull == 1,
            "overall opacity: retired, the overlay is drawn full whatever value is saved", new { half, visorHalf });
    }

    /// <summary>The local player's health reaches only their own row, clamped; downed and dead carry no share.</summary>
    private static void LocalVitals()
    {
        using var window = OverlayVisorTests.Window(4, 1920, 1080, row: i => OverlayVisorTests.Player(i) with { IsSelf = i == 0 });
        OverlayVisorMember[] Members() => [.. ((OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!).Members];
        Check(Members().All(m => m.Vitals == OverlayVisorVitals.Unknown), "local health: unknown on every row until a reader reports it");
        window.SetLocalVitals(OverlayVisorVitals.Alive, 0.6f);
        var rows = Members();
        var self = rows.Where(m => m.Vitals != OverlayVisorVitals.Unknown).ToArray();
        Check(self.Length == 1 && self[0].Name.Contains(OverlayVisorTests.Player(0).Name, StringComparison.Ordinal) && Math.Abs(self[0].Health - 0.6f) < 0.001f,
            "local health: 60% lands on the local player's own row only", new { Rows = string.Join(",", rows.Select(m => $"{m.Name}:{m.Vitals}:{m.Health}")) });
        window.SetLocalVitals(OverlayVisorVitals.Alive, 1.7f);
        var high = Members().Single(m => m.Vitals != OverlayVisorVitals.Unknown).Health;
        window.SetLocalVitals(OverlayVisorVitals.Alive, float.NaN);
        var nan = Members().Single(m => m.Vitals != OverlayVisorVitals.Unknown).Health;
        window.SetLocalVitals(OverlayVisorVitals.Downed, 0.4f);
        var downed = Members().Single(m => m.Vitals != OverlayVisorVitals.Unknown);
        Check(high == 1 && nan == 0 && downed is { Vitals: OverlayVisorVitals.Downed, Health: 0 },
            "local health: kept within 0..1, an unreadable value is 0, downed carries no share", new { high, nan, downed.Vitals });
    }

    /// <summary>
    /// A real overlay HUD in the ordinary appearance, shown and closed the way the app does it, before the visor's own
    /// open and close in the same process (m86: the visor's release must not depend on what ran before it). Closing it
    /// must release it and end its render thread, and leave this thread's dispatcher running.
    /// </summary>
    private static void OtherHudShownAndClosed()
    {
        var window = OverlayVisorTests.Window(5, 480, 320, tweak: s => s with { Skin = OverlaySkin.Default, EnableStartupTransition = true });
        try
        {
            window.Show();
            var wait = Stopwatch.StartNew();
            while (!window.FirstFrameCommitted && wait.ElapsedMilliseconds < 5000) Thread.Sleep(20);
            Check(window.FirstFrameCommitted, "ordinary HUD before the visor: commits its first frame");
        }
        finally { window.Close(); }
        // pump this thread a little, as the app's own dispatcher would
        var frame = new System.Windows.Threading.DispatcherFrame();
        var pump = Stopwatch.StartNew();
        System.Windows.Threading.Dispatcher.CurrentDispatcher.BeginInvoke(new Action(async () =>
        {
            while (pump.ElapsedMilliseconds < 300) await Task.Delay(10);
            frame.Continue = false;
        }));
        System.Windows.Threading.Dispatcher.PushFrame(frame);
        var thread = (Thread?)Field(window, "_thread");
        var finished = thread is not null && thread.Join(10000);
        var main = System.Windows.Threading.Dispatcher.CurrentDispatcher;
        Check((bool)Field(window, "_disposed")! && finished && !main.HasShutdownStarted,
            "ordinary HUD before the visor: released on Close, render thread ended, this thread's dispatcher still running", new { finished });
    }

    /// <summary>
    /// A real visor HUD with the startup transition on (a small click-through window): the opening starts with the first
    /// frame, Close plays the closing before the window goes, and the device is released after it. With motion off in this
    /// session (system animations off), Close is immediate instead.
    /// </summary>
    private static void HudOpensAndClosesWithItsOwnMotion()
    {
        var window = OverlayVisorTests.Window(5, 480, 320, tweak: s => s with { EnableStartupTransition = true },
            row: i => OverlayVisorTests.Player(i) with { IsSelf = i == 0 });
        ID3D11Device? device = null;
        try
        {
            var motion = UiMotion.IsEnabled;
            bool closingAfterClose, disposedAfterClose;
            var sinceClose = new Stopwatch();
            try
            {
                // a cached health reaches the window before Show (CX-VISOR-INTRO-R2): the opening must still run
                window.SetLocalVitals(OverlayVisorVitals.Alive, 0.6f);
                window.Show();
                var wait = Stopwatch.StartNew();
                while (!window.FirstFrameCommitted && wait.ElapsedMilliseconds < 5000) Thread.Sleep(20);
                Check(window.FirstFrameCommitted, "visor HUD with motion: commits its first frame");
                // the first committed frame comes before the HUD's state arrives; the opening starts with the first visor frame
                var visorFrame = Stopwatch.StartNew();
                while (motion && double.IsNegativeInfinity((double)Field(window, "_visorOpenAt")!) && visorFrame.ElapsedMilliseconds < 3000) Thread.Sleep(20);
                var openAt = (double)Field(window, "_visorOpenAt")!;
                Check(motion ? double.IsFinite(openAt) : double.IsNegativeInfinity(openAt) && !(bool)Field(window, "_visorOpenPending")!,
                    "visor HUD: the opening starts with the first visor frame (or not at all with motion off)", new { motion, openAt });
                // the opening, timed from when the window had its frame scheduler, is still running right after the first frame
                Check(!motion || OverlayVisorRenderer.IntroBusy(openAt, double.PositiveInfinity, (double)window.GetType().GetProperty("VisorNow", All)!.GetValue(null)!),
                    "visor HUD: with a health set before Show, the opening is still running once the window is up");
                if (Field(window, "_d3dDevice") is ID3D11Device hud)
                {
                    device = new ID3D11Device(hud.NativePointer);
                    device.AddRef();
                }
                Thread.Sleep((int)(OverlayVisorRenderer.Durations.Open * 1000) + 600); // the opening is over, the frames have stopped
                if (motion && Field(window, "_visorRenderer") is OverlayVisorRenderer renderer)
                {
                    // a loss: its flash runs over several frames, which only come if the frame after the change asks for them.
                    // Idle first (no live redraws for a while), then the loss, then idle again once the flash is over.
                    var scheduler = Field(window, "_frameScheduler")!;
                    var active = scheduler.GetType().GetField("_active", All)!;
                    double Now() => (double)window.GetType().GetProperty("VisorNow", All)!.GetValue(null)!;
                    // idle: the renderer has nothing moving, the frame scheduler has stopped, and no live redraw for 300 ms
                    int Settle()
                    {
                        var wait = Stopwatch.StartNew();
                        var count = renderer.ScrollRedraws;
                        var still = 0;
                        while (wait.ElapsedMilliseconds < 6000)
                        {
                            Thread.Sleep(100);
                            var now = renderer.ScrollRedraws;
                            still = now == count && !renderer.Animating(Now()) && (int)active.GetValue(scheduler)! == 0 ? still + 1 : 0;
                            count = now;
                            if (still >= 3) return now;
                        }
                        return -1;
                    }
                    var idle = Settle();
                    window.SetLocalVitals(OverlayVisorVitals.Alive, 0.3f);
                    // the change has reached the render thread once the live layer was redrawn for it
                    var handled = Stopwatch.StartNew();
                    while (renderer.ScrollRedraws == idle && handled.ElapsedMilliseconds < 3000) Thread.Sleep(10);
                    var afterFlash = Settle();
                    var stillIdle = Settle();
                    var flashFrames = afterFlash - idle;
                    // at least the loss's own frame and one the scheduler brought after it (a stalled render thread may skip the
                    // middle of the flash; the frame-by-frame flash is checked on a controlled clock in RingMotion, review R6)
                    Check(idle >= 0 && flashFrames >= 2 && stillIdle == afterFlash,
                        "visor HUD: from idle, a health loss brings frames after its own, then the frames stop again", new { idle, flashFrames, stillIdle });
                }
            }
            finally
            {
                sinceClose.Start();
                window.Close();
                closingAfterClose = (bool)Field(window, "_visorClosing")!;
                disposedAfterClose = (bool)Field(window, "_disposed")!;
            }
            Check(motion ? closingAfterClose && !disposedAfterClose : disposedAfterClose,
                "visor HUD: Close plays the closing first (motion on) or closes at once (motion off)", new { motion, closingAfterClose, disposedAfterClose });

            // the owner dispatcher runs the timer that disposes after the closing
            var frame = new System.Windows.Threading.DispatcherFrame();
            var disposedMs = -1L;
            System.Windows.Threading.Dispatcher.CurrentDispatcher.BeginInvoke(new Action(async () =>
            {
                while (!(bool)Field(window, "_disposed")! && sinceClose.ElapsedMilliseconds < 4000) await Task.Delay(5);
                if ((bool)Field(window, "_disposed")!) disposedMs = sinceClose.ElapsedMilliseconds;
                frame.Continue = false;
            }));
            System.Windows.Threading.Dispatcher.PushFrame(frame);
            var thread = (Thread?)Field(window, "_thread");
            var finished = thread is not null && thread.Join(10000);
            // the dispose timer starts once the render thread has begun the closing, so Dispose comes no sooner than that
            Check(disposedMs >= 0 && disposedMs >= (motion ? OverlayVisorRenderer.Durations.Close * 1000 : 0) && disposedMs < 3000 && finished,
                "visor HUD: disposed after the closing has played (timed from Close), render thread ended", new { disposedMs, finished });
            device!.AddRef();
            var left = device.Release() - 1;
            Check(left == 0, "visor HUD with motion: no device reference left after the closing", new { left });
        }
        finally
        {
            device?.Dispose();
            if (!(bool)Field(window, "_disposed")!) window.Dispose();
        }
    }
}
