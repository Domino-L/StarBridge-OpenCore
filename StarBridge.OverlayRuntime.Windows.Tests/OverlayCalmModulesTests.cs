using StarBridge.Desktop;

namespace StarBridge.Desktop.Tests;

/// <summary>Calm display: modules rest after a quiet period, light for relevant changes, peek shows all.</summary>
internal static class OverlayCalmModulesTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);
    private static readonly OverlayCalmDisplayLevels On =
        OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { Opacity = 1 });

    internal static void RunAll()
    {
        OffLeavesNormalOpacity();
        RestsAfterQuietPeriodAndLightsOnlyItsModule();
        IrrelevantChangesStayResting();
        PeekBlendsEverythingToLitAndBack();
        LowOpacityUsersRestAtTheirOwnLevel();
        AnimationOffSnaps();
        DataGapsAreNotChanges();
        NothingRunsWhileIdle();
        Console.WriteLine("PASS calm modules: off leaves normal opacity, rest/light/peek at user levels, gaps ignored, idle has no timer");
    }

    private static void OffLeavesNormalOpacity()
    {
        var tracker = new OverlayCalmModulesTracker();
        tracker.Wake(T0);
        Check(!tracker.Levels.Enabled, "calm display is off until configured");
        foreach (var module in Enum.GetValues<OverlayCalmModule>())
        {
            Check(tracker.Level(module, T0 + TimeSpan.FromMinutes(5)) is null, $"{module} keeps the normal opacity while off");
        }

        Check(!tracker.Observe(OverlayCalmModule.Members, true, T0), "nothing lights while off");
        Check(tracker.NextTransitionAt(T0) is null && !tracker.IsAnimating(T0), "off never asks for frames");
        var upgraded = OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { CalmDisplay = OverlayCalmDisplay.Unset });
        Check(!upgraded.Enabled, "an upgraded file (Unset) stays off");
    }

    private static void RestsAfterQuietPeriodAndLightsOnlyItsModule()
    {
        var tracker = Tracker();
        Check(tracker.Level(OverlayCalmModule.Members, T0 + Seconds(9)) == 1, "lit while the quiet period runs");
        Check(Near(tracker.Level(OverlayCalmModule.Members, T0 + Seconds(11)), 0.35), "rests at the idle level after the fade");
        var mid = tracker.Level(OverlayCalmModule.Members, T0 + Seconds(10) + Milliseconds(450))!.Value;
        Check(mid < 1 && mid > 0.35, "fades gradually, not in one step");

        var change = T0 + Seconds(20);
        Check(tracker.Observe(OverlayCalmModule.Members, true, change), "a relevant change lights the module");
        Check(Near(tracker.Level(OverlayCalmModule.Members, change), 0.35), "rising starts from the resting level");
        Check(tracker.Level(OverlayCalmModule.Members, change + Milliseconds(160)) == 1, "fully lit after the short rise");
        Check(Near(tracker.Level(OverlayCalmModule.Squads, change + Milliseconds(160)), 0.35), "other modules keep resting");
        Check(tracker.Level(OverlayCalmModule.Members, change + Seconds(9)) == 1, "stays lit for a full quiet period");
        Check(Near(tracker.Level(OverlayCalmModule.Members, change + Seconds(11)), 0.35), "then rests again");

        tracker.Observe(OverlayCalmModule.Chat, true, change + Seconds(30));
        tracker.Observe(OverlayCalmModule.Chat, true, change + Seconds(38));
        Check(tracker.Level(OverlayCalmModule.Chat, change + Seconds(47)) == 1, "a change while lit extends the period");
    }

    private static void IrrelevantChangesStayResting()
    {
        var tracker = Tracker();
        var later = T0 + Seconds(30);
        Check(!tracker.Observe(OverlayCalmModule.Squads, false, later), "an unrelated change does not light by default");
        Check(Near(tracker.Level(OverlayCalmModule.Squads, later + Seconds(1)), 0.35), "it keeps resting");
        tracker.Configure(On with { LightWhen = OverlayCalmLightWhen.Any }, later + Seconds(2));
        Check(Near(tracker.Level(OverlayCalmModule.Squads, later + Seconds(3)), 0.35), "changing when to light does not light");
        tracker.Configure(On with { LightWhen = OverlayCalmLightWhen.Any, Idle = 0.5 }, later + Seconds(4));
        Check(Near(tracker.Level(OverlayCalmModule.Squads, later + Seconds(5)), 0.5), "a new idle level shows in place, still resting");
        Check(tracker.Observe(OverlayCalmModule.Squads, false, later + Seconds(20)), "'any change' lights for every change");
    }

    private static void PeekBlendsEverythingToLitAndBack()
    {
        var tracker = Tracker();
        var down = T0 + Seconds(30);
        tracker.SetPeek(true, down);
        Check(Near(tracker.Level(OverlayCalmModule.Chat, down), 0.35), "peek blends from where the module was");
        Check(tracker.Level(OverlayCalmModule.Chat, down + Milliseconds(120)) == 1, "held peek shows every module lit");
        tracker.SetPeek(false, down + Seconds(6));
        Check(Near(tracker.Level(OverlayCalmModule.Squads, down + Seconds(6) + Milliseconds(120)), 0.35), "release returns to resting");
    }

    private static void LowOpacityUsersRestAtTheirOwnLevel()
    {
        var tracker = new OverlayCalmModulesTracker();
        tracker.Configure(OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { Opacity = 0.25 }), T0);
        Check(Near(tracker.Level(OverlayCalmModule.Members, T0 + Seconds(1)), 0.85), "lit lifts a low opacity to a readable 85%");
        Check(Near(tracker.Level(OverlayCalmModule.Members, T0 + Seconds(12)), 0.25), "resting never goes below the user's own 25%");
        var custom = new OverlayCalmModulesTracker();
        custom.Configure(OverlayCalmDisplayLevels.Resolve(OverlayDisplaySettings.Default with { CalmIdleOpacity = 0.5, CalmLitOpacity = 0.7 }), T0);
        Check(Near(custom.Level(OverlayCalmModule.Chat, T0 + Seconds(1)), 0.7) &&
              Near(custom.Level(OverlayCalmModule.Chat, T0 + Seconds(12)), 0.5), "user-chosen levels are used as set");
    }

    private static void AnimationOffSnaps()
    {
        var tracker = Tracker();
        Check(tracker.Level(OverlayCalmModule.Members, T0 + Seconds(10) + Milliseconds(100), animate: false) == 0.35,
            "with animation off the module rests at once, no fade frames");
    }

    private static void DataGapsAreNotChanges()
    {
        var a = new OverlayCalmContent(1, 1, 5, 2, "m1");
        Check(OverlayCalmContent.Changes(a, a).Count == 0, "same content is no change");
        Check(OverlayCalmContent.Changes(a, OverlayCalmContent.Unknown).Count == 0, "unknown content is no change");
        Check(OverlayCalmContent.Changes(OverlayCalmContent.Unknown, a).Count == 0, "first known content is a baseline");
        var changes = OverlayCalmContent.Changes(a, new OverlayCalmContent(2, 1, 6, 3, "m2"));
        Check(changes.SequenceEqual([
            (OverlayCalmModule.Squads, false),
            (OverlayCalmModule.Members, true),
            (OverlayCalmModule.Chat, true),
        ]), "each module reports its change and whether it concerns the viewer");
        var tracker = Tracker();
        tracker.Observe(a, new OverlayCalmContent(2, 1, 5, 2, "m1"), T0 + Seconds(30));
        Check(Near(tracker.Level(OverlayCalmModule.Squads, T0 + Seconds(31)), 0.35), "content diffs apply the relevance rule");
    }

    private static void NothingRunsWhileIdle()
    {
        var tracker = Tracker();
        Check(tracker.NextTransitionAt(T0 + Seconds(1)) == T0 + Seconds(10), "the only wait is the quiet period");
        Check(!tracker.IsAnimating(T0 + Seconds(5)), "no frames while lit and steady");
        Check(tracker.IsAnimating(T0 + Seconds(10) + Milliseconds(100)), "frames only during the fade");
        Check(tracker.NextTransitionAt(T0 + Seconds(12)) is null && !tracker.IsAnimating(T0 + Seconds(12)),
            "nothing is scheduled once every module rests");
    }

    private static OverlayCalmModulesTracker Tracker()
    {
        var tracker = new OverlayCalmModulesTracker();
        tracker.Configure(On, T0);
        return tracker;
    }

    private static TimeSpan Seconds(double value) => TimeSpan.FromSeconds(value);
    private static TimeSpan Milliseconds(double value) => TimeSpan.FromMilliseconds(value);
    private static bool Near(double? actual, double expected) => actual is { } value && Math.Abs(value - expected) < 1e-9;
    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
