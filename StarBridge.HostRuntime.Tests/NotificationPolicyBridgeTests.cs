using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class NotificationPolicyBridgeTests
{
    private sealed class Directory : IBridgeRequestDispatcher {
        internal DateTimeOffset Joined = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        internal bool Fail, Empty, NoPrimary, SameName;
        internal Action? During;
        internal int Calls;
        internal BridgeAccountContext Owner = new("fixture", "fixture", "owner");
        internal bool Legacy;
        internal bool OfficialMember = true;
        internal bool SwitchAfterOfficialRead;
        internal int OfficialReads;
        internal Action? DuringOfficial;
        internal string OfficialSource = "officialFleet:7";
        internal string Freshness = "live";
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public void Dispose() { }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) {
            if (request.Name == "account.getCurrent") return ValueTask.FromResult(new BridgeDispatchBatch(
                BridgeEnvelope.Response(request, new { schemaVersion = 1, state = Legacy ? "legacySignedIn" : "signedIn" }, Owner, preserveRequestAccountContext: false), []));
            if (request.Name == "officialFleet.getIdentity") {
                OfficialReads++; DuringOfficial?.Invoke();
                var response = BridgeEnvelope.Response(request, new { schemaVersion = 1, freshness = Freshness, state = OfficialMember ? "member" : "notMember",
                    fleet = OfficialMember ? new { sourceRef = OfficialSource, name = "Fixture official fleet" } : null });
                if (SwitchAfterOfficialRead) { SwitchAfterOfficialRead = false; OfficialSource = "officialFleet:8"; }
                return ValueTask.FromResult(new BridgeDispatchBatch(response, []));
            }
            Check(request.Name == "privacy.communityTargets", "Only existing membership directory or deferred official identity can be read.");
            Calls++; During?.Invoke();
            return ValueTask.FromResult(new BridgeDispatchBatch(Fail ? BridgeEnvelope.ErrorResponse(request, new("unavailable", "fixture")) :
                BridgeEnvelope.Response(request, new CommunitySharingTargets(2, Empty || NoPrimary ? null : "A",
                    Empty ? [] : SameName ? [new("A", "Fixture organization", Joined), new("B", "Fixture organization", Joined)] :
                    [new("A", "Fixture organization", Joined)])), []));
        }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "notification-policy-bridge-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try {
            var owner = new BridgeAccountContext("fixture", "fixture", "owner");
            BridgeAccountContext? active = owner;
            var directory = new Directory();
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1);
            using var bridge = new NotificationPolicyBridgeDispatcher(settings, directory, () => (active, 1));
            Task<BridgeDispatchBatch> Read(BridgeAccountContext? context) => bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.read",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, context)).AsTask();
            var response = (await Read(owner)).Response;
            Check(response.Status == "ok" && response.Payload.GetProperty("revision").GetInt64() == 0, "Read starts without implicit write.");
            Check(new[] { "roomMode", "friendMode", "directMessageMode" }.All(field =>
                response.Payload.GetProperty(field).GetString() == "normal"), "All built-in source modes are explicitly projected.");
            var key = response.Payload.GetProperty("sources")[0].GetProperty("sourceRef").GetString()!;
            Check(response.Payload.GetProperty("sources")[0].EnumerateObject().Select(p => p.Name).Order().SequenceEqual(
                new[] { "displayName", "kind", "mode", "sourceRef" }), "V1 read row keys remain unchanged, with no organization code or null logo.");
            directory.NoPrimary = true;
            Check((await Read(owner)).Response.Status == "ok", "Community members without a primary fleet can read source rules.");
            var operation = Guid.NewGuid().ToString("N");
            Task<BridgeDispatchBatch> Save(string source, string op, long revision = 0) => bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.save",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1, expectedRevision = revision, operationId = op,
                    rules = new[] { new { sourceRef = source, mode = "importantOnly" } } }, owner)).AsTask();
            Check((await Save(key, operation)).Response.Status == "ok", "Authorized rules save through bridge.");
            Check((await Save(key, operation)).Response.Payload.GetProperty("revision").GetInt64() == 1, "Retry returns the same revision.");
            Check((await Save(key, Guid.NewGuid().ToString("N"))).Response.Status != "ok", "Stale editor cannot overwrite.");
            Check((await Save("organization:" + new string('f', 64), Guid.NewGuid().ToString("N"), 1)).Response.Status != "ok", "Unknown organization cannot be written.");
            var calls = directory.Calls;
            Check((await Read(owner with { Subject = "other" })).Response.Status != "ok" && directory.Calls == calls, "Wrong owner rejected before network.");
            directory.Fail = true;
            Check((await Save(key, Guid.NewGuid().ToString("N"), 1)).Response.Status != "ok" && settings.ReadPolicies(owner).Revision == 1,
                "Unavailable membership does not commit a draft.");
            directory.Fail = false; directory.Empty = true;
            Check((await Read(owner)).Response.Status == "ok", "Accounts without communities can read built-in source rules.");
            Check((await Save(key, Guid.NewGuid().ToString("N"), 1)).Response.Status != "ok", "Departed source cannot be saved.");
            directory.Empty = false; directory.During = () => active = null;
            Check((await Save(key, Guid.NewGuid().ToString("N"), 1)).Response.Status != "ok" && settings.ReadPolicies(owner).Revision == 1,
                "Account changes during membership reads cannot commit.");

            var v2Root = Path.Combine(root, "v2");
            using var v2Settings = new NotificationSettingsBridgeDispatcher(v2Root, () => 1);
            var v2Directory = new Directory { SameName = true };
            BridgeAccountContext? v2Owner = owner;
            using var v2 = new NotificationPolicyBridgeDispatcher(v2Settings, v2Directory, () => (v2Owner, 1));
            var v2Read = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.readV2", Guid.NewGuid().ToString("N"),
                1, new { schemaVersion = 2 }, owner))).Response;
            Check(v2Read.Status == "ok", "actual source policy dispatcher must support explicitly advertised V2 official source reads");
            using (var wire = JsonDocument.Parse(JsonSerializer.Serialize(v2Read, BridgeProtocol.JsonOptions))) {
                var rows = wire.RootElement.GetProperty("payload").GetProperty("sources").EnumerateArray().ToArray();
                var communities = rows.Where(row => row.GetProperty("kind").GetString() == "community").ToArray();
                Check(communities.Length == 2 && communities.Select(row => row.GetProperty("displayName").GetString()).Distinct().Count() == 1,
                    "Same-name organizations remain distinct notification sources.");
                foreach (var code in new[] { "A", "B" }) {
                    var row = communities.Single(row => row.GetProperty("organizationCode").GetString() == code);
                    Check(row.GetProperty("sourceRef").GetString() == NotificationPolicyStore.Organization(code, v2Directory.Joined),
                        "V2 read reports the membership code alongside its unchanged opaque source reference.");
                    Check(row.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(
                        new[] { "displayName", "kind", "mode", "organizationCode", "sourceRef" }), "V2 community wire row keys include organizationCode.");
                }
                var fleet = rows.Single(row => row.GetProperty("kind").GetString() == "officialFleet");
                Check(!fleet.TryGetProperty("organizationCode", out _) && fleet.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(
                    new[] { "displayName", "kind", "mode", "sourceRef" }), "Main fleet wire row omits organizationCode entirely.");
            }
            v2Directory.SameName = false;
            v2Directory.Freshness = "retained";
            var retained = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.readV2", Guid.NewGuid().ToString("N"),
                1, new { schemaVersion = 2 }, owner))).Response;
            Check(retained.Status != "ok", "retained official identity cannot grant a current notification source");
            v2Directory.Freshness = "live";
            var official = v2Read.Payload.GetProperty("sources").EnumerateArray().Single(row => row.GetProperty("kind").GetString() == "officialFleet");
            var officialKey = official.GetProperty("sourceRef").GetString()!;
            Check(officialKey == NotificationPolicyStore.OfficialFleet("officialFleet:7"), "V2 uses an independent stable official key");
            var muted = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.saveV2", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 2, expectedRevision = 0, operationId = Guid.NewGuid().ToString("N"), rules = new[] { new { sourceRef = officialKey, mode = "doNotDisturb" } } }, owner))).Response;
            Check(muted.Status == "ok", "official source mode saves through the same policy store");
            Check(muted.Payload.GetProperty("sources").EnumerateArray().All(row => !row.TryGetProperty("organizationCode", out _)),
                "V2 save response keeps its existing row shape.");
            var invalidSave = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.saveV2", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 2, expectedRevision = 1, operationId = Guid.NewGuid().ToString("N"), rules = new[] {
                    new { sourceRef = key, mode = "normal", organizationCode = "A" } } }, owner))).Response;
            Check(invalidSave.Error?.Code == "notificationPolicies.invalid_request" && v2Settings.ReadPolicies(owner).Revision == 1,
                "Organization code is read-only and is rejected in save rules without writing.");
            var v1Read = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.read", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, owner))).Response;
            Check(v1Read.Status == "ok" && v1Read.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
                v1Read.Payload.GetProperty("sources").EnumerateArray().All(row => row.GetProperty("kind").GetString() == "community"), "V1 wire remains community-only");
            var communityKey = v1Read.Payload.GetProperty("sources")[0].GetProperty("sourceRef").GetString()!;
            var v1Save = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.save", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, expectedRevision = 1, operationId = Guid.NewGuid().ToString("N"), rules = new[] { new { sourceRef = communityKey, mode = "normal" } } }, owner))).Response;
            Check(v1Save.Status == "ok" && v2Settings.ReadPolicies(owner).For(officialKey) == NotificationSourceMode.DoNotDisturb,
                "an older V1 editor must not silently unmute the official source it cannot represent");
            async Task<BridgeEnvelope> SaveV2(string source) => (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.saveV2", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 2, expectedRevision = 2, operationId = Guid.NewGuid().ToString("N"), rules = new[] { new { sourceRef = source, mode = "normal" } } }, owner))).Response;
            Check((await SaveV2("officialFleet:" + new string('f', 64))).Status != "ok" && v2Settings.ReadPolicies(owner).Revision == 2,
                "a syntactically valid forged official policy key cannot be saved");
            v2Directory.SwitchAfterOfficialRead = true;
            Check((await SaveV2(officialKey)).Status != "ok" && v2Settings.ReadPolicies(owner).Revision == 2,
                "official source replacement during the final source read cannot commit an old editor");
            v2Directory.OfficialSource = "officialFleet:7";
            v2Directory.DuringOfficial = () => v2Owner = null;
            Check((await SaveV2(officialKey)).Status != "ok" && v2Settings.ReadPolicies(owner).Revision == 2,
                "account loss during official identity reading cannot commit a preference");
            v2Directory.DuringOfficial = null; v2Owner = owner;
            v2Directory.OfficialMember = false;
            var absent = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.readV2", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 2 }, owner))).Response;
            Check(absent.Status == "ok" && absent.Payload.GetProperty("sources").GetArrayLength() == 1,
                "actual notMember is absence, not a fabricated official source");
            Check((await SaveV2(officialKey)).Status != "ok", "departed official source cannot be changed by stale editor");
            v2Directory.Legacy = true;
            var officialCalls = v2Directory.OfficialReads;
            var legacy = (await v2.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.readV2", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 2 }, owner))).Response;
            Check(legacy.Status == "ok" && legacy.Payload.GetProperty("sources").GetArrayLength() == 1 && v2Directory.OfficialReads == officialCalls,
                "explicit legacy owner keeps community rules without trying SCM identity or using primary community as official proof");
        } finally { System.IO.Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
