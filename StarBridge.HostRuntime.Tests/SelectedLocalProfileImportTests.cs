using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Profiles;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class SelectedLocalProfileImportTests
{
    public static Task Run()
    {
        const string ownShip = "11111111111111111111111111111111";
        const string oldShip = "22222222222222222222222222222222";
        var current = new LocalProfileContent("Current", "Keep introduction", 2, "none",
            [new("favorite-ships", 3, true, 6, [ownShip]),
             new("hangar-summary", 3, true, 9)], [ownShip],
            new(["pilot"], ["exploration"], ["medical"]),
            new("", "irregular", []), true);
        var source = new LocalProfileContent("Imported", "Never import this", 1, "other",
            [new("favorite-ships", 2, true, 0, [oldShip]),
             new("skilled-roles", 2, true, 2), new("hangar-summary", 1, false, 4)], [oldShip],
            new(["medic"], [], []), null);
        var original = JsonSerializer.Serialize(current);
        var name = SelectedLocalProfileImport.Project(current, source, new([], [], true));
        Check(name.CallSign == "Imported" && name.Introduction == current.Introduction &&
            name.AvatarStyle == 2 && name.WallpaperId == "none" && name.Schedule == current.Schedule &&
            name.PlayStyle == current.PlayStyle && name.PreserveEmptyFields, "Only selected name changes");
        var avatar = SelectedLocalProfileImport.Project(current, source, new([], [], false, true));
        Check(JsonSerializer.Serialize(avatar) == original, "Avatar choice does not alter local style or fields");
        Expect("profile_local.import_replacement_required", () =>
            SelectedLocalProfileImport.Project(current, source, new(["hangar-summary"], [], false)));
        var layout = SelectedLocalProfileImport.Project(current, source,
            new(["hangar-summary", "skilled-roles"], ["hangar-summary"], false));
        Check(layout.CallSign == "Current" && layout.Modules[1] == new LocalProfileLayout("hangar-summary", 1, true, 9),
            "Replacement preserves current visibility and position");
        Check(layout.Modules[2] == new LocalProfileLayout("skilled-roles", 2, false, -1) &&
            layout.PlayStyle!.Roles!.SequenceEqual(["medic"]), "New module is hidden and selected roles imported");
        var favorites = SelectedLocalProfileImport.Project(current, source,
            new(["favorite-ships"], ["favorite-ships"], false));
        Check(favorites.Modules[0].FavoriteShipIds!.SequenceEqual([ownShip]) &&
            favorites.FavoriteShipIds!.SequenceEqual([ownShip]), "Only current inventory references survive");
        const string secondShip = "33333333333333333333333333333333";
        var multiple = current with
        {
            Modules = [.. current.Modules, new("favorite-ships-1", 1, false, -1, [secondShip])],
            FavoriteShipIds = [ownShip, secondShip]
        };
        var multipleResult = SelectedLocalProfileImport.Project(multiple, source,
            new(["favorite-ships"], ["favorite-ships"], false));
        Check(multipleResult.Modules[2] == multiple.Modules[2] &&
            multipleResult.FavoriteShipIds!.SequenceEqual([ownShip, secondShip]),
            "Other favorite module instances and their selections stay intact");
        Expect("profile_local.import_reselection_required", () => SelectedLocalProfileImport.Project(
            current with { Modules = [new("favorite-ships", 3, true, 0, [ownShip, secondShip])],
                FavoriteShipIds = [ownShip, secondShip] },
            source with { Modules = [new("favorite-ships", 1, true, 0, [oldShip])] },
            new(["favorite-ships"], ["favorite-ships"], false)));
        var empty = current with { Modules = [], FavoriteShipIds = null };
        var added = SelectedLocalProfileImport.Project(empty, source, new(["favorite-ships"], [], false));
        Check(added.Modules[0].FavoriteShipIds!.Count == 0 && added.FavoriteShipIds!.Count == 0 &&
            !added.Modules[0].IsVisible, "New favorite module never copies old inventory references");
        Expect("profile_local.import_source_missing", () => SelectedLocalProfileImport.Project(current,
            source with { Modules = [] }, new(["skilled-roles"], [], false)));
        Expect("profile_local.import_reselection_required", () => SelectedLocalProfileImport.Project(
            current with { Modules = [new("favorite-ships", 3, true, 0)] }, source,
            new(["favorite-ships"], ["favorite-ships"], false)));
        Check(JsonSerializer.Serialize(current) == original, "Projection leaves original snapshot untouched");
        var historic = source with { PlayStyle = new(["旧版自定义岗位"],
            ["舰队行动", "小队任务", "采矿", "探索"], ["医疗救援"]) };
        var historicResult = SelectedLocalProfileImport.Project(current, historic,
            new(["skilled-roles"], [], false));
        Check(historicResult.PlayStyle!.Roles!.SequenceEqual(historic.PlayStyle.Roles!) &&
            historicResult.PlayStyle.Interests!.SequenceEqual(historic.PlayStyle.Interests!) &&
            historicResult.PlayStyle.Support!.SequenceEqual(historic.PlayStyle.Support!),
            "Import preserves bounded historic labels and selections above current editor limits");
        StorageAndIsolation(current, source);
        HistoricLabels(historicResult);
        Console.WriteLine("PASS selected local import field, layout and inventory-reference policy");
        return Task.CompletedTask;
    }
    private static void HistoricLabels(LocalProfileContent content)
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-import-labels-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://authority.invalid", "synthetic-labels");
            var store = new LocalPersonalProfileStore(root);
            Expect("profile_local.invalid_request", () => store.Save(owner, 0,
                Guid.NewGuid().ToString("N"), content, () => true));
            store.SaveImported(owner, 0, Guid.NewGuid().ToString("N"), content, () => true);
            var reopened = new LocalPersonalProfileStore(root).Read(owner).Content!;
            Check(JsonSerializer.Serialize(reopened.PlayStyle) == JsonSerializer.Serialize(content.PlayStyle),
                "Historic labels survive import projection and local store reopen without truncation");
            var edited = reopened with { Introduction = "An unrelated edit" };
            store.Save(owner, 1, Guid.NewGuid().ToString("N"), edited, () => true);
            var removed = edited with { PlayStyle = edited.PlayStyle! with { Roles = [],
                Interests = ["舰队行动", "小队任务", "采矿"] } };
            store.Save(owner, 2, Guid.NewGuid().ToString("N"), removed, () => true);
            Expect("profile_local.invalid_request", () => store.Save(owner, 3, Guid.NewGuid().ToString("N"),
                removed with { PlayStyle = removed.PlayStyle! with { Roles = ["new-unknown"] } }, () => true));
            foreach (var tags in new[] { new[] { "bad\nlabel" }, new[] { new string('x', 81) },
                new[] { "duplicate", "duplicate" }, Enumerable.Range(0, 9).Select(i => "label" + i).ToArray() })
                Expect("profile_local.invalid_request", () => store.SaveImported(owner, 3, Guid.NewGuid().ToString("N"),
                    removed with { PlayStyle = removed.PlayStyle! with { Roles = tags } }, () => true));
            Check(store.Read(owner).Revision == 3, "Invalid new labels and malformed imports do not write");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void StorageAndIsolation(LocalProfileContent seed, LocalProfileContent source)
    {
        // Dedicated synthetic root, never the running client's account store.
        var root = Path.Combine(Path.GetTempPath(), "starbridge-selected-import-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://authority.invalid", "synthetic-owner");
            var other = owner with { Subject = "synthetic-other" };
            var account = (Context: (BridgeAccountContext?)owner, Generation: 1L);
            var store = new LocalPersonalProfileStore(root);
            var hangar = new LocalHangarStore(root);
            var inventory = hangar.Save(owner, 0, "synthetic-scan",
                [new("synthetic-pledge", 0, "Synthetic ship", "Fixture", "fixture")], false, false);
            var shipId = inventory.Ships.Single().Id;
            var initial = seed with { Modules = [new("favorite-ships", 3, true, 6, [shipId])], FavoriteShipIds = [shipId] };
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), initial, () => true);
            var files = Directory.GetFiles(Path.Combine(root, "hangar-local-v1"), "*", SearchOption.AllDirectories)
                .ToDictionary(path => path, File.ReadAllBytes);
            var projected = SelectedLocalProfileImport.Project(initial, source,
                new(["favorite-ships"], ["favorite-ships"], true));
            var dispatcher = new LocalPersonalProfileDispatcher(store, hangar, () => account);
            var request = BridgeEnvelope.Request("personalProfile.localSave", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, expectedRevision = 1, operationId = Guid.NewGuid().ToString("N"), content = projected }, owner);
            Check(dispatcher.Dispatch(request, new CancellationToken(true)).Response.Error is not null &&
                store.Read(owner).Revision == 1, "Cancelled import leaves original local revision");
            account = (other, 2);
            Check(dispatcher.Dispatch(request).Response.Error?.Code == "profile_local.account_changed" &&
                store.Read(other).Revision == 0, "Switched account never receives prior preview");
            account = (owner, 1);
            Check(dispatcher.Dispatch(request).Response.Error is null, "Projected import passes existing save contract");
            Check(dispatcher.Dispatch(request).Response.Error is null && store.Read(owner).Revision == 2,
                "Lost response replay does not duplicate local revision");
            store.Save(owner, 2, Guid.NewGuid().ToString("N"), projected with { Introduction = "New local edit" }, () => true);
            Check(dispatcher.Dispatch(request).Response.Error?.Code == "profile_local.conflict" &&
                store.Read(owner).Content!.Introduction == "New local edit", "Late replay cannot overwrite newer edits");
            Check(new LocalPersonalProfileStore(root).Read(owner).Content!.CallSign == "Imported",
                "Explicit imported call sign survives process reopen");
            Check(files.All(file => File.ReadAllBytes(file.Key).SequenceEqual(file.Value)) &&
                Directory.GetFiles(Path.Combine(root, "hangar-local-v1"), "*", SearchOption.AllDirectories).Length == files.Count,
                "Real local inventory store is byte-for-byte unchanged");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); } catch (LocalProfileException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
}
