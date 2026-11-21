using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

/// <summary>
/// What the visor would show, for the client's layout editor (11-12 user: "编辑里还是要用模拟面板，只不过信息都一致",
/// "可以是简化版的面板，只有框和背景那种，其他都按照真实的来"): the editor's draft settings and layout, the live sources read
/// the way the overlay reads them (the module sources, else the room or community), through the visor's own scene. The
/// editor draws its own simplified panels from this text; nothing is drawn here (the off-screen render of 11-11 showed
/// blurred and blinked in the editor, user: "看不清或一闪一闪").
///
/// It touches nothing of the live overlay: no window is shown, the module read is projected without the live sync's
/// bookkeeping, nothing is saved. With no members to show it gives sample members and says so; the events are the ones the
/// live overlay shows right now, else samples filling the box (it is sized by the most at once); chat shows what there
/// is, else samples. Samples never reach the live overlay. Sample names are plainly samples (user: "示例数据就写全用示例名字/模拟名字 不要去真的模拟用户名").
/// </summary>
public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayEditorPreviewRuntime
{
    public async ValueTask<InformationOverlayEditorContent> ReadEditorContentAsync(
        InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        cancellationToken.ThrowIfCancellationRequested();
        var dispatcher = PreviewDispatcher();
        return await dispatcher.InvokeAsync(() =>
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            cancellationToken.ThrowIfCancellationRequested();
            return ReadEditorContentCore(workspace);
        }, DispatcherPriority.Background, cancellationToken).Task.ConfigureAwait(false);
    }

    private InformationOverlayEditorContent ReadEditorContentCore(InformationOverlayRuntimeWorkspace workspace)
    {
        var language = workspace.Language;
        var session = SafeReadSession();
        var presence = ReadLocalDisplayPresence();
        var resolution = OverlaySkinCatalog.ResolveForDrawing(workspace.Settings, SafeReadEntitlements());
        var settings = OverlaySkinCatalog.WithShipTheme(resolution.Settings, CurrentShip(session)) with
        {
            EnableStartupTransition = false,
            AutoFocusGameWindowOnOpen = false,
        };
        var (content, modules) = ReadEditorPreviewContent(workspace with { Session = session }, settings, session, presence);
        var sample = content.Scene.Players.Count == 0;
        var players = sample ? EditorPreviewSamplePlayers(language) : content.Scene.Players;
        using var window = new OverlayCompositionHudWindow(new OverlayAuthorizedRoster(players), content.Chat,
            ToDesktopLayout(workspace.Layout), settings, ReadRosterSettings(), language, hasFleet: content.Scene.HasContent || sample,
            content.Command, presence ?? PlayerPresenceKind.AppOnline, session.Server.Shard ?? string.Empty,
            new System.Windows.Rect(0, 0, 1920, 1080), OverlayStartupTransitionContext.ForLanguage(language), content.Scene.Context, 1.0,
            sample ? null : modules);
        var vitals = Volatile.Read(ref _localVitals);
        window.SetLocalVitals(vitals.Vitals, vitals.Health);
        var scene = window.EditorPreviewScene();
        // the events the live overlay shows right now (review CX-OVERLAY-TIDY-R1: real ones first), else samples filling
        // the box (it holds the most at once); chat shows what there is, else samples
        var events = Math.Clamp(settings.EventNotificationMaxVisibleCount, 1, OverlayDisplaySettings.MaxEventNotificationCount);
        var live = _window?.EditorLiveEvents() ?? [];
        var eventsSample = live.Count == 0;
        var chatSample = scene.Chat.Count == 0;
        var deco = scene.Style.Deco;
        static int Byte(float v) => (int)Math.Round(Math.Clamp(v, 0, 1) * 255);
        return new InformationOverlayEditorContent(
            sample,
            $"#{Byte(deco.R):X2}{Byte(deco.G):X2}{Byte(deco.B):X2}",
            new InformationOverlayEditorMembers(scene.TeamHeading, scene.YouAt, scene.Online, scene.InGame, scene.SameServer,
                scene.PageLabel, scene.Members.Select(m => new InformationOverlayEditorMember(m.Name, m.Ship, m.Place, m.Status,
                    m.State.ToString(), m.SameServer, m.Pinned, m.Vitals.ToString(), m.Health)).ToArray(), scene.CountLabels),
            new InformationOverlayEditorEvents(scene.EventsTitle, eventsSample, (eventsSample ? EditorPreviewSampleEvents(language) : live).Take(events)
                .Select(e => new InformationOverlayEditorEvent(e.Title, e.Detail, e.Time, e.Tone.ToString())).ToArray()),
            new InformationOverlayEditorChat(scene.ChatTitle, chatSample,
                (chatSample ? EditorPreviewSampleChat(language) : scene.Chat)
                    .Select(c => new InformationOverlayEditorChatLine(c.Who, c.Text)).ToArray()));
    }

    /// <summary>
    /// The content the overlay would show for this draft (OpenCore and RefreshWindow's reads), without the live
    /// overlay's bookkeeping: no module sync marks, no validation timer, no failure code, no "last rendered" state.
    /// </summary>
    private ((OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat) Content, OverlayModulePresentation? Modules)
        ReadEditorPreviewContent(InformationOverlayRuntimeWorkspace workspace, OverlayDisplaySettings settings,
            StarBridge.HostRuntime.Presence.GameLogSessionSnapshot session, PlayerPresenceKind? presence)
    {
        if (workspace.UsesModuleSources)
        {
            try
            {
                var local = ReadLocalSource();
                var result = workspace.HasInvalidConfiguration ? null
                    : local is not null ? local.ReadModules(workspace) : _moduleProvider?.Invoke(workspace);
                if (result is { Frame: { } frame, FailureCode: null })
                {
                    var modules = ProjectModules(frame, workspace.Language, DateTimeOffset.UtcNow, session, presence, local?.Read());
                    return ((modules.Members.Scene, modules.Notice.Command, modules.Chat.Chat.ToArray()), modules);
                }
            }
            catch
            {
                // a failed read shows samples, never old data
            }
            return ((new OverlaySceneSnapshot([], false, OverlaySceneContext.Local(OverlayScenePreference.Auto)),
                BuildCommandState(workspace.Language) with { NoticeTitle = "", NoticeText = "" }, []), null);
        }
        var room = SafeReadRoom();
        var sourceMode = SafeReadSourceMode();
        var preference = SourcePreference(sourceMode, settings.ScenePreference);
        var community = sourceMode == "community" || preference == OverlayScenePreference.Auto && room is null ? SafeReadCommunity() : null;
        var content = ReadLocalSource() is { } localFrame
            ? ProjectLocalOwned(localFrame.Read(), workspace.Language)
            : ProjectSource(room, community, preference, workspace.Language, sourceMode == "community", session, presence);
        return (content, null);
    }

    private static bool English(string language) => language.StartsWith("en", StringComparison.OrdinalIgnoreCase);
    private static bool Traditional(string language) =>
        language.Contains("TW", StringComparison.OrdinalIgnoreCase) || language.Contains("Hant", StringComparison.OrdinalIgnoreCase);

    /// <summary>"示例队员 01" (or its Traditional / English form): a name that is plainly a sample.</summary>
    private static string SampleName(string language, int number) =>
        (English(language) ? "Sample member " : Traditional(language) ? "範例隊員 " : "示例队员 ") + number.ToString("00");

    /// <summary>Members to show when the sources have none (not signed in, no fleet); the editor says they are samples.</summary>
    internal static IReadOnlyList<PlayerRow> EditorPreviewSamplePlayers(string language)
    {
        var en = English(language);
        var tw = Traditional(language);
        (string Ship, string Place, string Live)[] rows =
        [
            (en ? "Cutlass Black" : tw ? "黑彎刀" : "黑弯刀", en ? "Orison" : tw ? "奧里森" : "奥里森", "InGame"),
            ("Hornet Mk II", en ? "Orison" : tw ? "奧里森" : "奥里森", "InGame"),
            (en ? "Cutlass Black" : tw ? "黑彎刀" : "黑弯刀", en ? "Lorville" : tw ? "羅威爾" : "罗威尔", "InGame"),
            ("Constellation", en ? "Lorville" : tw ? "羅威爾" : "罗威尔", "AppOnline"),
            ("Hornet Mk II", en ? "Orison" : tw ? "奧里森" : "奥里森", "InGame"),
            (en ? "Cutlass Black" : tw ? "黑彎刀" : "黑弯刀", en ? "New Babbage" : tw ? "新巴貝奇" : "新巴贝奇", "InGame"),
        ];
        return rows.Select((r, i) =>
        {
            var name = SampleName(language, i + 1);
            return new PlayerRow(name, "Online", r.Ship, r.Ship, r.Place, Callsign: name, RawLocation: r.Place,
                LiveStatus: r.Live, AccountId: $"sample-{i + 1}", SharedOnlineStatus: "Online", SharedLiveStatus: r.Live,
                SharedShip: r.Ship, SharedLocation: r.Place);
        }).ToArray();
    }

    /// <summary>The sample events, one of each common kind, each with its kind's title colour (11-12).</summary>
    internal static IReadOnlyList<OverlayVisorEvent> EditorPreviewSampleEvents(string language)
    {
        var en = English(language);
        var tw = Traditional(language);
        string N(int i) => SampleName(language, i);
        return
        [
            new(en ? "Arrived" : tw ? "到達" : "到达", en ? $"{N(2)} arrived at Orison" : tw ? $"{N(2)} 到達奧里森" : $"{N(2)} 到达奥里森",
                "20:41", 1, 1, Tone: OverlayVisorEventTone.Place),
            new(en ? "Ship" : tw ? "換船" : "换船", en ? $"{N(3)} switched to Cutlass Black" : tw ? $"{N(3)} 切換飛船：黑彎刀" : $"{N(3)} 切换飞船：黑弯刀",
                "20:39", 1, 1, Tone: OverlayVisorEventTone.Ship),
            new(en ? "Server" : tw ? "換服" : "换服", en ? $"{N(4)} moved to EU #009" : tw ? $"{N(4)} 換到 歐服 #009" : $"{N(4)} 换到 欧服 #009",
                "20:37", 1, 1, Tone: OverlayVisorEventTone.Server),
            new(en ? "Location" : "位置", en ? $"{N(5)} heading to New Babbage" : tw ? $"{N(5)} 前往新巴貝奇" : $"{N(5)} 前往新巴贝奇",
                "20:35", 1, 1, Tone: OverlayVisorEventTone.Place),
            new(en ? "Same server" : "同服", en ? $"{N(1)} is on your server" : $"{N(1)} 和你同服",
                "20:33", 1, 1, Tone: OverlayVisorEventTone.SameServer),
        ];
    }

    internal static IReadOnlyList<OverlayVisorChatLine> EditorPreviewSampleChat(string language)
    {
        var en = English(language);
        var tw = Traditional(language);
        return
        [
            new(SampleName(language, 1), en ? "Ready, heading to the meeting point." : tw ? "準備完成，正在前往集合點。" : "准备完成，正在前往集合点。", 1),
            new(SampleName(language, 2), en ? "Copy, five minutes out." : tw ? "收到，五分鐘到。" : "收到，五分钟到。", 1),
        ];
    }
}
