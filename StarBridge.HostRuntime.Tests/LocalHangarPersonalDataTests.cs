using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class LocalHangarPersonalDataTests
{
    public static void Verify()
    {
        var root = Directory.CreateTempSubdirectory("sb-hangar-personal-data-");
        var owner = new BridgeAccountContext("test", "synthetic", "owner");
        try
        {
            var store = new LocalHangarStore(root.FullName);
            CollectedHangarShip[] observed = [new("pack", 0, "Carrack", "Anvil", null), new("pack", 1, "Carrack", "Anvil", null)];
            var first = store.Save(owner, 0, "seed", observed, false, false);
            var path = Directory.GetFiles(Path.Combine(root.FullName, "hangar-local-v1"), "*.json").Single();
            var legacy = File.ReadAllBytes(path);
            Require(!File.ReadAllText(path).Contains("Nickname") && !File.ReadAllText(path).Contains("Notes"), "Absent fields preserve the legacy wire checksum shape.");
            _ = new LocalHangarStore(root.FullName).Read(owner);
            Require(File.ReadAllBytes(path).SequenceEqual(legacy), "Opening legacy data does not rewrite it.");
            var a = first.Ships[0].Id; var b = first.Ships[1].Id;
            var marked = store.SetFavorite(owner, 1, "mark", a, true);
            const string png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
            var image = store.SaveCustomImage(owner, 2, "image", a, png);
            var saved = store.SavePersonalData(owner, 3, "data", a, "  Serenity  ", "  Personal notes\r\nSecond line\ttext  ");
            Require(saved.Ships.Single(s => s.Id == a) is { Nickname: "Serenity", Notes: "Personal notes\nSecond line\ttext", IsFavorite: true }, "Personal fields normalize and stay attached to one instance.");
            Require(saved.Ships.Single(s => s.Id == b).Nickname is null && saved.Ships.Single(s => s.Id == a).CustomImagePath == image.Ships.Single(s => s.Id == a).CustomImagePath,
                "A duplicate's metadata and the existing custom image are independent.");
            Require(saved.InventorySavedAt == first.InventorySavedAt && saved.SavedAt >= image.SavedAt, "Local edits preserve the RSI inventory time.");
            var retry = store.SavePersonalData(owner, 3, "data", a, "Serenity", "Personal notes\nSecond line\ttext");
            Require(retry.Revision == saved.Revision && retry.SavedAt == saved.SavedAt, "Identical retries do not write again.");
            var before = File.ReadAllBytes(path);
            Expect("hangar.revision_conflict", () => store.SavePersonalData(owner, 3, "data", a, "Changed", null));
            Expect("hangar.revision_conflict", () => store.SavePersonalData(owner, 3, "stale", a, "Changed", null));
            Expect("hangar.ship_unavailable", () => store.SavePersonalData(owner, 4, "unknown", Guid.NewGuid().ToString("N"), "Other", null));
            Expect("hangar.account_changed", () => store.SavePersonalData(owner, 4, "cancelled", a, "Other", null, () => false));
            foreach (var invalid in new[] { new string('x', 65), "line\nbreak", "bad\0text", "\uD800" })
                Expect("hangar.invalid_personal_data", () => store.SavePersonalData(owner, 4, "invalid", a, invalid, null));
            Expect("hangar.invalid_personal_data", () => store.SavePersonalData(owner, 4, "invalid-notes", a, null, new string('x', 2001)));
            Require(File.ReadAllBytes(path).SequenceEqual(before), "Rejected edits preserve every byte.");
            var publication = JsonSerializer.Serialize(CommunityHangarPublication.Build(saved));
            Require(!publication.Contains("Serenity") && !publication.Contains("Personal notes") && publication.Contains("Carrack"), "Community projection excludes private metadata and keeps the model.");
            var partial = store.Save(owner, 4, "partial", [observed[0]], true, false);
            Require(partial.Ships.Single(s => s.Id == a).Nickname == "Serenity" && partial.Ships.Count == 2, "Partial scans retain per-instance fields.");
            var grown = store.Save(owner, 5, "increase", [.. observed, observed[0] with { ItemIndex = 9 }], false, false);
            var newId = grown.Ships.Single(s => s.Id != a && s.Id != b).Id;
            Require(grown.Ships.Single(s => s.Id == newId).Nickname is null, "New duplicates do not inherit a nickname.");
            var archived = store.Save(owner, 6, "archive", [observed[0]], false, false, removedShipIds: [a, newId]);
            Require(archived.FormerShips!.Single(s => s.Id == a).Notes == "Personal notes\nSecond line\ttext", "N1 archive preserves notes and nickname with the selected ID.");
            var editedHistory = store.SavePersonalData(owner, 7, "history-data", a, "Nora", "");
            Require(editedHistory.FormerShips!.Single(s => s.Id == a).Nickname == "Nora" && editedHistory.FormerShips!.Single(s => s.Id == a).Notes is null &&
                editedHistory.InventorySavedAt == archived.InventorySavedAt && editedHistory.Ships.Single().Id == b, "Historical instances remain editable without changing current ownership or RSI time.");
            var emoji = string.Concat(Enumerable.Repeat("👩‍🚀", 64));
            var unicode = store.SavePersonalData(owner, 8, "unicode", a, emoji, null);
            Require(unicode.FormerShips!.Single(s => s.Id == a).Nickname == emoji, "The length limit counts displayed graphemes, not UTF-16 halves.");
            var cleared = store.SavePersonalData(owner, 9, "clear", a, "  ", null);
            Require(new LocalHangarStore(root.FullName).Read(owner).FormerShips!.Single(s => s.Id == a).Nickname is null && cleared.Revision == 10, "Clearing and reopening preserve normalized absence.");
            VerifyBridge(root.FullName + "-bridge");
        }
        finally { root.Delete(true); }
    }

    private static void VerifyBridge(string root)
    {
        try
        {
            var store = new LocalHangarStore(root);
            using var test = new HangarLockedScanTests.Harness(store);
            var first = store.Save(test.Owner.Account, 0, "seed", [new("hidden-pledge", 0, "Carrack", null, null)], false, false);
            var response = test.Send("personalData", new JsonObject { ["expectedRevision"] = 1, ["shipId"] = first.Ships[0].Id, ["nickname"] = "Local alias", ["notes"] = "Private notes" });
            Require(response.Error is null && response.Payload.GetProperty("ships")[0].GetProperty("nickname").GetString() == "Local alias" &&
                response.Payload.GetProperty("ships")[0].GetProperty("notes").GetString() == "Private notes" && !response.Payload.GetRawText().Contains("hidden-pledge"), "The guarded local bridge projects fields without exposing pledge keys.");
            var injected = test.Send("personalData", new JsonObject { ["expectedRevision"] = 2, ["shipId"] = first.Ships[0].Id,
                ["nickname"] = "Forged", ["notes"] = null, ["title"] = "Different model" });
            Require(injected.Error?.Code == "hangar.invalid_observation" && store.Read(test.Owner.Account).Revision == 2, "Client cannot edit authoritative model fields.");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); throw new Exception("Expected " + code); }
        catch (LocalHangarStoreException error) when (error.Code == code) { }
    }
}
