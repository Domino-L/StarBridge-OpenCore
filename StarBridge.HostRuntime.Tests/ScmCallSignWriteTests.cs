using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmCallSignWrite()
    {
        await ProfileConfirmationReauthorization();
        using var transport = new ScmCallSignTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmBackgroundAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "SCM Username", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<AccountBridgeDispatchResult> Write(string expected = "Inherited", string name = "Manual Commander") =>
            dispatcher.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "callsign", generation,
                new { schemaVersion = 1, expectedCallSign = expected, callSign = name }, owner));
        foreach (var name in new[] { "", "Pilot\nInjected", new string('x', 33) }) {
            Check((await Write(name: name)).Response.Error?.Code == "account.callsign_invalid" && transport.Writes == 0,
                "invalid call sign never authorizes or writes");
        }
        foreach (var mode in new[] { "denied", "wrong-subject", "missing-scope" }) {
            authorization.Mode = mode;
            var rejected = await Write();
            Check(rejected.Response.Status != "ok" && rejected.Events.Count == 0 && transport.Writes == 0,
                "call sign requires current-owner write grant: " + mode);
        }
        authorization.Mode = "granted";
        var saved = await Write();
        Check(saved.Response.Error is null && transport.Writes == 1 && saved.Events.Single().Name == "account.presentationChanged",
            "only confirmed Java call sign publishes presentation invalidation");
        var read = JsonSerializer.SerializeToElement(await host.ReadAvatarAsync(owner, default));
        Check(read.GetProperty("callSign").GetString() == "Manual Commander" && (await host.GetCurrentAsync(default)).DisplayName == "Manual Commander",
            "account display follows Java call sign without changing SCM identity");
        Check((await Write()).Response.Error is null && transport.Writes == 1,
            "lost acknowledgement retry recognizes already-saved call sign without writing again");
        Check((await Write("Inherited", "Stale")).Response.Error?.Code == "account.callsign_conflict" && transport.Writes == 1,
            "old editor cannot overwrite a different device's call sign");
        transport.Status = HttpStatusCode.Conflict;
        Check((await Write("Manual Commander", "Racing")).Response.Error?.Code == "account.callsign_conflict" && transport.Writes == 2,
            "server CAS conflict is not replayed");
        transport.Status = HttpStatusCode.OK;
        transport.WrongAck = true;
        var invalid = await Write("Manual Commander", "Invalid Ack");
        Check(invalid.Response.Error is not null && invalid.Events.Count == 0, "wrong acknowledgement never reports success");
        transport.WrongAck = false;
        transport.HideWriteOnRead = true;
        var unconfirmed = await Write(transport.CallSign, "Unconfirmed");
        Check(unconfirmed.Response.Error?.Code == "account.callsign_unconfirmed" && unconfirmed.Events.Count == 0,
            "write is not called confirmed until normal read authority agrees");
        transport.HideWriteOnRead = false;
        transport.WrongConfirmationOwner = true;
        var writesBeforeOwnerChange = transport.Writes;
        var wrongOwner = await Write(transport.CallSign, "Same Name Other Owner");
        Check(wrongOwner.Response.Error?.Code == "account.callsign_unconfirmed" && wrongOwner.Events.Count == 0 &&
            transport.Writes == writesBeforeOwnerChange + 1, "different readback owner cannot confirm or replay call sign");
        Check((await host.GetCurrentAsync(default)).DisplayName == "Manual Commander",
            "different owner readback does not replace the confirmed display cache");
        transport.WrongConfirmationOwner = false;
        foreach (var mode in new[] { "forbidden", "invalid" })
        {
            transport.ConfirmationMode = mode;
            var writesBefore = transport.Writes;
            var failed = await Write(transport.CallSign, "Unconfirmed " + mode);
            Check(failed.Response.Error?.Code == "account.callsign_unconfirmed" && failed.Events.Count == 0 &&
                transport.Writes == writesBefore + 1, $"confirmation failure cannot publish or replay call sign: {mode}, code={failed.Response.Error?.Code}, events={failed.Events.Count}, writes={transport.Writes}, before={writesBefore}");
        }
        transport.ConfirmationMode = null;
        transport.Status = HttpStatusCode.ServiceUnavailable;
        transport.CommitBeforeError = true;
        var writesBeforeUncertain = transport.Writes;
        var grantsBeforeUncertain = authorization.Calls;
        var uncertain = await Write(transport.CallSign, "Committed Before Error");
        Check(uncertain.Response.Error?.Code == "account.callsign_unconfirmed" && uncertain.Events.Count == 0 &&
            transport.Writes == writesBeforeUncertain + 1, "committed call sign with failed acknowledgement cannot report success or replay");
        Check((await host.GetCurrentAsync(default)).DisplayName == "Manual Commander",
            "failed acknowledgement cannot replace the confirmed display cache");
        var recovered = JsonSerializer.SerializeToElement(await host.ReadAvatarAsync(owner, default));
        Check(recovered.GetProperty("callSign").GetString() == "Committed Before Error" &&
            (await host.GetCurrentAsync(default)).DisplayName == "Committed Before Error" &&
            transport.Writes == writesBeforeUncertain + 1 && authorization.Calls == grantsBeforeUncertain + 1,
            "call sign recovery uses ordinary read authority without replay or a new grant");
        transport.Status = HttpStatusCode.OK;
        transport.CommitBeforeError = false;
        transport.CallSign = "Other Device Commander";
        transport.Revision++;
        var writesBeforeRefresh = transport.Writes;
        var refreshed = JsonSerializer.SerializeToElement(await host.ReadAvatarAsync(owner, default));
        Check(refreshed.GetProperty("callSign").GetString() == "Other Device Commander" &&
            (await host.GetCurrentAsync(default)).DisplayName == "Other Device Commander" &&
            transport.Writes == writesBeforeRefresh,
            "normal presentation refresh observes another device's call sign without writing or replaying an uncertain write");
        await host.LogoutAsync(owner, default);
        var before = transport.Writes;
        Check((await Write()).Response.Error is not null && transport.Writes == before,
            "old account cannot rename after logout");
        Check((await host.GetCurrentAsync(default)).DisplayName is null, "logout clears cached call sign");
    }

    private sealed class ScmCallSignTransport : HttpMessageHandler
    {
        internal int Writes;
        internal long Revision = 7;
        internal string CallSign = "Inherited";
        internal bool WrongAck, HideWriteOnRead;
        internal bool WrongConfirmationOwner;
        internal string? ConfirmationMode;
        internal bool CommitBeforeError;
        private bool _confirmationPending;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/business-identity")
                return new(HttpStatusCode.ServiceUnavailable); // Optional enrollment is outside this synthetic fixture.
            if (request.Method == HttpMethod.Patch) {
                Writes++;
                Check(request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile/callsign" &&
                    request.Headers.Authorization?.Parameter == "synthetic-write-token", "dedicated call sign route and write grant");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 2 && body.RootElement.GetProperty("expectedRevision").GetInt64() == Revision,
                    "call sign write carries revision, no unrelated fields or owner selector");
                var name = body.RootElement.GetProperty("callSign").GetString()!;
                var savedRevision = Revision + 1;
                _confirmationPending = Status == HttpStatusCode.OK && !WrongAck;
                if ((Status == HttpStatusCode.OK || CommitBeforeError) && !HideWriteOnRead) { CallSign = name; Revision++; }
                return new(Status) { Content = JsonContent.Create(new { schemaVersion = 1, revision = savedRevision,
                    callSign = WrongAck ? "Wrong" : name }) };
            }
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile" &&
                request.Headers.Authorization?.Parameter == "synthetic-read-token", "read keeps normal session; never legacy login or write grant");
            var wrongOwner = _confirmationPending && WrongConfirmationOwner;
            var mode = _confirmationPending ? ConfirmationMode : null;
            _confirmationPending = false;
            if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "invalid") return new(HttpStatusCode.OK) { Content = new StringContent("{invalid") };
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new StarBridge.Core.Profiles.PersonalProfileDocumentContract(
                3, wrongOwner ? "other-public" : "fixture-public", false, Revision, DateTimeOffset.UnixEpoch, new(CallSign, "Verified-Handle", null),
                StarBridge.Core.Profiles.PersonalProfileContentContract.Empty, null)) };
        }
    }
}
