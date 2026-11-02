using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class OfficialFleetCommunicationBridgeTests
{
    internal static async Task Run()
    {
        using var handler = new Handler();
        using var communication = new CommunityClient(new("https://relay.example.test/"), handler);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["organizations.read"]);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
            new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null, initialSession: session, initialGeneration: 1,
            communities: communication);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!;
        var opened = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.communication", "official-open", 1,
            new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "open" }, owner));
        Check(opened.Response.Status == "ok" && opened.Response.Payload.GetProperty("chatAvailable").GetBoolean(), "actual dispatcher opens scoped communication");
        var reference = opened.Response.Payload.GetProperty("targetRef").GetString();
        Check(reference?.Length == 32 && !opened.Response.Payload.TryGetProperty("fleetCode", out _), "Host hides service namespace");
        Check(!opened.Response.Payload.GetProperty("activityAvailable").GetBoolean(), "old Relay context explicitly disables activity support");
        var calls = handler.Calls;
        foreach (var body in new object[] {
            new { sourceRef = "officialFleet:7", action = "open" },
            new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "manageAnnouncements", targetRef = reference },
            new { schemaVersion = 1, sourceRef = "officialFleet:8", action = "chat", targetRef = reference },
            new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "open", targetRef = reference } }) {
            var denied = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.communication", Guid.NewGuid().ToString("N"), 1, body, owner));
            Check(denied.Response.Status != "ok", "unsupported action, mismatched source or extra payload denied");
        }
        Check(handler.Calls == calls, "invalid requests never reach Relay");
        object waitBody = new { schemaVersion = 1, sourceRef = "officialFleet:7", instance = "", version = -1 };
        var waited = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.wait", "official-wait", 1, waitBody, owner));
        Check(waited.Response.Status == "ok" && waited.Response.Payload.GetProperty("sourceRef").GetString() == "officialFleet:7",
            "actual Host dispatcher accepts source-bound official wait outside ordinary writes");
        Check(BridgeRequestPolicy.IsActivityWait("officialFleet.wait"), "official wait uses the existing bounded pipe wait lane");
        calls = handler.Calls;
        var invalidWait = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.wait", "invalid-wait", 1,
            new { schemaVersion = 1, sourceRef = "officialFleet:7", instance = "", version = -1, targetRef = reference }, owner));
        Check(invalidWait.Response.Status != "ok" && handler.Calls == calls, "strict wait rejects extra fields before HTTP");
        handler.BadWaitSource = true;
        var wrongWait = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.wait", "wrong-wait-source", 1, waitBody, owner));
        Check(wrongWait.Response.Status != "ok", "mismatched service wait source cannot publish a hint");
        handler.BadWaitSource = false;
        handler.HoldWait = true;
        var pendingWait = dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.wait", "held-wait", 1, waitBody, owner));
        await handler.WaitStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var duplicateWait = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.wait", "second-wait", 1, waitBody, owner));
        Check(duplicateWait.Response.Error?.Code == "bridge.backpressure", "one existing bounded slot per official wait command");
        var cancelled = await dispatcher.DispatchAsync(BridgeEnvelope.Request("bridge.cancel", "cancel-wait", 1,
            new { targetCorrelationId = "held-wait" }));
        Check(cancelled.Response.Payload.GetProperty("cancelled").GetBoolean(), "existing out-of-band cancellation reaches official wait");
        Check((await pendingWait).Response.Status == "cancelled", "cancelled wait never publishes late success");
        handler.HoldWait = false;
        handler.Hold = true;
        var late = host.OfficialFleetCommunicationAsync(owner, JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sourceRef = "officialFleet:7", action = "open" }), default);
        await handler.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        host.Dispose(); handler.Release.SetResult();
        var stale = false;
        try { await late; }
        catch (Exception error) when (error is AccountBridgeHostException or BridgeStaleGenerationException) { stale = true; }
        Check(stale, "disposed account cannot publish a late communication context");
    }
    private sealed class Vault : ITokenVault {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class Handler : HttpMessageHandler {
        internal int Calls;
        internal bool Hold;
        internal bool HoldWait, BadWaitSource;
        internal TaskCompletionSource WaitStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously), Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Calls++;
            if (request.RequestUri?.AbsolutePath == "/api/official-fleets/activity") {
                Check(request.Headers.Authorization?.Parameter == "synthetic-access", "official wait uses current SCM bearer");
                if (HoldWait) { WaitStarted.TrySetResult(); await Task.Delay(Timeout.Infinite, token); }
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    sourceRef = BadWaitSource ? "officialFleet:8" : "officialFleet:7", instanceId = new string('a', 32),
                    version = 1, serverTime = DateTimeOffset.UtcNow }) };
            }
            Check(request.RequestUri?.AbsoluteUri == "https://relay.example.test/api/official-fleets/context" &&
                request.Headers.Authorization?.Parameter == "synthetic-access", "only scoped Relay context requested with SCM token");
            if (Hold) { Started.SetResult(); await Release.Task.WaitAsync(token); }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1,
                sourceRef = "officialFleet:7", fleetCode = "OFFICIALFLEET:7", name = "Fixture", announcementsAvailable = true,
                chatAvailable = true, canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false }) };
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
