using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

/// <summary>Account copy of the local hangar (user 11-05, default on). Synthetic data only; no network.</summary>
internal static class HangarCloudSyncTests
{
    private static readonly BridgeAccountContext Owner = new("Test", "https://authority.invalid", "synthetic-owner");
    private static readonly BridgeAccountContext Other = new("Test", "https://authority.invalid", "synthetic-other");

    public static async Task Verify()
    {
        ArchiveCarriesBusinessFieldsOnly();
        RestoreWritesOnlyIntoANeverSavedHangarInTheNormalFormat();
        SettingsDefaultOnAndSurviveDamage();
        await UploadsTheLocalHangarAfterSavesAndLocalWinsAConflict();
        await NothingIsUploadedWhenEmptyLegacyOrAnotherAccount();
        await RestoresOnlyEmptyAccountsAndReportsIt();
        await ThereIsNoSwitchAndAnEarlierOffIsIgnored();
        await SignInUploadsAnExistingHangarAndRequestsAreStrict();
        await ServerSwitchOffShowsNoAccountCopy();
        await FirstOpenShowsOneStateUntilTheServerAnswers();
        Console.WriteLine("PASS hangar cloud: archive fields, restore-only-empty, upload/conflict, off/delete, legacy and account isolation");
    }

    private static CollectedHangarShip Ship(string pledge, int index, string title) =>
        new(pledge, index, title, "Anvil Aerospace", "synthetic acquisition");

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception("hangar cloud: " + message);
    }

    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-hangar-cloud-tests", Guid.NewGuid().ToString("N"));
        public Fixture() => Directory.CreateDirectory(Root);
        public void Dispose() { try { Directory.Delete(Root, true); } catch (IOException) { } }
    }

    private sealed class FakeRemote : IHangarArchiveRemote
    {
        public bool Supported = true;
        public long Revision;
        public JsonElement? Archive;
        public bool ConflictOnce;
        public bool FailDelete;
        public readonly List<(string Kind, long Expected, int Bytes)> Calls = [];
        public bool Supports(BridgeAccountContext owner, long generation) => Supported && owner == Owner && generation == 1;
        public Task<HangarArchiveReadResult> ReadArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            lock (Calls) Calls.Add(("read", 0, 0));
            return Task.FromResult(new HangarArchiveReadResult(HangarArchiveOutcome.Ok, Archive is not null, Revision, Archive));
        }
        public Task<HangarArchiveWriteResult> WriteArchiveAsync(BridgeAccountContext owner, long generation, long expected,
            byte[] archive, CancellationToken token)
        {
            lock (Calls) Calls.Add(("write", expected, archive.Length));
            if (ConflictOnce) { ConflictOnce = false; Revision += 5; return Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.Conflict, Revision)); }
            if (expected != Revision) return Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.Conflict, Revision));
            Revision++;
            Archive = JsonDocument.Parse(archive).RootElement.Clone();
            return Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.Ok, Revision));
        }
        public Task<HangarArchiveWriteResult> DeleteArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            lock (Calls) Calls.Add(("delete", 0, 0));
            if (FailDelete) return Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.RateLimited, 0));
            Archive = null; Revision++;
            return Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.Ok, Revision));
        }
    }

    private static HangarAccountIdentity Identity(BridgeAccountContext account) =>
        new(account, 1, new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Unknown, null, null));

    private static HangarCloudSync Sync(LocalHangarStore store, string root, FakeRemote remote,
        Func<HangarAccountIdentity?> current, List<long>? changed = null) =>
        new(store, new HangarCloudSettingsStore(root), remote, current, g => changed?.Add(g),
            delay: (_, _) => Task.CompletedTask, debounce: TimeSpan.Zero);

    private static async Task Until(Func<bool> condition, string message)
    {
        for (var i = 0; i < 200 && !condition(); i++) await Task.Delay(10);
        Require(condition(), message);
    }

    private static void ArchiveCarriesBusinessFieldsOnly()
    {
        var now = DateTimeOffset.UtcNow;
        var ship = new LocalHangarShip(Guid.NewGuid().ToString("N"), "pledge-1", "Carrack", "Anvil Aerospace", "acq", now,
            CustomImagePath: "C:\\Users\\x\\secret.png", CustomImageCrop: new(0, 0, 1, 1), IsFavorite: true,
            Nickname: "旗舰", Notes: "备注");
        var snapshot = new LocalHangarSnapshot(3, now, "op", [ship], false);
        var json = System.Text.Encoding.UTF8.GetString(HangarArchive.Serialize(HangarArchive.FromSnapshot(snapshot)));
        Require(!json.Contains("customImage", StringComparison.OrdinalIgnoreCase) && !json.Contains("secret.png") &&
                !json.Contains("crop", StringComparison.OrdinalIgnoreCase), "images and crops never leave the device");
        foreach (var field in new[] { "\"schemaVersion\":1", "pledge-1", "Carrack", "\"nickname\":", "\"notes\":", "\"isFavorite\":true" })
            Require(json.Contains(field), "archive keeps " + field);
        var parsed = HangarArchive.Parse(JsonDocument.Parse(json).RootElement);
        Require(parsed.Ships.Single().Nickname == "旗舰" && parsed.Ships.Single().IsFavorite, "archive round trip");
        foreach (var bad in new[] { "{\"schemaVersion\":2,\"partial\":false,\"ships\":[]}",
                     "{\"schemaVersion\":1,\"partial\":false,\"ships\":[],\"cookies\":\"x\"}", "[]" })
        {
            try { HangarArchive.Parse(JsonDocument.Parse(bad).RootElement); throw new Exception("hangar cloud: accepted " + bad); }
            catch (LocalHangarStoreException error) when (error.Code == "hangar.archive_invalid") { }
        }
    }

    private static void RestoreWritesOnlyIntoANeverSavedHangarInTheNormalFormat()
    {
        using var test = new Fixture();
        var source = new LocalHangarStore(test.Root);
        source.Save(Other, 0, "source", [Ship("p1", 0, "Carrack"), Ship("p2", 0, "Vulture")], false, false);
        var withNote = source.Read(Other);
        source.SavePersonalData(Other, withNote.Revision, "note", withNote.Ships[0].Id, "旗舰", "备注");
        var archive = HangarArchive.FromSnapshot(source.Read(Other));

        var store = new LocalHangarStore(test.Root);
        var restored = store.RestoreFromArchive(Owner, archive, Guid.NewGuid().ToString("N"));
        Require(restored is { Revision: 1 } && restored.Ships.Count == 2, "restore into an empty account");
        // A fresh store reads the restored file: same envelope and fields as a normal save (0.7.2.x reads it; 0.7.1 cannot read any current save).
        var reread = new LocalHangarStore(test.Root).Read(Owner);
        Require(reread.Ships.Count == 2 && reread.Ships.Any(s => s.Nickname == "旗舰" && s.Notes == "备注"),
            "restored hangar is a normal hangar-local-v1 file with notes");
        Require(reread.Ships.Select(s => s.Id).OrderBy(x => x).SequenceEqual(archive.Ships.Select(s => s.Id).OrderBy(x => x)),
            "instance ids survive, so later saves still match ships");
        Require(store.RestoreFromArchive(Owner, archive, Guid.NewGuid().ToString("N")) is null,
            "an existing local hangar is never replaced");
        // Later normal saves keep working on the restored file.
        var after = store.Save(Owner, reread.Revision, "after-restore", [Ship("p1", 0, "Carrack"), Ship("p2", 0, "Vulture")], false, false);
        Require(after.Revision == reread.Revision + 1 && after.Ships.Any(s => s.Nickname == "旗舰"), "notes survive a later RSI save");
    }

    private static void SettingsDefaultOnAndSurviveDamage()
    {
        using var test = new Fixture();
        var settings = new HangarCloudSettingsStore(test.Root);
        Require(settings.Read(Owner) == HangarCloudSettingsStore.Default && settings.Read(Owner).Enabled, "default on");
        settings.Save(Owner, new(false, true));
        Require(settings.Read(Owner) == new HangarCloudSettingsStore.Settings(false, true), "choice persists");
        Require(settings.Read(Other).Enabled, "per account");
        foreach (var file in Directory.GetFiles(Path.Combine(test.Root, "hangar-cloud-v1"), "*.json"))
            File.WriteAllText(file, "{\"schemaVersion\":1}");
        Require(settings.Read(Owner) == HangarCloudSettingsStore.Unreadable && !settings.Read(Owner).Enabled, "a damaged choice counts as off, never silently back on");
    }

    private static async Task UploadsTheLocalHangarAfterSavesAndLocalWinsAConflict()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var remote = new FakeRemote { Revision = 4, Archive = JsonDocument.Parse("{\"schemaVersion\":1,\"partial\":false,\"ships\":[]}").RootElement };
        using var sync = Sync(store, test.Root, remote, () => Identity(Owner));
        store.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        sync.LocalSaved(Owner, 1);
        await Until(() => remote.Revision == 5, "uploaded at the server's current revision");
        Require(remote.Calls.Any(c => c is ("write", 4, > 0)), "write used the read revision");
        remote.ConflictOnce = true;
        var current = store.Read(Owner);
        store.SetFavorite(Owner, current.Revision, "fav", current.Ships[0].Id, true);
        sync.LocalSaved(Owner, 1);
        await Until(() => remote.Archive?.GetRawText().Contains("\"isFavorite\":true") == true, "conflict retried once at the newer revision");
    }

    private static async Task NothingIsUploadedWhenEmptyLegacyOrAnotherAccount()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var remote = new FakeRemote();
        HangarAccountIdentity? identity = Identity(Owner);
        using var sync = Sync(store, test.Root, remote, () => identity);
        sync.LocalSaved(Owner, 1);           // nothing saved locally yet
        await Task.Delay(100);
        Require(!remote.Calls.Any(c => c.Kind == "write"), "an empty local hangar is never uploaded");
        store.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        remote.Supported = false;           // legacy (non-SCM) sign-in
        sync.LocalSaved(Owner, 1);
        await Task.Delay(100);
        Require(!remote.Calls.Any(), "legacy accounts never upload or read");
        remote.Supported = true;
        sync.LocalSaved(Other, 1);          // not the current account
        await Task.Delay(100);
        Require(!remote.Calls.Any(), "another account's save is ignored");
    }

    private static async Task RestoresOnlyEmptyAccountsAndReportsIt()
    {
        using var test = new Fixture();
        var source = new LocalHangarStore(Path.Combine(test.Root, "other-device"));
        source.Save(Owner, 0, "src", [Ship("p1", 0, "Carrack"), Ship("p2", 0, "Vulture")], false, false);
        var archive = JsonSerializer.SerializeToElement(HangarArchive.FromSnapshot(source.Read(Owner)), HangarArchive.Json);
        var store = new LocalHangarStore(test.Root);
        var remote = new FakeRemote { Revision = 7, Archive = archive };
        var changed = new List<long>();
        using var sync = Sync(store, test.Root, remote, () => Identity(Owner), changed);
        await sync.RestoreIfEmptyAsync();
        Require(store.Read(Owner).Ships.Count == 2 && changed.Contains(1), "restored and announced");
        var view = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "c1", 1, new { schemaVersion = 1 }, Owner), default);
        Require(view.Response.Payload.GetProperty("restoredShips").GetInt32() == 2, "restore count reported once");
        await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudAcknowledge", "c2", 1,
            new { schemaVersion = 1, notice = "restored" }, Owner), default);
        view = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "c3", 1, new { schemaVersion = 1 }, Owner), default);
        Require(!view.Response.Payload.TryGetProperty("restoredShips", out var left) || left.ValueKind == JsonValueKind.Null, "acknowledged");

        // An account that already has a local hangar is never overwritten.
        using var second = new Fixture();
        var existing = new LocalHangarStore(second.Root);
        existing.Save(Owner, 0, "mine", [Ship("x", 0, "Cutlass")], false, false);
        using var sync2 = Sync(existing, second.Root, new FakeRemote { Revision = 7, Archive = archive }, () => Identity(Owner));
        await sync2.RestoreIfEmptyAsync();
        Require(existing.Read(Owner).Ships.Single().Title == "Cutlass", "non-empty local hangar wins");
    }

    // User 11-05: "存到账号应该是必须的". No switch, no off-and-delete, and an "off" saved by an earlier
    // 0.7.3 build no longer stops anything.
    private static async Task ThereIsNoSwitchAndAnEarlierOffIsIgnored()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        new HangarCloudSettingsStore(test.Root).Save(Owner, new(false, false));
        var remote = new FakeRemote { Revision = 2, Archive = JsonDocument.Parse("{\"schemaVersion\":1,\"partial\":false,\"ships\":[]}").RootElement };
        using var sync = Sync(store, test.Root, remote, () => Identity(Owner));
        var set = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudSet", "k", 1,
            new { schemaVersion = 1, enabled = false, deleteAccountCopy = true }, Owner), default);
        Require(set.Response.Status != BridgeResponseStatuses.Ok && !remote.Calls.Any(c => c.Kind == "delete"),
            "the switch request is gone and never deletes");
        sync.LocalSaved(Owner, 1);
        await Until(() => remote.Revision == 3, "an earlier 'off' no longer stops the upload");
        var view = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "v", 1, new { schemaVersion = 1 }, Owner), default);
        Require(!view.Response.Payload.TryGetProperty("enabled", out _), "no switch state on the wire");
        var wrongAccount = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "w", 1,
            new { schemaVersion = 1 }, Other), default);
        Require(wrongAccount.Response.Error?.Code == "hangar.account_changed", "requests are bound to the current account");

        // A never-saved hangar is restored even when an earlier build stored "off".
        using var empty = new Fixture();
        new HangarCloudSettingsStore(empty.Root).Save(Owner, new(false, false));
        var source = new LocalHangarStore(Path.Combine(empty.Root, "other-device"));
        source.Save(Owner, 0, "src", [Ship("p9", 0, "Vulture")], false, false);
        var emptyStore = new LocalHangarStore(empty.Root);
        using var emptySync = Sync(emptyStore, empty.Root, new FakeRemote { Revision = 1,
            Archive = JsonSerializer.SerializeToElement(HangarArchive.FromSnapshot(source.Read(Owner)), HangarArchive.Json) },
            () => Identity(Owner));
        await emptySync.RestoreIfEmptyAsync();
        Require(emptyStore.Read(Owner).Ships.Single().Title == "Vulture", "restored regardless of an earlier 'off'");
    }

    private static async Task SignInUploadsAnExistingHangarAndRequestsAreStrict()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "upgraded", [Ship("p1", 0, "Carrack")], false, false);
        var remote = new FakeRemote();
        using var sync = Sync(store, test.Root, remote, () => Identity(Owner));
        await sync.RestoreIfEmptyAsync();
        await Until(() => remote.Revision == 1, "an existing local hangar is uploaded once on sign-in (0.7.2 upgrades)");
        Require(store.Read(Owner).Ships.Single().Title == "Carrack", "sign-in never restores over a local hangar");
        foreach (var bad in new object[] {
            new { schemaVersion = 1.5 },
            new { schemaVersion = 1, enabled = true } })
        {
            var response = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "bad", 1, bad, Owner), default);
            Require(response.Response.Error?.Code == "hangar.invalid_request", "strict request: " + bad);
        }
        var ack = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudAcknowledge", "n", 1,
            new { schemaVersion = 1, notice = 3 }, Owner), default);
        Require(ack.Response.Error?.Code == "hangar.invalid_request", "notice must be text");
    }

    private static async Task ServerSwitchOffShowsNoAccountCopy()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        var remote = new OffRemote();
        using var sync = new HangarCloudSync(store, new HangarCloudSettingsStore(test.Root), remote, () => Identity(Owner), _ => { },
            delay: (_, _) => Task.CompletedTask, debounce: TimeSpan.Zero);
        sync.LocalSaved(Owner, 1);
        await Until(() => remote.Reads > 0, "tried once");
        await Task.Delay(50);
        var view = await sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "v", 1, new { schemaVersion = 1 }, Owner), default);
        Require(!view.Response.Payload.GetProperty("available").GetBoolean(), "server switch off reads as unavailable");

        // The restore path (a never-saved account) learns it the same way.
        using var empty = new Fixture();
        var emptyRemote = new OffRemote();
        using var emptySync = new HangarCloudSync(new LocalHangarStore(empty.Root), new HangarCloudSettingsStore(empty.Root),
            emptyRemote, () => Identity(Owner), _ => { }, delay: (_, _) => Task.CompletedTask, debounce: TimeSpan.Zero);
        await emptySync.RestoreIfEmptyAsync();
        var emptyView = await emptySync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", "e", 1, new { schemaVersion = 1 }, Owner), default);
        Require(!emptyView.Response.Payload.GetProperty("available").GetBoolean(), "restore path: server off reads as unavailable");

        var settings = new HangarCloudSettingsStore(empty.Root);
        Parallel.For(0, 40, i => settings.Update(Owner, s => i % 2 == 0 ? s with { NoticeShown = true } : s with { Enabled = false }));
        Require(settings.Read(Owner) == new HangarCloudSettingsStore.Settings(false, true), "concurrent updates never undo each other");
    }

    // build 65: the first open showed the switch (unasked server = available), the next open the local line.
    private static async Task FirstOpenShowsOneStateUntilTheServerAnswers()
    {
        static Task<StarBridge.HostRuntime.BridgeDispatchBatch> Read(HangarCloudSync sync, string id) =>
            sync.DispatchAsync(BridgeEnvelope.Request("hangarReader.cloudRead", id, 1, new { schemaVersion = 1 }, Owner), default);
        static bool Available(StarBridge.HostRuntime.BridgeDispatchBatch view) => view.Response.Payload.GetProperty("available").GetBoolean();

        // Before the HK release: a local hangar exists, the endpoint is a 404. Never available, on any open.
        using var off = new Fixture();
        var offStore = new LocalHangarStore(off.Root);
        offStore.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        var offRemote = new OffRemote();
        using var offSync = new HangarCloudSync(offStore, new HangarCloudSettingsStore(off.Root), offRemote, () => Identity(Owner), _ => { });
        Require(!Available(await Read(offSync, "o1")), "first open before the release: this computer only");
        Require(!Available(await Read(offSync, "o2")), "second open before the release: this computer only");

        // The server never answers: still this computer only, never the switch.
        using var silent = new Fixture();
        var silentStore = new LocalHangarStore(silent.Root);
        silentStore.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        using var silentSync = new HangarCloudSync(silentStore, new HangarCloudSettingsStore(silent.Root), new SilentRemote(),
            () => Identity(Owner), _ => { });
        Require(!Available(await Read(silentSync, "s1")), "no answer yet: this computer only");

        // After the release: the first open already shows the switch, and the check uploads nothing by itself.
        using var on = new Fixture();
        var onStore = new LocalHangarStore(on.Root);
        onStore.Save(Owner, 0, "first", [Ship("p1", 0, "Carrack")], false, false);
        var onRemote = new FakeRemote();
        var changed = new List<long>();
        using var onSync = new HangarCloudSync(onStore, new HangarCloudSettingsStore(on.Root), onRemote, () => Identity(Owner),
            g => { lock (changed) changed.Add(g); }, delay: (_, token) => Task.Delay(Timeout.Infinite, token));
        Require(Available(await Read(onSync, "a1")), "first open after the release: the switch");
        Require(Available(await Read(onSync, "a2")), "and it stays");
        lock (onRemote.Calls) Require(onRemote.Calls.All(c => c.Kind == "read"), "the check only reads");
        lock (onRemote.Calls) Require(onRemote.Calls.Count == 1, "the first open reads the account copy once, not twice");
    }

    private sealed class SilentRemote : IHangarArchiveRemote
    {
        public bool Supports(BridgeAccountContext owner, long generation) => true;
        public async Task<HangarArchiveReadResult> ReadArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        { await Task.Delay(Timeout.Infinite, token); throw new OperationCanceledException(); }
        public Task<HangarArchiveWriteResult> WriteArchiveAsync(BridgeAccountContext owner, long generation, long expected, byte[] archive, CancellationToken token) =>
            throw new Exception("hangar cloud: no write without an answer");
        public Task<HangarArchiveWriteResult> DeleteArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
            throw new Exception("hangar cloud: no delete without an answer");
    }

    private sealed class OffRemote : IHangarArchiveRemote
    {
        public int Reads;
        public bool Supports(BridgeAccountContext owner, long generation) => true;
        public Task<HangarArchiveReadResult> ReadArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        { Interlocked.Increment(ref Reads); return Task.FromResult(new HangarArchiveReadResult(HangarArchiveOutcome.Unsupported, false, 0, null)); }
        public Task<HangarArchiveWriteResult> WriteArchiveAsync(BridgeAccountContext owner, long generation, long expected, byte[] archive, CancellationToken token) =>
            throw new Exception("hangar cloud: no write when the server is off");
        public Task<HangarArchiveWriteResult> DeleteArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
            Task.FromResult(new HangarArchiveWriteResult(HangarArchiveOutcome.Unsupported, 0));
    }
}
