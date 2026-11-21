using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

/// <summary>11-15 decision 甲: one callsign for SCM accounts. The Relay (r49) is written
/// first, Hong Kong's profile callsign and handle-privacy are kept in step and read back.</summary>
internal static partial class LegacyPasswordLoginTests
{
    // Client review (decision 乙) P1s: a first rename and an unreadable Hong Kong never skip
    // the one-time import of an explicit Hong Kong hide.
    internal static async Task ScmSingleCallsignImportGuards()
    {
        using var hk = new SingleCallsignHkTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(hk), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmVisibilityAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        var relay = new ScmDisplayRelayFake();
        using var relayWire = new SingleCallsignRelayTransport(relay);
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, relayWire));
        var settings = new GameIdSettingsDispatcher(host, () => (host.GameplayTimeContext, host.Generation));
        using var account = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<BridgeDispatchBatch> Read() => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "import-guards", generation,
            new { schemaVersion = 1 }, owner), default);

        hk.PrivacyRevision = 3; hk.Locations = 2;
        // Hong Kong unreadable while the Relay has no row: unknown, never "show".
        hk.PrivacyDown = true;
        var unknown = await Read();
        Check(unknown.Response.Error?.Code == "gameId.unavailable" && relay.Writes == 0 && relay.Revision == 0,
            "an unreadable Hong Kong blocks the read instead of offering the Relay's show default");
        var blockedRename = await account.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "import-guards", generation,
            new { schemaVersion = 1, expectedCallSign = "Inherited", callSign = "Viper" }, owner));
        Check(blockedRename.Response.Error is not null && relay.Writes == 0 && hk.CallSignWrites == 0,
            "a first rename waits too: no Relay write without a known import state");
        hk.PrivacyDown = false;

        // The first Relay write is a rename (profile editor), before any settings read.
        var renamed = await account.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "import-guards", generation,
            new { schemaVersion = 1, expectedCallSign = "Inherited", callSign = "Viper" }, owner));
        Check(renamed.Response.Error is null && relay.Imports == 1 && relay.Locations == 2 && relay.Callsign == "Viper" &&
            hk.Locations == 2 && hk.CallSign == "Viper", "a first rename imports the Hong Kong hide before writing the callsign");
        var after = await Read();
        Check(after.Response.Error is null && after.Response.Payload.GetProperty("locations").GetInt32() == 2 &&
            hk.Locations == 2 && relay.Imports == 1, "the later settings read keeps the hide and never pushes show");
    }

    // Client review R2 P1s: a settings save from a revision-0 snapshot imports first, and an
    // import that cannot land never lets the Relay's "show" default reach Hong Kong.
    internal static async Task ScmSingleCallsignImportGuardsSaves()
    {
        foreach (var scenario in new[] { "stale-snapshot", "import-conflict", "retry-race", "callsign-then-retry", "show-only-in-own-save", "superseded-by-other-device", "later-hide-same-value", "same-hide-not-configurable", "refused-then-barrier" })
        {
            using var hk = new SingleCallsignHkTransport();
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(hk), new ScmVisitorVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: new ScmVisibilityAuthorization());
            var relay = new ScmDisplayRelayFake();
            using var relayWire = new SingleCallsignRelayTransport(relay);
            host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, relayWire));
            var settings = new GameIdSettingsDispatcher(host, () => (host.GameplayTimeContext, host.Generation));
            var owner = host.CurrentContext!; var generation = host.Generation;
            Task<BridgeDispatchBatch> Read() => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "import-saves", generation,
                new { schemaVersion = 1 }, owner), default);
            static string Mirror(BridgeDispatchBatch batch) =>
                batch.Response.Error is null ? batch.Response.Payload.GetProperty("mirror").GetString()! : "error:" + batch.Response.Error.Code;
            if (scenario == "stale-snapshot")
            {
                var snapshot = await Read();
                Check(snapshot.Response.Error is null && relay.Revision == 0, "a fresh account reads the show default");
                var stamp = relay.Stamp;
                // An older client now saves an explicit hide on Hong Kong.
                hk.PrivacyRevision = 3; hk.Locations = 2;
                var save = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check(save.Response.Error?.Code == "gameId.conflict" && relay.Imports == 1 && relay.Locations == 2 &&
                    relay.Callsign is null && hk.Locations == 2, "a revision-0 draft imports first and becomes a conflict to refresh");
            }
            else if (scenario == "later-hide-same-value")
            {
                // Review R10 P1: the other device's later hide finds Hong Kong already hidden; its own save
                // still writes Hong Kong (same value), which moves the revision and stops the older show.
                hk.Locations = 15;
                Task<BridgeDispatchBatch> SaveLocations(int mask) => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save",
                    "import-saves", generation, new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp,
                        locations = mask }, owner), default);
                await Read();
                await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check((await SaveLocations(0)).Response.Error is null && hk.Locations == 0, "the user's own hide reaches Hong Kong");
                var touched = hk.PrivacyRevision;
                Check((await SaveLocations(0)).Response.Error is null && hk.PrivacyRevision == touched + 1 && hk.Locations == 0,
                    "saving the same hide again still writes Hong Kong, moving its revision");
                // This device's show starts; the other device's same-value hide then moves only the revision.
                hk.AfterPrivacyRead = () => { hk.PrivacyRevision++; };
                var shown = await SaveLocations(15);
                Check(shown.Response.Error is null && relay.Locations == 15 && hk.Locations == 0 && Mirror(shown) == "pending",
                    "an older show never overwrites a later hide, even when that hide changed no value");
            }
            else if (scenario == "refused-then-barrier")
            {
                // Review R13 P1: Hong Kong refuses the first write (its identity changed and came back); the save
                // reads once more and writes again, so Hong Kong's revision still moves.
                hk.Locations = 15;
                Task<BridgeDispatchBatch> SaveLocations(int mask) => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save",
                    "import-saves", generation, new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp,
                        locations = mask }, owner), default);
                await Read();
                await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check((await SaveLocations(2)).Response.Error is null && hk.Locations == 2, "the user's own hide reaches Hong Kong");
                hk.RefuseNextPatch = true; var touched = hk.PrivacyRevision;
                Check((await SaveLocations(0)).Response.Error is null && hk.PrivacyRevision == touched + 1 && hk.Locations == 0,
                    "a refused hide is read again and written");
                hk.RefuseNextPatch = true; touched = hk.PrivacyRevision;
                var shown = await SaveLocations(15);
                Check(shown.Response.Error is null && relay.Locations == 15 && hk.Locations == 0 && hk.PrivacyRevision == touched + 1 &&
                    Mirror(shown) == "pending", "a refused show writes only what Hong Kong shows, moving its revision, and stays pending");
            }
            else if (scenario == "same-hide-not-configurable")
            {
                // Review R11 P1: while Hong Kong briefly cannot be configured, the user's own same-value hide
                // still writes Hong Kong, so an older show from another device fails once Hong Kong recovers.
                hk.Locations = 15;
                Task<BridgeDispatchBatch> SaveLocations(int mask) => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save",
                    "import-saves", generation, new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp,
                        locations = mask }, owner), default);
                await Read();
                await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check((await SaveLocations(0)).Response.Error is null && hk.Locations == 0, "the user's own hide reaches Hong Kong");
                hk.CanConfigure = false;
                var touched = hk.PrivacyRevision;
                var same = await SaveLocations(0);
                Check(same.Response.Error is null && hk.PrivacyRevision == touched + 1 && hk.Locations == 0 && Mirror(same) == "synced",
                    "the same hide is written even while Hong Kong cannot be configured, moving its revision");
                // Review R12 P1: Hong Kong shows nothing while its identity is unusable; a partial hide is still written,
                // and Hong Kong's 0 reply confirms it (review R14 P2: the fake answers like Hong Kong does).
                touched = hk.PrivacyRevision;
                var partial = await SaveLocations(2);
                Check(partial.Response.Error is null && hk.PrivacyRevision == touched + 1 && hk.Locations == 2 && Mirror(partial) == "synced",
                    "a partial hide is written while Hong Kong cannot be configured, moving its revision");
            }
            else if (scenario == "superseded-by-other-device")
            {
                // Review R9 P1: another device hides on Hong Kong while this device's show is in flight.
                hk.Locations = 15;
                Task<BridgeDispatchBatch> SaveLocations(int mask) => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save",
                    "import-saves", generation, new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp,
                        locations = mask }, owner), default);
                await Read();
                await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check((await SaveLocations(2)).Response.Error is null && hk.Locations == 2, "the user's own hide reaches Hong Kong");
                // The save's starting read sees 2; another device then hides everything on Hong Kong.
                var afterOther = 0L;
                hk.AfterPrivacyRead = () => { hk.PrivacyRevision++; hk.Locations = 0; afterOther = hk.PrivacyRevision; };
                var shown = await SaveLocations(15);
                Check(shown.Response.Error is null && relay.Locations == 15 && hk.Locations == 0 && Mirror(shown) == "pending",
                    "a show never overwrites a hide written on Hong Kong after the save started");
                Check(hk.PrivacyRevision == afterOther + 1, "the refused show still writes what Hong Kong shows, moving its revision");
            }
            else if (scenario == "show-only-in-own-save")
            {
                // Simplified rule (user 11-16): Hong Kong becomes more public only inside the user's own save.
                hk.Locations = 15;
                Task<BridgeDispatchBatch> SaveLocations(int mask) => settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save",
                    "import-saves", generation, new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp,
                        locations = mask }, owner), default);
                await Read();
                var named = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check(named.Response.Error is null && relay.Callsign == "Viper", "a callsign first, so places may be hidden");
                Check((await SaveLocations(2)).Response.Error is null && hk.Locations == 2, "the user's own hide reaches Hong Kong");
                hk.PrivacyDown = true;
                var shown = await SaveLocations(15);
                Check(shown.Response.Error is null && relay.Locations == 15 && hk.Locations == 2 && Mirror(shown) == "pending",
                    "the user's own show saves on the Relay while Hong Kong is down");
                hk.PrivacyDown = false;
                foreach (var automatic in new[] { false, true })
                {
                    var retry = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.retrySync", "import-saves", generation,
                        automatic ? new { schemaVersion = 1, automatic = true } : (object)new { schemaVersion = 1 }, owner), default);
                    Check(hk.Locations == 2 && Mirror(retry) == "pending", "retries never make Hong Kong more public: " + automatic);
                }
                var again = await SaveLocations(15);
                Check(again.Response.Error is null && hk.Locations == 15 && Mirror(again) == "synced",
                    "saving again completes the show on Hong Kong");
            }
            else if (scenario == "callsign-then-retry")
            {
                // Review R4 P1: the first callsign save passes the import check, an older client then
                // saves a Hong Kong hide; later retries must not reveal it (only the user's own
                // locations save may).
                hk.Locations = 15;
                var snapshot = await Read();
                Check(snapshot.Response.Error is null && relay.Revision == 0, "fresh account before the first callsign");
                hk.AfterPrivacyRead = () => { hk.PrivacyRevision = 3; hk.Locations = 2; };
                var save = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "import-saves", generation,
                    new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = 0L, ["identityStamp"] = relay.Stamp,
                        ["callsign"] = "Viper" }, owner), default);
                Check(save.Response.Error is null && relay.Revision == 1 && relay.Callsign == "Viper" && relay.Locations == 15,
                    "the first callsign save lands with the default locations");
                foreach (var automatic in new[] { false, true })
                    await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.retrySync", "import-saves", generation,
                        automatic ? new { schemaVersion = 1, automatic = true } : (object)new { schemaVersion = 1 }, owner), default);
                Check(hk.Locations == 2 && hk.PrivacyRevision == 3,
                    "manual and automatic retries never reveal a Hong Kong hide the user did not undo here");
            }
            else if (scenario == "retry-race")
            {
                // The import check sees no hide; an older client saves one before the mirror step.
                hk.Locations = 15;
                hk.AfterPrivacyRead = () => { hk.PrivacyRevision = 3; hk.Locations = 2; };
                var retry = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.retrySync", "import-saves", generation,
                    new { schemaVersion = 1 }, owner), default);
                Check(hk.Locations == 2 && hk.PrivacyRevision == 3 && relay.Revision == 0,
                    "a Relay without a row never pushes show over a Hong Kong hide: " + retry.Response.Error?.Code);
            }
            else
            {
                hk.PrivacyRevision = 3; hk.Locations = 2; relay.ImportConflict = true;
                var patchesBefore = hk.PrivacyRevision;
                var read = await Read();
                Check(read.Response.Error?.Code == "gameId.unavailable" && relay.Revision == 0 && hk.Locations == 2 &&
                    hk.PrivacyRevision == patchesBefore, "an import that cannot land stops; show is never pushed to Hong Kong");
            }
        }
    }

    internal static async Task ScmSingleCallsign()
    {
        using var hk = new SingleCallsignHkTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(hk), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmVisibilityAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        var relay = new ScmDisplayRelayFake();
        using var relayWire = new SingleCallsignRelayTransport(relay);
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, relayWire));
        var settings = new GameIdSettingsDispatcher(host, () => (host.GameplayTimeContext, host.Generation));
        using var account = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<BridgeDispatchBatch> SaveCallsign(string? callsign, long? revision = null) => settings.DispatchAsync(
            BridgeEnvelope.Request("gameIdVisibility.saveCallsign", "single-callsign", generation,
                // A dictionary keeps an explicit null (the bridge drops null properties), as Flutter sends it.
                new Dictionary<string, object?> { ["schemaVersion"] = 1, ["expectedRevision"] = revision ?? relay.Revision,
                    ["identityStamp"] = relay.Stamp, ["callsign"] = callsign }, owner), default);
        Task<BridgeDispatchBatch> Retry(bool automatic = false) => settings.DispatchAsync(
            BridgeEnvelope.Request("gameIdVisibility.retrySync", "single-callsign", generation,
                automatic ? new { schemaVersion = 1, automatic = true } : (object)new { schemaVersion = 1 }, owner), default);
        static string Mirror(BridgeDispatchBatch batch) => batch.Response.Payload.GetProperty("mirror").GetString()!;

        // Decision 乙: an explicit hide saved earlier on Hong Kong is imported once into
        // the Relay (which never had a row) before anything is pushed back.
        hk.PrivacyRevision = 3; hk.Locations = 2;
        var first = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "single-callsign", generation,
            new { schemaVersion = 1 }, owner), default);
        Check(first.Response.Error is null && relay.Imports == 1 && relay.Locations == 2 && relay.Revision == 1 &&
            hk.Locations == 2 && Mirror(first) == "synced", "explicit Hong Kong hide is kept, never pushed to show");
        await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "single-callsign", generation,
            new { schemaVersion = 1 }, owner), default);
        Check(relay.Imports == 1, "the import happens once");
        var stampBefore = relay.Stamp;
        var saved = await SaveCallsign("  飞鹰 ");
        Check(saved.Response.Payload.GetProperty("identityStamp").GetString() == relay.Stamp && relay.Stamp != stampBefore,
            "a rename returns the Relay's new identity stamp");
        Check(saved.Response.Error is null && relay.Callsign == "飞鹰" && hk.CallSign == "飞鹰" && Mirror(saved) == "synced" &&
            saved.Response.Payload.GetProperty("callsign").GetString() == "飞鹰", "callsign trims, writes the Relay, then Hong Kong");

        var writes = relay.Writes + hk.CallSignWrites;
        foreach (var invalid in new[] { new string('x', 11), "中文中文中文", "A\u0001" })
            Check((await SaveCallsign(invalid)).Response.Error?.Code == "callsign.invalid" && relay.Writes + hk.CallSignWrites == writes,
                "legacy callsign rules reject before any write: " + invalid.Length);

        Check((await SaveCallsign("Ace", relay.Revision - 1)).Response.Error?.Code == "gameId.conflict" && relay.Callsign == "飞鹰",
            "a stale draft is a conflict and changes nothing");

        // Decision 乙: the imported hide is still in place, so the Relay refuses the clear.
        var refusedClear = await SaveCallsign(null);
        Check(refusedClear.Response.Error?.Code == "callsign.hidden_requires_callsign" && relay.Callsign == "飞鹰",
            "clearing while a place is hidden is refused with the rule 乙 code");
        var shown = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save", "single-callsign", generation,
            new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp, locations = 15 }, owner), default);
        Check(shown.Response.Error is null && relay.Locations == 15, "show everywhere first");

        hk.RestoreSupported = false;
        var cleared = await SaveCallsign(null);
        Check(cleared.Response.Error is null && relay.Callsign is null && hk.CallSign == "飞鹰" && Mirror(cleared) == "restorePending",
            "clearing before Hong Kong swap 7: the Relay clears, the profile name waits");
        // Hong Kong before swap 7: the card's automatic retry waits (no write at all).
        var writesBeforeAuto = hk.CallSignWrites;
        var automaticRetry = await Retry(automatic: true);
        Check(automaticRetry.Response.Error is null && hk.CallSignWrites == writesBeforeAuto && Mirror(automaticRetry) == "restorePending",
            "automatic retries honour the restore cooldown");
        // Decision 乙: without a callsign nothing can be hidden.
        var hideRefused = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save", "single-callsign", generation,
            new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp, locations = 4 }, owner), default);
        Check(hideRefused.Response.Error?.Code == "gameId.callsign_required" && relay.Locations == 15,
            "hiding without a callsign is refused with the rule 乙 code");
        // A locations-only save must not clear the pending restore.
        var locationsSaved = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.save", "single-callsign", generation,
            new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp, locations = 15 }, owner), default);
        Check(locationsSaved.Response.Error is null && hk.Locations == 15 && Mirror(locationsSaved) == "restorePending",
            "a locations-only save keeps the pending restore visible");
        hk.RestoreSupported = true;
        var restored = await Retry();
        Check(restored.Response.Error is null && hk.CallSign == SingleCallsignHkTransport.DefaultName && Mirror(restored) == "synced",
            "after swap 7 an empty name restores the SCM default name");

        // With the name restored and nothing pending, a locations mismatch alone never
        // rewrites the Hong Kong profile name. A hide made on Hong Kong (here 8 against the
        // Relay's 15) is not revealed by a retry: only the user's own locations save may (review R4).
        hk.Locations = 8;
        var nameWrites = hk.CallSignWrites;
        var locationsOnly = await Retry();
        Check(locationsOnly.Response.Error is null && hk.CallSignWrites == nameWrites && hk.Locations == 8 &&
            Mirror(locationsOnly) == "pending", "retry leaves the profile name alone and never reveals a Hong Kong hide");
        hk.Locations = 15; // the Hong Kong hide is undone there; the callsign half is tested on its own below
        hk.CallSignStatus = HttpStatusCode.ServiceUnavailable;
        var pending = await SaveCallsign("Ace");
        Check(pending.Response.Error is null && relay.Callsign == "Ace" && Mirror(pending) == "pending",
            "a Hong Kong outage keeps the Relay save and reports pending");
        hk.CallSignStatus = HttpStatusCode.OK;
        var synced = await Retry();
        Check(synced.Response.Error is null && hk.CallSign == "Ace" && Mirror(synced) == "synced", "retry finishes the Hong Kong half");

        var read = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "single-callsign", generation,
            new { schemaVersion = 1 }, owner), default);
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("callsign").GetString() == "Ace" && Mirror(read) == "synced",
            "settings read shows the one callsign and its sync state");

        // The profile editor edits the same callsign: both sides change.
        var edited = await account.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "single-callsign-editor", generation,
            new { schemaVersion = 1, expectedCallSign = "Ace", callSign = "Viper" }, owner));
        Check(edited.Response.Error is null && relay.Callsign == "Viper" && hk.CallSign == "Viper",
            "profile editor writes the Relay and the SCM profile name");
        // A stale editor draft (another device renamed since) writes nothing anywhere.
        hk.CallSign = "OtherDev"; relay.Callsign = "OtherDev";
        var relayWrites = relay.Writes; var hkWrites = hk.CallSignWrites;
        var stale = await account.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "single-callsign-editor", generation,
            new { schemaVersion = 1, expectedCallSign = "Viper", callSign = "Ghost" }, owner));
        Check(stale.Response.Error?.Code == "account.callsign_conflict" && relay.Writes == relayWrites &&
            hk.CallSignWrites == hkWrites && relay.Callsign == "OtherDev", "stale editor draft is refused before any write");
        hk.CallSign = "Viper"; relay.Callsign = "Viper";
        var tooLong = await account.DispatchAsync(BridgeEnvelope.Request("account.updateCallSign", "single-callsign-editor", generation,
            new { schemaVersion = 1, expectedCallSign = "Viper", callSign = "Manual Commander" }, owner));
        Check(tooLong.Response.Error?.Code == "account.callsign_invalid" && relay.Callsign == "Viper",
            "profile editor follows the same 10-weight rule");
        // Another device finishes a non-empty name on both sides: the local pending
        // restore ends on the next confirmed read.
        hk.RestoreSupported = false;
        var clearedAgain = await SaveCallsign(null);
        Check(Mirror(clearedAgain) == "restorePending", "second clear waits for Hong Kong");
        relay.Callsign = "Remote"; relay.Revision++; hk.CallSign = "Remote";
        var afterRemote = await settings.DispatchAsync(BridgeEnvelope.Request("gameIdVisibility.read", "single-callsign", generation,
            new { schemaVersion = 1 }, owner), default);
        Check(afterRemote.Response.Error is null && Mirror(afterRemote) == "synced", "a name finished elsewhere ends the pending restore");
        Console.WriteLine("PASS SCM single callsign: Relay first, Hong Kong kept in step, restore and retry");
    }

    private sealed class SingleCallsignRelayTransport(ScmDisplayRelayFake relay) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(ScmDisplayRelayFake.Handles(request), "only display settings reach the Relay");
            return relay.SendAsync(request, token);
        }
    }

    private sealed class SingleCallsignHkTransport : HttpMessageHandler
    {
        internal const string DefaultName = "SCM 昵称";
        internal string CallSign = "Inherited";
        internal long ProfileRevision = 7, PrivacyRevision;
        internal int Locations, CallSignWrites;
        internal bool RestoreSupported = true, PrivacyDown, ProfileDown, CanConfigure = true, RefuseNextPatch;
        // Runs after each handle-privacy read (the response is already built): lets a test
        // change Hong Kong between two reads, like an older client saving meanwhile.
        internal Action? AfterPrivacyRead;
        internal HttpStatusCode CallSignStatus = HttpStatusCode.OK;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/app-api/starbridge/v1/business-identity") return new(HttpStatusCode.ServiceUnavailable);
            if (path == "/app-api/starbridge/v1/handle-privacy")
            {
                if (PrivacyDown) return new(HttpStatusCode.ServiceUnavailable);
                if (request.Method == HttpMethod.Patch)
                {
                    using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                    if (RefuseNextPatch) { RefuseNextPatch = false; return new(HttpStatusCode.Conflict); }
                    if (body.RootElement.GetProperty("expectedRevision").GetInt64() != PrivacyRevision) return new(HttpStatusCode.Conflict);
                    var wanted = body.RootElement.GetProperty("locations").GetInt32();
                    // Like Hong Kong: without an independent name only a superset of the current bits is accepted.
                    // Here "cannot configure" stands for an unusable identity: Hong Kong stores the choice and shows 0.
                    var effective = CanConfigure ? Locations : 0;
                    if (!CanConfigure && (wanted & effective) != effective) return new(HttpStatusCode.UnprocessableEntity);
                    Locations = wanted; PrivacyRevision++;
                }
                var privacy = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, revision = PrivacyRevision,
                    locations = CanConfigure ? Locations : 0, canConfigure = CanConfigure, identityStamp = new string('a', 64) }) };
                if (request.Method == HttpMethod.Get) { var after = AfterPrivacyRead; AfterPrivacyRead = null; after?.Invoke(); }
                return privacy;
            }
            if (request.Method == HttpMethod.Patch)
            {
                Check(path == "/app-api/starbridge/v1/personal-profile/callsign" &&
                    request.Headers.Authorization?.Parameter == "synthetic-write-token", "callsign route uses a write grant");
                CallSignWrites++;
                if (CallSignStatus != HttpStatusCode.OK) return new(CallSignStatus);
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                if (body.RootElement.GetProperty("expectedRevision").GetInt64() != ProfileRevision) return new(HttpStatusCode.Conflict);
                var name = body.RootElement.GetProperty("callSign").GetString()!;
                if (name.Length == 0 && !RestoreSupported) return new(HttpStatusCode.BadRequest);
                CallSign = name.Length == 0 ? DefaultName : name; ProfileRevision++;
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, revision = ProfileRevision, callSign = CallSign }) };
            }
            Check(request.Method == HttpMethod.Get && path == "/app-api/starbridge/v1/personal-profile", "profile read");
            if (ProfileDown) return new(HttpStatusCode.ServiceUnavailable);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new StarBridge.Core.Profiles.PersonalProfileDocumentContract(
                3, "fixture-public", false, ProfileRevision, DateTimeOffset.UnixEpoch, new(CallSign, "Verified-Handle", null),
                StarBridge.Core.Profiles.PersonalProfileContentContract.Empty, null)) };
        }
    }
}
