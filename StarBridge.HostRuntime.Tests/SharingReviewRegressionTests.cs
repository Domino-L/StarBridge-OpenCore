using System.Net;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task Run()
    {
        var failures = new List<string>();
        foreach (var (name, test) in new (string, Func<Task>)[] {
            ("membership wait revalidates positive admission", PendingPositive),
            ("switch withdrawal retries", SwitchWithdrawal),
            ("never consented remains inactive", NeverConsented),
            ("remote invisible survives observation and restart", RemotePause),
            ("temporary suspension then remote invisible", SuspensionThenPause),
            ("online receipt precedes observation", OnlineReceipt),
            ("final admission and close share a boundary", FinalAdmission),
            ("all realtime writers serialize close", AllWriterAdmissions),
            ("three unauthorized responses wait for ready identity", Unauthorized),
            ("withdrawal refresh failure asks for sign-in", WithdrawalIdentity),
            ("one visibility snapshot covers both observation races", SnapshotRaces),
            ("online confirmation survives failed clear", OnlineClearRecovery),
            ("online receipt rejects foreign scopes", ReceiptIsolation),
            ("Save and revoke wait for response body without Stop", BodyAdmission),
            ("long retry keeps consent and cause", LongRetry),
            ("caller cancellation retains recovery", CallerCancellation),
            ("admission timeout and cancellation release waiters", AdmissionTimeout),
            ("visibility callback has a total deadline", VisibilityDeadline),
        }) {
            try { await test(); Console.WriteLine("PASS M04b " + name); }
            catch (Exception e) { failures.Add(name + ": " + e.Message); Console.WriteLine("FAIL M04b " + failures[^1]); }
        }
        if (failures.Count != 0) throw new Exception(string.Join("; ", failures));
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("sharing-review-").FullName;
        internal readonly BridgeAccountContext Owner = new("test", "sharing.invalid", "fixture");
        internal PrivacyPublicationInput Input;
        internal readonly LocalPrivacyStore Store;
        internal readonly LocalPrivacySettings Settings = new(true,
            new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false));
        internal Fixture()
        {
            Input = new(Owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            Store = new(Root);
            Store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        }
        public void Dispose() => Directory.Delete(Root, true);
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    private static async Task PendingPositive()
    {
        foreach (var change in new[] { "disabled", "revoked", "revision", "invisible" })
        {
            using var f = new Fixture();
            using var handler = new HeldMembership();
            using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
            var visibility = PlayerPresenceVisibilityMode.Online;
            using var p = new PrivacyPublication(f.Store, () => f.Input,
                (input, body, ct) => writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission),
                startTimer: false, visibility: () => visibility);
            var pending = p.ApplyAsync(f.Owner, 1, 1, default);
            await handler.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
            try
            {
                switch (change)
                {
                    case "disabled": f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"),
                        f.Settings with { PublicationEnabled = false }, () => true); break;
                    case "revoked": f.Store.SetPublicationConsent(f.Owner, 1, false, () => true); break;
                    case "revision": f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"),
                        f.Settings with { Fleet = new(PlayerSharedStateFields.None, false, false, []) }, () => true); break;
                    case "invisible": visibility = PlayerPresenceVisibilityMode.Invisible; break;
                }
            }
            finally { handler.Release.TrySetResult(); }
            await pending;
            Check(handler.PositivePosts == 0, "stale positive POST escaped after " + change);
            if (change != "revision")
                Check(p.Status.State == "withdrawn", "discarded positive must finish manual withdrawal: " + change);
            else
            {
                await p.TickAsync();
                Check(p.Status.State == "applied", "a changed policy must be rebuilt without a permanent failure");
            }
        }
    }
    private sealed class HeldMembership : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int PositivePosts;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Method == HttpMethod.Get)
            {
                Entered.TrySetResult(); await Release.Task.WaitAsync(ct);
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"fleetCode\":null}") };
            }
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var json = JsonDocument.Parse(body);
            if (json.RootElement.GetProperty("online").GetBoolean()) PositivePosts++;
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) };
            response.Headers.Add("X-StarBridge-Realtime-Version", "1");
            return response;
        }
    }

    private static async Task Unauthorized()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        var attempts = 0;
        var fail = true;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
            if (body.GetProperty("online").GetBoolean())
            {
                attempts++;
                if (fail) throw new HttpRequestException(null, null, HttpStatusCode.Unauthorized);
            }
            return Task.CompletedTask;
        }, startTimer: false, timeProvider: clock);
        await p.ApplyAsync(f.Owner, 1, 1, default);
        for (var i = 0; i < 2; i++) { clock.Advance(60); await p.TickAsync(); }
        Check(attempts == 3 && p.Status.State == "identityRequired" &&
            p.Status.ErrorCode == "privacy_publication.identity_unavailable" && f.Store.HasPublicationConsent(f.Owner),
            "three 401s must require sign-in while retaining consent");
        clock.Advance(120); await p.TickAsync();
        Check(attempts == 3, "identityRequired cannot retry positive writes on timer");
        fail = false; f.Input = f.Input with { Generation = 2 }; p.Invalidate();
        await p.TickAsync();
        Check(attempts == 4 && p.Status.State == "applied", "ready account automatically resumes retained consent");
    }

    private static async Task SwitchWithdrawal()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        var clearFails = false;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, payload, _) => {
            if (clearFails && !payload.GetProperty("online").GetBoolean()) throw new HttpRequestException();
            return Task.CompletedTask;
        }, startTimer: false, timeProvider: clock);
        await p.ApplyAsync(f.Owner, 1, 1, default);
        f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"), f.Settings with { PublicationEnabled = false }, () => true);
        clearFails = true;
        await p.TickAsync();
        Check(p.Status.State == "withdrawalPending", "failed switch clear must remain withdrawalPending: " + p.Status.State);
        clearFails = false;
        clock.Advance(60);
        await p.TickAsync();
        Check(p.Status.State == "withdrawn", "successful switch clear retry must become withdrawn");
    }

    private static async Task WithdrawalIdentity()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        var fail = false;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
            if (fail && !body.GetProperty("online").GetBoolean())
                throw new AccountBridgeHostException("privacy_publication.identity_unavailable");
            return Task.CompletedTask;
        }, startTimer: false, timeProvider: clock);
        await p.ApplyAsync(f.Owner, 1, 1, default);
        fail = true;
        await p.StopAsync(default, explicitRequest: true);
        Check(p.Status.State == "identityRequired" && p.Status.ErrorCode == "privacy_publication.identity_unavailable",
            "exhausted withdrawal refresh must also ask for sign-in");
        fail = false;
        clock.Advance(60);
        await p.TickAsync();
        Check(p.Status.State == "withdrawn" && !f.Store.HasPublicationConsent(f.Owner),
            "manual clear success must not retain a positive publication failure");
    }

    private static async Task NeverConsented()
    {
        using var f = new Fixture();
        var sends = 0;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, _, _) => { sends++; return Task.CompletedTask; },
            startTimer: false, visibility: () => PlayerPresenceVisibilityMode.Invisible,
            visibilitySnapshot: () => new(f.Owner, 1, "", null, PlayerPresenceVisibilityMode.Invisible, "privacy_publication.network_unavailable"));
        await p.ChangeVisibilityAsync(f.Owner, 1, _ => Task.CompletedTask, default);
        Check(p.Status.State == "inactive" && sends == 0, "no consent or clear obligation must stay inactive");
    }

    private static async Task RemotePause()
    {
        foreach (int? missing in new int?[] { null, 0 })
        foreach (var explicitApply in new[] { false, true })
        {
            using var f = new Fixture();
            int? observed = 1;
            var positives = 0;
            PresenceVisibilityBridge? bridge = null;
            PrivacyPublication Create(LocalPrivacyStore store) => new(store, () => f.Input, (_, payload, _) => {
                if (payload.GetProperty("online").GetBoolean()) positives++;
                return Task.CompletedTask;
            }, startTimer: false, visibility: () => bridge!.PublicationMode,
                visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g),
                consumeExplicitOnlineResume: (o, g) => bridge!.ConsumeExplicitOnlineResume(o, g));
            var visibilityStore = new PresenceVisibilityStore(f.Root);
            using (var p = Create(f.Store))
            {
                bridge = new(visibilityStore, () => (f.Owner, f.Input.Generation), p.ChangeVisibilityAsync,
                    (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
                await p.ApplyAsync(f.Owner, 1, 1, default);
                Check(positives == 1, "fixture starts online");
                observed = 3;
                await p.TickAsync();
                Check(p.Status.State == "withdrawn", "explicit remote invisibility clears");
                observed = missing; await p.TickAsync();
                observed = 1; await p.TickAsync();
                Check(positives == 1, "ordinary online observation must not release remote pause");
                p.Invalidate(); await p.TickAsync();
                Check(positives == 1, "Invalidate must preserve remote pause");
                bridge.Dispose();
            }
            f.Input = f.Input with { Generation = 2 };
            using var restarted = Create(new LocalPrivacyStore(f.Root));
            using var freshBridge = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 2L), restarted.ChangeVisibilityAsync,
                (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
            bridge = freshBridge;
            await restarted.TickAsync();
            Check(positives == 1, "cold start must preserve remote pause");
            if (explicitApply) await restarted.ApplyAsync(f.Owner, 2, 1, default);
            else await freshBridge.DispatchAsync(BridgeEnvelope.Request("presence.set", "explicit-online", 2,
                new { schemaVersion = 1, expectedRevision = visibilityStore.Read().Revision, mode = "online" }, f.Owner));
            Check(positives == 2 && restarted.Status.State == "applied", "explicit client action must resume");
        }
    }

    private static async Task SuspensionThenPause()
    {
        foreach (int? missing in new int?[] { null, 0 })
        foreach (var restart in new[] { "tick", "invalidate", "cold" })
        {
            using var f = new Fixture();
            int? observed = 1;
            var positives = 0;
            PresenceVisibilityBridge? bridge = null;
            PrivacyPublication Create(LocalPrivacyStore store) => new(store, () => f.Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) positives++;
                return Task.CompletedTask;
            }, startTimer: false, visibility: () => bridge!.PublicationMode,
                visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g),
                consumeExplicitOnlineResume: (o, g) => bridge!.ConsumeExplicitOnlineResume(o, g));
            using (var p = Create(f.Store))
            {
                bridge = new(new(f.Root), () => (f.Owner, 1L), p.ChangeVisibilityAsync,
                    (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
                await p.ApplyAsync(f.Owner, 1, 1, default);
                observed = missing; await p.TickAsync();
                observed = 3; await p.TickAsync();
                Check(f.Store.IsPublicationPaused(f.Owner), "missing -> 3 must persist pause before early return");
                observed = 1;
                if (restart == "invalidate") p.Invalidate();
                if (restart != "cold") await p.TickAsync();
                bridge.Dispose();
            }
            if (restart == "cold")
            {
                f.Input = f.Input with { Generation = 2 };
                using var p = Create(new(f.Root));
                using var fresh = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 2L), p.ChangeVisibilityAsync,
                    (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
                bridge = fresh;
                await p.TickAsync();
            }
            Check(positives == 1, "missing -> 3 -> 1 resumed after " + restart);
        }
    }

    private static async Task OnlineReceipt()
    {
        foreach (int? stale in new int?[] { 3, null, 0 })
        {
            using var f = new Fixture();
            int? observed = 1;
            var positives = 0;
            PresenceVisibilityBridge? bridge = null;
            using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) positives++;
                return Task.CompletedTask;
            }, startTimer: false, visibility: () => bridge!.PublicationMode,
                visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g),
                consumeExplicitOnlineResume: (o, g) => bridge!.ConsumeExplicitOnlineResume(o, g));
            var visibility = new PresenceVisibilityStore(f.Root);
            using var local = new PresenceVisibilityBridge(visibility, () => (f.Owner, f.Input.Generation), p.ChangeVisibilityAsync,
                (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
            bridge = local;
            await p.ApplyAsync(f.Owner, 1, 1, default);
            observed = 3; await p.TickAsync();
            observed = stale;
            var result = await local.DispatchAsync(BridgeEnvelope.Request("presence.set", "online-before-observation", 1,
                new { schemaVersion = 1, expectedRevision = visibility.Read().Revision, mode = "online" }, f.Owner));
            Check(result.Response.Error is null, "online receipt should succeed");
            Check(f.Store.IsPublicationPaused(f.Owner) == (stale == 3), "only a new definite 3 may latch pause after an online action");
            await p.TickAsync();
            Check(positives == 1 && f.Store.IsPublicationPaused(f.Owner) == (stale == 3), "null/0 remain provisional; definite 3 remains paused");
            observed = 1; await p.TickAsync();
            if (stale == 3)
            {
                Check(positives == 1 && f.Store.IsPublicationPaused(f.Owner), "online cannot erase a captured 3");
                await p.ApplyAsync(f.Owner, 1, 1, default);
            }
            Check(positives == 2 && p.Status.State == "applied", "provisional absence resumes automatically; captured 3 requires explicit apply");
            observed = 3; await p.TickAsync();
            Check(f.Store.IsPublicationPaused(f.Owner), "a later new invisible observation must pause again");
        }
    }

    private static async Task FinalAdmission()
    {
        using var f = new Fixture();
        using var handler = new HeldMembership();
        handler.Release.TrySetResult();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        var admitted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var release = new ManualResetEventSlim();
        using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, () => {
                input.RequirePositiveAdmission?.Invoke();
                if (body.GetProperty("online").GetBoolean()) { admitted.TrySetResult(); release.Wait(ct); }
            }, admission: input.PositiveAdmission), startTimer: false);
        var send = Task.Run(() => p.ApplyAsync(f.Owner, 1, 1, default));
        await admitted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var closing = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var close = Task.Run(() => {
            closing.TrySetResult();
            f.Store.Save(f.Owner, 1, Guid.NewGuid().ToString("N"), f.Settings with { PublicationEnabled = false }, () => true);
        });
        bool waited;
        try {
            await closing.Task;
            waited = await Task.WhenAny(close, Task.Delay(150)) != close;
        }
        finally { release.Set(); }
        await Task.WhenAll(send, close).WaitAsync(TimeSpan.FromSeconds(3));
        Check(waited, "close completed between final admission and POST");
        var count = handler.PositivePosts;
        await p.TickAsync(); await p.TickAsync();
        Check(handler.PositivePosts == count && p.Status.State == "withdrawn", "close must clear and prevent later POSTs");
    }
}
