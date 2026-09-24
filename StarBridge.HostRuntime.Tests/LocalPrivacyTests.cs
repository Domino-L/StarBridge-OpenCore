using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class LocalPrivacyTests
{
    private static readonly BridgeAccountContext Owner = new("test", "https://privacy.invalid", "MixedCaseOwner");
    private static LocalPrivacySettings Settings => new(true,
        new(PlayerSharedStateFields.Presence | PlayerSharedStateFields.Server, true, false, ["group-1"]),
        new(PlayerSharedStateFields.Location | PlayerSharedStateFields.SharedEvents, true));

    public static Task Storage()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        Require(store.Read(Owner) is { Revision: 0, Settings: null }, "Missing is not default consent.");
        Require(!Directory.Exists(fixture.Root), "Read does not create or migrate files.");
        var op = Guid.NewGuid().ToString("N");
        var first = store.Save(Owner, 0, op, Settings, () => true);
        var reopened = new LocalPrivacyStore(fixture.Root).Read(Owner);
        Require(reopened.Revision == 1 && reopened.Settings!.Fleet.Fields == Settings.Fleet.Fields &&
            reopened.Settings.Room.Fields == Settings.Room.Fields && reopened.Settings.Fleet.VisibilityGroupIds.Single() == "group-1",
            "Both axes and group references survive reopening independently.");
        Require(store.Save(Owner, 0, op, Settings, () => true).SavedAt == first.SavedAt, "Uncertain response retry is idempotent.");
        Expect("privacy_local.conflict", () => store.Save(Owner, 0, op, Settings with { PublicationEnabled = false }, () => true));
        Expect("privacy_local.conflict", () => store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true));
        foreach (var other in new[] { Owner with { Subject = "other" }, Owner with { Subject = "mixedcaseowner" },
            Owner with { Environment = "other" }, Owner with { Authority = "https://other.invalid" } })
            Require(store.Read(other).Settings is null, "Owner dimensions, including case, remain separate.");
        var checks = 0;
        Expect("privacy_local.account_changed", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Settings, () => ++checks < 3));
        Require(store.Read(Owner).Revision == 1 && !Directory.EnumerateFiles(fixture.Root, "*.tmp", SearchOption.AllDirectories).Any(),
            "Account change immediately before replacement preserves prior settings and cleans only its temp file.");
        var groups = new[] { "original" };
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Settings with { Fleet = Settings.Fleet with { VisibilityGroupIds = groups } },
            () => { groups[0] = "mutated"; return true; });
        Require(store.Read(Owner).Settings!.Fleet.VisibilityGroupIds.Single() == "original", "Save snapshots mutable inputs.");
        return Task.CompletedTask;
    }

    public static Task FailClosed()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        var path = Directory.GetFiles(Path.Combine(fixture.Root, "privacy-local-v1"), "*.json").Single();
        var original = File.ReadAllText(path);
        using (var locked = new FileStream(path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Expect("privacy_local.write_failed", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Settings, () => true));
        Require(File.ReadAllText(path) == original, "Exclusive writer cannot overwrite another writer.");
        foreach (var broken in new[] { "{}", original.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            original.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            original.Replace("\"publicationEnabled\":true", "\"publicationEnabled\":false"), new string('x', 17000) })
        {
            File.WriteAllText(path, broken);
            Expect("privacy_local.read_failed", () => store.Read(Owner));
            Expect("privacy_local.read_failed", () => store.Save(Owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults, () => true));
            Require(File.ReadAllText(path) == broken, "Corrupt data is neither reset nor overwritten with permissive defaults.");
        }
        File.WriteAllText(path, original);
        foreach (var settings in new[] {
            Settings with { Fleet = Settings.Fleet with { Fields = (PlayerSharedStateFields)64 } },
            Settings with { Room = Settings.Room with { Fields = (PlayerSharedStateFields)(-1) } },
            Settings with { Fleet = Settings.Fleet with { VisibilityGroupIds = ["a", "A"] } },
            Settings with { Fleet = Settings.Fleet with { VisibilityGroupIds = [" padded "] } },
            Settings with { Fleet = Settings.Fleet with { VisibilityGroupIds = Enumerable.Range(0, 13).Select(i => i.ToString()).ToArray() } }
        }) Expect("privacy_local.invalid_request", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), settings, () => true));
        Require(File.ReadAllText(path) == original, "Invalid fields and audiences never mutate saved preferences.");
        return Task.CompletedTask;
    }

    public static Task Contract()
    {
        using var fixture = new Fixture();
        var store = new LocalPrivacyStore(fixture.Root);
        var current = (Context: (BridgeAccountContext?)Owner, Generation: 4L);
        var dispatcher = new LocalPrivacyDispatcher(store, () => current);
        BridgeEnvelope Request(string name, object body) =>
            BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 4, body, Owner);
        var read = Request("privacy.localRead", new { schemaVersion = 1 });
        var response = dispatcher.Dispatch(read).Response;
        Require(response.Error is null && !response.Payload.GetProperty("publicationAvailable").GetBoolean() &&
            !response.Payload.TryGetProperty("settings", out _), "Local read cannot claim remote publication or implicit consent.");
        Require(dispatcher.Dispatch(read with { AccountContext = Owner with { Subject = "other" } }).Response.Error?.Code == "privacy_local.account_changed", "Foreign owner rejected.");
        Require(dispatcher.Dispatch(read with { SessionGeneration = 3 }).Response.Error?.Code == "privacy_local.account_changed", "Stale generation rejected.");
        var save = Request("privacy.localSave", new { schemaVersion = 1, expectedRevision = 0, operationId = Guid.NewGuid().ToString("N"), settings = Settings });
        Require(dispatcher.Dispatch(save, new CancellationToken(true)).Response.Error is not null && !Directory.Exists(fixture.Root), "Cancelled write has no storage side effect.");
        Require(dispatcher.Dispatch(save).Response.Error is null && dispatcher.Dispatch(save).Response.Error is null &&
            store.Read(Owner).Revision == 1, "Save and lost-response retry use one revision.");
        foreach (var malformed in new[] { "{}", "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":1,\"extra\":true}" })
            Require(dispatcher.Dispatch(read with { Payload = JsonDocument.Parse(malformed).RootElement.Clone() }).Response.Error?.Code == "privacy_local.invalid_request", "Strict read contract.");
        var payload = save.Payload.GetRawText();
        foreach (var malformed in new[] { payload.Replace("\"publicationEnabled\":true,", ""),
            payload.Replace("\"allMembersCanView\":true", "\"allMembersCanView\":true,\"visibilityGroupIds\":[\"retired\"]"),
            payload.Replace("\"fields\":9", "\"fields\":999") })
            Require(dispatcher.Dispatch(save with { Payload = JsonDocument.Parse(malformed).RootElement.Clone() }).Response.Error is not null,
                "Missing consent, retired room groups and unknown field bits fail.");
        current = (null, 5);
        Require(dispatcher.Dispatch(read).Response.Error?.Code == "privacy_local.account_changed", "Logout invalidates old reads.");
        current = (Owner, 6);
        Require(dispatcher.Dispatch(save).Response.Error?.Code == "privacy_local.account_changed", "Same account relogin invalidates old edit leases.");
        return Task.CompletedTask;
    }

    private static void Expect(string code, Action action)
    {
        try { action(); } catch (LocalPrivacyException e) when (e.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-privacy-test-" + Guid.NewGuid().ToString("N"));
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
}
