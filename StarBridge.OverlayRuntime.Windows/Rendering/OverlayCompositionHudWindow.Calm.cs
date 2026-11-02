using System.Runtime.InteropServices;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

/// <summary>
/// Calm display in the HUD. Everything here runs on the render thread. Content
/// changes arrive with each published frame; between them nothing runs except one
/// timer for the next fade and, only while a peek key is bound and the HUD is
/// shown, a 50 ms key poll. Opacity enters drawing through the per-module reveal.
/// </summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private static readonly TimeSpan CalmPeekPollInterval = TimeSpan.FromMilliseconds(50);
    private const int VkShift = 0x10;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;
    private const int VkLeftWindows = 0x5B;
    private const int VkRightWindows = 0x5C;

    private readonly OverlayCalmModulesTracker _calm = new();
    private OverlayCalmContent _calmContent = OverlayCalmContent.Unknown;
    private string _calmPeekHotkey = "";
    private OverlayHotkeyChord? _calmPeekChord;
    private DispatcherTimer? _calmWakeTimer;
    private DispatcherTimer? _calmPeekTimer;

    /// <summary>A newly published frame: settings resolved on the owner thread travel with it.</summary>
    private void ObserveCalm(
        OverlayCompositionFrameState? previous,
        OverlayCompositionFrameState next,
        OverlayCalmDisplayLevels levels,
        string peekHotkey)
    {
        var now = DateTimeOffset.UtcNow;
        _calm.Configure(levels, now);
        var content = CalmContentOf(next);
        var baseline = _calmContent;
        // A member page flip shows other rows; that is rotation, not a change.
        if (previous is not null && previous.MemberPaging.FlipSequence != next.MemberPaging.FlipSequence)
        {
            baseline = baseline with { Members = null, MembersRelevant = null };
        }

        _calm.Observe(baseline, content, now);
        _calmContent = content;
        _calmPeekHotkey = peekHotkey;
        UpdateCalmPeek(now);
        ScheduleCalmWake(now);
    }

    /// <summary>The HUD was shown or hidden.</summary>
    private void ObserveCalmVisibility(bool visible)
    {
        var now = DateTimeOffset.UtcNow;
        if (visible) _calm.Wake(now);
        UpdateCalmPeek(now);
        ScheduleCalmWake(now);
    }

    /// <summary>Calm display scales a module's reveal so its drawn opacity becomes the calm level.</summary>
    private double CalmFactor(WpfRect rect)
    {
        if (_state is not { } state || !_calm.Levels.Enabled) return 1;
        OverlayCalmModule? module =
            rect == state.SquadsRect ? OverlayCalmModule.Squads :
            rect == state.MembersRect ? OverlayCalmModule.Members :
            rect == state.ChatRect && state.ChatDisplayMode == OverlayChatDisplayMode.MessageList ? OverlayCalmModule.Chat :
            null;
        if (module is null) return 1;
        var animate = state.AnimationFrameRate != OverlayAnimationFrameRate.Off;
        return _calm.Level(module.Value, _frameNowUtc, animate) is { } level
            ? level / Math.Max(state.Opacity, 0.01)
            : 1;
    }

    /// <summary>
    /// Decorations that join adjacent modules follow the brightest calm module, so a
    /// connector never glows between resting panels and never fades beside a lit one.
    /// </summary>
    private OverlayCompositionFrameState CalmJoined(OverlayCompositionFrameState state)
    {
        if (!_calm.Levels.Enabled) return state;
        var factor = 0.0;
        if (state.ShowSquads) factor = Math.Max(factor, CalmFactor(state.SquadsRect));
        if (state.ShowMembers) factor = Math.Max(factor, CalmFactor(state.MembersRect));
        if (state.ShowChat && state.ChatDisplayMode == OverlayChatDisplayMode.MessageList)
        {
            factor = Math.Max(factor, CalmFactor(state.ChatRect));
        }

        return factor > 0 && factor != 1 ? state with { Opacity = state.Opacity * factor } : state;
    }

    private bool IsCalmMotionActive() =>
        _state is { AnimationFrameRate: not OverlayAnimationFrameRate.Off } &&
        _calm.IsAnimating(DateTimeOffset.UtcNow);

    private void ScheduleCalmWake(DateTimeOffset now)
    {
        var next = _isVisible ? _calm.NextTransitionAt(now) : null;
        if (next is null || _renderDispatcher is not { } dispatcher)
        {
            _calmWakeTimer?.Stop();
            return;
        }

        _calmWakeTimer ??= new DispatcherTimer(DispatcherPriority.Render, dispatcher);
        _calmWakeTimer.Tick -= OnCalmWake;
        _calmWakeTimer.Tick += OnCalmWake;
        _calmWakeTimer.Stop();
        _calmWakeTimer.Interval = TimeSpan.FromTicks(Math.Max(TimeSpan.TicksPerMillisecond, (next.Value - now).Ticks));
        _calmWakeTimer.Start();
    }

    private void OnCalmWake(object? sender, EventArgs e)
    {
        _calmWakeTimer?.Stop();
        if (_disposed || _renderThreadDisposed) return;
        var now = DateTimeOffset.UtcNow;
        RedrawCalm();
        ScheduleCalmWake(now);
    }

    /// <summary>Animated changes run on the frame scheduler; with animation off one frame is enough.</summary>
    private void RedrawCalm()
    {
        if (IsCalmMotionActive())
        {
            var requested = ResolveMotionFramesPerSecond(_settings.AnimationFrameRate);
            _frameScheduler?.Start(_adaptiveFramePacer.Resolve(requested, Environment.TickCount64));
            return;
        }

        DrawFrame();
    }

    private void UpdateCalmPeek(DateTimeOffset now)
    {
        _calmPeekChord = _calm.Levels.Enabled && _isVisible &&
                         OverlayHotkeyBindingPolicy.TryParse(_calmPeekHotkey, out var chord)
            ? chord
            : null;
        if (_calmPeekChord is null || _renderDispatcher is not { } dispatcher)
        {
            _calmPeekTimer?.Stop();
            _calm.SetPeek(false, now);
            return;
        }

        if (_calmPeekTimer is null)
        {
            _calmPeekTimer = new DispatcherTimer(DispatcherPriority.Render, dispatcher) { Interval = CalmPeekPollInterval };
            _calmPeekTimer.Tick += OnCalmPeekPoll;
        }

        if (!_calmPeekTimer.IsEnabled) _calmPeekTimer.Start();
    }

    private void OnCalmPeekPoll(object? sender, EventArgs e)
    {
        if (_disposed || _renderThreadDisposed || _calmPeekChord is not { } chord) return;
        var down = IsCalmKeyDown((int)chord.VirtualKey) && CalmModifiersDown(chord.Modifiers);
        var now = DateTimeOffset.UtcNow;
        var before = _calm.Level(OverlayCalmModule.Squads, now);
        _calm.SetPeek(down, now);
        if (before == _calm.Level(OverlayCalmModule.Squads, now + OverlayCalmModulesTracker.PeekBlend)) return;
        RedrawCalm();
        ScheduleCalmWake(now);
    }

    private static bool CalmModifiersDown(uint modifiers) =>
        ((modifiers & GameCompatibleHotkeyModifiers.Control) == 0 || IsCalmKeyDown(VkControl)) &&
        ((modifiers & GameCompatibleHotkeyModifiers.Alt) == 0 || IsCalmKeyDown(VkMenu)) &&
        ((modifiers & GameCompatibleHotkeyModifiers.Shift) == 0 || IsCalmKeyDown(VkShift)) &&
        ((modifiers & GameCompatibleHotkeyModifiers.Windows) == 0 ||
         IsCalmKeyDown(VkLeftWindows) || IsCalmKeyDown(VkRightWindows));

    private static bool IsCalmKeyDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    private void StopCalm()
    {
        _calmWakeTimer?.Stop();
        _calmPeekTimer?.Stop();
    }

    private static OverlayCalmContent CalmContentOf(OverlayCompositionFrameState state)
    {
        int? squads = null, squadsRelevant = null, members = null, membersRelevant = null;
        string? chat = null;
        if (state.ShowSquads && !string.IsNullOrEmpty(state.SquadSummary))
        {
            var all = new HashCode();
            all.Add(state.SquadPrimaryName);
            all.Add(state.SquadSummary);
            all.Add(state.SquadServerSummary);
            all.Add(state.SquadFocusLine);
            foreach (var location in state.OverviewTopLocations) all.Add(location);
            squads = all.ToHashCode();
            // "With you on this server: N" is the part that concerns the viewer.
            squadsRelevant = HashCode.Combine(state.SquadFocusLine);
        }

        if (state.ShowMembers && state.MemberRows.Count > 0)
        {
            var all = new HashCode();
            var relevant = new HashCode();
            foreach (var row in state.MemberRows)
            {
                var value = HashCode.Combine(row.Key ?? row.DisplayName, row.Status, row.Ship, row.Location, row.Group);
                all.Add(value);
                if (row.Group is OverlayRosterGroup.SameServer or OverlayRosterGroup.Pinned) relevant.Add(value);
            }

            members = all.ToHashCode();
            membersRelevant = relevant.ToHashCode();
        }

        if (state.ShowChat && state.ChatDisplayMode == OverlayChatDisplayMode.MessageList && state.ChatRows.Count > 0)
        {
            var last = state.ChatRows[^1];
            chat = $"{last.Title}\u001f{last.Detail}\u001f{last.Timestamp}";
        }

        return new OverlayCalmContent(squads, squadsRelevant, members, membersRelevant, chat);
    }

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);
}
