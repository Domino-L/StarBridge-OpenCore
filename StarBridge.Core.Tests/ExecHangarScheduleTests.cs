using StarBridge.Core.Tools;
namespace StarBridge.Core.Tests;

internal static class ExecHangarScheduleTests
{
    internal static void RunAll()
    {
        var origin = DateTimeOffset.Parse("2026-09-16T13:05:05.639-06:00");
        var config = new ExecHangarConfig("test", "test", null, origin, 350, 65, 120, 1);
        var schedule = new ExecHangarSchedule(config);
        Check(typeof(ExecHangarMonitor).GetMethod(nameof(ExecHangarMonitor.Immediate),
            [typeof(ExecHangarSchedule), typeof(DateTimeOffset), typeof(ExecHangarReminders), typeof(ExecHangarMonitoring)]) is not null,
            "the existing four-argument reminder API remains compatible with packaged callers");
        Check(!new ExecHangarReminders().AutoDuringGame, "automatic game monitoring is opt-in");
        var game = ExecHangarGameMonitoring.Observe(null, "running", "game-one", origin)!;
        var paused = game with { Paused = true };
        Check(ExecHangarGameMonitoring.Observe(paused, "running", "game-one", origin.AddSeconds(1)) == paused,
            "manual pause remains in the same game process");
        Check(ExecHangarGameMonitoring.Observe(paused, "running", "game-two", origin.AddSeconds(2)) is { Paused: false },
            "a different game process starts a fresh monitor");
        var missing = ExecHangarGameMonitoring.Observe(game, "notRunning", null, origin.AddSeconds(1))!;
        Check(ExecHangarGameMonitoring.Observe(missing, "notRunning", null, origin.AddSeconds(10)) is not null,
            "brief missing process does not manufacture a new game session");
        Check(ExecHangarGameMonitoring.Observe(missing, "notRunning", null, origin.AddSeconds(11)) is null,
            "ten seconds of confirmed absence ends the game session");
        var unknown = ExecHangarGameMonitoring.Observe(missing, "unknown", null, origin.AddSeconds(11))!;
        Check(unknown.Id == game.Id && unknown.MissingSince is null,
            "unknown observation preserves session and breaks exit confirmation");
        Check(schedule.CycleMs == 11100350 && schedule.OpenMs == 3900123, "SCM millisecond rounding");
        var phases = schedule.Phases(origin);
        Check(phases.Count == 22 && phases[0].GreenLights == 5 && phases[5].GreenLights == 0, "six open light stages");
        Check(phases[6].RedLights == 5 && phases[10].GreenLights == 4, "five closed light stages");
        Check(phases[6].Start == origin.AddMilliseconds(schedule.OpenMs) && !phases[6].Open, "close boundary belongs to closed phase");
        var leaveOnly = new ExecHangarReminders(true, false, false, 5, false, 5, false, 5, false, true);
        var warning = schedule.Due(phases[5].Start.AddMilliseconds(-1), phases[5].Start, leaveOnly).Single();
        Check(warning.Kind == "leave" && warning.Due == phases[5].Start && warning.Boundary == phases[5].End && !warning.Opening,
            "leave warning uses exact all-lights-off boundary, including drift rounding");
        Check(schedule.Due(phases[5].Start.AddMilliseconds(-2), phases[5].Start.AddMilliseconds(-1), leaveOnly).Count == 0,
            "leave warning never fires before phase begins");
        Check(schedule.Due(phases[5].Start, phases[5].Start.AddSeconds(1), leaveOnly).Count == 0, "leave warning is not repeated");
        Check(schedule.Notices(origin, origin.AddDays(1), leaveOnly with { LeaveWarning = false }).Count == 0,
            "leave rule is independently optional");
        var withinWarning = phases[5].Start.AddSeconds(1);
        var leaveWatch = new ExecHangarMonitoring(Guid.NewGuid(), withinWarning, phases[5].End, true, phases[5].End);
        Check(ExecHangarMonitor.Immediate(schedule, withinWarning, leaveOnly, leaveWatch)?.Kind == "leave",
            "starting in warning phase provides one current leave reminder");
        Check(ExecHangarMonitor.Immediate(schedule, withinWarning, leaveOnly, leaveWatch with { EndsAt = phases[5].End.AddSeconds(-1) }) is null,
            "leave warnings obey finite selected-event boundaries");
        for (var i = 1; i < phases.Count; i++) Check(phases[i].Start == phases[i - 1].End, "continuous light intervals");
        Check(schedule.Windows(origin.AddMilliseconds(-1))[0].Cycle == 0, "normalized modulo before epoch");
        var next = origin.AddMilliseconds(schedule.CycleMs);
        var settings = new ExecHangarReminders(true);
        var before = schedule.Due(next.AddMinutes(-5).AddSeconds(-1), next.AddMinutes(-5), settings);
        Check(before.Count == 2 && before.All(n => n.Opening), "coincident opening lead reminders");
        Check(schedule.Due(next.AddMilliseconds(-1), next, settings).Single().Kind == "open", "opening fires exactly at boundary");
        Check(schedule.Due(next.AddMinutes(-10), next, settings).Count == 0, "no sleep backlog");
        Check(schedule.Due(next, next.AddSeconds(-1), settings).Count == 0, "no backwards clock replay");
        var fast = new ExecHangarSchedule(config with { DesignOnlineMin = 1, DesignOfflineMin = 1, CycleDriftMs = 0 });
        Check(fast.Due(origin.AddSeconds(-1), origin, settings with { OnOpen = false, BeforeOpenMinutes = 120 }).Any(n => n.Kind == "beforeOpen"), "long lead on short cycle");
        Invalid(() => new ExecHangarSchedule(config with { DesignOnlineMin = 0 }));
        Invalid(() => new ExecHangarSchedule(config with { CycleDriftMs = int.MinValue }));
        Invalid(() => (settings with { BeforeOpenMinutes = 121 }).Validate());
        var split = new ExecHangarReminders(true, true, true, 7, false, 5, true, 3, true);
        var close = origin.AddMilliseconds(schedule.OpenMs);
        Check(schedule.Due(close.AddMinutes(-3).AddSeconds(-1), close.AddMinutes(-3), split).Single().Kind == "beforeClose", "closure has independent lead");
        Check(schedule.Due(close.AddMilliseconds(-1), close, split).Single().Kind == "close", "closure has its own at-time rule");
        Check(schedule.Due(next.AddMinutes(-7).AddSeconds(-1), next.AddMinutes(-7), split).Single().Kind == "beforeOpen", "opening has independent lead");
        var began = next.AddMinutes(-2);
        var watch = new ExecHangarMonitoring(Guid.NewGuid(), began, began.AddMinutes(1), true, next);
        var plan = ExecHangarMonitor.Plan(schedule, began, split, watch, []);
        Check(plan.Active && plan.State == "noEvent" && plan.Next is null && plan.Outside?.Boundary == next, "target outside duration is not alerted even inside its lead interval");
        watch = watch with { EndsAt = next };
        var immediate = ExecHangarMonitor.Immediate(schedule, began, split, watch);
        Check(immediate is { Kind: "beforeOpen" } && immediate.Due == began && immediate.Boundary == next, "start inside lead interval gives one current notice");
        Check(ExecHangarMonitor.Immediate(schedule, began, split, null, [immediate!.Key]) is null,
            "editing a continuous lead time cannot replay an accepted event");
        Check(ExecHangarMonitor.Immediate(schedule, began, split, null, [], next) is null,
            "continuous settings edits retain suppression of the current event");
        var beforeOnly = split with { OnOpen = false, BeforeClose = false, OnClose = false };
        var alreadyReminded = ExecHangarMonitor.Plan(schedule, began, beforeOnly, watch, [ExecHangarMonitor.Receipt(immediate!, watch)]);
        Check(alreadyReminded is { State: "waiting", Next: null } && alreadyReminded.Waiting?.Boundary == next, "current target remains visible after its advance notice instead of false no-event state");
        Check(ExecHangarMonitor.Eligible(schedule, began, split, watch).All(n => n.Boundary == next), "only next means all rules for one boundary");
        Check(ExecHangarMonitor.Immediate(schedule, began, split, watch with { MutedBoundary = next }) is null, "muting this event suppresses its remaining rules");
        Check(ExecHangarMonitor.Plan(schedule, next.AddSeconds(1), split, watch, []).State == "complete", "one-event session completes");
        Check(ExecHangarMonitor.Plan(schedule, began.AddDays(10), split, watch, []).Next is null, "old finite sessions stay stopped without invalid interval arithmetic");
    }
    private static void Check(bool condition, string why) { if (!condition) throw new InvalidOperationException(why); }
    private static void Invalid(Action action) { try { action(); } catch (ArgumentException) { return; } throw new InvalidOperationException("Invalid calibration accepted."); }
}
