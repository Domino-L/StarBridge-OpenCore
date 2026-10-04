using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using System.Text;
using System.Text.Json;

internal static class MenuBrowserResumeTests
{
    internal static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-browser-resume-").FullName;
        var ownerA = new string('A', 64); var ownerB = new string('B', 64);
        const string address = "https://example.invalid/one?search=synthetic#section";
        var store = new MenuBrowserResumeStore(root);
        try
        {
            Require(store.Read(ownerA) == new MenuBrowserResumeStore.Snapshot(0, true) && !Directory.Exists(Path.Combine(root, "menu-browser-resume-v1")), "read is non-mutating and defaults on");
            store.Remember(ownerA, 0, address, () => true);
            Require(store.Read(ownerA).Url == address, "default remembers only this account's last page");
            store.SetConsent(ownerA, 0, true, () => true);
            store.Remember(ownerA, 1, address, () => true);
            Require(new MenuBrowserResumeStore(root).Read(ownerA).Url == address, "one address survives restart");
            Require(store.Read(ownerB).Url is null && store.Read(ownerB).Enabled, "second authenticated owner uses default without inheriting an address");
            var path = Path.Combine(root, "menu-browser-resume-v1", ownerA + ".bin");
            var committed = File.ReadAllBytes(path);
            Require(!Encoding.UTF8.GetString(committed).Contains("example.invalid") && !Encoding.UTF8.GetString(committed).Contains(ownerA), "DPAPI payload contains no plaintext owner or address");
            foreach (var url in new[] { "file:///C:/", "javascript:alert(1)", "data:text/html,test", "starbridge://account",
                "https://user:pass@example.invalid/", " https://example.invalid/", "https://example.invalid/\n", "https://example.invalid/\\unsafe", "https://example.invalid/a b", "https:///", new string('a', 4097) })
                Reject(() => store.Remember(ownerA, 1, url, () => true), "unsafe address rejected");
            Require(File.ReadAllBytes(path).SequenceEqual(committed), "invalid inputs preserve committed bytes");
            Reject(() => store.SetConsent(ownerA, 0, false, () => true), "stale consent revision rejected");
            int checks = 0;
            Reject(() => store.Remember(ownerA, 1, "https://example.invalid/late", () => ++checks == 1), "revocation during disk I/O cancels commit");
            Require(checks == 2 && File.ReadAllBytes(path).SequenceEqual(committed) && Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 0, "revoked write leaves previous address and no temporary file");
            using (var blocked = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None))
                Reject(() => store.SetConsent(ownerA, 1, false, () => true), "locked save fails without overwriting");
            Require(File.ReadAllBytes(path).SequenceEqual(committed), "failed save preserves address and consent");
            store.SetConsent(ownerA, 1, false, () => true);
            Require(store.Read(ownerA) == new MenuBrowserResumeStore.Snapshot(2, false), "disabling atomically clears address");
            Require(!new MenuBrowserResumeStore(root).Read(ownerA).Enabled, "explicitly disabled setting survives restart despite new default");
            Reject(() => store.Remember(ownerA, 2, address, () => true), "explicitly disabled cannot remember");
            Reject(() => store.Remember(ownerA, 1, address, () => true), "old enabled callback cannot repopulate cleared address");
            store.SetConsent(ownerA, 2, true, () => true);
            Reject(() => store.Remember(ownerA, 1, address, () => true), "re-enabling does not revive old policy revision");
            var unicode = "https://example.invalid/?q=" + new string('字', 4000);
            store.Remember(ownerA, 3, unicode, () => true);
            Require(store.Read(ownerA).Url == unicode, "maximum non-ASCII address remains readable within file budget");
            File.Copy(path, Path.Combine(Path.GetDirectoryName(path)!, ownerB + ".bin"));
            Reject(() => store.Read(ownerB), "ciphertext bound to owner cannot be copied to another account");
            File.WriteAllBytes(path, [1, 2, 3]);
            Reject(() => store.Read(ownerA), "corruption is unknown failure, not silently disabled/empty");
            Reject(() => store.SetConsent(ownerA, 3, true, () => true), "corrupt storage cannot be overwritten by implicit recovery");
            Require(File.ReadAllBytes(path).SequenceEqual(new byte[] { 1, 2, 3 }), "failed read preserves original file");
        }
        finally { Directory.Delete(root, true); }
        await Dispatch();
        Console.WriteLine("PASS browser resume default, explicit disable, encrypted restart, isolation, cancellation, CAS, revocation and exact Host routing");
    }
    private static async Task Dispatch()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-browser-resume-bridge-").FullName;
        (string? OwnerKey, long Generation) scope = (null, 1);
        using var browser = new MenuBrowserResumeBridgeDispatcher(root, () => scope);
        try
        {
            async Task<BridgeEnvelope> Send(string name, object payload, long? generation = null) =>
                (await browser.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation ?? scope.Generation, payload))).Response;
            Require((await Send("menuBrowserResume.read", new { schemaVersion = 1 })).Status == "error", "signed-out account denied even with current generation");
            Require(!Directory.Exists(Path.Combine(root, "menu-browser-resume-v1")), "unsigned read/write creates no file");
            scope = (new string('A', 64), 2);
            Require((await Send("menuBrowserResume.read", new { schemaVersion = 1 })).Payload.GetProperty("enabled").GetBoolean(), "authenticated default on");
            Require((await Send("menuBrowserResume.update", new { schemaVersion = 1, expectedRevision = 0, enabled = true })).Status == "ok", "explicit consent only");
            foreach (var payload in new object[] { new { schemaVersion = 1, owner = "forbidden" }, new { schemaVersion = "1" },
                JsonSerializer.Deserialize<JsonElement>("{\"schemaVersion\":1,\"schemaVersion\":1}"), new { schemaVersion = 2 } })
                Require((await Send("menuBrowserResume.read", payload)).Error?.Code == "menuBrowserResume.invalid_value", "strict read schema and owner rejection");
            foreach (var payload in new object[] { new { schemaVersion = 1, expectedRevision = 1, enabled = "true" },
                new { schemaVersion = 1, expectedRevision = 1.5, enabled = true }, new { schemaVersion = 1, expectedRevision = 1 },
                new { schemaVersion = 1, expectedRevision = 1, enabled = false, path = "forbidden" } })
                Require((await Send("menuBrowserResume.update", payload)).Status == "error", "strict update types and no arbitrary paths");
            const string url = "https://example.invalid/synthetic";
            var remembered = await Send("menuBrowserResume.remember", new { schemaVersion = 1, expectedRevision = 1, url });
            Require(remembered.Status == "ok" && remembered.AccountContext is null && remembered.Payload.GetProperty("url").GetString() == url, "exact current-account reply without identity echo");
            scope = (new string('B', 64), 3);
            Require((await Send("menuBrowserResume.remember", new { schemaVersion = 1, expectedRevision = 1, url }, 2)).Status == "error", "old generation cannot write new owner");
            Require((await Send("menuBrowserResume.read", new { schemaVersion = 1 })).Payload.GetProperty("url").ValueKind == JsonValueKind.Null, "new owner has no old address");
            var context = new BridgeAccountContext("synthetic", "synthetic", "synthetic");
            Require((await browser.DispatchAsync(BridgeEnvelope.Request("menuBrowserResume.read", Guid.NewGuid().ToString("N"), 3, new { schemaVersion = 1 }, context))).Response.Status == "error", "renderer account spoof rejected");
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            Require((await browser.DispatchAsync(BridgeEnvelope.Request("menuBrowserResume.read", Guid.NewGuid().ToString("N"), 3, new { schemaVersion = 1 }), cancelled.Token)).Response.Status == "cancelled", "cancelled read returns no address");
            using var inert = new Inert();
            using var composed = new CompositeBridgeDispatcher(inert, inert, inert, menuBrowserResume: browser);
            var request = BridgeEnvelope.Request("menuBrowserResume.read", Guid.NewGuid().ToString("N"), 3, new { schemaVersion = 1 });
            Require((await composed.DispatchAsync(request)).Response.Status == "ok", "production composite routes exact read to the browser owner");
            Require((await composed.DispatchAsync(request with { Name = "menuBrowserResume.unknown" })).Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "unknown prefix cannot reach new capability");
            foreach (var name in MenuBrowserResumeBridgeDispatcher.Capabilities) Require(!BridgeRequestPolicy.RequiresAccountContext(name), "shared policy derives owner only in Host");
            browser.Dispose();
            Require((await Send("menuBrowserResume.read", new { schemaVersion = 1 })).Status == "error", "disposed owner returns no address");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Reject(Action action, string name)
    { try { action(); } catch (Exception) { return; } throw new Exception(name); }
    private static void Require(bool value, string name) { if (!value) throw new Exception(name); }
    private sealed class Inert : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) => throw new Exception("wrong owner");
        public void Dispose() { }
    }
}
