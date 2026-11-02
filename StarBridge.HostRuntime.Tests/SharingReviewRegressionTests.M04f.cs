using System.Net;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04f()
    {
        var failures = new List<string>();
        var tests = new List<(string Name, Func<Task> Run)> {
            ("heartbeat failure observes invisible before null", () => HeartbeatInvisible(null)),
            ("heartbeat failure observes invisible before zero", () => HeartbeatInvisible(0)),
            ("heartbeat pause write timeout retains obligation", () => HeartbeatInvisible(null, failPersistence: true)),
            ("visibility architecture rejects discarded or unreviewed reads", VisibilityReadArchitecture),
            ("apply cannot forget invisible observed during consent commit", () => ExplicitResumeObservationRace(false)),
            ("online cannot forget invisible observed during pause reset", () => ExplicitResumeObservationRace(true)),
        };
        foreach (var point in new[] { "apply", "tick", "change", "bridgeMode", "bridgeSnapshot", "bridgeConfirm", "bridgeDispatch" })
            tests.Add((point + " persists captured invisible", () => SnapshotReadPoint(point)));
        foreach (var point in new[] { "ordinary", "community", "officialConsent", "official", "officialAfterReceipt", "officialAfterConsent" })
            tests.Add((point + " writer persists captured invisible", () => WriterReadPoint(point)));
        foreach (var (name, run) in tests) {
            try { await run(); Console.WriteLine("PASS M04f " + name); }
            catch (Exception error) { failures.Add(name); Console.WriteLine("FAIL M04f " + name + ": " + error.Message); }
        }
        Console.WriteLine($"M04f cases: {tests.Count - failures.Count} passed, {failures.Count} failed");
        if (failures.Count > 0) throw new Exception(string.Join("; ", failures));
    }

    private static async Task HeartbeatInvisible(int? missing, bool failPersistence = false)
    {
        using var f = new Fixture();
        int? observed = 1;
        using var handler = new M04fHandler();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        PresenceVisibilityBridge? bridge = null;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
            startTimer: false, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
            confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g));
        using var local = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 1L), p.ChangeVisibilityAsync,
            (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
        bridge = local;
        IDisposable? heldAdmission = null;
        f.Store.PositiveAdmission.WaitTimeout = TimeSpan.FromMilliseconds(40);
        await p.ApplyAsync(f.Owner, 1, 1, default);
        Check(handler.Positives == 1, "initial real writer must publish");
        handler.FailPositive = () => {
            observed = 3;
            local.SnapshotCaptured = () => {
                observed = missing; local.SnapshotCaptured = null;
                if (failPersistence) heldAdmission = f.Store.PositiveAdmission.EnterAsync(default).GetAwaiter().GetResult();
            };
        };
        try {
            await p.TickAsync();
            if (failPersistence) {
                Check(!f.Store.IsPublicationPaused(f.Owner), "held admission must prevent immediate persistence");
                var fields = typeof(PrivacyPublication).GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
                Check(fields.Single(x => x.Name == "_pendingPause").GetValue(p) is not null, "failed persistence must retain pending pause");
                Check(fields.Single(x => x.Name == "_recovery").GetValue(p) is null, "failed persistence must clear recovery");
            }
        } finally { heldAdmission?.Dispose(); }
        if (failPersistence) await p.TickAsync();
        Check(handler.Positives == 2, "heartbeat must reach real HTTP handler and fail there");
        Check(f.Store.IsPublicationPaused(f.Owner), "network exception recheck must persist its captured 3");
        Check(p.Status.State == "withdrawn", "invisible must clear recovery intent");
        handler.FailPositive = null;
        await p.TickAsync();
        observed = 1;
        await p.TickAsync(); await p.TickAsync();
        Check(handler.Positives == 2, "null/0 then online must not resume positive sends");
        using var restarted = new PrivacyPublication(new(f.Root), () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
            startTimer: false);
        await restarted.TickAsync();
        Check(handler.Positives == 2, "pause must survive publisher and store reconstruction");
    }

    private static async Task SnapshotReadPoint(string point)
    {
        using var f = new Fixture();
        int? observed = 1;
        using var handler = new M04fHandler();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        PresenceVisibilityBridge? bridge = null;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
            startTimer: false, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(wakePublication: false));
        using var local = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 1L), p.ChangeVisibilityAsync,
            (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed,
            observeVisibility: p.ObserveVisibility);
        bridge = local;
        local.ConfirmObservedModeForExplicitSharing(f.Owner, 1);
        if (point != "apply") await p.ApplyAsync(f.Owner, 1, 1, default);
        var before = handler.Positives;
        observed = 3;
        local.SnapshotCaptured = () => { observed = null; local.SnapshotCaptured = null; };
        switch (point) {
            case "apply": await p.ApplyAsync(f.Owner, 1, 1, default); break;
            case "tick": await p.TickAsync(); break;
            case "change": await p.ChangeVisibilityAsync(f.Owner, 1, _ => Task.CompletedTask, default); break;
            case "bridgeMode": Check(local.PublicationMode == PlayerPresenceVisibilityMode.Invisible, "mode projection"); break;
            case "bridgeSnapshot": Check(local.ReadPublicationSnapshot().Observation == 3, "snapshot projection"); break;
            case "bridgeConfirm": local.ConfirmObservedModeForExplicitSharing(f.Owner, 1); observed = null; break;
            case "bridgeDispatch":
                var reply = await local.DispatchAsync(BridgeEnvelope.Request("presence.read", "m04f-read", 1,
                    new { schemaVersion = 1 }, f.Owner));
                Check(reply.Response.Payload.GetProperty("realtimeStatus").GetInt32() == 3, "UI response retains captured observation");
                break;
        }
        local.SnapshotCaptured = null;
        // Also waits for independent bridge wakeups to finish under the same gate.
        await p.ChangeVisibilityAsync(f.Owner, 1, _ => Task.CompletedTask, default);
        Check(new LocalPrivacyStore(f.Root).IsPublicationPaused(f.Owner), point + " must persist the first 3 through null");
        observed = 1;
        await p.TickAsync(); await p.TickAsync();
        Check(handler.Positives == before, point + " must not resume on later online");
    }

    private static async Task WriterReadPoint(string point)
    {
        using var f = new Fixture();
        var route = point is "officialAfterReceipt" ? "official" : point is "officialAfterConsent" ? "officialConsent" : point;
        using var handler = new AdmissionHandler(route);
        handler.Release.TrySetResult();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        var settings = route == "ordinary" ? f.Settings : f.Settings with {
            Fleet = new(PlayerSharedStateFields.None, false, false, []),
            Communities = route == "community" ? [new("FIXTURE", AdmissionHandler.Joined,
                PlayerSharedStateFields.Presence, false, true, [])] : [],
            OfficialFleet = route.StartsWith("official", StringComparison.Ordinal) ? handler.Choice : null
        };
        f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"), settings, () => true);
        f.Input = f.Input with { AppPresenceConfirmed = true };
        var reads = 0;
        var target = point is "officialAfterReceipt" or "officialAfterConsent" ? 3 : 2;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission,
                allowOfficialPositive: true, admission: input.PositiveAdmission), startTimer: false,
            visibilitySnapshot: () => {
                var invisible = ++reads == target;
                return new(f.Owner, 1, "fixture", invisible ? 3 : 1,
                    invisible ? PlayerPresenceVisibilityMode.Invisible : PlayerPresenceVisibilityMode.Online, null);
            });
        await p.ApplyAsync(f.Owner, 1, 2, default);
        Check(reads == target, point + " must reach exactly the selected check, without re-sampling rejection");
        Check(f.Store.IsPublicationPaused(f.Owner), point + " must persist writer observation");
        var writes = handler.PositiveWrites;
        Check(writes == (target == 3 ? 1 : 0), point + " must reject the selected positive write/check");
        await p.TickAsync(); await p.TickAsync();
        Check(handler.PositiveWrites == writes && handler.Clears > 0, point + " must clear and never resume");
    }

    private static async Task ExplicitResumeObservationRace(bool online)
    {
        using var f = new Fixture();
        int? observed = 1;
        var positives = 0;
        var blockResume = false;
        IDisposable? lease = null;
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
            if (body.GetProperty("online").GetBoolean()) positives++;
            return Task.CompletedTask;
        }, startTimer: false, visibilitySnapshot: () => new(f.Owner, 1, "fixture", observed,
            observed == 1 ? PlayerPresenceVisibilityMode.Online : PlayerPresenceVisibilityMode.Invisible,
            observed is null ? "privacy_publication.network_unavailable" : null),
            consumeExplicitOnlineResume: (_, _) => {
                if (blockResume) {
                    lease = f.Store.PositiveAdmission.EnterAsync(default).GetAwaiter().GetResult();
                    entered.TrySetResult();
                }
                return true;
            });
        await p.ApplyAsync(f.Owner, 1, 1, default);
        observed = 3; await p.TickAsync();
        Check(f.Store.IsPublicationPaused(f.Owner), "seed durable pause");
        observed = 1;
        Task resume;
        if (online) {
            blockResume = true;
            resume = p.ChangeVisibilityAsync(f.Owner, 1, _ => Task.CompletedTask, default);
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        } else {
            lease = await f.Store.PositiveAdmission.EnterAsync(default);
            resume = p.ApplyAsync(f.Owner, 1, 1, default);
        }
        try {
            Check(!resume.IsCompleted, "explicit resume must be waiting for admission");
            p.ObserveVisibility(new(f.Owner, 1, "fixture", 3, PlayerPresenceVisibilityMode.Invisible, null));
            observed = null;
        } finally { lease?.Dispose(); }
        await resume.WaitAsync(TimeSpan.FromSeconds(3));
        Check(f.Store.IsPublicationPaused(f.Owner), "new invisible observation cannot be erased by an older explicit resume");
        observed = 1;
        await p.TickAsync(); await p.TickAsync();
        Check(positives == 1, "concurrent invisible observation must block later positives");
    }

    private sealed class M04fHandler : HttpMessageHandler
    {
        internal int Positives, Clears;
        internal Action? FailPositive;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"fleetCode\":null}") };
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var json = JsonDocument.Parse(body);
            if (json.RootElement.GetProperty("online").GetBoolean()) {
                Positives++;
                if (FailPositive is { } fail) { fail(); throw new HttpRequestException("Synthetic network failure"); }
            } else Clears++;
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) };
            response.Headers.Add("X-StarBridge-Realtime-Version", "1");
            return response;
        }
    }
}
