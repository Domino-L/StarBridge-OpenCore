using System.Windows;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

/// <summary>Temporary presentation intent, not a saved workspace or source grant.
/// Layout is copied at the seam because the normal layout DTO is mutable.</summary>
internal sealed class OverlayAppearancePreviewFrame
{
    private readonly InformationOverlayLayoutItem[] _layout;
    internal long Revision { get; }
    internal OverlayDisplaySettings Settings { get; }
    internal OverlayAnimationFrameRate BarrageFrameRate { get; }
    internal string Language { get; }

    internal OverlayAppearancePreviewFrame(long revision, OverlaySkin skin,
        OverlayDisplaySettings settings, IEnumerable<InformationOverlayLayoutItem> layout,
        OverlayAppearanceOptions options, string language, bool reduceMotion = false)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(layout);
        ArgumentNullException.ThrowIfNull(options);
        if (revision < 0 || !Enum.IsDefined(skin)) throw new ArgumentOutOfRangeException(nameof(revision));
        if (language is not ("zh" or "zh-CN" or "zh-Hant" or "en" or "en-US"))
            throw new ArgumentException("Unsupported preview language.", nameof(language));
        var profile = OverlaySkinCatalog.Listed.SingleOrDefault(p => p.Id == skin && p.IsPreviewAvailable)
            ?? throw new ArgumentException("Appearance is not previewable.", nameof(skin));
        var items = layout.Take(9).ToArray();
        if (items.Length is < 1 or > 8 || items.Any(item => item is null) ||
            items.Select(item => item.Key).Distinct(StringComparer.Ordinal).Count() != items.Length)
            throw new ArgumentException("Invalid preview layout.", nameof(layout));
        foreach (var item in items)
        {
            if (item.Key is not ("Notice" or "Squads" or "Members" or "Chat" or "Crosshair") ||
                !Enum.IsDefined(item.HorizontalAnchor) || !Enum.IsDefined(item.VerticalAnchor) ||
                !Range(item.X, 0, .95) || !Range(item.Y, 0, .95) ||
                !Range(item.Width, .05, 1) || !Range(item.Height, .05, 1) ||
                !Range(item.TextOpacity, 0, 1) || !Range(item.BackgroundOpacity, 0, 1) ||
                !Range(item.DecorationOpacity, 0, 1))
                throw new ArgumentException("Invalid preview module.", nameof(layout));
        }
        _layout = items.Select(Copy).ToArray();
        Revision = revision;
        Language = language;
        // Preserve reading cadence before reduced presentation turns ornaments Off.
        BarrageFrameRate = settings.AnimationFrameRate == OverlayAnimationFrameRate.Off
            ? OverlayAnimationFrameRate.Fps60 : settings.AnimationFrameRate;
        // Preview follows the chosen installed renderer, not the entitlement
        // resolution for normal Open. This never changes IsReleased or CanUse.
        Settings = settings with
        {
            Skin = skin, RequestedSkin = skin, AppearanceOptions = options,
            Theme = profile.LocksTheme ? profile.DefaultTheme : settings.Theme,
            AutoThemeByShip = profile.LocksTheme ? false : settings.AutoThemeByShip,
            StartupTransitionFollowOverlayTheme = true,
            StartupTransitionStyle = profile.StartupTransition,
            EnableStartupTransition = false, AutoFocusGameWindowOnOpen = false,
            AnimationFrameRate = reduceMotion ? OverlayAnimationFrameRate.Off : settings.AnimationFrameRate
        };
    }

    internal IReadOnlyList<InformationOverlayLayoutItem> CopyLayout() => _layout.Select(Copy).ToArray();
    internal OverlayLayoutItem[] DesktopLayout() => _layout.Select(item => new OverlayLayoutItem(
        item.Key, item.Key, item.X, item.Y, item.Width, item.Height, Brushes.Transparent,
        item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked, item.TextOpacity,
        item.BackgroundOpacity, item.DecorationOpacity)).ToArray();
    private static bool Range(double value, double min, double max) => double.IsFinite(value) && value >= min && value <= max;
    private static InformationOverlayLayoutItem Copy(InformationOverlayLayoutItem item) => new(
        item.Key, item.X, item.Y, item.Width, item.Height, item.HorizontalAnchor, item.VerticalAnchor,
        item.IsLocked, item.TextOpacity, item.BackgroundOpacity, item.DecorationOpacity);
}

internal enum OverlayAppearancePreviewExample { Notice, Event, Barrage }

/// <summary>One real D2D HUD throughout a preview session. No WPF carrier, account
/// provider, normal-Open side effects, usage lease, persistence, or pet commands.
/// The owner resolves the SAME viewport as normal Open and calls this on its STA.
/// Host/session restoration and inspector occlusion belong to the owning mode.</summary>
internal sealed partial class OverlayAppearancePreviewSurface : IDisposable
{
    private const string Channel = "appearance-center-example";
    private readonly Dispatcher _owner = Dispatcher.CurrentDispatcher;
    private readonly OverlayCompositionHudWindow _hud;
    private readonly List<OverlayChatMessage> _messages = [];
    private readonly OverlaySceneContext _scene;
    private OverlayAppearancePreviewFrame _frame;
    private Rect _bounds;
    private double _dpi;
    private long _sequence;
    private bool _disposed;

    internal OverlayCompositionHudWindow Hud => _hud;
    internal long AppliedRevision => _frame.Revision;
    internal bool Released => _disposed;

    internal OverlayAppearancePreviewSurface(OverlayAppearancePreviewFrame frame, Rect bounds, double dpi, bool protectControlsOnCreate = false)
    {
        ValidateViewport(bounds, dpi);
        _frame = frame ?? throw new ArgumentNullException(nameof(frame));
        _bounds = bounds;
        _dpi = dpi;
        _scene = OverlaySceneContext.Local(frame.Settings.ScenePreference) with
        { ChatChannelId = Channel, ChatChannelTitle = "Preview examples" };
        _hud = new OverlayCompositionHudWindow(new OverlayAuthorizedRoster([]), [], frame.DesktopLayout(),
            frame.Settings, new OverlayRosterSelectionSettings(), frame.Language, false, EmptyCommand(),
            PlayerPresenceKind.AppOnline, "", bounds, OverlayStartupTransitionContext.ForLanguage(frame.Language), _scene, dpi);
        // Normal constructors announce a receiver/Fleet link. This temporary
        // source has neither: clear those initial rows before its first Show,
        // then install explicit empty local notice/chat modules. No public
        // constructor or normal source behavior is changed.
        _hud.PrepareQuietPreviewExamples();
        Refresh(frame, bounds, dpi);
        if (protectControlsOnCreate) _hud.PreparePreviewControlProtection();
        try { _hud.Show(); } catch { _hud.Dispose(); throw; }
    }

    /// <summary>Returns false for delayed/duplicate revisions. No replace-HWND
    /// cycle, startup replay or cat reset for every setting change.</summary>
    internal bool Update(OverlayAppearancePreviewFrame frame, Rect bounds, double dpi)
    {
        VerifyAlive();
        ArgumentNullException.ThrowIfNull(frame);
        if (frame.Revision <= _frame.Revision) return false;
        ValidateViewport(bounds, dpi);
        if (_exampleSequence is not null) { StopExampleSequence(); InvalidatePreviewEvents(); }
        StopPreviewTransition();
        Refresh(frame, bounds, dpi);
        _frame = frame;
        _bounds = bounds;
        _dpi = dpi;
        return true;
    }

    /// <summary>Normal finite example arrivals only. Not arbitrary text, source
    /// content or an action for the pet. Quiet preview never invokes this.</summary>
    internal void PublishExample(OverlayAppearancePreviewExample example)
    {
        VerifyAlive();
        if (!Enum.IsDefined(example)) throw new ArgumentOutOfRangeException(nameof(example));
        var zh = _frame.Language.StartsWith("zh", StringComparison.Ordinal);
        switch (example)
        {
            case OverlayAppearancePreviewExample.Notice:
                _hud.QueueCommunicationEvent(zh ? "公告 · 预览示例" : "Notice · preview example",
                    zh ? "这是一条示例公告，不是实际舰队消息。" : "Example announcement, not a real fleet message.");
                break;
            case OverlayAppearancePreviewExample.Event:
                var sequence = ++_sequence;
                _hud.QueueGameEventNotification(OverlayEventNotificationTypes.MemberPresence,
                    zh ? $"事件 {sequence} · 预览示例" : $"Event {sequence} · preview example",
                    zh ? "示例成员状态变化；保留正常事件顺序。" : "Example presence change; normal event ordering.", false, sequence % 2 != 0);
                break;
            case OverlayAppearancePreviewExample.Barrage:
                if (_messages.Count == 8) _messages.RemoveAt(0);
                _messages.Add(new(++_sequence, Channel, "Preview peer", "示例成员",
                    zh ? "这是一条预览示例弹幕。" : "This is an example preview message.",
                    DateTimeOffset.UtcNow, false, false, "#D5C59F"));
                Refresh(_frame, _bounds, _dpi);
                break;
        }
    }

    private void Refresh(OverlayAppearancePreviewFrame frame, Rect bounds, double dpi)
    {
        _hud.UpdatePreviewBarrageFrameRate(frame.BarrageFrameRate);
        _hud.RefreshWithDpi(new OverlayAuthorizedRoster([]), _messages.ToArray(), frame.DesktopLayout(), frame.Settings,
            new OverlayRosterSelectionSettings(), frame.Language, false, EmptyCommand(), PlayerPresenceKind.AppOnline,
            "", bounds, OverlayStartupTransitionContext.ForLanguage(frame.Language),
            _scene with { Preference = frame.Settings.ScenePreference }, dpi, PreviewModules(frame));
    }

    private OverlayModulePresentation PreviewModules(OverlayAppearancePreviewFrame frame)
    {
        var local = _scene with { Preference = frame.Settings.ScenePreference };
        var ordinary = new OverlayModuleScene(new([], false, local), EmptyCommand(), [], null, true, Channel);
        // Community accepts an explicitly empty announcement without inventing
        // a fleet-link message; ordinary module headings keep the local scene.
        var notice = ordinary with { Scene = new([], false, local with { Kind = OverlaySceneKind.Community }) };
        var chat = ordinary with { Chat = _messages.ToArray(), ChatSourceKeys = [Channel] };
        return new(notice, ordinary, ordinary, chat, ordinary, Channel);
    }

    private static OverlayCommandState EmptyCommand() => new(null, null, null, null, null, null);
    private static void ValidateViewport(Rect bounds, double dpi)
    {
        if (bounds.IsEmpty || !double.IsFinite(bounds.X) || !double.IsFinite(bounds.Y) ||
            !double.IsFinite(bounds.Width) || !double.IsFinite(bounds.Height) ||
            bounds.Width is < 1 or > 16384 || bounds.Height is < 1 or > 16384 ||
            !double.IsFinite(dpi) || dpi is < .5 or > 8 ||
            bounds.Width * dpi > 16384 || bounds.Height * dpi > 16384)
            throw new ArgumentOutOfRangeException(nameof(bounds));
    }
    private void VerifyAlive()
    {
        _owner.VerifyAccess();
        ObjectDisposedException.ThrowIf(_disposed, this);
    }
    public void Dispose()
    {
        _owner.VerifyAccess();
        if (_disposed) return;
        _disposed = true;
        StopExampleSequence();
        StopPreviewTransition();
        InvalidatePreviewEvents();
        _messages.Clear();
        _hud.Dispose();
    }
}
