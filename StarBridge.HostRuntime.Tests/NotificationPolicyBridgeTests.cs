using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class NotificationPolicyBridgeTests
{
    private sealed class Directory : IBridgeRequestDispatcher {
        internal DateTimeOffset Joined = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        internal bool Fail, Empty, NoPrimary;
        internal Action? During;
        internal int Calls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public void Dispose() { }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) {
            Check(request.Name == "privacy.communityTargets", "Only existing membership directory can be read.");
            Calls++; During?.Invoke();
            return ValueTask.FromResult(new BridgeDispatchBatch(Fail ? BridgeEnvelope.ErrorResponse(request, new("unavailable", "fixture")) :
                BridgeEnvelope.Response(request, new CommunitySharingTargets(2, Empty || NoPrimary ? null : "A",
                    Empty ? [] : [new("A", "Fixture organization", Joined)])), []));
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
        } finally { System.IO.Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
