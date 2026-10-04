using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task HandleChangeCompatibility()
    {
        foreach (var scenario in new[] { "success", "cancel", "observation", "owner", "timeout", "timeoutBeforeCommit", "rejected", "foreign", "malformed", "lateOwner", "unauthorized" })
        {
            using var http = new HandleTransport();
            var saved = new Store();
            using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), http, saved);
            var observed = "Pilot-New";
            using var host = new ScmAccountBridgeHost(
                new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "development", () => observed, legacyPasswordLogin: client);
            using var runtime = new AccountBridgeRuntime(host);
            await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
            var original = host.Generation;
            var owner = host.CurrentContext;
            async Task<BridgeDispatchBatch> Send(string name, object body) => await runtime.DispatchAsync(
                BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), original, body, owner));
            var ready = await Send("gameIdentity.prepareHandleChange", new { schemaVersion = 1 });
            Check(ready.Response.Status == "ok" && ready.Response.Payload.GetProperty("state").GetString() == "ready", scenario + " ready");
            Check(http.Writes == 0, "prepare must never write");
            var id = ready.Response.Payload.GetProperty("confirmationId").GetString();
            var confirmation = new { schemaVersion = 1, confirmationId = id };
            if (scenario == "cancel") await Send("gameIdentity.cancelHandleChange", confirmation);
            if (scenario == "observation") observed = "Other-Pilot";
            if (scenario == "owner") await host.LogoutAsync(owner!, default);
            if (scenario == "lateOwner") http.OnWrite = () => host.LogoutAsync(owner!, default);
            http.Mode = scenario;
            var result = await Send("gameIdentity.confirmHandleChange", confirmation);
            var expectedWrites = scenario is "cancel" or "observation" or "owner" or "unauthorized" ? 0 : 1;
            Check(http.Writes == expectedWrites, scenario + " bounded writes");
            Check(result.Response.Status == (scenario == "success" ? "ok" : "error"), scenario + " response");
            await Send("gameIdentity.confirmHandleChange", confirmation);
            Check(http.Writes == expectedWrites, scenario + " duplicate ticket cannot replay");
            if (scenario == "success") {
                Check(host.Generation > original && host.HangarIdentity?.Identity.Handle == "Pilot-New", "confirmed readback advances identity generation");
                Check(result.Events.Any(e => e.Name == "account.changed"), "dependent consumers invalidate");
                var restored = await client.RestoreAsync(default);
                Check(restored.Identity?.Handle == "Pilot-New", "restart session reads back persisted new identity");
            } else if (scenario is "timeout" or "foreign" or "malformed") {
                Check(host.HangarIdentity?.Identity.Handle == "Pilot_Old", "uncertain response cannot update local identity");
                http.Mode = "success";
                var recovered = await Send("gameIdentity.prepareHandleChange", new { schemaVersion = 1 });
                Check(recovered.Response.Status == "ok" && host.HangarIdentity?.Identity.Handle == "Pilot-New", "GET reconciles committed write");
                Check(http.Writes == 1, "recovery never repeats PUT");
            } else if (scenario is "rejected" or "timeoutBeforeCommit") {
                http.Mode = "success";
                var blocked = await Send("gameIdentity.prepareHandleChange", new { schemaVersion = 1 });
                Check(blocked.Response.Payload.GetProperty("state").GetString() == (scenario == "rejected" ? "ready" : "outcomeUnknown"),
                    "definite rejection permits fresh confirmation; uncertain noncommit remains read-only");
                Check(http.Writes == 1 && host.HangarIdentity?.Identity.Handle == "Pilot_Old", "no unconfirmed local changes");
            } else if (scenario is "owner" or "lateOwner") {
                Check(host.HangarIdentity is null, "late rename cannot revive signed-out account");
            } else {
                Check(saved.Value is not null && host.HangarIdentity?.Identity.Handle == "Pilot_Old", "failure/cancel keeps credential and identity");
            }
        }
        using var scm = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "development", () => "Pilot-New",
            initialSession: new ScmOAuthSession("scm", "subject", "Synthetic", "token", DateTimeOffset.UtcNow.AddHours(1), [],
                GameIdentityVerified: true, GameIdentityHandle: "Pilot_Old"));
        var view = JsonSerializer.SerializeToElement(await scm.PrepareHandleChangeAsync(scm.CurrentContext!, default));
        Check(view.GetProperty("state").GetString() == "unknown" && view.GetProperty("confirmationId").ValueKind == JsonValueKind.Null,
            "SCM sessions never receive compatibility write capability");
        Console.WriteLine("PASS legacy Handle confirmation, cancel, stale observation/owner, readback, uncertain recovery and SCM exclusion");
    }

    private sealed class HandleTransport : HttpMessageHandler
    {
        internal string Mode = "success", Handle = "Pilot_Old";
        internal int Writes;
        internal Func<Task>? OnWrite;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Get && Mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (request.Method == HttpMethod.Put) {
                Check(request.RequestUri!.AbsolutePath == "/api/auth/identity-binding" && request.Headers.Authorization?.Parameter == "synthetic-token", "existing owner-authenticated route");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 2 && body.RootElement.GetProperty("replaceExisting").GetBoolean(), "only existing contract fields");
                Writes++;
                if (Mode == "timeoutBeforeCommit") throw new HttpRequestException("synthetic connection loss");
                if (Mode == "rejected") return new(HttpStatusCode.Conflict);
                Handle = body.RootElement.GetProperty("gameName").GetString()!;
                if (OnWrite is not null) await OnWrite();
                if (Mode == "timeout") throw new HttpRequestException("synthetic disconnect after commit");
                if (Mode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                accountId = Mode == "foreign" && request.Method == HttpMethod.Put ? "other-account" : "legacy-synthetic",
                email = "old@example.invalid", token = "synthetic-token", callsign = "Synthetic",
                gameName = Handle, identityBindingRequired = false, identityBindingConfirmedAt = "2026-09-10T00:00:00Z"
            }) };
        }
    }
}
