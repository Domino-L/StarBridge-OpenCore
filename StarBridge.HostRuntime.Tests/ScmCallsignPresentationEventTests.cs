using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    // 11-17 build 100 E item 6: a rename saved in Settings changed the one callsign, but the top bar and the
    // friends header kept the old name until restart, because only the profile editor announced it.
    internal static async Task ScmCallsignPresentationEvent()
    {
        var root = Directory.CreateTempSubdirectory("sb-callsign-presentation-");
        try
        {
            using var hk = new SingleCallsignHkTransport();
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(hk), new ScmVisitorVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: new ScmVisibilityAuthorization());
            var relay = new ScmDisplayRelayFake();
            hk.Locations = 15; // both sides show everywhere, so a finished sync can read back fully in step
            using var relayWire = new SingleCallsignRelayTransport(relay);
            host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, relayWire));
            using var runtime = new AccountBridgeRuntime(host, privacy: new LocalPrivacyStore(root.FullName));
            var events = new List<string>();
            runtime.EventReady += envelope => { lock (events) events.Add(envelope.Name); };
            var owner = host.CurrentContext!; var generation = host.Generation;
            int Presentations() { lock (events) return events.Count(name => name == "account.presentationChanged"); }
            // Events published inside a dispatch ride back with its response (BridgeDispatchBatch.Events);
            // the rest arrive through EventReady. Flutter receives both, so count both.
            async Task<BridgeDispatchBatch> Send(string name, object payload)
            {
                var batch = await runtime.DispatchAsync(BridgeEnvelope.Request(name, "callsign-presentation", generation, payload, owner));
                lock (events) events.AddRange(batch.Events.Select(e => e.Name));
                return batch;
            }
            Task<BridgeDispatchBatch> SaveCallsign(string callsign) => Send("gameIdVisibility.saveCallsign",
                new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = relay.Revision,
                    ["identityStamp"] = relay.Stamp, ["callsign"] = callsign });

            var read = await Send("gameIdVisibility.read", new { schemaVersion = 1 });
            Check(read.Response.Error is null && Presentations() == 0, "reading the settings card announces nothing");

            // 1. Settings rename: same announcement as the profile editor.
            var saved = await SaveCallsign("多米诺1");
            Check(saved.Response.Error is null && relay.Callsign == "多米诺1" && hk.CallSign == "多米诺1" && Presentations() == 1,
                "a Settings rename announces account.presentationChanged once");

            // A refused rename changes nothing and announces nothing.
            var before = Presentations();
            var refused = await SaveCallsign(new string('x', 11));
            Check(refused.Response.Error?.Code == "callsign.invalid" && Presentations() == before,
                "a refused Settings rename announces nothing");
            var stale = await Send("gameIdVisibility.saveCallsign", new Dictionary<string, object?> { ["schemaVersion"] = 1,
                ["expectedRevision"] = relay.Revision - 1, ["identityStamp"] = relay.Stamp, ["callsign"] = "Ace" });
            Check(stale.Response.Error?.Code == "gameId.conflict" && Presentations() == before,
                "a conflicting Settings rename announces nothing");

            // 2. Profile editor rename keeps announcing it (unchanged path).
            before = Presentations();
            var edited = await Send("account.updateCallSign",
                new { schemaVersion = 1, expectedCallSign = "多米诺1", callSign = "多米诺2" });
            Check(edited.Response.Error is null && hk.CallSign == "多米诺2" && Presentations() == before + 1,
                "a profile editor rename announces account.presentationChanged");

            // 3. Hong Kong down: the Settings save still announces (the Relay changed). A retry, automatic or
            // tapped, announces exactly when Hong Kong confirmed the name during it.
            static string Mirror(BridgeDispatchBatch batch) => batch.Response.Payload.GetProperty("mirror").GetString()!;
            hk.CallSignStatus = System.Net.HttpStatusCode.ServiceUnavailable;
            before = Presentations();
            var pending = await SaveCallsign("多米诺3");
            Check(pending.Response.Error is null && relay.Callsign == "多米诺3" && Mirror(pending) == "pending" &&
                Presentations() == before + 1, "a Settings rename with Hong Kong down still announces once");
            before = Presentations();
            var downAuto = await Send("gameIdVisibility.retrySync", new { schemaVersion = 1, automatic = true });
            var downTap = await Send("gameIdVisibility.retrySync", new { schemaVersion = 1 });
            Check(downAuto.Response.Error is null && downTap.Response.Error is null && Mirror(downTap) == "pending" &&
                hk.CallSign == "多米诺2" && Presentations() == before, "retries that cannot reach Hong Kong announce nothing");
            hk.CallSignStatus = System.Net.HttpStatusCode.OK;
            var writes = hk.CallSignWrites;
            var retried = await Send("gameIdVisibility.retrySync", new { schemaVersion = 1, automatic = true });
            Check(retried.Response.Error is null && hk.CallSignWrites == writes + 1 && hk.CallSign == "多米诺3" &&
                Mirror(retried) == "synced" && Presentations() == before + 1,
                "the automatic retry that pushes the name announces once and ends fully in step");
            before = Presentations();
            await Send("gameIdVisibility.retrySync", new { schemaVersion = 1, automatic = true });
            await Send("gameIdVisibility.retrySync", new { schemaVersion = 1 });
            Check(Presentations() == before, "retries with nothing to push announce nothing");

            // Locations half stuck pending (Hong Kong hidden, Relay showing: retries never reveal). The name half
            // still goes through, and each retry that pushes it announces, tapped (review P3) or automatic (review P2).
            hk.Locations = 0;
            foreach (var (name, automaticRetry) in new[] { ("多米诺4", false), ("多米诺5", true) })
            {
                hk.CallSignStatus = System.Net.HttpStatusCode.ServiceUnavailable;
                await SaveCallsign(name);
                hk.CallSignStatus = System.Net.HttpStatusCode.OK;
                Check(hk.CallSign != name, "Hong Kong still has the old name before the retry: " + automaticRetry);
                before = Presentations(); writes = hk.CallSignWrites;
                var stuck = await Send("gameIdVisibility.retrySync", automaticRetry
                    ? new { schemaVersion = 1, automatic = true } : (object)new { schemaVersion = 1 });
                Check(stuck.Response.Error is null && hk.CallSignWrites == writes + 1 && hk.CallSign == name &&
                    Mirror(stuck) == "pending" && Presentations() == before + 1,
                    "a retry pushes the name and announces once while the locations half stays pending: " + automaticRetry);
                before = Presentations();
                await Send("gameIdVisibility.retrySync", new { schemaVersion = 1, automatic = true });
                Check(Presentations() == before, "the next automatic retry has nothing to push and announces nothing: " + automaticRetry);
            }

            // Reading the card is not a rename.
            before = Presentations();
            await Send("gameIdVisibility.read", new { schemaVersion = 1 });
            Check(Presentations() == before, "a settings read announces nothing");
        }
        finally
        {
            try { root.Delete(recursive: true); } catch (IOException) { }
        }
    }
}
