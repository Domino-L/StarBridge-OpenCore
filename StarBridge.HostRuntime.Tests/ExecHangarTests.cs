using System.Net;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using StarBridge.Core.Tools;
using StarBridge.HostRuntime.Tools;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class ExecHangarTests
{
    private static readonly DateTimeOffset Origin = new(2026, 10, 9, 0, 0, 0, TimeSpan.Zero);
    internal static async Task Run()
    {
        foreach (var capability in ExecHangarBridgeDispatcher.Capabilities)
            BridgeEnvelopeValidator.RequireAccountContext(capability, null);
        ReminderAudio();
        await Monitoring();
        await EnhancedMonitoring();
        await LegacyRestore();
        await RealTestContent();
        await AutomaticGameMonitoring();
        await ContinuousMonitoring();
        await ContinuousSettingsChanges();
        using var f = new Fixture();
        var initial = await f.Runtime.ReadAsync();
        Check(initial.Reliable && !initial.Reminders.Enabled && initial.Windows.Count == 6, "fresh anonymous calibration, opt-in default");
        await f.Runtime.SaveAsync(new(true), initial.Revision, () => true);
        await f.Tick(Origin.AddMinutes(180).AddSeconds(-1));
        await f.Tick(Origin.AddMinutes(180));
        Check(f.Deliveries.Count == 1 && f.Deliveries[0].Notices.Count == 2, "coincident lead events merged into one native delivery");
        await f.Tick(Origin.AddMinutes(180).AddSeconds(1)); Check(f.Deliveries.Count == 1, "no duplicate tick");
        await f.Tick(Origin.AddMinutes(185).AddSeconds(-1));
        await f.Tick(Origin.AddMinutes(185)); Check(f.Deliveries.Count == 2, "opening independently delivered");
        using (var restarted = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time)) {
            Check((await restarted.ReadAsync()).Reminders.Enabled, "device-local persistence");
            await restarted.TickAsync(); Check(f.Deliveries.Count == 2, "restart does not repeat accepted event");
        }
        var current = await f.Runtime.ReadAsync();
        await Expect<ExecHangarConflictException>(() => f.Runtime.SaveAsync(new(false), 0, () => true));
        Check((await f.Runtime.ReadAsync()).Revision == current.Revision, "revision conflict preserves settings");
        await Expect<OperationCanceledException>(() => f.Runtime.SaveAsync(new(false), current.Revision, () => false));
        Check((await f.Runtime.ReadAsync()).Reminders.Enabled, "generation changed before commit");

        f.Client.Fail = true;
        var cached = await f.Runtime.ReadAsync(true);
        Check(cached.Config != null && cached.RefreshFailed && cached.Reliable, "offline keeps recent good cache");
        f.Time.AdvanceTo(Origin.AddHours(10));
        await f.Runtime.TickAsync(); Check(!(await f.Runtime.ReadAsync()).Reliable && f.Deliveries.Count == 2, "expiry pauses reminders");
        f.Client.Fail = false; f.Client.Config = f.Client.Config with { Stale = true };
        Check(!(await f.Runtime.ReadAsync(true)).Reliable, "remote stale marker pauses reminders");
        f.Client.Config = f.Client.Config with { Stale = false };
        await f.Runtime.ReadAsync(true); await f.Runtime.TickAsync();
        await f.Tick(Origin.AddMinutes(730));
        Check(f.Deliveries.Count == 2, "long suspension skips missed reminders");
        f.Time.JumpUtc(Origin.AddMinutes(740)); await f.Runtime.TickAsync();
        Check(f.Deliveries.Count == 2, "wall-clock jump cannot create an opening alert");

        var bridge = new ExecHangarBridgeDispatcher(f.Runtime, () => 3);
        var request = BridgeEnvelope.Request("execHangar.read", "read", 3, new { schemaVersion = 1 });
        Check((await bridge.DispatchAsync(request)).Response.MessageType == BridgeMessageTypes.Response, "accountless bridge read");
        Check((await bridge.DispatchAsync(request with { SessionGeneration = 2 })).Response.Status == BridgeResponseStatuses.Error, "stale generation rejected");
        Check((await bridge.DispatchAsync(request with { Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, path = "unexpected" }) })).Response.Status == BridgeResponseStatuses.Error, "extra input rejected");

        File.WriteAllText(Path.Combine(f.Root, "exec-hangar.v1.json"), "{\"schemaVersion\":1,\"schemaVersion\":1}");
        using (var corrupt = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time))
            await Expect<InvalidDataException>(() => corrupt.ReadAsync());
        Check(File.ReadAllText(Path.Combine(f.Root, "exec-hangar.v1.json")).Contains("schemaVersion\":1,\"schemaVersion"), "corrupt settings not replaced");

        await PublicClient();
        await ChannelPolicy();
        await TestSuppressionFeedback();
        Console.WriteLine("PASS executive hangar: public config, persistence, clock/sleep, dedupe, stale cache, bridge and notification policies");
    }
    private static async Task ContinuousMonitoring()
    {
        using var f = new Fixture();
        var s = await f.Runtime.ReadAsync();
        f.Time.AdvanceTo(Origin.AddMinutes(181));
        var beforePreview = File.ReadAllText(Path.Combine(f.Root, "exec-hangar.v1.json"));
        var preview = await f.Runtime.PreviewAsync(s.Reminders, -1, false);
        Check(preview.Plan is { Active: true, EndsAt: null } && preview.Monitoring is null &&
            File.ReadAllText(Path.Combine(f.Root, "exec-hangar.v1.json")) == beforePreview,
            "continuous preview has no manufactured deadline and writes nothing");
        await Expect<ArgumentException>(() => f.Runtime.PreviewAsync(s.Reminders, -1, true));
        var bridge = new ExecHangarBridgeDispatcher(f.Runtime, () => 3);
        var reply = (await bridge.DispatchAsync(BridgeEnvelope.Request("execHangar.continuous", "always", 3,
            new { schemaVersion = 1, expectedRevision = s.Revision }))).Response;
        Check(reply.MessageType == BridgeMessageTypes.Response && reply.Payload.GetProperty("monitoringSource").GetString() == "manual",
            "continuous entry passes complete accountless host bridge");
        s = await f.Runtime.ReadAsync();
        Check(s.Monitoring is null && s.Reminders.Enabled && s.Plan is { Active: true, EndsAt: null },
            "continuous monitoring is durable and not a finite timer");
        using (var restarted = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time)) {
            Check((await restarted.ReadAsync()).MonitoringSource == "manual", "continuous pending reminder survives restart");
            await restarted.TickAsync();
            Check(f.Deliveries.Count == 1 && f.Deliveries[0].MonitoringEndsAt is null,
                "start inside lead interval emits one real continuous reminder after restart");
        }
        // Read the current document into its sole test owner before advancing.
        using var owner = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time);
        s = await owner.ReadAsync(); await owner.TickAsync();
        Check(f.Deliveries.Count == 1, "continuous current lead receipt is not replayed");
        f.Time.AdvanceTo(Origin.AddMinutes(185).AddSeconds(-1)); await owner.TickAsync();
        f.Time.AdvanceTo(Origin.AddMinutes(185)); await owner.TickAsync();
        Check(f.Deliveries.Count == 2 && f.Deliveries[^1].Notices.Any(n => n.Kind == "open"),
            "continuous watch also delivers the actual opening");
        f.Time.AdvanceTo(Origin.AddDays(3));
        s = await owner.ReadAsync(); await owner.TickAsync();
        Check(s.Plan is { Active: true, EndsAt: null } && s.MonitoringSource == "manual" && f.Deliveries.Count == 2,
            "continuous watch remains active beyond finite cap without a missed-event backlog");
        s = await owner.MonitorAsync("stop", s.Revision, 0, false, () => true);
        Check(!s.Reminders.Enabled && s.Plan?.Active == false, "explicit stop ends continuous monitoring");
        using var stopped = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time);
        Check(!(await stopped.ReadAsync()).Reminders.Enabled, "continuous stop persists across restart");
        using var priority = new Fixture();
        priority.Game = new("running", SessionId: "manual-priority-game");
        var current = await priority.Runtime.ReadAsync();
        current = await priority.Runtime.SaveAsync(current.Reminders with { AutoDuringGame = true }, current.Revision, () => true);
        await priority.Runtime.MonitorAsync("continuous", current.Revision, 0, false, () => true);
        await priority.Tick(Origin.AddMinutes(185).AddSeconds(-1));
        priority.Game = new("notRunning");
        await priority.Tick(Origin.AddMinutes(185));
        Check(priority.Deliveries.Count == 1 && priority.Deliveries[0].Notices.Any(n => n.Kind == "open") &&
            (await priority.Runtime.ReadAsync()).MonitoringSource == "manual",
            "game exit cannot cancel or skip an always-on manual event at the same tick");
    }
    private static async Task ContinuousSettingsChanges()
    {
        var failures = new List<string>();
        void Verify(bool ok, string message) { if (!ok) failures.Add(message); }
        var rules = new ExecHangarReminders(true, BeforeChange: false, BeforeClose: false);
        using (var crossing = new Fixture()) {
            var s = await crossing.Runtime.ReadAsync();
            s = await crossing.Runtime.SaveAsync(rules, s.Revision, () => true);
            await crossing.Tick(Origin.AddMinutes(180).AddSeconds(-1));
            s = await crossing.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 4 }, s.Revision, () => true);
            await crossing.Tick(Origin.AddMinutes(181));
            Verify(crossing.Deliveries.Count == 1 && crossing.Deliveries[0].Notices.Any(n => n.Kind == "beforeOpen"),
                "saving an active continuous watch preserves the next due crossing");
        }
        using (var moved = new Fixture()) {
            var s = await moved.Runtime.ReadAsync();
            s = await moved.Runtime.SaveAsync(rules, s.Revision, () => true);
            await moved.Tick(Origin.AddMinutes(178));
            s = await moved.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 10 }, s.Revision, () => true);
            await moved.Tick(Origin.AddMinutes(178).AddSeconds(1));
            Verify(moved.Deliveries.Count == 1 && moved.Deliveries[0].Notices.Any(n => n.Kind == "beforeOpen" && n.Boundary == Origin.AddMinutes(185)),
                "moving a lead time into the current interval retains the upcoming event");
            s = await moved.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 8 }, s.Revision, () => true);
            await moved.Tick(Origin.AddMinutes(178).AddSeconds(2));
            Verify(moved.Deliveries.Count == 1, "editing lead time does not repeat an accepted event");
            await moved.Tick(Origin.AddMinutes(185).AddSeconds(-1));
            s = await moved.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 7 }, s.Revision, () => true);
            await moved.Tick(Origin.AddMinutes(185));
            Verify(moved.Deliveries.Count == 2 && moved.Deliveries[^1].Notices.Any(n => n.Kind == "open"),
                "saving just before opening does not discard the actual opening crossing");
        }
        using (var pending = new Fixture()) {
            var s = await pending.Runtime.ReadAsync();
            s = await pending.Runtime.SaveAsync(rules with { Enabled = false }, s.Revision, () => true);
            pending.Time.AdvanceTo(Origin.AddMinutes(181));
            s = await pending.Runtime.MonitorAsync("continuous", s.Revision, 0, false, () => true);
            await pending.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 6 }, s.Revision, () => true);
            using var restart = new ExecHangarRuntime(pending.Root, pending.Client, pending.Deliver, pending.Time);
            await restart.ReadAsync(); await restart.TickAsync();
            Verify(pending.Deliveries.Count == 1, "saving keeps a current continuous reminder durable before its first tick");
        }
        using (var shorter = new Fixture()) {
            var s = await shorter.Runtime.ReadAsync();
            s = await shorter.Runtime.SaveAsync(rules with { Enabled = false }, s.Revision, () => true);
            shorter.Time.AdvanceTo(Origin.AddMinutes(181));
            s = await shorter.Runtime.MonitorAsync("continuous", s.Revision, 0, false, () => true);
            s = await shorter.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 2 }, s.Revision, () => true);
            await shorter.Runtime.TickAsync();
            Verify(shorter.Deliveries.Count == 0, "shortening the lead cancels the previous pending reminder");
            await shorter.Tick(Origin.AddMinutes(183).AddSeconds(-1));
            await shorter.Tick(Origin.AddMinutes(183));
            Verify(shorter.Deliveries.Count == 1, "shortened lead is detected at its new due time");
            shorter.Deliveries[0].Mute!();
            s = await shorter.Runtime.ReadAsync();
            s = await shorter.Runtime.SaveAsync(rules with { BeforeOpenMinutes = 10 }, s.Revision, () => true);
            await shorter.Tick(Origin.AddMinutes(183).AddSeconds(1));
            await shorter.Tick(Origin.AddMinutes(185).AddSeconds(-1));
            await shorter.Tick(Origin.AddMinutes(185));
            Verify(shorter.Deliveries.Count == 1, "settings edits preserve mute of the whole current event");
        }
        using (var disabled = new Fixture()) {
            var s = await disabled.Runtime.ReadAsync();
            s = await disabled.Runtime.SaveAsync(rules with { Enabled = false }, s.Revision, () => true);
            disabled.Time.AdvanceTo(Origin.AddMinutes(181));
            s = await disabled.Runtime.MonitorAsync("continuous", s.Revision, 0, false, () => true);
            await disabled.Runtime.SaveAsync(rules with { BeforeOpen = false }, s.Revision, () => true);
            await disabled.Runtime.TickAsync();
            Verify(disabled.Deliveries.Count == 0, "disabling a lead rule cancels its pending reminder");
        }
        using (var automatic = new Fixture()) {
            automatic.Game = new("running", SessionId: "editing-rules-game");
            var s = await automatic.Runtime.ReadAsync();
            s = await automatic.Runtime.SaveAsync(rules with { Enabled = false, AutoDuringGame = true }, s.Revision, () => true);
            await automatic.Tick(Origin.AddMinutes(178));
            s = await automatic.Runtime.SaveAsync(s.Reminders with { BeforeOpenMinutes = 10 }, s.Revision, () => true);
            await automatic.Tick(Origin.AddMinutes(178).AddSeconds(1));
            Verify(automatic.Deliveries.Count == 1, "game monitoring reconciles a changed lead in its current interval");
            await automatic.Tick(Origin.AddMinutes(185).AddSeconds(-1));
            s = await automatic.Runtime.SaveAsync(s.Reminders with { BeforeOpenMinutes = 8 }, s.Revision, () => true);
            await automatic.Tick(Origin.AddMinutes(185));
            Verify(automatic.Deliveries.Count == 2 && automatic.Deliveries[^1].Notices.Any(n => n.Kind == "open"),
                "same game session retains the actual opening crossing after settings save");
        }
        using (var atDue = new Fixture()) {
            var s = await atDue.Runtime.ReadAsync();
            s = await atDue.Runtime.SaveAsync(rules, s.Revision, () => true);
            await atDue.Tick(Origin.AddMinutes(180).AddSeconds(-1));
            atDue.Time.AdvanceTo(Origin.AddMinutes(180));
            await atDue.Runtime.SaveAsync(rules with { OnClose = true }, s.Revision, () => true);
            await atDue.Tick(Origin.AddMinutes(180).AddSeconds(1));
            Verify(atDue.Deliveries.Count == 1 && atDue.Deliveries[0].Notices.Count == 1,
                "a due crossing and settings reconciliation produce one notice for the same event rule");
        }
        Check(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }
    private static async Task AutomaticGameMonitoring()
    {
        using var f = new Fixture();
        var s = await f.Runtime.ReadAsync();
        f.Game = new("running", SessionId: "first-game");
        Check((await f.Runtime.ReadAsync()).MonitoringSource == "none", "game launch does not opt in");
        f.Time.AdvanceTo(Origin.AddMinutes(181));
        s = await f.Runtime.SaveAsync(s.Reminders with { AutoDuringGame = true }, s.Revision, () => true);
        Check(s is { MonitoringSource: "game", GameMonitoringState: "watching" } && s.Plan is { Active: true, EndsAt: null } &&
            !s.Reminders.Enabled && s.Reminders.AutoDuringGame, "opt in during running game uses saved rules without a finite or manual watch");
        var preferenceRevision = s.Revision;
        await f.Runtime.TickAsync();
        Check(f.Deliveries.Count == 1 && f.Deliveries[0].Notices.All(n => n.Opening && n.Boundary == Origin.AddMinutes(185)),
            "automatic start inside lead interval gives one real opening reminder");
        using (var restart = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time, () => f.Game)) {
            var resumed = await restart.ReadAsync();
            await restart.TickAsync();
            Check(resumed.MonitoringSource == "game" && resumed.Revision == preferenceRevision && f.Deliveries.Count == 1,
                "restart restores automatic preference and durable event receipt without replay");
        }
        f.Game = new("unknown");
        await f.Tick(Origin.AddMinutes(182));
        Check((await f.Runtime.ReadAsync()).GameMonitoringState == "unknown" && f.Deliveries.Count == 1,
            "unknown game observation pauses automatic delivery");
        f.Game = new("running", SessionId: "first-game");
        await f.Runtime.ReadAsync(); await f.Runtime.TickAsync();
        Check(f.Deliveries.Count == 1, "recovering same process does not repeat its lead notice");
        s = await f.Runtime.ReadAsync();
        s = await f.Runtime.MonitorAsync("stop", s.Revision, 0, false, () => true);
        Check(s.GameMonitoringState == "paused" && s.Plan?.Active == false && s.Reminders.AutoDuringGame,
            "stop retains preference while pausing this game session");
        await f.Tick(Origin.AddMinutes(185));
        Check(f.Deliveries.Count == 1, "manual stop cannot be immediately undone by timer");
        using (var restart = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time, () => f.Game))
            Check((await restart.ReadAsync()).GameMonitoringState == "paused", "same-game manual pause survives client restart");
        f.Game = new("running", SessionId: "second-game");
        s = await f.Runtime.ReadAsync();
        Check(s.MonitoringSource == "game" && s.Revision == preferenceRevision + 1,
            "new game resumes automatically without changing settings revision");
        f.Time.AdvanceTo(Origin.AddMinutes(185).AddSeconds(1));
        s = await f.Runtime.MonitorAsync("start", s.Revision, 10, true, () => true);
        var manual = s.Monitoring;
        Check(s.MonitoringSource == "manual" && manual is { OnlyNext: true }, "manual duration and selected event take priority");
        f.Game = new("notRunning");
        await f.Runtime.ReadAsync();
        await f.Tick(Origin.AddMinutes(186));
        s = await f.Runtime.ReadAsync();
        Check(s.MonitoringSource == "manual" && s.Monitoring == manual, "game exit preserves manual watch");
        s = await f.Runtime.MonitorAsync("stop", s.Revision, 0, false, () => true);
        f.Game = new("running", SessionId: "third-game");
        s = await f.Runtime.ReadAsync();
        Check(s.MonitoringSource == "game", "next game recovers automatic mode after manual watch stopped");
        f.Game = new("notRunning");
        await f.Runtime.ReadAsync();
        await f.Tick(Origin.AddMinutes(187));
        s = await f.Runtime.ReadAsync();
        Check(s is { MonitoringSource: "none", GameMonitoringState: "waiting" } && s.GameMonitoringState != "disabled",
            "confirmed game exit stops automatic watch while retaining opt in");
        f.Game = new("running", SessionId: "fourth-game");
        s = await f.Runtime.ReadAsync();
        s = await f.Runtime.SaveAsync(s.Reminders with { AutoDuringGame = false }, s.Revision, () => true);
        Check(s.MonitoringSource == "none" && s.GameMonitoringState == "disabled", "turning off preference stops automatic watch");
        s = await f.Runtime.SaveAsync(new(false, false, false, 5, false, 5, false, 5, AutoDuringGame: true), s.Revision, () => true);
        Check(s.GameMonitoringState == "noRules" && s.Plan?.Active == false, "automatic mode never invents enabled reminder rules");
        var bridge = new ExecHangarBridgeDispatcher(f.Runtime, () => 3);
        var save = BridgeEnvelope.Request("execHangar.save", "auto-save", 3, new { schemaVersion = 1, expectedRevision = s.Revision,
            enabled = false, onOpen = true, beforeOpen = true, beforeOpenMinutes = 5, beforeChange = false,
            beforeChangeMinutes = 5, beforeClose = true, beforeCloseMinutes = 5, onClose = false, leaveWarning = true, autoDuringGame = true });
        var reply = (await bridge.DispatchAsync(save)).Response;
        Check(reply.MessageType == BridgeMessageTypes.Response && reply.Payload.GetProperty("reminders").GetProperty("autoDuringGame").GetBoolean() &&
            reply.Payload.GetProperty("monitoringSource").GetString() == "game", "accountless save roundtrip carries auto preference and effective source");
        var beforeLeave = f.Deliveries.Count;
        await f.Tick(Origin.AddMinutes(245).AddSeconds(-1));
        await f.Tick(Origin.AddMinutes(245));
        Check(f.Deliveries.Count == beforeLeave + 1 && f.Deliveries[^1].MonitoringEndsAt is null &&
            f.Deliveries[^1].Notices.Any(n => n.Kind == "leave") && f.Deliveries[^1].Notices.Any(n => n.Kind == "beforeClose"),
            "game monitoring keeps independent closing and clearance rules, coalesced at real all-off boundary");
        var mutedCard = f.Deliveries[^1];
        mutedCard.Mute!();
        s = await f.Runtime.ReadAsync();
        Check(s.Plan?.MutedBoundary == Origin.AddMinutes(250), "auto card skips its event within the game watch");
        s = await f.Runtime.MonitorAsync("restore", s.Revision, 0, false, () => true);
        Check(s.MonitoringSource == "game" && !s.Reminders.Enabled && s.Plan?.MutedBoundary is null,
            "restoring automatic event does not accidentally enable legacy continuous monitoring");
        await f.Runtime.TickAsync();
        Check(f.Deliveries.Count == beforeLeave + 1, "restore cannot replay claimed automatic notices");
    }
    private static async Task RealTestContent()
    {
        using var f = new Fixture();
        Check((await f.Runtime.TestAsync(() => true)).DeliveryState == "paused" && f.Deliveries.Count == 0,
            "missing calibration never invents a test boundary");
        var s = await f.Runtime.ReadAsync();
        f.Time.AdvanceTo(Origin.AddMinutes(90));
        await f.Runtime.TestAsync(() => true);
        var notice = f.Deliveries[^1];
        Check(notice.Test && notice.Config == s.Config && notice.Notices.Single() is { Opening: true, Kind: "beforeOpen" } &&
            notice.Notices[0].Boundary == Origin.AddMinutes(185), "closed-state test uses actual next opening, not synthetic five-minute closure");
        f.Time.AdvanceTo(Origin.AddMinutes(20));
        await f.Runtime.TestAsync(() => true);
        Check(f.Deliveries[^1].Notices.Single() is { Opening: false, Kind: "beforeClose" } &&
            f.Deliveries[^1].Notices[0].Boundary == Origin.AddMinutes(65), "open-state test uses actual close without premature clearance warning");
        f.Time.AdvanceTo(Origin.AddMinutes(62));
        await f.Runtime.TestAsync(() => true);
        Check(f.Deliveries[^1].Notices.Single().Kind == "leave" && f.Deliveries[^1].Notices[0].Boundary == Origin.AddMinutes(65),
            "only actual all-off phase previews the leave warning");
        s = await f.Runtime.SaveAsync(new(false, true, true, 5, false, 5, false, 5), s.Revision, () => true);
        f.Time.AdvanceTo(Origin.AddMinutes(20));
        await f.Runtime.TestAsync(() => true);
        Check(f.Deliveries[^1].Notices.Single().Opening && f.Deliveries[^1].Notices[0].Boundary == Origin.AddMinutes(185),
            "opening-only preference is preserved even while hangar is open");
        s = await f.Runtime.SaveAsync(new(false, false, false, 5, false, 5, true, 5), s.Revision, () => true);
        f.Time.AdvanceTo(Origin.AddMinutes(90));
        await f.Runtime.TestAsync(() => true);
        Check(!f.Deliveries[^1].Notices.Single().Opening && f.Deliveries[^1].Notices[0].Boundary == Origin.AddMinutes(250),
            "closing-only preference selects the real future close while currently closed");
        var count = f.Deliveries.Count;
        f.Time.AdvanceTo(Origin.AddHours(7));
        Check((await f.Runtime.TestAsync(() => true)).DeliveryState == "paused" && f.Deliveries.Count == count,
            "expired calibration never manufactures a successful test card");
    }
    private static async Task LegacyRestore()
    {
        using var f = new Fixture(); var s = await f.Runtime.ReadAsync();
        s = await f.Runtime.SaveAsync(new(true, false, false, 5, false, 5, true, 5, true, true), s.Revision, () => true);
        await f.Tick(Origin.AddMinutes(60).AddSeconds(-1)); await f.Tick(Origin.AddMinutes(60));
        f.Deliveries.Single().Mute!(); s = await f.Runtime.ReadAsync();
        Check(s.Monitoring is null && s.Plan!.MutedBoundary == Origin.AddMinutes(65), "legacy continuous suppression remains readable");
        s = await f.Runtime.MonitorAsync("restore", s.Revision, 0, false, () => true);
        Check(s.Monitoring is null && s.Plan!.MutedBoundary is null, "restore works for existing continuous settings without creating a session");
        await f.Tick(Origin.AddMinutes(60).AddSeconds(1));
        Check(f.Deliveries.Count == 1, "legacy restore does not replay past advance warning");
        await f.Tick(Origin.AddMinutes(65).AddSeconds(-1)); await f.Tick(Origin.AddMinutes(65));
        Check(f.Deliveries.Count == 2 && f.Deliveries[^1].Notices.Single().Kind == "close", "legacy restore allows only future rules");
    }
    private static async Task EnhancedMonitoring()
    {
        using var f = new Fixture();
        var s = await f.Runtime.ReadAsync();
        var leave = new ExecHangarReminders(false, false, false, 5, false, 5, true, 5, true, true);
        var preview = await f.Runtime.PreviewAsync(leave, 60, false);
        Check(preview.Plan is { State: "noEvent" } && preview.Plan.Outside?.Boundary == Origin.AddMinutes(65), "preview exposes target outside duration before starting");
        Check((await f.Runtime.ReadAsync()).Revision == s.Revision && !File.Exists(Path.Combine(f.Root, "unexpected")) && f.Deliveries.Count == 0,
            "preview does not save preferences, start monitoring or deliver");
        f.Time.AdvanceTo(Origin.AddMinutes(59));
        preview = await f.Runtime.PreviewAsync(leave, 60, true);
        Check(preview.Plan!.Next?.Due == Origin.AddMinutes(60), "preview uses authoritative upcoming warning time");
        s = await f.Runtime.SaveAsync(leave, s.Revision, () => true);
        s = await f.Runtime.MonitorAsync("start", s.Revision, 60, false, () => true);
        var id = s.Monitoring!.Id; var began = s.Monitoring.StartedAt; var until = s.Monitoring.EndsAt;
        await f.Tick(Origin.AddMinutes(60).AddSeconds(-1)); await f.Tick(Origin.AddMinutes(60));
        Check(f.Deliveries.Count == 1 && f.Deliveries[0].Notices.Select(n => n.Kind).Order().SequenceEqual(new[] { "beforeClose", "leave" }),
            "coincident closing and all-off reminders merge into one card");
        f.Deliveries[0].Mute!();
        s = await f.Runtime.ReadAsync();
        Check(s.Monitoring!.MutedBoundary == Origin.AddMinutes(65), "warning suppression belongs to closing event");
        s = await f.Runtime.MonitorAsync("addHour", s.Revision, 0, false, () => true);
        Check(s.Monitoring!.Id == id && s.Monitoring.StartedAt == began && s.Monitoring.EndsAt == until.AddHours(1) && s.Monitoring.MutedBoundary != null,
            "add hour preserves session identity, suppression and original start");
        s = await f.Runtime.MonitorAsync("restore", s.Revision, 0, false, () => true);
        await f.Tick(Origin.AddMinutes(60).AddSeconds(1));
        Check(s.Monitoring!.MutedBoundary == null && f.Deliveries.Count == 1, "restoring suppression never replays past warning");
        await f.Tick(Origin.AddMinutes(65).AddSeconds(-1)); await f.Tick(Origin.AddMinutes(65));
        Check(f.Deliveries.Count == 2 && f.Deliveries[^1].Notices.Single().Kind == "close", "restored future at-time notice is delivered");
        using (var restarted = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time)) {
            Check((await restarted.ReadAsync()).Monitoring!.Id == id, "extended session survives restart");
            await restarted.TickAsync(); Check(f.Deliveries.Count == 2, "restart preserves merged warning receipts");
        }
        var before = File.ReadAllBytes(Path.Combine(f.Root, "exec-hangar.v1.json"));
        var test = await f.Runtime.TestAsync(() => true);
        Check(f.Deliveries[^1].Test && f.Deliveries[^1].Mute == null && test.Revision == s.Revision &&
            File.ReadAllBytes(Path.Combine(f.Root, "exec-hangar.v1.json")).SequenceEqual(before), "sample notification has no real-monitoring writes or mute action");
        var count = f.Deliveries.Count;
        await Expect<OperationCanceledException>(() => f.Runtime.TestAsync(() => false));
        Check(f.Deliveries.Count == count, "stale test generation never delivers");
        s = await f.Runtime.MonitorAsync("start", s.Revision, 1440, false, () => true);
        await Expect<InvalidOperationException>(() => f.Runtime.MonitorAsync("addHour", s.Revision, 0, false, () => true));
        Check((await f.Runtime.ReadAsync()).Revision == s.Revision, "24-hour cap rejects extension without writes");
        var bridge = new ExecHangarBridgeDispatcher(f.Runtime, () => 9);
        var payload = new { schemaVersion = 1, durationMinutes = 1, onlyNext = true, enabled = false,
            onOpen = false, beforeOpen = false, beforeOpenMinutes = 5, beforeChange = false, beforeChangeMinutes = 5,
            beforeClose = false, beforeCloseMinutes = 5, onClose = false, leaveWarning = true };
        var request = BridgeEnvelope.Request("execHangar.preview", "preview", 9, payload);
        Check((await bridge.DispatchAsync(request)).Response.MessageType == BridgeMessageTypes.Response, "typed preview accepts leave-only drafts");
        Check((await f.Runtime.ReadAsync()).Revision == s.Revision, "bridge preview remains read-only");
        var warningOnly = leave with { BeforeClose = false, OnClose = false };
        f.Time.AdvanceTo(Origin.AddMinutes(248));
        s = await f.Runtime.SaveAsync(warningOnly, s.Revision, () => true);
        s = await f.Runtime.MonitorAsync("start", s.Revision, 10, true, () => true);
        await f.Runtime.TickAsync();
        Check(f.Deliveries[^1].Notices.Single().Kind == "leave", "leave-only start inside warning phase delivers immediately");
        f.Deliveries[^1].Mute!(); s = await f.Runtime.ReadAsync();
        s = await f.Runtime.MonitorAsync("restore", s.Revision, 0, false, () => true);
        Check(s.Monitoring!.Target == Origin.AddMinutes(250), "restoring next-event warning retains current closure target");
        await f.Tick(Origin.AddMinutes(248).AddSeconds(1));
        Check(f.Deliveries[^1].Notices.Single().Kind == "leave" && f.Deliveries.Count == count + 1,
            "restore does not replay immediate warning");
    }
    private static async Task Monitoring()
    {
        using var f = new Fixture();
        var s = await f.Runtime.ReadAsync();
        s = await f.Runtime.SaveAsync(new(true, false, false, 5, false, 5, true, 5, true), s.Revision, () => true);
        f.Time.AdvanceTo(Origin.AddMinutes(63));
        s = await f.Runtime.MonitorAsync("start", s.Revision, 1, true, () => true);
        Check(s.Plan is { Active: true, State: "noEvent", Next: null } && s.Plan.Outside!.Boundary == Origin.AddMinutes(65), "finite window excludes out-of-window target");
        await f.Runtime.TickAsync(); Check(f.Deliveries.Count == 0, "no immediate notice for boundary outside monitor interval");
        f.Time.AdvanceTo(Origin.AddMinutes(63).AddSeconds(30));
        s = await f.Runtime.MonitorAsync("extend", s.Revision, 0, false, () => true);
        Check(s.Monitoring!.EndsAt == Origin.AddMinutes(65), "extend ends at selected boundary");
        using (var restart = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time))
            Check((await restart.ReadAsync()).Monitoring?.EndsAt == Origin.AddMinutes(65), "pending extension at a later start time remains readable");
        await f.Runtime.TickAsync(); Check(f.Deliveries.Count == 1 && f.Deliveries[0].Notices.Single().Kind == "beforeClose", "start/extend inside lead delivers current card once");
        await f.Runtime.TickAsync(); Check(f.Deliveries.Count == 1, "immediate notice durably consumed");
        using (var restart = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time)) {
            Check((await restart.ReadAsync()).Monitoring?.EndsAt == Origin.AddMinutes(65), "finite monitoring persists with independent close rule");
            await restart.TickAsync(); Check(f.Deliveries.Count == 1, "restart cannot replay immediate alert");
        }
        await f.Tick(Origin.AddMinutes(64).AddSeconds(59));
        await f.Tick(Origin.AddMinutes(65).AddMilliseconds(150));
        Check(f.Deliveries.Count == 2 && f.Deliveries[1].Notices.Single().Kind == "close", "timer jitter still delivers exact boundary before finite/one-next completion");
        Check((await f.Runtime.ReadAsync()).Plan?.State == "complete", "only-next monitor completes automatically");
        await f.Tick(Origin.AddMinutes(66)); Check(f.Deliveries.Count == 2, "completed session stays silent");

        s = await f.Runtime.ReadAsync(); f.Time.AdvanceTo(Origin.AddMinutes(248));
        s = await f.Runtime.MonitorAsync("start", s.Revision, 10, false, () => true);
        await f.Runtime.TickAsync(); Check(f.Deliveries.Count == 3, "new explicit monitor accepts next upcoming closure");
        var card = f.Deliveries[^1]; card.Mute!();
        s = await f.Runtime.ReadAsync();
        Check(!card.IsCurrent() && s.Monitoring!.MutedBoundary == Origin.AddMinutes(250) && s.Reminders.OnClose, "card mute revokes this boundary and preserves future preferences");
        await f.Tick(Origin.AddMinutes(249).AddSeconds(59)); await f.Tick(Origin.AddMinutes(250));
        Check(f.Deliveries.Count == 3, "muted event at-time rule suppressed");
        f.Time.AdvanceTo(Origin.AddMinutes(259));
        Check((await f.Runtime.ReadAsync()).Plan?.State == "expired", "timed monitoring ends");
        using (var restart = new ExecHangarRuntime(f.Root, f.Client, f.Deliver, f.Time)) {
            Check((await restart.ReadAsync()).Plan is { Active: false, State: "expired" }, "restart does not reactivate expired watch");
        }
        var bridge = new ExecHangarBridgeDispatcher(f.Runtime, () => 9);
        var request = BridgeEnvelope.Request("execHangar.start", "start", 9,
            new { schemaVersion = 1, expectedRevision = s.Revision, durationMinutes = 60, onlyNext = false });
        Check((await bridge.DispatchAsync(request)).Response.MessageType == BridgeMessageTypes.Response, "finite accountless start bridge accepts typed command");
        Check((await bridge.DispatchAsync(request)).Response.Status == BridgeResponseStatuses.Error, "monitor revision conflict rejected");
        request = request with { Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, expectedRevision = 0, durationMinutes = 999999, onlyNext = false }) };
        Check((await bridge.DispatchAsync(request)).Response.Status == BridgeResponseStatuses.Error, "monitor duration bound enforced");
    }
    private static void ReminderAudio()
    {
        using var f = new Fixture();
        Directory.CreateDirectory(f.Root);
        var message = NotificationAudioTests.Wave();
        var operation = NotificationAudioTests.Wave(16);
        File.WriteAllBytes(Path.Combine(f.Root, "message.wav"), message);
        File.WriteAllBytes(Path.Combine(f.Root, "operation.wav"), operation);
        object Asset(string cue, string file, string tier, int priority, byte[] wave) => new {
            assetId = cue, cueId = cue, fileName = file, tier, priority,
            sha256 = Convert.ToHexString(SHA256.HashData(wave))
        };
        File.WriteAllText(Path.Combine(f.Root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new {
            schemaVersion = 1, assets = new[] {
                Asset("notify.soft", "message.wav", "approved", 320, message),
                Asset("notify.operation", "operation.wav", "candidate", 220, operation)
            }
        }));
        var settings = new NotificationAudioSettingsStore(f.Root);
        settings.Save(0, true, 0.4);
        var output = new AudioOutput(); var allowed = true;
        using var audio = new NotificationAudioBridgeDispatcher(f.Root, NotificationAudioCatalog.Load(f.Root),
            output, () => 1, time: f.Time, canPlaySocial: () => allowed);
        void AudioReason(string stage) {
            var last = File.ReadLines(Path.Combine(f.Root, "notification-delivery-diagnostics.log")).Last();
            Check(last.Contains(" ExecHangarAudio " + stage + " trace="), "hangar-specific audio diagnostic: " + stage);
        }
        Check(audio.TryPlayExecHangar(() => true) && output.Last!.SequenceEqual(NotificationWaveGain.Apply(operation, 0.4)),
            "hangar uses operation notification sound with playback volume, not message cue");
        AudioReason("NativeAccepted");
        Check(File.ReadLines(Path.Combine(f.Root, "notification-delivery-diagnostics.log")).Last().Contains("result=acceptedUnverified"),
            "native sound acceptance never claims audibility");
        Check(!audio.TryPlayExecHangar(() => true, () => true), "hangar retains global one-second sound throttle");
        AudioReason("Throttled");
        f.Time.AdvanceTo(Origin.AddSeconds(2)); allowed = false;
        Check(!audio.TryPlayExecHangar(() => true), "system quiet mode suppresses hangar audio");
        AudioReason("EnvironmentSuppressed");
        Check(audio.TryPlayExecHangar(() => true, () => true),
            "explicit hangar game/DND guard plays the operation cue independently of social DND");
        f.Time.AdvanceTo(Origin.AddSeconds(4));
        var checks = 0;
        Check(!audio.TryPlayExecHangar(() => true, () => ++checks == 1) && output.Plays == 2,
            "hangar environment is revalidated immediately before sound playback");
        AudioReason("EnvironmentSuppressed");
        Check(!audio.TryPlayExecHangar(() => false, () => true), "expired compact reminder cannot play audio");
        AudioReason("Stale");
        var freshnessChecks = 0;
        Check(!audio.TryPlayExecHangar(() => ++freshnessChecks == 1, () => true) && output.Plays == 2,
            "hangar freshness is revalidated immediately before sound playback");
        AudioReason("Stale");
        allowed = true; settings.Save(1, false, 0.4);
        Check(!audio.TryPlayExecHangar(() => true, () => true), "global audio switch suppresses hangar audio even in game/DND");
        AudioReason("ChannelDisabled");
        settings.Save(2, true, 0.4);
        output.Accept = false;
        Check(!audio.TryPlayExecHangar(() => true, () => true) && output.Plays == 3, "native audio rejection is retained");
        AudioReason("NativeRejected");
        output.Accept = true;
        output.Throw = true;
        Check(!audio.TryPlayExecHangar(() => true, () => true), "native output exception remains a local failure");
        AudioReason("Failed");
        output.Throw = false;
        File.Delete(Path.Combine(f.Root, "operation.wav"));
        Check(!audio.TryPlayExecHangar(() => true, () => true) && output.Plays == 3, "missing operation sound never falls back to message sound");
        AudioReason("CueUnavailable");
        using var noCatalog = new NotificationAudioBridgeDispatcher(f.Root, null, output, () => 1, time: f.Time);
        Check(!noCatalog.TryPlayExecHangar(() => true, () => true), "missing catalog cannot play a message substitute");
        AudioReason("CueUnavailable");
    }
    private sealed class AudioOutput : INotificationAudioOutput
    {
        internal byte[]? Last; internal int Plays; internal bool Accept = true, Throw;
        public bool TryPlay(byte[] wave) {
            if (Throw) throw new InvalidOperationException("fixture output unavailable");
            Last = wave; Plays++; return Accept;
        }
        public void Stop() { } public void Dispose() { }
    }
    private static async Task ChannelPolicy()
    {
        using var f = new Fixture(); using var sink = new Sink();
        using var notices = new NotificationSettingsBridgeDispatcher(f.Root, () => 1, desktop: sink);
        var delivery = new ExecHangarDelivery([new(Origin, Origin, "open", true)], () => true);
        Check(await notices.PresentExecHangarAsync(delivery, () => true, default) == "windowsDisabled" && sink.Notices.Count == 0, "global desktop switch honored");
        var save = BridgeEnvelope.Request("notificationSettings.save", "save", 1, new { schemaVersion = 1, expectedRevision = 0,
            inAppEnabled = true, position = "bottomRight", preview = "sourceOnly", windowsEnabled = true });
        Check((await notices.DispatchAsync(save)).Response.MessageType == BridgeMessageTypes.Response, "notification preference save");
        Check(await notices.PresentExecHangarAsync(delivery, () => false, default) == "suppressed" && sink.Notices.Count == 0, "quiet/unknown environment honored");
        Check(await notices.PresentExecHangarAsync(delivery, () => true, default) == "submitted" && sink.Notices.Single().ExecHangar != null, "typed forecast content, one card");
        Check(await notices.PresentExecHangarAsync(delivery with { IsCurrent = () => false }, () => true, default) == "expired", "disabled/expired callbacks revoked");
        await notices.PresentExecHangarAsync(delivery with { Notices = [new(Origin, Origin.AddMinutes(5), "leave", false)], Test = true }, () => true, default);
        Check(sink.Notices[^1].ExecHangar is { LeaveWarning: true, Test: true, Mute: null }, "leave test has explicit native content and no real suppression action");
    }
    private static async Task TestSuppressionFeedback()
    {
        using var f = new Fixture(); using var sink = new Sink();
        var reason = "doNotDisturb";
        using var notices = new NotificationSettingsBridgeDispatcher(f.Root, () => 1, desktop: sink,
            desktopSuppressionReason: () => reason);
        using var runtime = new ExecHangarRuntime(f.Root, f.Client,
            (delivery, token) => notices.PresentExecHangarAsync(delivery, () => false, token), f.Time);
        await runtime.ReadAsync();
        var result = await runtime.TestAsync(() => true);
        Check(result.DeliveryState == "doNotDisturb" && sink.Notices.Count == 0,
            "test feedback preserves actual do-not-disturb reason without sending a card");
        foreach (var state in new[] { "fullScreen", "inactiveDesktop", "quietTime", "systemBusy", "queueFull", "expired", "environmentUnknown" }) {
            reason = state;
            Check((await runtime.TestAsync(() => true)).DeliveryState == state && sink.Notices.Count == 0,
                "specific environment reason survives the complete test route: " + state);
        }
        reason = "unexpected-platform-reason";
        Check((await runtime.TestAsync(() => true)).DeliveryState == "suppressed", "unknown reasons retain safe generic feedback");
        var save = BridgeEnvelope.Request("notificationSettings.save", "save", 1, new { schemaVersion = 1, expectedRevision = 0,
            inAppEnabled = true, position = "bottomRight", preview = "sourceOnly", windowsEnabled = true });
        await notices.DispatchAsync(save);
        sink.Rejection = "doNotDisturb";
        Check(await notices.PresentExecHangarAsync(new([new(Origin, Origin, "leave", false)], () => true, Test: true), () => true, default) == "doNotDisturb",
            "native visual rejection reason preserved even when sound environment permits delivery");
    }
    private static async Task PublicClient()
    {
        const string calibration = "{\"code\":0,\"data\":{\"version\":\"test\",\"lastModified\":\"test\",\"sourceUrl\":\"https://example.org/\",\"initialOpenTime\":\"2026-09-16T13:05:05.639-06:00\",\"cycleDriftMs\":350,\"designOnlineMin\":65,\"designOfflineMin\":120,\"cycleNumberOffset\":1,\"stale\":false}}";
        var handler = new Handler(calibration);
        using var client = new ExecHangarConfigClient(new("https://example.org/"), handler);
        Check(!(await client.FetchAsync(default)).Stale && handler.Uri!.AbsolutePath == "/app-api/system/exec-hangar/config" && !handler.Authorized, "exact anonymous endpoint");
        handler.Body = calibration.Replace("350", "60001");
        await Expect<ArgumentException>(() => client.FetchAsync(default));
        handler.Body = new string(' ', 32769); await Expect<InvalidDataException>(() => client.FetchAsync(default));
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Expect<T>(Func<Task> action) where T : Exception {
        try { await action(); } catch (T) { return; } throw new InvalidOperationException("Expected " + typeof(T).Name);
    }
    private sealed class Clock : TimeProvider {
        private DateTimeOffset _now = Origin; private long _stamp;
        public override DateTimeOffset GetUtcNow() => _now;
        public override long GetTimestamp() => _stamp;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public void AdvanceTo(DateTimeOffset now) { _stamp += (now - _now).Ticks; _now = now; }
        public void JumpUtc(DateTimeOffset now) => _now = now;
    }
    private sealed class Client : IExecHangarConfigClient {
        internal bool Fail;
        internal ExecHangarConfig Config = new("test", "test", null, Origin, 0, 65, 120, 0);
        public Task<ExecHangarConfig> FetchAsync(CancellationToken token) => Fail ? Task.FromException<ExecHangarConfig>(new HttpRequestException()) : Task.FromResult(Config);
    }
    private sealed class Fixture : IDisposable {
        internal readonly string Root = Path.Combine(AppContext.BaseDirectory, "exec-fixtures-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new(); internal readonly Client Client = new();
        internal readonly List<ExecHangarDelivery> Deliveries = [];
        internal StarBridge.HostRuntime.Presence.GameProcessSession Game = new("notRunning");
        internal readonly ExecHangarRuntime Runtime;
        internal Fixture() => Runtime = new(Root, Client, Deliver, Time, () => Game);
        internal ValueTask<string> Deliver(ExecHangarDelivery notice, CancellationToken token) {
            Check(notice.IsCurrent(), "current delivery"); Deliveries.Add(notice); return ValueTask.FromResult("submitted");
        }
        internal async Task Tick(DateTimeOffset now) { Time.AdvanceTo(now); await Runtime.TickAsync(); }
        public void Dispose() {
            Runtime.Dispose();
            if (!Path.GetFullPath(Root).StartsWith(Path.GetFullPath(AppContext.BaseDirectory) + "exec-fixtures-", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Unexpected fixture directory.");
            if (Directory.Exists(Root)) Directory.Delete(Root, true);
        }
    }
    private sealed class Handler(string body) : HttpMessageHandler {
        internal string Body = body; internal Uri? Uri; internal bool Authorized;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Uri = request.RequestUri; Authorized = request.Headers.Authorization != null || request.Headers.Contains("Cookie");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Body, Encoding.UTF8, "application/json") });
        }
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        internal string? Rejection;
        public async ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notification, CancellationToken token) =>
            Rejection is {} reason ? new(false, reason) : new(await TryPresentAsync(notification, token), "submitted");
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token) { Notices.Add(notification); return ValueTask.FromResult(true); }
        public void Clear() { } public void Dispose() { }
    }
}
