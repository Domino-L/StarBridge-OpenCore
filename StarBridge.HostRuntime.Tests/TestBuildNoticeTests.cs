using System.Text.Json;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class TestBuildNoticeTests
{
    public static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-notice-").FullName;
        try
        {
            var reader = new ClientLicenseReader(root);
            var store = new TestBuildNoticeStore(root);
            var path = Path.Combine(root, "official-binary-license.accepted.json");
            await File.WriteAllTextAsync(Path.Combine(root, ClientLicenseReader.FileName), "Synthetic terms");
            long generation = 4;
            using var dispatcher = new ClientLicenseBridgeDispatcher(reader, () => generation, store);
            BridgeEnvelope Request(string name, object? payload = null) => BridgeEnvelope.Request(name,
                Guid.NewGuid().ToString("N"), 4, payload ?? new { schemaVersion = 1 });
            var read = Request(ClientLicenseBridgeDispatcher.NoticeRead);
            var accept = Request(ClientLicenseBridgeDispatcher.NoticeAccept,
                new { schemaVersion = 1, termsVersion = TestBuildNoticeStore.TermsVersion });
            var initial = (await dispatcher.DispatchAsync(read)).Response;
            Require(!initial.Payload.GetProperty("acknowledged").GetBoolean() && !File.Exists(path));
            Require((await dispatcher.DispatchAsync(Request(ClientLicenseBridgeDispatcher.NoticeAccept,
                new { schemaVersion = 1, termsVersion = "wrong" }))).Response.Status == "error");
            generation = 5;
            Require((await dispatcher.DispatchAsync(accept)).Response.Status == "error" && !File.Exists(path));
            generation = 4;
            Require((await dispatcher.DispatchAsync(accept)).Response.Payload.GetProperty("acknowledged").GetBoolean());
            Require(new TestBuildNoticeStore(root).IsAcknowledged());
            // Ordinary binary/document packaging updates do not reset the agreed terms version.
            await File.WriteAllTextAsync(Path.Combine(root, ClientLicenseReader.FileName), "Synthetic updated packaging");
            Require((await dispatcher.DispatchAsync(read)).Response.Payload.GetProperty("acknowledged").GetBoolean());
            // Exact WPF marker shape is reused read-only, without touching any account file.
            var old = JsonSerializer.SerializeToUtf8Bytes(new { SchemaVersion = 1,
                TermsVersion = TestBuildNoticeStore.TermsVersion, AppVersion = "0.6.6.1",
                AcceptedAtUtc = DateTimeOffset.UtcNow, TermsSha256 = "fixture" });
            await File.WriteAllBytesAsync(path, old);
            Require(store.IsAcknowledged() && old.SequenceEqual(await File.ReadAllBytesAsync(path)));
            await File.WriteAllTextAsync(path, "broken");
            Require(!store.IsAcknowledged());
            try { store.Acknowledge(TestBuildNoticeStore.TermsVersion, "fixture", () => false); }
            catch (OperationCanceledException) { }
            Require(await File.ReadAllTextAsync(path) == "broken");
            var privacy = new LocalPrivacyStore(root);
            var owner = new BridgeAccountContext("test", "fixture", "new-user");
            Require(privacy.NeedsFirstChoice(owner));
            await File.WriteAllTextAsync(Path.Combine(root, "onboarding.complete"), "starbridge-onboarding-v6");
            Require(!privacy.NeedsFirstChoice(owner));
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Require(bool value) { if (!value) throw new Exception("First-use notice regression."); }
}
