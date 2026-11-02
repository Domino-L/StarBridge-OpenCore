using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    private static async Task SnapshotRaces()
    {
        foreach (int? missing in new int?[] { null, 0 })
        foreach (var definite in new[] { false, true })
        {
            using var f = new Fixture();
            int? observed = 1;
            PresenceVisibilityBridge? bridge = null;
            var positives = 0;
            using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) positives++;
                return Task.CompletedTask;
            }, startTimer: false, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g));
            using var local = new PresenceVisibilityBridge(new(f.Root), () => (f.Owner, 1L), p.ChangeVisibilityAsync,
                (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
            bridge = local;
            await p.ApplyAsync(f.Owner, 1, 1, default);
            observed = definite ? 3 : missing;
            var captured = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            using var release = new ManualResetEventSlim();
            local.SnapshotCaptured = () => { local.SnapshotCaptured = null; captured.TrySetResult(); release.Wait(TimeSpan.FromSeconds(3)); };
            var ticking = Task.Run(p.TickAsync);
            try {
                await captured.Task.WaitAsync(TimeSpan.FromSeconds(2));
                observed = definite ? missing : 1;
            } finally { release.Set(); }
            await ticking;
            Check(f.Store.IsPublicationPaused(f.Owner) == definite,
                "snapshot race must persist exactly the captured definite invisible observation");
            observed = 1;
            await p.TickAsync();
            Check(positives == (definite ? 1 : 2), "provisional visibility must recover; definite invisible must stay paused");
        }
    }

    private static async Task OnlineClearRecovery()
    {
        foreach (int? stale in new int?[] { 3, null, 0 })
        {
            using var f = new Fixture();
            int? observed = 1;
            var clearFails = false;
            var positives = 0;
            var clock = new SharingTestClock();
            PresenceVisibilityBridge? bridge = null;
            using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) positives++;
                else if (clearFails) throw new HttpRequestException();
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g),
                consumeExplicitOnlineResume: (o, g) => bridge!.ConsumeExplicitOnlineResume(o, g));
            var store = new PresenceVisibilityStore(f.Root);
            using var local = new PresenceVisibilityBridge(store, () => (f.Owner, 1L), p.ChangeVisibilityAsync,
                (_, _, mode, _) => Task.FromResult(mode), () => true, () => observed);
            bridge = local;
            await p.ApplyAsync(f.Owner, 1, 1, default);
            observed = 3; await p.TickAsync();
            observed = stale; clearFails = true;
            var result = await local.DispatchAsync(BridgeEnvelope.Request("presence.set", "online-clear-failure", 1,
                new { schemaVersion = 1, expectedRevision = store.Read().Revision, mode = "online" }, f.Owner));
            Check(result.Response.Error is null && f.Store.IsPublicationPaused(f.Owner) == (stale == 3) && p.ClearPending,
                "online authority success and pending clear must be stored separately");
            clearFails = false; observed = 1; clock.Advance(60);
            await p.TickAsync();
            Check(!p.ClearPending, "successful clear retry removes its obligation");
            await p.TickAsync();
            if (stale == 3)
            {
                Check(positives == 1 && f.Store.IsPublicationPaused(f.Owner), "definite 3 remains paused after clear retry");
                await p.ApplyAsync(f.Owner, 1, 1, default);
            }
            Check(positives == 2 && p.Status.State == "applied", "retry preserves automatic recovery for null/0 and explicit recovery for 3");
        }
    }

    private static async Task ReceiptIsolation()
    {
        foreach (var mutation in new[] { "none", "owner", "generation", "revision" })
        {
            using var f = new Fixture();
            var current = (Owner: f.Owner, Generation: 1L);
            var store = new PresenceVisibilityStore(f.Root);
            using var bridge = new PresenceVisibilityBridge(store, () => current,
                async (_, _, change, ct) => { await change(ct); return true; },
                (_, _, mode, _) => Task.FromResult(mode), () => true, () => 1);
            await bridge.DispatchAsync(BridgeEnvelope.Request("presence.set", "receipt-scope", 1,
                new { schemaVersion = 1, expectedRevision = store.Read().Revision, mode = "online" }, f.Owner));
            switch (mutation) {
                case "owner": current = (f.Owner with { Subject = "other" }, 1); break;
                case "generation": current = (f.Owner, 2); break;
                case "revision": store.Save(PlayerPresenceVisibilityMode.InGame, store.Read().Revision, () => { }); break;
            }
            Check(bridge.ConsumeExplicitOnlineResume(f.Owner, 1) == (mutation == "none"), "online receipt isolation: " + mutation);
            Check(!bridge.ConsumeExplicitOnlineResume(f.Owner, 1), "online receipt must be single-use");
        }
    }

    private static async Task BodyAdmission()
    {
        foreach (var revoke in new[] { false, true })
        {
            using var f = new Fixture();
            using var handler = new BodyHandler();
            using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
            using var p = new PrivacyPublication(f.Store, () => f.Input, (input, body, ct) =>
                writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, admission: input.PositiveAdmission), startTimer: false);
            var sending = p.ApplyAsync(f.Owner, 1, 1, default);
            await handler.Reading.Task.WaitAsync(TimeSpan.FromSeconds(3));
            // The handler already returned status + headers. HttpClient is now
            // buffering HttpContent. No StopAsync participates in this close.
            var closing = revoke
                ? f.Store.SetPublicationConsentAsync(f.Owner, 1, false, () => true)
                : f.Store.SaveAsync(f.Owner, 1, Guid.NewGuid().ToString("N"), f.Settings with { PublicationEnabled = false }, () => true);
            bool waited;
            try { waited = await Task.WhenAny(closing, Task.Delay(80)) != closing; }
            finally { handler.Release.TrySetResult(); }
            await Task.WhenAll(sending, closing).WaitAsync(TimeSpan.FromSeconds(3));
            Check(waited && !f.Store.HasPublicationConsent(f.Owner), "Save/revoke escaped the response-body admission lock");
            await p.TickAsync(); await p.TickAsync();
            Check(handler.Positives == 1 && p.Status.State == "withdrawn", "no positive sends after independent close");
        }
    }
    private sealed class BodyHandler : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Reading = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Positives;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Method == HttpMethod.Get) return new(HttpStatusCode.OK) { Content = new StringContent("{\"fleetCode\":null}") };
            var body = await request.Content!.ReadAsStringAsync(ct);
            using var json = JsonDocument.Parse(body);
            var positive = json.RootElement.GetProperty("online").GetBoolean();
            if (positive) Positives++;
            var response = new HttpResponseMessage(HttpStatusCode.OK) {
                Content = positive ? new HeldContent(body, Reading, Release, ct) : new StringContent(body) };
            response.Headers.Add("X-StarBridge-Realtime-Version", "1");
            return response;
        }
    }
    private sealed class HeldContent(string body, TaskCompletionSource reading, TaskCompletionSource release, CancellationToken ct) : HttpContent
    {
        protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        {
            reading.TrySetResult();
            await release.Task.WaitAsync(ct);
            await stream.WriteAsync(Encoding.UTF8.GetBytes(body), ct);
        }
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }

    private static async Task LongRetry()
    {
        foreach (var code in new[] { "forbidden", "response_invalid", "unavailable", "business", "protocol" })
        {
            using var f = new Fixture();
            var clock = new SharingTestClock();
            var fail = true;
            var attempts = 0;
            var expectedCode = code switch { "business" => "unavailable", "protocol" => "response_invalid", _ => code };
            using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) {
                    attempts++;
                    if (fail) throw code switch {
                        "business" => new StarBridge.HostRuntime.Auth.ScmApiUnavailableException("Synthetic business failure"),
                        "protocol" => new StarBridge.HostRuntime.Auth.ScmApiProtocolException("Synthetic protocol failure"),
                        _ => new AccountBridgeHostException("privacy_publication." + code)
                    };
                }
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock);
            await p.ApplyAsync(f.Owner, 1, 1, default);
            foreach (var seconds in new[] { 60, 300, 900, 900 }) {
                Check(p.Status.State == "reconnecting" && p.Status.ErrorCode == "privacy_publication." + expectedCode &&
                    f.Store.HasPublicationConsent(f.Owner), "long retry must retain consent and its specific cause");
                var before = attempts;
                clock.Advance(seconds - 1); await p.TickAsync();
                Check(attempts == before, "input wake bypassed long retry");
                clock.Advance(1); await p.TickAsync();
                Check(attempts == before + 1, "long retry failed to run at its deadline");
            }
            fail = false; clock.Advance(900); await p.TickAsync();
            Check(p.Status.State == "applied", "non-auth failure must recover without manual apply");
        }
    }

    private static async Task CallerCancellation()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        using var cancelled = new CancellationTokenSource();
        var first = true;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, body, token) => {
            if (body.GetProperty("online").GetBoolean() && first) {
                first = false; cancelled.Cancel(); token.ThrowIfCancellationRequested();
            }
            return Task.CompletedTask;
        }, startTimer: false, timeProvider: clock);
        await p.ApplyAsync(f.Owner, 1, 1, cancelled.Token);
        Check(f.Store.HasPublicationConsent(f.Owner) && p.Status.State == "reconnecting", "caller cancellation cannot revoke recovery");
        clock.Advance(60); await p.TickAsync(); await p.TickAsync();
        Check(p.Status.State == "applied", "page cancellation must recover without apply");
    }

    private static async Task AdmissionTimeout()
    {
        using var f = new Fixture();
        f.Store.PositiveAdmission.WaitTimeout = TimeSpan.FromMilliseconds(50);
        using (await f.Store.PositiveAdmission.EnterAsync(default)) {
            try { await f.Store.SaveAsync(f.Owner, 1, Guid.NewGuid().ToString("N"), f.Settings, () => true); throw new Exception("expected lock timeout"); }
            catch (TimeoutException) { }
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            try { await f.Store.SetPublicationConsentAsync(f.Owner, 1, false, () => true, cancelled.Token); throw new Exception("expected cancellation"); }
            catch (OperationCanceledException) { }
        }
        Check(f.Store.Read(f.Owner).Revision == 1, "timed out/cancelled wait cannot commit");
        await f.Store.SetPublicationConsentAsync(f.Owner, 1, true, () => true);
        Check(f.Store.HasPublicationConsent(f.Owner), "later admission must still succeed");
        var clock = new SharingTestClock();
        using var p = new PrivacyPublication(f.Store, () => f.Input, async (input, body, token) => {
            if (!body.GetProperty("online").GetBoolean()) return;
            using var lease = await input.PositiveAdmission!.EnterAsync(token);
            input.RequirePositiveAdmission!();
        }, startTimer: false, timeProvider: clock);
        using (await f.Store.PositiveAdmission.EnterAsync(default)) await p.TickAsync();
        Check(p.Status.State == "reconnecting" && p.Status.ErrorCode == "privacy_publication.timeout",
            "writer admission timeout must be a temporary failure");
        clock.Advance(5); await p.TickAsync();
        Check(p.Status.State == "applied", "writer admission timeout cannot block later sharing");
        var visibility = PlayerPresenceVisibilityMode.Invisible;
        using var pausing = new PrivacyPublication(f.Store, () => f.Input, (_, _, _) => Task.CompletedTask,
            startTimer: false, visibility: () => visibility, timeProvider: clock);
        using (await f.Store.PositiveAdmission.EnterAsync(default)) await pausing.TickAsync();
        visibility = PlayerPresenceVisibilityMode.Online;
        clock.Advance(5); await pausing.TickAsync();
        Check(f.Store.IsPublicationPaused(f.Owner), "admission timeout must not forget a captured definite invisible pause");
    }

    private static async Task VisibilityDeadline()
    {
        using var f = new Fixture();
        var clock = new SharingTestClock();
        PresenceVisibilityBridge? bridge = null;
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, _, _) => Task.CompletedTask,
            startTimer: false, timeProvider: clock, visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(),
            confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g)) {
            VisibilityTimeout = TimeSpan.FromMilliseconds(80) };
        var release = new TaskCompletionSource<PlayerPresenceVisibilityMode>(TaskCreationOptions.RunContinuationsAsynchronously);
        var store = new PresenceVisibilityStore(f.Root);
        using var local = new PresenceVisibilityBridge(store, () => (f.Owner, 1L), p.ChangeVisibilityAsync,
            (_, _, _, _) => release.Task, () => true, () => 1);
        bridge = local;
        await p.ApplyAsync(f.Owner, 1, 1, default);
        var revision = store.Read().Revision;
        await local.DispatchAsync(BridgeEnvelope.Request("presence.set", "visibility-timeout", 1,
            new { schemaVersion = 1, expectedRevision = revision, mode = "invisible" }, f.Owner)).AsTask().WaitAsync(TimeSpan.FromSeconds(2));
        release.TrySetResult(PlayerPresenceVisibilityMode.Invisible);
        await Task.Delay(30);
        Check(store.Read().Revision == revision, "a callback completing after deadline cannot commit");
        clock.Advance(60); await p.TickAsync(); await p.TickAsync();
        Check(p.Status.State == "applied", "visibility timeout cannot block the session");
    }
}
