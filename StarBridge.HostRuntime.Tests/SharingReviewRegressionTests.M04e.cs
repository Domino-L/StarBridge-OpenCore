using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04e()
    {
        var failures = new List<string>();
        var tests = new List<(string Name, Func<Task> Run)> {
            ("final admission retains invisible snapshot through null", () => FinalInvisibleSnapshot(null)),
            ("final admission retains invisible snapshot through zero", () => FinalInvisibleSnapshot(0)),
            ("failed compensating clears back off independently", FailedClearBackoff),
            ("cold OAuth restore uses credential rejection for HTTP 401", AccountSessionRestoreTests.RefreshStatusRejection),
        };
        foreach (var outcome in new[] { "refresh401Empty", "refresh401Html", "refresh401InvalidJson", "refresh2xxInvalidJson" })
            tests.Add((outcome, () => AccountSessionRestoreTests.PrivacyRefresh(outcome)));
        foreach (var (name, run) in tests) {
            try { await run(); Console.WriteLine("PASS M04e " + name); }
            catch (Exception error) { failures.Add(name); Console.WriteLine("FAIL M04e " + name + ": " + error.Message); }
        }
        Console.WriteLine($"M04e cases: {tests.Count - failures.Count} passed, {failures.Count} failed");
        if (failures.Count > 0) throw new Exception(string.Join("; ", failures));
    }

    private static async Task FinalInvisibleSnapshot(int? missing)
    {
        using var f = new Fixture();
        using var handler = new M04eHandler();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        int? observed = 1;
        PresenceVisibilityBridge? bridge = null;
        using (var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
            startTimer: false, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
            confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g)))
        using (var local = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 1L), p.ChangeVisibilityAsync,
            (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed))
        {
            bridge = local;
            await p.ApplyAsync(f.Owner, 1, 1, default);
            Check(handler.Positives == 1, "initial real writer publication must succeed");
            var snapshots = 0;
            local.SnapshotCaptured = () => {
                if (++snapshots == 1) observed = 3; // tick captured online
                else if (snapshots == 2) observed = missing; // final admission captured invisible
            };
            await p.TickAsync();
            Check(snapshots == 2, "rejection handling must not re-sample final admission visibility");
            Check(f.Store.IsPublicationPaused(f.Owner), "captured definite invisible must persist pause");
            Check(handler.Positives == 1, "real writer must reject the second positive request");
            local.SnapshotCaptured = null;
            observed = 1;
            await p.TickAsync(); await p.TickAsync();
            Check(handler.Positives == 1 && p.Status.State == "withdrawn", "later online cannot resume paused sharing");
        }
        using var restarted = new PrivacyPublication(new LocalPrivacyStore(f.Root), () => f.Input,
            (input, body, ct) => writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission,
                admission: input.PositiveAdmission), startTimer: false);
        await restarted.TickAsync();
        Check(handler.Positives == 1, "persistent pause must survive publisher restart");
    }

    private static async Task FailedClearBackoff()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        using var handler = new M04eHandler { Reject = true };
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
            startTimer: false, timeProvider: clock);
        await p.ApplyAsync(f.Owner, 1, 1, default);
        Check(handler.Positives == 1 && handler.Clears == 1 && p.ClearPending, "403 must immediately attempt first clear");
        foreach (var seconds in new[] { 60, 300, 900, 900 }) {
            var before = handler.Clears;
            for (var elapsed = 0; elapsed < seconds - 1; elapsed++) {
                clock.Advance(1);
                await p.TickAsync(); await p.TickAsync(); // repeated input wakes
            }
            Check(handler.Clears == before, "input wakes bypassed clear backoff of " + seconds);
            clock.Advance(1); await p.TickAsync();
            Check(handler.Clears == before + 1, "clear missing at deadline of " + seconds);
            Check(handler.Positives == 1 && p.ClearPending, "pending clear must block positive retries");
        }
        handler.Reject = false;
        clock.Advance(900); await p.TickAsync(); await p.TickAsync();
        Check(!p.ClearPending && p.Status.State == "applied" && handler.Positives == 2,
            "successful clear must release retained consent for recovery");
        handler.Reject = true;
        await p.TickAsync();
        var freshClear = handler.Clears;
        clock.Advance(59); await p.TickAsync();
        Check(handler.Clears == freshClear, "new clear failure starts at one minute");
        clock.Advance(1); await p.TickAsync();
        Check(handler.Clears == freshClear + 1, "successful clear resets clear backoff");
    }

    private sealed class M04eHandler : HttpMessageHandler
    {
        internal int Positives, Clears;
        internal bool Reject;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"fleetCode\":null}") };
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var json = JsonDocument.Parse(body);
            if (json.RootElement.GetProperty("online").GetBoolean()) Positives++;
            else Clears++;
            var response = new HttpResponseMessage(Reject ? HttpStatusCode.Forbidden : HttpStatusCode.OK) {
                Content = new StringContent(body) };
            response.Headers.Add("X-StarBridge-Realtime-Version", "1");
            return response;
        }
    }
}
