using System.Net;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class SharingStatusDetailTests
{
    internal static async Task Run()
    {
        await ScopedWithdrawalRoute();
        await Backoff();
        var root = Directory.CreateTempSubdirectory("starbridge-sharing-detail-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "sharing.invalid", "fixture");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
            using (var inactive = new PrivacyPublication(store, () => input, (_, _, _) => Task.CompletedTask, startTimer: false))
            {
                Require(inactive.StatusFor(owner).ErrorCode == "privacy_publication.consent_required",
                    "Saved enabled policy without consent must explain confirmation, not imply network retry.");
            }
            foreach (var (http, reason) in new[] {
                (HttpStatusCode.RequestTimeout, "timeout"), (HttpStatusCode.TooManyRequests, "rate_limited"),
                (HttpStatusCode.ServiceUnavailable, "server_error"), (HttpStatusCode.BadGateway, "server_error") })
            {
                using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), new Handler(http));
                using var publisher = new PrivacyPublication(store, () => input,
                    (_, payload, token) => writer.SendAsync("fixture", payload, token), startTimer: false);
                await publisher.ApplyAsync(owner, 1, 1, default);
                Require(publisher.Status.State == "reconnecting" &&
                    publisher.Status.ErrorCode == "privacy_publication." + reason,
                    "HTTP failure must retain a safe, specific reason: " + http);
                Require(store.HasPublicationConsent(owner), "Transient HTTP failure must not revoke confirmed consent.");
            }
        }
        finally { Directory.Delete(root, true); }
    }
    private static async Task ScopedWithdrawalRoute()
    {
        var clock = new SharingTestClock();
        var root = Directory.CreateTempSubdirectory("starbridge-scoped-withdraw-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "sharing.invalid", "scoped");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"),
                LocalPrivacySettings.EditorDefaults with { Communities = [] }, () => true);
            var routes = new List<string>();
            var handler = new ScopedHandler(routes);
            using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
            using var publisher = new PrivacyPublication(store, () => input,
                (_, payload, token) => writer.SendAsync("synthetic-only", payload, token), startTimer: false, timeProvider: clock);
            await publisher.ApplyAsync(owner, 1, 1, default);
            Require(publisher.Status.State == "applied", "Scoped synthetic apply must succeed.");
            routes.Clear();
            handler.RejectReads = true;
            await publisher.StopAsync(default, explicitRequest: true);
            Require(publisher.Status.State == "withdrawn" && !routes.Contains("/api/players/realtime"),
                "Scoped withdrawal must remain on the SCM-capable scoped route; actual: " +
                publisher.Status.State + "; routes=" + string.Join(",", routes));
            Require(!routes.Contains("/api/privacy/community-scopes"),
                "An all-audience clear must not depend on an organization read before authenticated withdrawal.");
            handler.RejectReads = false;
            await publisher.ApplyAsync(owner, 1, 1, default);
            handler.RejectWrites = true;
            routes.Clear();
            await publisher.StopAsync(default, explicitRequest: true);
            Require(publisher.Status.State == "withdrawalPending" &&
                publisher.Status.ErrorCode == "privacy_publication.forbidden" &&
                routes.SequenceEqual(new[] { "/api/players/realtime-scoped" }),
                "A rejected clear must remain unconfirmed without retrying through directory or legacy routes.");
            handler.RejectWrites = false;
            clock.Advance(60);
            await publisher.TickAsync();
            Require(publisher.Status.State == "withdrawn", "Scoped clear retries only after its backoff.");
            routes.Clear();
            handler.FailNextOnline = true;
            await publisher.ApplyAsync(owner, 1, 1, default);
            Require(publisher.Status.State == "reconnecting" &&
                routes.Count(path => path == "/api/players/realtime-scoped") == 2 &&
                !routes.Contains("/api/players/realtime"),
                "Failed scoped apply must withdraw on the same route and retain authorized recovery.");
            Require(handler.LastWriteWasClear, "Failure cleanup must remove every audience and live field.");
            await publisher.ApplyAsync(owner, 1, 1, default);
            var policy = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
            File.WriteAllText(policy, "invalid synthetic policy");
            routes.Clear();
            await publisher.TickAsync();
            Require(publisher.Status.State == "failed" && handler.LastWriteWasClear &&
                routes.Contains("/api/players/realtime-scoped") && !routes.Contains("/api/players/realtime"),
                "Unreadable scoped policy must still clear on the same account's remembered wire contract.");
        }
        finally { Directory.Delete(root, true); }
    }
    private sealed class ScopedHandler(List<string> routes) : HttpMessageHandler
    {
        internal bool FailNextOnline { get; set; }
        internal bool RejectReads { get; set; }
        internal bool RejectWrites { get; set; }
        internal bool LastWriteWasClear { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            routes.Add(path);
            if (path == "/api/privacy/community-scopes")
            {
                if (RejectReads) return new(HttpStatusCode.ServiceUnavailable);
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":2,\"primaryFleetCode\":null,\"communities\":[]}") };
            }
            if (path != "/api/players/realtime-scoped") return new(HttpStatusCode.Unauthorized);
            if (RejectWrites) return new(HttpStatusCode.Forbidden);
            var body = await request.Content!.ReadAsStringAsync(token);
            using var document = JsonDocument.Parse(body);
            var state = document.RootElement.GetProperty("state");
            if (state.GetProperty("online").GetBoolean() && FailNextOnline)
            {
                FailNextOnline = false;
                throw new OperationCanceledException("Synthetic deadline");
            }
            LastWriteWasClear = !state.GetProperty("online").GetBoolean() &&
                document.RootElement.GetProperty("communities").GetArrayLength() == 0 &&
                state.GetProperty("roomSharedStateFields").GetInt32() == 0 &&
                state.GetProperty("fleetSharedStateFields").GetInt32() == 0;
            var response = new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(body)
            };
            response.Headers.Add("X-StarBridge-Realtime-Version", "3");
            return response;
        }
    }
    private static async Task Backoff()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-sharing-backoff-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "sharing.invalid", "backoff");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false));
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var clock = new SharingTestClock();
            var fail = false; var attempts = 0; var clears = 0; string? version = null;
            var prioritized = false;
            using var publisher = new PrivacyPublication(store, () => input, (publicationInput, payload, _) => {
                prioritized = publicationInput.PrioritizeNetwork;
                if (!payload.GetProperty("online").GetBoolean()) { clears++; return Task.CompletedTask; }
                attempts++; version = payload.GetProperty("gameVersion").GetString();
                if (fail) throw new HttpRequestException();
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock);
            await publisher.ApplyAsync(owner, 1, 1, default);
            Require(prioritized, "Explicit apply requests may yield a read-only lookup.");
            fail = true;
            await publisher.TickAsync();
            Require(!prioritized, "Periodic heartbeats must not repeatedly interrupt privacy reads.");
            foreach (var delay in new[] { 5, 10, 20, 40, 60, 60 })
            {
                var previous = attempts;
                for (var i = 0; i < 10; i++) await publisher.TickAsync();
                clock.Advance(delay - 1);
                await publisher.TickAsync();
                Require(attempts == previous, "Input wakes must not bypass recovery backoff.");
                clock.Advance(1);
                await publisher.TickAsync();
                Require(attempts == previous + 1, "Recovery must retry at the bounded deadline.");
                Require(publisher.Status.ErrorCode == "privacy_publication.network_unavailable", "Network evidence must not become a server error.");
            }
            Require(clears == 0, "Unchanged failed heartbeats must not insert offline writes.");
            fail = false;
            input = input with { GameVersion = "EPTU" };
            await publisher.ApplyAsync(owner, 1, 1, default);
            Require(publisher.Status.State == "applied" && version == "EPTU", "Manual retry bypasses backoff and uses current evidence.");
            fail = true;
            await publisher.TickAsync();
            var before = attempts;
            clock.Advance(5);
            await publisher.TickAsync();
            Require(attempts == before + 1, "Successful apply resets backoff.");
            await publisher.StopAsync(default, explicitRequest: true);
            Require(clears == 1 && !store.HasPublicationConsent(owner), "Explicit stop bypasses backoff and revokes consent.");
            clock.Advance(120);
            await publisher.TickAsync();
            Require(attempts == before + 1, "Stopped sharing cannot resume automatically.");
            fail = false;
            await publisher.ApplyAsync(owner, 1, 1, default);
            fail = true;
            await publisher.TickAsync();
            var clearBefore = clears;
            store.Save(owner, 1, Guid.NewGuid().ToString("N"), settings with {
                Fleet = new(PlayerSharedStateFields.None, false, true, [])
            }, () => true);
            await publisher.TickAsync();
            Require(clears == clearBefore + 1 && publisher.Status.AppliedRevision == 2,
                "A narrowed policy revision must not wait for transport backoff.");
        }
        finally { Directory.Delete(root, true); }
    }
    private sealed class Handler(HttpStatusCode status) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(status));
    }
    private static void Require(bool condition, string message)
    { if (!condition) throw new Exception(message); }
}

internal sealed class SharingTestClock : TimeProvider
{
    private DateTimeOffset _now = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset GetUtcNow() => _now;
    internal void Advance(int seconds) => _now = _now.AddSeconds(seconds);
}
