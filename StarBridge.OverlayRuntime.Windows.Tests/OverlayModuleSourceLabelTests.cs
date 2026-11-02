using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
/// P3 (2026-10-20): every module title names its source, an own source reads
/// amber, an unavailable source is explained in full once (members, then chat,
/// then overview) and in one line elsewhere, and syncing names what is read.
/// Renders use the shipping scene drawing on WARP; all names are synthetic.
/// </summary>
internal static class OverlayModuleSourceLabelTests
{
    private const string Language = "zh"; // Runtime codes: zh, zh-Hant, en.
    private const string OwnerKey = "fixture-owner";
    private const string Hint = "Alt+M › 信息浮层 可换来源";
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private static readonly BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    private static readonly Dictionary<string, string> Names = new() { ["voyager"] = "远航者组织", ["obsidian"] = "黑曜工业" };
    private static readonly OverlaySourceModule[] Visible = Enum.GetValues<OverlaySourceModule>();

    internal static void RunAll()
    {
        LabelsNameEverySource();
        ReasonsNeverBorrowAnotherSource();
        FullExplanationOnce();
        SyncingNamesTheSource();
        RenderPublicAppearances();
        Console.WriteLine("PASS overlay module titles name sources, accent own sources and explain unavailable sources once");
    }

    private static OverlaySourceBinding Org(string code) => new(OverlaySourceMode.Community, code, OwnerKey);

    private static OverlayModulePresentation Project(OverlaySourceBinding choice, IReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding>? own = null,
        bool room = true, string[]? reachable = null, bool roomAbsent = false, bool signedOut = false,
        IReadOnlyCollection<OverlaySourceModule>? visible = null, int messages = 1)
    {
        var key = signedOut ? "anonymous-local" : OwnerKey;
        var orgs = (reachable ?? ["voyager"]).ToDictionary(code => code,
            code => new OverlaySourceLease(OverlaySourceMode.Community, code, key, 1, Now.AddMinutes(5)));
        var roomLease = new OverlaySourceLease(OverlaySourceMode.Room, "mining", key, 1, Now.AddMinutes(5));
        var context = new OverlaySourceResolutionContext(key, 1, Now, signedOut ? OverlaySourceBinding.Automatic : choice,
            room && !signedOut ? roomLease : null, null, signedOut ? new Dictionary<string, OverlaySourceLease>() : orgs);
        InformationOverlaySourceSnapshot? Read(OverlayResolvedSource source) => source.Mode switch
        {
            OverlaySourceMode.Room => new(roomLease, roomLease.ValidUntil, room: new("mining", "采矿小队", "", 6, "",
                [new("Kestrel", "Kestrel_Fixture", true, "InGame", "Orison", "Prospector", "US"),
                 new("Lumen", "Lumen_Fixture", false, "InGame", "Orison", "MOLE", "US"),
                 new("Marlow", "Marlow_Fixture", false, "AppOnline", "", "", "")],
                [.. Enumerable.Range(1, messages).Select(i => new InformationOverlayRoomMessage(i, "Lumen", "Lumen_Fixture", "矿点坐标已发到频道", Now, false))])),
            OverlaySourceMode.Community => new(orgs[source.Id!], Now.AddMinutes(5), community: new(source.Id!, Names[source.Id!],
                [new("Nova_Fixture", "Nova", "Member", "InGame", "Carrack", "New Babbage", "EU", false),
                 new("Orion_Fixture", "Orion", "Member", "InGame", "Cutlass Black", "Lorville", "US", false),
                 // The live (second) frame brings one presence change and a new notice, as in the game.
                 new("Vesper_Fixture", "Vesper", "Member", messages > 1 ? "InGame" : "AppOnline", "", "", "", false)])
            {
                AnnouncementTitle = "公告", AnnouncementText = messages > 1 ? "今晚 20:00 集合，前往采矿点" : "本周例行巡逻",
                Messages = [.. Enumerable.Range(1, messages).Select(i => new InformationOverlayRoomMessage(i, "Orion", "Orion_Fixture", "收到，马上到", Now, false))]
            }),
            _ => null
        };
        var frame = InformationOverlayModuleFrame.Capture(new(OverlaySourceBinding.Follow, modules: own), context, Read,
            () => true, _ => true, activeModules: visible ?? Visible,
            communityName: code => Names.GetValueOrDefault(code), signedOut: signedOut, roomAbsent: roomAbsent);
        return NativeInformationOverlayRuntime.ProjectModules(frame, Language, Now);
    }

    private static Dictionary<OverlaySourceModule, OverlaySourceBinding> Own(OverlaySourceModule module, OverlaySourceBinding binding) =>
        new() { [module] = binding };

    private static void LabelsNameEverySource()
    {
        var p = Project(Org("voyager"), Own(OverlaySourceModule.Members, new(OverlaySourceMode.Room)));
        Check(p.Notice.SourceLabel == "远航者组织" && p.Overview.SourceLabel == "远航者组织" && p.Chat.SourceLabel == "远航者组织" &&
            p.Events.SourceLabel == "远航者组织" && p.Members.SourceLabel == "采矿小队",
            "Every visible module title names its own source: organization name or room title.");
        var labels = OverlayModuleSourceLabels.From(p);
        Check(labels.Own == OverlayModuleFlags.Members && labels.IsOwn(OverlayModuleFlags.Members) && !labels.IsOwn(OverlayModuleFlags.Overview),
            "Only the module with its own source is accented.");
        Check(labels.RowPrefix(OverlayModuleFlags.Events, labels.Events) is null && labels.RowPrefix(OverlayModuleFlags.Members, "x") == "x",
            "Rows repeat only an own source; a shared source is named once by the header.");
        var hidden = Project(Org("voyager"), visible: [OverlaySourceModule.Members]);
        Check(hidden.Overview.SourceLabel is null && hidden.Overview.EmptyMessage is null && hidden.Members.SourceLabel == "远航者组织",
            "A hidden module has neither label nor status.");
        var local = Project(OverlaySourceBinding.Automatic, room: false, reachable: []);
        Check(local.Members.SourceLabel == "本地" && local.Members.Available, "Automatic with nothing remote reads as local.");
    }

    private static void ReasonsNeverBorrowAnotherSource()
    {
        var down = Project(Org("voyager"), Own(OverlaySourceModule.Members, Org("obsidian")));
        Check(down.Members.EmptyMessage?.Headline == "黑曜工业 暂时连不上" && down.Members.SourceLabel == "黑曜工业" && down.Members.OwnSource &&
            !down.Members.Available && down.Members.Scene.Players.Count == 0 && down.Overview.Available,
            "An unreachable own source is explained as itself, keeps its own label and shows no other source's members.");
        Check(!down.Members.EmptyMessage!.Headline.Contains("远航者") && !(down.Members.EmptyMessage.Detail ?? "").Contains("远航者"),
            "Unavailable text never names the source that is still available.");
        var noRoom = Project(new(OverlaySourceMode.Room), room: false, roomAbsent: true);
        Check(noRoom.Members.EmptyMessage is { Headline: "你现在不在房间里", Detail: "加入房间后这里会显示房间成员。" } &&
            noRoom.Chat.EmptyMessage?.Detail == "加入房间后这里会显示房间聊天。" && noRoom.Members.SourceLabel == "当前房间",
            "Confirmed absence reads as not in a room, with a module-specific reason.");
        var lapsed = Project(new(OverlaySourceMode.Room), room: false);
        Check(lapsed.Members.EmptyMessage?.Headline == "当前房间 暂时连不上" && lapsed.Members.EmptyMessage.Detail == "会自动重试，不需要操作。",
            "A lapsed room is unreachable, not absent.");
        var signedOut = Project(OverlaySourceBinding.Automatic, Own(OverlaySourceModule.Members, Org("voyager")), signedOut: true);
        Check(signedOut.Members.EmptyMessage is { Headline: "登录后可显示组织和房间", Detail: "现在只显示你自己的信息。" } &&
            signedOut.Members.SourceLabel == "组织" && signedOut.Overview is { Available: true, SourceLabel: "本地" },
            "Signed out explains remote modules without naming a stale organization; local modules stay local.");
        var unnamed = OverlayModuleSourceCopy.Unavailable(OverlaySourceModule.Overview,
            new(OverlaySourceMode.Community, null, false, "community_unavailable"), InformationOverlayModuleSourceDisplay.None, "en");
        var traditional = OverlayModuleSourceCopy.Unavailable(OverlaySourceModule.Members, new(OverlaySourceMode.Room, null, false, "room_unavailable"),
            new(null, false, false, RoomAbsent: true), "zh-Hant");
        Check(unnamed?.Headline == "This organization can't be reached right now" && traditional?.Headline == "你目前不在房間裡",
            "English and Traditional Chinese carry the same reasons.");
        Check(OverlayModuleSourceCopy.SwitchHint("Alt+M", Language) == Hint &&
            OverlayModuleSourceCopy.SwitchHint(null, Language) == "主程序 › 信息浮层 可换来源",
            "The switch hint names the actual menu hotkey, or the app when the menu hotkey is off.");
    }

    private static void FullExplanationOnce()
    {
        var down = OverlayModuleSourceCopy.ExplainOnce(Project(Org("obsidian")), chatIsPanel: true, Hint);
        Check(down.Members.EmptyMessage is { Expanded: true, Hint: Hint, Headline: "黑曜工业 暂时连不上" } &&
            new[] { down.Chat, down.Overview, down.Notice, down.Events }.All(m => m.EmptyMessage is { Expanded: false, Hint: null, Headline: "黑曜工业 暂时连不上" }),
            "One source failure is explained in full once, in members; every other module carries one line.");
        var noMembers = OverlayModuleSourceCopy.ExplainOnce(Project(Org("obsidian"),
            visible: [OverlaySourceModule.Notice, OverlaySourceModule.Overview, OverlaySourceModule.Chat]), true, Hint);
        Check(noMembers.Chat.EmptyMessage!.Expanded && !noMembers.Overview.EmptyMessage!.Expanded, "Without members, chat explains.");
        var barrage = OverlayModuleSourceCopy.ExplainOnce(Project(Org("obsidian"),
            visible: [OverlaySourceModule.Notice, OverlaySourceModule.Overview, OverlaySourceModule.Chat]), false, Hint);
        Check(!barrage.Chat.EmptyMessage!.Expanded && barrage.Overview.EmptyMessage!.Expanded, "A barrage draws no panel, so overview explains.");
        var small = OverlayModuleSourceCopy.ExplainOnce(Project(Org("obsidian"),
            visible: [OverlaySourceModule.Notice, OverlaySourceModule.Events]), true, Hint);
        Check(!small.Notice.EmptyMessage!.Expanded && !small.Events.EmptyMessage!.Expanded, "Notice and events always stay one line.");
        var two = OverlayModuleSourceCopy.ExplainOnce(Project(Org("obsidian"), Own(OverlaySourceModule.Members, new(OverlaySourceMode.Room)),
            room: false, roomAbsent: true), true, Hint);
        Check(two.Members.EmptyMessage is { Expanded: true, Headline: "你现在不在房间里" } &&
            two.Chat.EmptyMessage is { Expanded: true, Headline: "黑曜工业 暂时连不上" } && !two.Overview.EmptyMessage!.Expanded,
            "Two different problems are each explained once, in the first large module that has them.");
    }

    private static void SyncingNamesTheSource()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        var flags = BindingFlags.NonPublic | BindingFlags.Instance;
        typeof(NativeInformationOverlayRuntime).GetMethod("StartModuleSync", flags)!.Invoke(runtime, [(DateTimeOffset?)Now]);
        var synced = (OverlayModulePresentation)typeof(NativeInformationOverlayRuntime).GetMethod("ApplyModuleSync", flags)!
            .Invoke(runtime, [Project(Org("obsidian")), Language, Now.AddSeconds(1)])!;
        Check(synced.Members.EmptyMessage == new OverlayModuleEmptyState("正在同步 黑曜工业…", OverlayModuleEmptyKind.Syncing) &&
            synced.Notice.EmptyMessage?.Headline == "正在同步 黑曜工业…",
            "During the sync window a module names the source being read instead of a generic syncing text.");
        var explained = OverlayModuleSourceCopy.ExplainOnce(synced, true, Hint);
        Check(!explained.Members.EmptyMessage!.Expanded, "Syncing is never presented as a failure explanation.");
    }

    private static void RenderPublicAppearances()
    {
        var output = Path.Combine(AppContext.BaseDirectory, "p3-source-labels");
        if (Directory.Exists(output)) foreach (var stale in Directory.GetFiles(output, "*.png")) File.Delete(stale);
        Directory.CreateDirectory(output);
        using var syncRuntime = new NativeInformationOverlayRuntime();
        var flags = BindingFlags.NonPublic | BindingFlags.Instance;
        typeof(NativeInformationOverlayRuntime).GetMethod("StartModuleSync", flags)!.Invoke(syncRuntime, [(DateTimeOffset?)Now]);
        var scenarios = new (string Name, Func<int, OverlayModulePresentation> Build)[]
        {
            ("normal", m => Project(Org("voyager"), Own(OverlaySourceModule.Members, new(OverlaySourceMode.Room)), messages: m)),
            ("org-unreachable", m => Project(Org("obsidian"), messages: m)),
            ("not-in-room", m => Project(Org("voyager"), Own(OverlaySourceModule.Members, new(OverlaySourceMode.Room)), room: false, roomAbsent: true, messages: m)),
            ("syncing", m => (OverlayModulePresentation)typeof(NativeInformationOverlayRuntime).GetMethod("ApplyModuleSync", flags)!
                .Invoke(syncRuntime, [Project(Org("obsidian"), messages: m), Language, Now.AddSeconds(1)])!),
            ("signed-out", m => Project(OverlaySourceBinding.Automatic, Own(OverlaySourceModule.Members, Org("voyager")), signedOut: true, messages: m))
        };
        foreach (var skin in new[] { OverlaySkin.Default })
            foreach (var (name, build) in scenarios)
            {
                var file = $"Default-{name}.png";
                var pixels = Render(skin, OverlayModuleSourceCopy.ExplainOnce(build(1), true, Hint),
                    OverlayModuleSourceCopy.ExplainOnce(build(2), true, Hint), Path.Combine(output, file), out var state);
                Check((OverlaySkinRenderKind)Get(state, "RenderKind")! == OverlaySkinCatalog.Get(skin).RenderKind,
                    "Each render uses the intended appearance's own drawing path.");
                if (skin != OverlaySkin.Default) continue;
                var members = (Rect)Get(state, "MembersRect")!;
                var overview = (Rect)Get(state, "SquadsRect")!;
                if (name == "normal")
                    Check(Amber(pixels, members.X, members.Y, members.Width, 40) > 8 && Amber(pixels, overview.X, overview.Y, overview.Width, 40) == 0,
                        "Rendered: the own member source label is amber and the shared overview label is not.");
                if (name == "org-unreachable")
                    Check(Amber(pixels, members.X, members.Y + 44, members.Width, members.Height - 44) > 8 &&
                        Amber(pixels, members.X, members.Y, members.Width, 40) == 0,
                        "Rendered: the reason headline is amber inside the members body; the shared header label is not.");
            }
        Console.WriteLine($"PASS P3 offscreen renders written: {output}");
    }

    private const int Width = 1920, Height = 1080;

    private static byte[] Render(OverlaySkin skin, OverlayModulePresentation first, OverlayModulePresentation live, string path, out object state)
    {
        var profile = OverlaySkinCatalog.Get(skin);
        var settings = OverlaySkinCatalog.ApplyLocks(OverlayDisplaySettings.Default, OverlaySkin.Default) with
        {
            Skin = profile.Id, Theme = profile.DefaultTheme,
            ShowNotice = true, ShowSquads = true, ShowMembers = true, ShowChat = true, ShowEventNotifications = true,
            ChatDisplayMode = OverlayChatDisplayMode.MessageList, ShowCrosshair = false,
            EnableStartupTransition = false, AnimationFrameRate = OverlayAnimationFrameRate.Off
        };
        var layout = OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray();
        var bounds = new Rect(0, 0, Width, Height);
        using var window = new OverlayCompositionHudWindow(new(first.Members.Scene.Players), first.Chat.Chat, layout, settings,
            OverlayRosterSelectionSettings.Default, Language, first.Members.Scene.HasContent, first.Notice.Command, PlayerPresenceKind.InGame, "",
            bounds, OverlayStartupTransitionContext.ForLanguage(Language), first.Members.Scene.Context, 1, first);
        // A second frame delivers one live chat message, as in the game; history is never replayed.
        window.RefreshWithDpi(new(live.Members.Scene.Players), live.Chat.Chat, layout, settings, OverlayRosterSelectionSettings.Default,
            Language, live.Members.Scene.HasContent, live.Notice.Command, PlayerPresenceKind.InGame, "", bounds,
            OverlayStartupTransitionContext.ForLanguage(Language), live.Members.Scene.Context, 1, live);
        // The device-local "event receiver connected" card would cover the events
        // module's own status line; it is unrelated to module sources.
        ((OverlayViewModel)Get(window, "_viewModel")!).EventNotifications.Clear();
        state = Call(window, "BuildFrameState")!;
        var d3d =D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        var dxgi = d3d.QueryInterface<IDXGIDevice>();
        var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>(Vortice.Direct2D1.FactoryType.SingleThreaded);
        var device = factory.CreateDevice(dxgi);
        var context = device.CreateDeviceContext(DeviceContextOptions.None);
        Set(window, "_d3dDevice", d3d); Set(window, "_dxgiDevice", dxgi); Set(window, "_d2dFactory", factory);
        Set(window, "_d2dDevice", device); Set(window, "_d2dDeviceContext", context);
        Call(window, "CreateStrokeStyles");
        Set(window, "_writeFactory", DWrite.DWriteCreateFactory<IDWriteFactory>(Vortice.DirectWrite.FactoryType.Shared));
        Call(window, "CreateTextFormats");
        try
        {
            context.SetDpi(96, 96);
            var format = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
            using var bitmap = context.CreateBitmap(new SizeI(Width, Height), IntPtr.Zero, 0, new BitmapProperties1(format, 96, 96, BitmapOptions.Target));
            context.Target = bitmap;
            var brushes = window.GetType().GetField("_frameBrushes", All)!;
            brushes.SetValue(window, Activator.CreateInstance(brushes.FieldType));
            context.BeginDraw();
            context.Clear(new Color4(6f / 255, 11f / 255, 18f / 255, 1)); // Opaque stand-in for the game scene.
            Call(window, "DrawScene", context, state);
            context.EndDraw().CheckError();
            context.Target = null;
            Call(window, "DisposeFrameBrushes");
            using var read = context.CreateBitmap(new SizeI(Width, Height), IntPtr.Zero, 0,
                new BitmapProperties1(format, 96, 96, BitmapOptions.CpuRead | BitmapOptions.CannotDraw));
            read.CopyFromBitmap(bitmap);
            var mapped = read.Map(MapOptions.Read);
            var pixels = new byte[Width * Height * 4];
            try { for (var y = 0; y < Height; y++) Marshal.Copy(mapped.Bits + y * (int)mapped.Pitch, pixels, y * Width * 4, Width * 4); }
            finally { read.Unmap(); }
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(BitmapSource.Create(Width, Height, 96, 96, PixelFormats.Pbgra32, null, pixels, Width * 4)));
            using (var stream = File.Create(path)) encoder.Save(stream);
            return pixels;
        }
        finally { Call(window, "DisposeOnRenderThread"); }
    }

    // Amber-hued text pixels (BGRA): red well above green, green well above blue.
    private static int Amber(byte[] pixels, double x, double y, double width, double height)
    {
        var count = 0;
        for (var row = (int)Math.Max(0, y); row < Math.Min(Height, y + height); row++)
            for (var column = (int)Math.Max(0, x); column < Math.Min(Width, x + width); column++)
            {
                var i = (row * Width + column) * 4;
                int b = pixels[i], g = pixels[i + 1], r = pixels[i + 2];
                if (r > 150 && r > g + 25 && g > b + 50) count++;
            }
        return count;
    }

    private static object? Call(object target, string name, params object?[] values) => target.GetType().GetMethods(All)
        .Single(method => method.Name == name && method.GetParameters().Length == values.Length).Invoke(target, values);
    private static object? Get(object target, string name) => target.GetType().GetField(name, All)?.GetValue(target) ??
        target.GetType().GetProperty(name, All)!.GetValue(target);
    private static void Set(object target, string name, object? value) => target.GetType().GetField(name, All)!.SetValue(target, value);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
