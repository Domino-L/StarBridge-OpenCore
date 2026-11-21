using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class AnnouncementPersistenceTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "f3-owner");
    private static readonly DateTimeOffset Day = new(2026, 11, 4, 12, 0, 0, TimeSpan.Zero);
    private static int _checks;
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }
    private sealed class Clock : TimeProvider {
        internal DateTimeOffset Now = Day;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Now.UtcTicks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }
    private sealed class Handler(Clock clock, bool communities) : HttpMessageHandler {
        internal int Requests;
        internal string? Id;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Requests++;
            if (request.Method != HttpMethod.Get) throw new Exception("Unexpected fixture write");
            var path = request.RequestUri!.AbsolutePath;
            if (path.EndsWith("/chat/channels")) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            var code = path.StartsWith("/api/official-fleets/") ? "OFFICIALFLEET:7" :
                request.RequestUri.Query.Contains("fleetCode=B") ? "B" : "A";
            object body = path switch {
                "/api/fleets/notification-sources" => new { schemaVersion = 1, serverTime = clock.Now,
                    sources = (communities ? new[] { "A", "B" } : []).Select(c => new { code = c, name = c, joinedAt = Day.AddDays(-1),
                        managementAvailable = false, tasks = Array.Empty<object>(), chat = new { sequence = 0, createdAt = (string?)null,
                            incoming = false, unread = 0, callsign = "", text = "" } }).ToArray() },
                "/api/official-fleets/context" => new { schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = code,
                    name = "Fixture", chatAvailable = true, canManageAnnouncements = false },
                "/api/fleets/announcements" or "/api/official-fleets/announcements" => new {
                    schemaVersion = 1, membershipModelVersion = 2, fleetCode = code, revision = 1, refreshedAt = clock.Now,
                    offset = 0, next = (int?)null, totalHistoryCount = 0, history = Array.Empty<object>(),
                    current = Id == null ? null : new { announcement = new { id = Id, fleetCode = code, state = "Published", revision = 1,
                        publishedAt = clock.Now, updatedAt = clock.Now } } },
                _ => throw new Exception("Unexpected fixture route: " + path)
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }
    private sealed class Reader(CommunityClient client) : ICommunityNotificationReader {
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
            client.ReadScmNotificationsWithOfficialAsync("synthetic", JsonSerializer.Serialize(owner) + ":" + generation, () => { }, token);
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) {
            Notices.Add(notice); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    private static async Task EnableDesktop(NotificationSettingsBridgeDispatcher settings, long generation) {
        var result = await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "f3-desktop", generation,
            new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, windowsEnabled = true, position = "bottomRight", preview = "fullContent" }));
        Check(result.Response.Status == "ok", "Isolated desktop fixture setup succeeds.");
    }
    private static void Rules(string root, bool? enabled) {
        var store = new NotificationPolicyStore(root);
        store.Save(Owner, store.Read(Owner).Revision, Guid.NewGuid().ToString("N"),
            new[] { NotificationPolicyStore.Organization("A", Day.AddDays(-1)), NotificationPolicyStore.Organization("B", Day.AddDays(-1)),
                NotificationPolicyStore.OfficialFleet("officialFleet:7") }.Select(key => new NotificationPolicyRule(key, NotificationSourceMode.Normal) {
                    TypeRules = enabled is null ? null : [new("announcement", enabled.Value ? "enabled" : "disabled")] }).ToArray(), () => true, extended: true);
    }
    internal static async Task ColdStart(string root) {
        Directory.CreateDirectory(root);
        var pids = new List<int>();
        foreach (var phase in new[] { "baseline", "recovery" }) {
            var host = Environment.ProcessPath!;
            var start = new ProcessStartInfo(host) { UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true };
            // `dotnet Tests.dll` needs the assembly path; the Tests.exe apphost must not get it, or the
            // worker sees an unknown argument list and runs the whole suite (which spawns again).
            if (string.Equals(Path.GetFileNameWithoutExtension(host), "dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(typeof(AnnouncementPersistenceTests).Assembly.Location);
            start.ArgumentList.Add("--cx-announce-cold-worker"); start.ArgumentList.Add(root); start.ArgumentList.Add(phase);
            using var child = Process.Start(start) ?? throw new IOException("Cold-start worker unavailable");
            try {
                pids.Add(child.Id);
                File.WriteAllText(Path.Combine(root, "child-pids.json"), JsonSerializer.Serialize(pids));
                var output = child.StandardOutput.ReadToEndAsync(); var error = child.StandardError.ReadToEndAsync();
                // The worker does one small fixed job; this bound only stops a hang, it does not race the machine.
                using var hang = new CancellationTokenSource(TimeSpan.FromMinutes(5));
                await child.WaitForExitAsync(hang.Token);
                Check(child.ExitCode == 0, "Real cold process " + phase + ": " + await output + await error);
            } finally {
                // A failed or timed-out check must never leave the worker holding the test bin directory.
                if (!child.HasExited) {
                    try { child.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                    child.WaitForExit(30_000);
                }
            }
        }
        Check(pids.Distinct().Count() == 2, "Baseline and recovery use distinct process IDs.");
    }
    internal static async Task<int> ColdWorker(string root, string phase) {
        if (!Path.GetFullPath(root).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) +
            Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return 97;
        try {
            var recovery = phase == "recovery";
            var clock = new Clock { Now = recovery ? Day.AddDays(1) : Day };
            using var handler = new Handler(clock, false) { Id = recovery ? "offline" : null };
            using var client = new CommunityClient(new("https://relay.invalid"), handler, clock);
            var reader = new Reader(client); var sink = new Sink();
            var generation = recovery ? 27 : 1; // A new session scope must not renew membership.
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => generation, () => true, desktop: sink, time: clock);
            if (!recovery) { await EnableDesktop(settings, generation); Rules(root, null); }
            using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, generation), settings.PresentCommunityAsync,
                clock, announcements: settings.CreateAnnouncementObserver());
            await runtime.TickAsync();
            Check(recovery ? sink.Notices is [{ Community.AnnouncementSummaryCount: 1 }] : sink.Notices.Count == 0,
                "A fresh client/observer/process resumes the same official-fleet baseline and summarizes offline publications.");
            if (recovery) {
                var reads = handler.Requests;
                Check(await sink.Notices[0].CanPresentAsync(default) && handler.Requests == reads, "Cold summary output uses local validity only.");
                await runtime.TickAsync();
                Check(sink.Notices.Count == 1, "Restarted tombstones prevent duplicate output.");
            }
            return 0;
        } catch (Exception e) { Console.Error.WriteLine(e); return 1; }
    }
    internal static async Task Run() {
        _checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-announce-f3-" + Guid.NewGuid().ToString("N"));
        try {
            await RequestCounts(root);
            Memberships(Path.Combine(root, "memberships"));
        } finally {
            if (!Path.GetFullPath(root).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) +
                Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
        Console.WriteLine($"PASS CX-ANNOUNCE-F3: {_checks} assertions, 0 failed");
    }
    private static async Task RequestCounts(string root) {
        var clock = new Clock(); using var handler = new Handler(clock, true);
        using var client = new CommunityClient(new("https://relay.invalid"), handler, clock);
        var reader = new Reader(client); var sink = new Sink(); var submitted = 0;
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock,
            activationEvent: (g, p) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, p));
        await EnableDesktop(settings, 1); Rules(root, null);
        using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, 1), async (notice, ct) => {
            submitted++; await settings.PresentCommunityAsync(notice, ct);
        }, clock, announcements: settings.CreateAnnouncementObserver());
        await runtime.TickAsync(); var normalReads = handler.Requests;
        Check(normalReads == 7 && sink.Notices.Count == 0, "Empty cycle reads directory, three pages, official context twice, and chat once.");
        clock.Now = clock.Now.AddSeconds(1); handler.Id = "new";
        await runtime.TickAsync();
        Check(handler.Requests == 2 * normalReads && sink.Notices.Count == 3 && submitted == 3,
            "Two communities and the official fleet publish together: the cycle still makes exactly seven fake HTTP requests.");
        var reads = handler.Requests;
        foreach (var notice in sink.Notices) {
            Check(await notice.CanPresentAsync(default), "Actual Show/dequeue validity is local.");
            Check(await notice.CanPresentAsync(default), "Hidden-card recovery uses the same local check.");
        }
        Check(handler.Requests == reads, "Repeated native presentation and hidden-card recovery make no network reads.");
        var clicked = sink.Notices[0]; clicked.Activated!();
        var result = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "f3-click", 1,
            new { schemaVersion = 1, activationId = clicked.Id.ToString("N") }))).Response;
        Check(handler.Requests == reads + normalReads && result.Payload.GetProperty("destination").GetString() == "communityAnnouncements",
            "Only user activation performs a fresh authorized read.");
        Rules(root, false); clock.Now = clock.Now.AddSeconds(1); handler.Id = "disabled-new";
        reads = handler.Requests; await runtime.TickAsync();
        Check(handler.Requests == reads + normalReads && submitted == 3, "Disabled announcement rows consume IDs before any output queue; polling frequency is unchanged.");
        Rules(root, true); clock.Now = clock.Now.AddSeconds(1); await runtime.TickAsync();
        Check(submitted == 3, "Reenabling a row never replays suppressed publications.");
    }
    private static void Memberships(string root) {
        var store = new AnnouncementObservationStore(root); var clock = new Clock();
        CommunityNotificationFeed Page(int second, string id) => new(Day.AddSeconds(second), [new("fixture", "A", null, false, null, false, [],
            NotificationPolicyStore.OfficialFleet("officialFleet:7"), SourceKind: OrganizationNotificationSourceKind.OfficialFleet,
            Announcements: new(Day.AddSeconds(second), [new(id, true, Day.AddSeconds(second))]),
            AnnouncementSource: "officialFleet:7", AnnouncementIdentity: "officialFleet:7")]);
        var other = Owner with { Subject = "other" };
        new AnnouncementNotificationObserver(store, clock).Observe(other, 1, Page(0, "other-old"), () => true);
        var observer = new AnnouncementNotificationObserver(store, clock);
        observer.Observe(Owner, 1, Page(0, "old"), () => true);
        observer.BindOwner(other);
        Check(new AnnouncementNotificationObserver(new(root), clock).Observe(other, 2, Page(60, "other-return"), () => true).Count == 0,
            "A live switch to an account with a baseline from an older process starts quietly.");
        observer.BindOwner(Owner);
        observer.ObserveOfficialMembership(Owner, "officialFleet:8", () => true);
        observer.ObserveOfficialMembership(Owner, "officialFleet:7", () => true);
        var beforeDeparture = store.ReadSnapshot(AnnouncementObservationStore.Owner(Owner)).Slots[AnnouncementObservationStore.Slot("", true)].Epoch;
        observer.ObserveOfficialMembership(Owner, null, () => true);
        observer.ObserveOfficialMembership(Owner, "officialFleet:7", () => true);
        Check(store.ReadSnapshot(AnnouncementObservationStore.Owner(Owner)).Slots[AnnouncementObservationStore.Slot("", true)].Epoch == beforeDeparture + 1,
            "An observed departure advances exactly once; rejoining that retired membership does not advance it again.");
        Check(new AnnouncementNotificationObserver(new(root), clock).Observe(Owner, 20, Page(3600, "offline"), () => true).Count == 0,
            "A-to-B-to-A observed between polls remains a quiet new generation even after another process starts.");
        observer.BindOwner(Owner with { Subject = "other" }); observer.BindOwner(Owner);
        Check(new AnnouncementNotificationObserver(new(root), clock).Observe(Owner, 21, Page(7200, "account-return"), () => true).Count == 0,
            "An observed account switch and return retires the prior generation durably.");
        File.WriteAllText(store.PathFor(AnnouncementObservationStore.Owner(Owner)), "broken");
        observer = new(new(root), clock);
        Check(observer.Observe(Owner, 22, Page(10800, "corrupt-baseline"), () => true).Count == 0,
            "Corrupt generations cannot produce a summary; recovery builds a quiet atomic baseline.");
        Check(new AnnouncementNotificationObserver(new(root), clock).Observe(Owner, 23, Page(14400, "after-corruption"), () => true)
            is [{ AnnouncementSummaryCount: 1 }], "Only the baseline committed after recovery may authorize later catch-up.");
        observer = new(new(root), clock);
        observer.Observe(Owner, 23, Page(14400, "after-corruption"), () => true);
        File.WriteAllText(store.PathFor(AnnouncementObservationStore.Owner(Owner)), "broken");
        Check(observer.Observe(Owner, 23, Page(14401, "continuous-corruption"), () => true).Count == 0,
            "Corruption also clears the in-memory continuous baseline before consuming the recovery page.");
    }
}
