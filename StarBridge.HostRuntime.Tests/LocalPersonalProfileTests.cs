using StarBridge.HostRuntime.Profiles;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class LocalPersonalProfileTests
{
    private static readonly BridgeAccountContext Owner = new("Test", "https://authority.invalid", "profile-owner");
    private static LocalProfileContent Content => new("测试呼号", "第一行\n第二行", 1, "none",
        [new("favorite-ships", 3, true, 0), new("hangar-summary", 3, true, 1)], null);
    public static Task Storage()
    {
        using var fixture = new Fixture();
        var store = new LocalPersonalProfileStore(fixture.Root);
        Require(store.Read(Owner).Revision == 0, "Missing differs from saved.");
        var operation = Guid.NewGuid().ToString("N");
        var saved = store.Save(Owner, 0, operation, Content, () => true);
        Require(new LocalPersonalProfileStore(fixture.Root).Read(Owner).Content!.CallSign == Content.CallSign, "Reopens UTF-8 data.");
        Require(store.Save(Owner, 0, operation, Content, () => true).SavedAt == saved.SavedAt, "Lost response retries are idempotent.");
        Expect("profile_local.conflict", () => store.Save(Owner, 0, operation, Content with { CallSign = "changed" }, () => true));
        Expect("profile_local.conflict", () => store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Content, () => true));
        foreach (var other in new[] { Owner with { Subject = "other" }, Owner with { Environment = "other" }, Owner with { Authority = "https://other.invalid" } })
            Require(store.Read(other).Revision == 0, "Every owner dimension isolates data.");
        var calls = 0;
        Expect("profile_local.account_changed", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Content, () => ++calls < 2));
        Require(store.Read(Owner).Revision == 1, "Cancellation at commit leaves prior revision.");
        var oldJson = File.ReadAllText(Directory.GetFiles(Path.Combine(fixture.Root, "personal-profile-local-v1"), "*.json").Single());
        Require(!oldJson.Contains("preserveEmptyFields"), "Old checksum shape is unchanged when provenance is absent.");
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Content with { Introduction = "", PreserveEmptyFields = true }, () => true);
        var cleared = new LocalPersonalProfileStore(fixture.Root).Read(Owner);
        Require(cleared.Content!.PreserveEmptyFields && cleared.Content.Introduction == "", "Explicit clears survive reopening.");
        Require(!Directory.EnumerateFiles(fixture.Root, "*.tmp", SearchOption.AllDirectories).Any(), "Own temporary file cleaned.");
        var path = Directory.GetFiles(Path.Combine(fixture.Root, "personal-profile-local-v1"), "*.json").Single();
        var original = File.ReadAllBytes(path);
        using (var locked = new FileStream(path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Expect("profile_local.write_failed", () => store.Save(Owner, 2, Guid.NewGuid().ToString("N"), Content, () => true));
        Require(File.ReadAllBytes(path).SequenceEqual(original), "Busy writer never overwrites.");
        File.WriteAllText(path, "{broken");
        Expect("profile_local.read_failed", () => store.Read(Owner));
        Expect("profile_local.read_failed", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), Content, () => true));
        Require(File.ReadAllText(path) == "{broken", "Corrupt data preserved for recovery.");
        return Task.CompletedTask;
    }
    public static Task Collaboration()
    {
        using var fixture = new Fixture();
        var store = new LocalPersonalProfileStore(fixture.Root);
        var style = new LocalProfilePlayStyle(["pilot", "medic"], ["exploration"], ["medical"]);
        var schedule = new LocalProfileSchedule("America/Regina", "weekends",
            [new([1, 3], "23:30", "02:15"), new([0], "08:07", "08:07")]);
        var content = Content with { PlayStyle = style, Schedule = schedule };
        var saved = store.Save(Owner, 0, Guid.NewGuid().ToString("N"), content, () => true);
        var read = new LocalPersonalProfileStore(fixture.Root).Read(Owner);
        Require(read.Content!.Schedule!.Windows[0].Days.SequenceEqual([1, 3]), "Exact days survive reopen.");
        Require(read.Content.Schedule.TimeZoneId == "America/Regina" && read.Content.Schedule.Rhythm == "weekends",
            "Zone and all WPF rhythms remain explicit.");
        Require(read.Content.Schedule.Windows[1].StartTime == "08:07" &&
            read.Content.PlayStyle!.Roles!.SequenceEqual(["pilot", "medic"]), "Minute precision and roles survive.");
        Require(store.Save(Owner, 0, saved.OperationId!, content, () => true).Revision == 1, "Collaboration retry idempotent.");
        foreach (var bad in new[] {
            content with { PlayStyle = style with { Roles = ["pilot", "pilot"] } },
            content with { PlayStyle = style with { Roles = ["not-a-role"] } },
            content with { PlayStyle = style with { Roles = ["pilot", "gunner", "medic", "scout", "trader", "navigator"] } },
            content with { PlayStyle = style with { Interests = ["pve", "pvp", "mining", "salvage"] } },
            content with { PlayStyle = style with { Support = ["command", "pilot", "gunner", "medical"] } },
            content with { Schedule = schedule with { Rhythm = "unknown" } },
            content with { Schedule = schedule with { TimeZoneId = "" } },
            content with { Schedule = schedule with { TimeZoneId = "Invalid/Zone" } },
            content with { Schedule = schedule with { Windows = [new([], "09:00", "10:00")] } },
            content with { Schedule = schedule with { Windows = [new([1, 1], "09:00", "10:00")] } },
            content with { Schedule = schedule with { Windows = [new([7], "09:00", "10:00")] } },
            content with { Schedule = schedule with { Windows = [new([1], "24:00", "10:00")] } },
            content with { Schedule = schedule with { Windows = [new([1], "9:00", "10:00")] } },
            content with { Schedule = schedule with { Windows = Enumerable.Repeat(schedule.Windows[0], 4).ToArray() } },
        })
        {
            Expect("profile_local.invalid_request", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), bad, () => true));
            Require(store.Read(Owner).Revision == 1, "Invalid fields do not replace good content.");
        }
        var cleared = content with { PlayStyle = new([], [], []), Schedule = new("", "irregular", []) };
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), cleared, () => true);
        Require(store.Read(Owner).Content!.Schedule!.Windows.Count == 0, "Explicit clear differs from missing fields.");
        return Task.CompletedTask;
    }
    public static Task PreviousFormat()
    {
        using var fixture = new Fixture();
        var json = new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web);
        string Hash(byte[] bytes) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes));
        byte[] Encode(object value) => System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(value, json);
        var hash = Hash(Encode(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
        // The exact pre-extension field order/shape, independent of the new record serializer.
        var oldContent = new { callSign = "旧资料", introduction = "保留", avatarStyle = 1, wallpaperId = "none",
            modules = new[] { new { id = "favorite-ships", span = 3, isVisible = true, position = 0 } },
            favoriteShipIds = (string[]?)null };
        var snapshot = new { revision = 4L, savedAt = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero),
            operationId = Guid.NewGuid().ToString("N"), content = oldContent };
        var integrity = Hash(Encode(new { schemaVersion = 1, owner = hash, snapshot }));
        var directory = Path.Combine(fixture.Root, "personal-profile-local-v1");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, hash + ".json");
        var original = Encode(new { schemaVersion = 1, ownerHash = hash, snapshot, integrity });
        File.WriteAllBytes(path, original);
        var store = new LocalPersonalProfileStore(fixture.Root);
        var read = store.Read(Owner);
        Require(read.Revision == 4 && read.Content!.PlayStyle is null && read.Content.Schedule is null,
            "Old integrity validates without pretending absent collaboration was cleared.");
        Require(original.SequenceEqual(File.ReadAllBytes(path)), "Read does not rewrite old data.");
        store.Save(Owner, 4, Guid.NewGuid().ToString("N"), read.Content! with { Introduction = "新简介" }, () => true);
        Require(store.Read(Owner).Content!.CallSign == "旧资料", "Old data remains editable.");
        return Task.CompletedTask;
    }
    public static Task Contract()
    {
        using var fixture = new Fixture();
        var store = new LocalPersonalProfileStore(fixture.Root);
        var hangar = new LocalHangarStore(fixture.Root);
        var current = (Context: (BridgeAccountContext?)Owner, Generation: 4L);
        var dispatcher = new LocalPersonalProfileDispatcher(store, hangar, () => current);
        BridgeEnvelope Request(string name, object body, BridgeAccountContext? owner = null, long generation = 4) =>
            BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, body, owner ?? Owner);
        var read = Request("personalProfile.localRead", new { schemaVersion = 1 });
        Require(dispatcher.Dispatch(read).Response.Error is null, "Normal local read.");
        Require(dispatcher.Dispatch(read with { AccountContext = Owner with { Subject = "other" } }).Response.Error?.Code == "profile_local.account_changed", "Foreign owner rejected.");
        Require(dispatcher.Dispatch(read with { SessionGeneration = 3 }).Response.Error?.Code == "profile_local.account_changed", "Stale generation rejected.");
        Require(dispatcher.Dispatch(Request(read.Name, new { schemaVersion = 1, unexpected = true })).Response.Error is not null, "Unknown read fields rejected.");
        var op = Guid.NewGuid().ToString("N");
        var save = Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 0, operationId = op, content = Content });
        Require(dispatcher.Dispatch(save, new CancellationToken(true)).Response.Error is not null, "Cancelled before write.");
        Require(store.Read(Owner).Revision == 0, "Cancelled write creates no record.");
        Require(dispatcher.Dispatch(save).Response.Error is null, "Saves without any remote writer.");
        Require(dispatcher.Dispatch(save).Response.Error is null && store.Read(Owner).Revision == 1, "Bridge retry no duplicate revision.");
        var inventory = hangar.Save(Owner, 0, "scan", [new("pledge", 0, "Carrack", "Anvil", "fixture")], false, false);
        var selected = Content with { FavoriteShipIds = [inventory.Ships[0].Id] };
        var favorite = Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 1, operationId = Guid.NewGuid().ToString("N"), content = selected });
        Require(dispatcher.Dispatch(favorite).Response.Error is null, "Owned saved instance accepted.");
        var foreign = Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 2, operationId = Guid.NewGuid().ToString("N"), content = Content with { FavoriteShipIds = [Guid.NewGuid().ToString("N")] } });
        Require(dispatcher.Dispatch(foreign).Response.Error?.Code == "profile_local.hangar_changed", "Unknown instance rejected.");
        Require(store.Read(Owner).Revision == 2, "Bad selection cannot overwrite.");
        hangar.Save(Owner, 1, "empty", [], false, true);
        Require(hangar.Read(Owner).FormerShips!.Single().Id == selected.FavoriteShipIds![0], "Removed favorite details retained.");
        Require(dispatcher.Dispatch(Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 2, operationId = Guid.NewGuid().ToString("N"), content = selected with { Introduction = "kept reference" } })).Response.Error is null, "Removed references survive unrelated edits.");
        Require(dispatcher.Dispatch(Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 3, operationId = Guid.NewGuid().ToString("N"), content = Content })).Response.Error is null, "Former favorite can be deselected.");
        Require(dispatcher.Dispatch(Request("personalProfile.localSave", new { schemaVersion = 1, expectedRevision = 4, operationId = Guid.NewGuid().ToString("N"), content = selected })).Response.Error is null, "Former ship can be selected again.");
        current = (null, 5);
        Require(dispatcher.Dispatch(read).Response.Error?.Code == "profile_local.account_changed", "Logout rejects old requests.");
        Expect("profile_local.invalid_request", () => store.Save(Owner, 3, Guid.NewGuid().ToString("N"), Content with { CallSign = new string('x', 33) }, () => true));
        return Task.CompletedTask;
    }
    public static Task FavoriteModules()
    {
        using var fixture = new Fixture();
        var store = new LocalPersonalProfileStore(fixture.Root);
        var a = Guid.NewGuid().ToString("N");
        var b = Guid.NewGuid().ToString("N");
        var content = Content with { Modules = [new("favorite-ships", 1, true, 0, [a]),
            new("favorite-ships-1", 2, false, -1, [b])], FavoriteShipIds = [a, b] };
        var operation = Guid.NewGuid().ToString("N");
        var saved = store.Save(Owner, 0, operation, content, () => true);
        var reopened = new LocalPersonalProfileStore(fixture.Root).Read(Owner);
        Require(reopened.Content!.Modules[0].FavoriteShipIds!.SequenceEqual([a]) &&
            reopened.Content.Modules[1].FavoriteShipIds!.SequenceEqual([b]), "Independent selections survive reopen, including hidden modules.");
        Require(store.Save(Owner, 0, operation, content, () => true).Revision == saved.Revision, "Module retries are idempotent.");
        foreach (var invalid in new[] {
            content with { Modules = [new("favorite-ships", 1, true, 0, [a, b])] },
            content with { Modules = [new("favorite-ships", 1, true, 0, [a]), new("favorite-ships-1", 2, false, -1, [a])] },
            content with { Modules = [new("favorite-ships", 2, true, 0, [a, a])] },
            content with { Modules = [new("hangar-summary", 3, true, 0, [a, b])] },
            content with { Modules = [new("favorite-ships-invalid", 3, true, 0, [a, b])] },
            content with { FavoriteShipIds = [a] }, content with { FavoriteShipIds = null },
        }) {
            Expect("profile_local.invalid_request", () => store.Save(Owner, 1, Guid.NewGuid().ToString("N"), invalid, () => true));
            Require(store.Read(Owner).Revision == 1, "Invalid layout never overwrites prior data.");
        }
        var large = Enumerable.Range(1, 20).Select(i => new LocalProfileLayout($"favorite-ships-{i}", 1, true, (i - 1) * 3, [Guid.NewGuid().ToString("N")])).ToArray();
        var expanded = content with { Modules = large, FavoriteShipIds = large.SelectMany(m => m.FavoriteShipIds!).ToArray() };
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), expanded, () => true);
        Require(store.Read(Owner).Content!.FavoriteShipIds!.Count == 20, "No legacy twelve-ship or nine-cell display cap.");
        return Task.CompletedTask;
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); } catch (LocalProfileException e) when (e.Code == code) { return; }
        throw new Exception($"Expected {code}");
    }
    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-profile-tests", Guid.NewGuid().ToString("N"));
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
}
