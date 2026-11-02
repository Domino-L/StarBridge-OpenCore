using StarBridge.Core.Overlay;

namespace StarBridge.Desktop;

/// <summary>The persistent modules that may rest at a lower opacity.</summary>
internal enum OverlayCalmModule
{
    Squads,
    Members,
    Chat
}

/// <summary>
/// What the modules show, reduced to what calm display compares between frames.
/// Signatures cover everything visible; relevant signatures only what concerns
/// the viewer. Null means unknown (data gap), which is never a change (IO-035).
/// </summary>
internal sealed record OverlayCalmContent(
    int? Squads,
    int? SquadsRelevant,
    int? Members,
    int? MembersRelevant,
    string? LastChatKey)
{
    public static OverlayCalmContent Unknown { get; } = new(null, null, null, null, null);

    /// <summary>Modules whose content changed, each with whether the change concerns the viewer.</summary>
    public static IReadOnlyList<(OverlayCalmModule Module, bool Relevant)> Changes(
        OverlayCalmContent previous,
        OverlayCalmContent next)
    {
        var changes = new List<(OverlayCalmModule, bool)>(3);
        if (Changed(previous.Squads, next.Squads))
        {
            changes.Add((OverlayCalmModule.Squads, Changed(previous.SquadsRelevant, next.SquadsRelevant)));
        }

        if (Changed(previous.Members, next.Members))
        {
            changes.Add((OverlayCalmModule.Members, Changed(previous.MembersRelevant, next.MembersRelevant)));
        }

        // Every new chat message concerns the viewer: it is addressed to the room or org.
        if (next.LastChatKey is not null && previous.LastChatKey is not null &&
            !string.Equals(previous.LastChatKey, next.LastChatKey, StringComparison.Ordinal))
        {
            changes.Add((OverlayCalmModule.Chat, true));
        }

        return changes;
    }

    private static bool Changed(int? previous, int? next) =>
        previous is not null && next is not null && previous != next;
}

/// <summary>
/// Calm display: each persistent module rests at the idle opacity once its content
/// has not changed for a while, and comes back to the lit opacity for a change that
/// matters. Peek shows everything lit while held. Pure and clocked by the caller:
/// nothing runs while idle, the renderer only asks <see cref="NextTransitionAt"/>
/// when the next frame is needed.
/// </summary>
internal sealed class OverlayCalmModulesTracker
{
    internal static readonly TimeSpan Rise = TimeSpan.FromMilliseconds(160);
    internal static readonly TimeSpan Fade = TimeSpan.FromMilliseconds(900);
    internal static readonly TimeSpan PeekBlend = TimeSpan.FromMilliseconds(120);

    private static readonly OverlayCalmDisplayLevels Off =
        new(false, 1, 1, TimeSpan.FromSeconds(OverlayCalmDisplayLevels.DefaultWaitSeconds), OverlayCalmLightWhen.Relevant);

    private readonly Dictionary<OverlayCalmModule, Phase> _phases = [];
    private OverlayCalmDisplayLevels _levels = Off;
    private bool _peek;
    private DateTimeOffset _peekChangedAt = DateTimeOffset.MinValue;

    internal OverlayCalmDisplayLevels Levels => _levels;

    /// <summary>A settings change starts every module lit again.</summary>
    internal void Configure(OverlayCalmDisplayLevels levels, DateTimeOffset now)
    {
        // Turning on or changing the wait restarts the timers; dragging the
        // idle/lit sliders only changes the levels so the user sees them in place.
        var wake = (!_levels.Enabled && levels.Enabled) || _levels.Wait != levels.Wait;
        _levels = levels;
        if (wake) Wake(now);
    }

    /// <summary>The HUD was shown: everything starts lit, then rests on its own timer.</summary>
    internal void Wake(DateTimeOffset now)
    {
        foreach (var module in Enum.GetValues<OverlayCalmModule>())
        {
            _phases[module] = new Phase(now - Rise, 1, now + _levels.Wait);
        }
    }

    /// <summary>A content change. Returns whether the module was lit by it.</summary>
    internal bool Observe(OverlayCalmModule module, bool relevant, DateTimeOffset now)
    {
        if (!_levels.Enabled) return false;
        if (!relevant && _levels.LightWhen == OverlayCalmLightWhen.Relevant) return false;
        var current = Progress01(module, now);
        _phases[module] = current >= 1
            ? PhaseOf(module) with { LitUntil = now + _levels.Wait }
            : new Phase(now, current, now + _levels.Wait);
        return true;
    }

    internal void Observe(OverlayCalmContent previous, OverlayCalmContent next, DateTimeOffset now)
    {
        foreach (var (module, relevant) in OverlayCalmContent.Changes(previous, next))
        {
            Observe(module, relevant, now);
        }
    }

    internal void SetPeek(bool down, DateTimeOffset now)
    {
        if (_peek == down) return;
        _peek = down;
        _peekChangedAt = now;
    }

    /// <summary>The module's opacity now, or null while calm display is off (use the normal opacity).</summary>
    internal double? Level(OverlayCalmModule module, DateTimeOffset now, bool animate = true)
    {
        if (!_levels.Enabled) return null;
        var lit = animate ? Progress01(module, now) : Settled01(module, now);
        var blend = animate ? Progress(now - _peekChangedAt, PeekBlend) : 1;
        var shown = _peek ? Lerp(lit, 1, blend) : blend >= 1 ? lit : Lerp(1, lit, blend);
        return Lerp(_levels.Idle, _levels.Lit, shown);
    }

    /// <summary>When the next visible change starts or ends; null while nothing will move.</summary>
    internal DateTimeOffset? NextTransitionAt(DateTimeOffset now)
    {
        if (!_levels.Enabled) return null;
        DateTimeOffset? next = null;
        void Consider(DateTimeOffset at)
        {
            if (at > now && (next is null || at < next)) next = at;
        }

        if (_peekChangedAt != DateTimeOffset.MinValue) Consider(_peekChangedAt + PeekBlend);
        foreach (var phase in _phases.Values)
        {
            Consider(phase.LitAt + Rise);
            Consider(phase.LitUntil);
            Consider(phase.LitUntil + Fade);
        }

        return next;
    }

    /// <summary>True while any module is rising, fading or blending for peek.</summary>
    internal bool IsAnimating(DateTimeOffset now)
    {
        if (!_levels.Enabled) return false;
        if (now - _peekChangedAt < PeekBlend) return true;
        return _phases.Values.Any(p =>
            now - p.LitAt < Rise ||
            (now >= p.LitUntil && now - p.LitUntil < Fade));
    }

    private Phase PhaseOf(OverlayCalmModule module) =>
        _phases.TryGetValue(module, out var phase)
            ? phase
            : new Phase(DateTimeOffset.MinValue, 1, DateTimeOffset.MinValue);

    /// <summary>1 = lit, 0 = resting, with the rise and fade curves.</summary>
    private double Progress01(OverlayCalmModule module, DateTimeOffset now)
    {
        var phase = PhaseOf(module);
        if (now < phase.LitUntil)
        {
            return Lerp(phase.From, 1, Progress(now - phase.LitAt, Rise));
        }

        return 1 - EaseOut(Progress(now - phase.LitUntil, Fade));
    }

    /// <summary>Animation off: lit until the quiet period ends, then resting.</summary>
    private double Settled01(OverlayCalmModule module, DateTimeOffset now) =>
        now < PhaseOf(module).LitUntil ? 1 : 0;

    private static double Progress(TimeSpan elapsed, TimeSpan duration) =>
        elapsed <= TimeSpan.Zero ? 0 : Math.Min(1, elapsed / duration);

    private static double EaseOut(double t) => 1 - (1 - t) * (1 - t);

    private static double Lerp(double from, double to, double t) => from + (to - from) * t;

    private readonly record struct Phase(DateTimeOffset LitAt, double From, DateTimeOffset LitUntil);
}
