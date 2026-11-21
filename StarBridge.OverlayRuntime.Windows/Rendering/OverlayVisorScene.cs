using Vortice.Mathematics;

namespace StarBridge.Desktop;

/// <summary>
/// A member's state on the visor. Unknown (11-14 user, "甲 按推荐"): the state is not known (the source read went stale,
/// or the room does not know it); drawn like offline with the word 未知, the name not dimmed.
/// </summary>
internal enum OverlayVisorMemberState { InGame, AppOnly, Away, Offline, Unknown }

/// <summary>A member's health as the visor shows it (user, 11-10): not known, alive with a share, downed, dead.</summary>
internal enum OverlayVisorVitals { Unknown, Alive, Downed, Dead }

internal sealed record OverlayVisorMember(string Name, string Ship, string Place, string Status, OverlayVisorMemberState State, bool Pinned, bool SameServer,
    OverlayVisorVitals Vitals = OverlayVisorVitals.Unknown, float Health = 0);

/// <summary>An event line; Reveal runs 0..1 while it enters (driven by the existing event motion).</summary>
/// <param name="Reveal">How far the event has opened (0..1, 1 once settled).</param>
/// <param name="Leave">How far it has gone while leaving (0..1, 0 until it leaves).</param>
/// <param name="LeaveFrom">How far it had opened when it began to leave (an event can leave before it has fully opened).</param>
internal sealed record OverlayVisorEvent(string Title, string Detail, string Time, float Reveal, float Opacity, float Leave = 0, float LeaveFrom = 1,
    OverlayVisorEventTone Tone = OverlayVisorEventTone.None);

/// <summary>
/// What kind of event a line is, for its title colour (user, 11-12: "根据事件不同定不一样的状态色"): arrivals and moves, ship
/// changes, server changes, joining your server, a loss (death, downed), a gain (respawn, revived), a reminder.
/// </summary>
internal enum OverlayVisorEventTone { None, Place, Ship, Server, SameServer, Bad, Good, Reminder }

internal sealed record OverlayVisorChatLine(string Who, string Text, float Opacity);

/// <summary>A group's text, background and decoration opacity (0..1).</summary>
internal readonly record struct OverlayVisorModuleOpacity(float Text, float Background, float Decoration)
{
    public static readonly OverlayVisorModuleOpacity Full = new(1, 1, 1);
}

/// <summary>Colours and look of the visor appearance (colours come from the existing overlay palette).</summary>
internal sealed record OverlayVisorStyle(
    float Tilt, Color4 Ink, Color4 Dim, Color4 Accent, Color4 Ok, Color4 Warn, Color4 Warm, Color4 Bad,
    float Bloom, float BloomThreshold, float Haze, float SizeFactor)
{
    public static Color4 Rgb(byte r, byte g, byte b, float a = 1) => new(r / 255f, g / 255f, b / 255f, a);

    /// <summary>
    /// The camera's viewing distance (视距), in design units of a 1080-high screen: nearer is a stronger perspective
    /// (11-11 user: "浮层外观应该让视距也可调"). 1000, the distance the visor always had, unless set.
    /// </summary>
    public float Distance { get; init; } = OverlayVisorRenderer.ViewingDistance;

    /// <summary>
    /// The decoration colour: the plate's faint tint, the outline, the rules and the events' opening line. It follows the
    /// colour setting (theme, or the ship maker's palette); status colours and text never do (user, 11-12: "颜色应该影响
    /// 背景，不应该影响状态色", "只改装饰类").
    /// </summary>
    public Color4 Deco { get; init; }

    /// <summary>The fixed status cyan (in game, app online, chat names) and text colour: the default palette's.</summary>
    public static readonly Color4 StatusAccent = Rgb(83, 190, 255), StatusInk = Rgb(235, 247, 255);

    /// <summary>The event title colours by kind (user, 11-12: "根据事件不同定不一样的状态色").</summary>
    public static readonly Color4 PlaceTone = Rgb(200, 241, 255), ServerTone = Rgb(185, 162, 255);

    public Color4 Tone(OverlayVisorEventTone tone) => tone switch
    {
        OverlayVisorEventTone.Place => PlaceTone,
        OverlayVisorEventTone.Server => ServerTone,
        OverlayVisorEventTone.SameServer or OverlayVisorEventTone.Good => Ok,
        OverlayVisorEventTone.Bad => Bad,
        OverlayVisorEventTone.Reminder => Warn,
        _ => Accent,
    };

    public static OverlayVisorStyle FromPalette(Color4 accent, Color4 ink, float sizeFactor = 1, float tilt = 15f)
    {
        var dim = new Color4(ink.R * 0.88f, ink.G * 0.9f, ink.B * 0.94f, 0.86f);
        return new(tilt, ink, dim, accent, Rgb(125, 255, 176), Rgb(255, 196, 107), Rgb(255, 242, 224), Rgb(255, 140, 120), 0.75f, 0.5f, 0.42f, sizeFactor)
        {
            Deco = accent,
        };
    }

    /// <summary>
    /// The user's visor settings: size S/M/L, the fold angle (立体程度, 0-60 degrees) and the holiday gold
    /// accent (Christmas line: gold accent on the fleet colours).
    /// </summary>
    public static OverlayVisorStyle FromSettings(Color4 accent, Color4 ink,
        StarBridge.Core.Overlay.OverlayVisorSize size, bool holidayGold, double tilt = StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorTilt,
        double distance = StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorViewingDistance)
    {
        var sizeFactor = size switch
        {
            StarBridge.Core.Overlay.OverlayVisorSize.Small => 0.86f,
            StarBridge.Core.Overlay.OverlayVisorSize.Large => 1.36f,
            _ => 1f,
        };
        // 11-06 user kept only the visor projection ("只保留默认的吧"); its decoration follows the ship-maker palette, its
        // status colours and text stay fixed (11-12). The ink parameter is the palette's text colour, no longer drawn.
        _ = ink;
        return FromPalette(StatusAccent, StatusInk, sizeFactor,
            (float)StarBridge.Core.Overlay.OverlayDisplaySettings.NormalizeVisorTilt(tilt)) with
        {
            Deco = holidayGold ? Rgb(232, 196, 120) : accent,
            Distance = (float)StarBridge.Core.Overlay.OverlayDisplaySettings.NormalizeVisorViewingDistance(distance),
        };
    }

    /// <summary>The visor never goes below 40% opacity (decided with the settings: opacity 40–100%).</summary>
    public const float MinimumOpacity = 0.4f;
}

/// <summary>Everything the visor draws for one frame, already taken from the overlay's own frame state.</summary>
internal sealed record OverlayVisorScene(
    bool ShowTeam,
    string TeamTitle,
    int Online,
    int InGame,
    int SameServer,
    string YouAt,
    IReadOnlyList<OverlayVisorMember> Members,
    string PageLabel,
    bool ShowEvents,
    string EventsTitle,
    IReadOnlyList<OverlayVisorEvent> Events,
    bool ShowChat,
    string ChatTitle,
    IReadOnlyList<OverlayVisorChatLine> Chat,
    bool ShowNotice,
    string NoticeTitle,
    string NoticeBody,
    string NoticeTimer,
    string NoticeHint,
    bool NoticeIsRally,
    string? DirectMessage,
    float TeamCalm,
    float EventsCalm,
    float ChatCalm,
    float NoticeCalm,
    float Opacity,
    OverlayVisorStyle Style)
{
    /// <summary>Where each group sits: a default slot, or where the user placed it.</summary>
    public IReadOnlyDictionary<string, StarBridge.Core.Overlay.OverlayVisorSpot> Spots { get; init; } =
        StarBridge.Core.Overlay.OverlayVisorLayout.DefaultLayout.ToDictionary(kv => kv.Key, kv => StarBridge.Core.Overlay.OverlayVisorSpot.At(kv.Value));
    /// <summary>
    /// The members size (11-07): with a dimension adaptive the members follow their content up to the value; otherwise
    /// they keep the value. Visor design units.
    /// </summary>
    public bool MembersAutoWidth { get; init; } = true;
    /// <summary>
    /// The visor's own open and close animation (user, 11-10: "转场动画应该做专属的"; "头盔上线", closing "反着收回"): when the
    /// opening started and when the closing started, on the renderer's clock (seconds). Not set: shown as usual.
    /// </summary>
    public double OpenAt { get; init; } = double.NegativeInfinity;
    public double CloseAt { get; init; } = double.PositiveInfinity;
    public bool MembersAutoHeight { get; init; }
    /// <summary>
    /// Whether the events and the chat groups have their place on screen: their settings, not whether they show
    /// anything now (build 86, user: "事件出现时会把成员往下挤，这个是不行的"). Null: whether they show now (older callers).
    /// </summary>
    public bool? EventsPlaced { get; init; }
    /// <summary>
    /// Each group's own text, background and decoration opacity (0..1) from its module settings (user, 11-10: "分模块都让
    /// 面罩用上"): the text, the faint plate behind it, and the frame lines and marks. A group not listed is fully shown.
    /// </summary>
    public IReadOnlyDictionary<string, OverlayVisorModuleOpacity> ModuleOpacity { get; init; } = new Dictionary<string, OverlayVisorModuleOpacity>();
    public bool? ChatPlaced { get; init; }
    /// <summary>
    /// "共 N 人" after the members title. The title names the source (11-13 user, B) and scrolls when too long like the
    /// visor's other text ("B过长时使用其他文字同样的滚动"); the count stays whole beside it.
    /// </summary>
    public string TeamCount { get; init; } = "";
    /// <summary>The members title line as one piece: the source, then the count.</summary>
    public string TeamHeading => TeamCount.Length == 0 ? TeamTitle : $"{TeamTitle} · {TeamCount}";
    public float MembersWidth { get; init; } = (float)StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorMembersWidth;
    public float MembersHeight { get; init; } = (float)StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorMembersHeight;
    /// <summary>
    /// The events and chat width (11-07 "2放"): adaptive up to the value, or fixed; and how many lines each shows (the
    /// existing "同时显示通知数" 1-5 and "同时显示消息数" 1-8), which also sets the box they are placed by.
    /// </summary>
    public bool EventsAutoWidth { get; init; } = true;
    public bool ChatAutoWidth { get; init; } = true;
    public float EventsWidth { get; init; } = (float)StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorMembersWidth;
    public float ChatWidth { get; init; } = (float)StarBridge.Core.Overlay.OverlayDisplaySettings.DefaultVisorMembersWidth;
    public int EventsCount { get; init; } = 3;
    public int ChatCount { get; init; } = 4;
    /// <summary>The chat group keeps its faint plate and outline (the "聊天底框" setting, on by default).</summary>
    public bool ChatPlate { get; init; } = true;
    /// <summary>The members' count labels (online, in game, same server) in the overlay's language.</summary>
    public IReadOnlyList<string> CountLabels { get; init; } = ["在线", "游戏中", "同服"];
    /// <summary>
    /// "实时状态未知" in place of the counts when every member's state is unknown (the read went stale), as the classic
    /// overview says (11-14); empty otherwise.
    /// </summary>
    public string RealtimeUnknown { get; init; } = "";
    /// <summary>The rally at the bottom centre instead of the top centre (user, 11-06: two fixed spots).</summary>
    public bool RallyBottom { get; init; }
    /// <summary>Where the DM badge sits: its default spot, or where the user placed it.</summary>
    public StarBridge.Core.Overlay.OverlayVisorSpot Badge { get; init; } =
        StarBridge.Core.Overlay.OverlayVisorSpot.At(StarBridge.Core.Overlay.OverlayVisorPlacement.BadgeSlot);
}
