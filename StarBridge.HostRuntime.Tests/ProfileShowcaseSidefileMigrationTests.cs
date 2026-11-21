using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Profiles;

internal static partial class ProfileShowcaseSidefileTests
{
    private static LocalProfileSnapshot SeedInline(Fixture f, bool empty, bool keepSide)
    {
        f.Save();
        var file = JsonNode.Parse(File.ReadAllBytes(f.Main))!.AsObject();
        var snapshot = new LocalProfileSnapshot(1, DateTimeOffset.UnixEpoch, Guid.NewGuid().ToString("N"),
            empty ? Content with { Showcases = [], AchievementShowcase = [] } : Content);
        var owner = file["ownerHash"]!.GetValue<string>();
        file["snapshot"] = JsonSerializer.SerializeToNode(snapshot, OldJson);
        file["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, OldJson));
        File.WriteAllBytes(f.Main, JsonSerializer.SerializeToUtf8Bytes(file, OldJson));
        if (!keepSide) File.Delete(f.Side);
        return snapshot;
    }

    private static void SameSnapshot(LocalProfileSnapshot actual, LocalProfileSnapshot expected, string message) =>
        Check(JsonSerializer.Serialize(actual, OldJson) == JsonSerializer.Serialize(expected, OldJson), message);

    private static void WriteFailed(Action save)
    {
        try { save(); throw new Exception("blocked migration succeeded"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
    }

    private static void NoTemps(Fixture f) =>
        Check(!Directory.GetFiles(Path.GetDirectoryName(f.Main)!, "*.tmp").Any(), "migration leaked temporary files");

    private static void InlineSideFailure(bool empty, bool directory)
    {
        using var f = new Fixture();
        var a = SeedInline(f, empty, !directory);
        var main = File.ReadAllBytes(f.Main);
        var oldSide = directory ? null : File.ReadAllBytes(f.Side);
        var operationB = Guid.NewGuid().ToString("N");
        var requested = Content with { Introduction = "B", Showcases = null, AchievementShowcase = null };
        if (directory) Directory.CreateDirectory(f.Side);
        using (var block = directory ? null : new FileStream(f.Side, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            WriteFailed(() => f.Save(requested, 1, operationB));
            WriteFailed(() => f.Save(requested, 1, operationB));
        }
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main), "side failure removed inline data or changed revision");
        if (directory) Directory.Delete(f.Side);
        else Check(File.ReadAllBytes(f.Side).SequenceEqual(oldSide!), "failed migration changed old side");
        SameSnapshot(f.Store.Read(Owner), a, "migration step 1 failure lost values or revived old values");
        NoTemps(f);
        var saved = f.Save(requested, 1, operationB);
        Check(saved.Revision == 2 && saved.OperationId == operationB, "retry did not commit B exactly once");
        SameSnapshot(saved, a with { Revision = 2, OperationId = operationB, SavedAt = saved.SavedAt,
            Content = a.Content! with { Introduction = "B" } }, "null retry lost inline values or clear");
        SameSnapshot(f.Store.Read(Owner), saved, "save and read differ after migration retry");
        SameSnapshot(f.Save(requested, 1, operationB), saved, "completed B replay differs");
        ReadOld(f.Main);
        NoTemps(f);
    }

    private static void InlineMainFailure(bool empty)
    {
        using var f = new Fixture();
        var a = SeedInline(f, empty, empty);
        var main = File.ReadAllBytes(f.Main);
        var operationB = Guid.NewGuid().ToString("N");
        var requested = Content with { Introduction = "B", Showcases = null, AchievementShowcase = null };
        using (var block = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            WriteFailed(() => f.Save(requested, 1, operationB));
            Check(File.Exists(f.Side), "step 1 did not persist migration sidefile before main rewrite");
            var side = JsonNode.Parse(File.ReadAllBytes(f.Side))!;
            Check(side["operationId"]!.GetValue<string>() == a.OperationId, "migration used B instead of A identity");
            Check(side["showcases"]!.AsArray().Count == a.Content!.Showcases!.Count &&
                side["achievementShowcase"]!.AsArray().Count == a.Content.AchievementShowcase!.Count,
                "step 1 persisted wrong migration values");
            Check(File.ReadAllBytes(f.Main).SequenceEqual(main), "step 2 failure changed inline main");
            SameSnapshot(f.Store.Read(Owner), a, "step 2 failure changed read");
            WriteFailed(() => f.Save(requested, 1, operationB));
        }
        NoTemps(f);
        // Finish migration via the already completed A, before saving B.
        SameSnapshot(f.Save(a.Content, 0, a.OperationId), a, "A retry after step 2 failure changed snapshot");
        Check(ReadOld(f.Main).Snapshot is { Revision: 1 } old && old.SavedAt == a.SavedAt &&
            old.OperationId == a.OperationId, "migration changed original metadata");
        SameSnapshot(f.Store.Read(Owner), a, "migration retry read differs");
        Conflict(() => f.Save(a.Content! with { AchievementShowcase = empty ? Content.AchievementShowcase : [] }, 0, a.OperationId));
        var saved = f.Save(requested, 1, operationB);
        SameSnapshot(f.Store.Read(Owner), saved, "B after migration differs from read");
        Check(saved.Revision == 2 && saved.Content!.Showcases!.Count == a.Content!.Showcases!.Count &&
            saved.Content.AchievementShowcase!.Count == a.Content.AchievementShowcase!.Count, "B retry lost migration data");
        ReadOld(f.Main);
        NoTemps(f);
    }

    private static void InlineOriginalReplay()
    {
        using var f = new Fixture();
        var a = SeedInline(f, false, false);
        var main = File.ReadAllBytes(f.Main);
        SameSnapshot(f.Store.Read(Owner), a, "inline read differs");
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main) && !File.Exists(f.Side), "read performed migration");
        SameSnapshot(f.Save(a.Content, 0, a.OperationId), a, "original A replay changed snapshot");
        var old = ReadOld(f.Main);
        Check(old.Snapshot.Revision == 1 && old.Snapshot.SavedAt == a.SavedAt &&
            old.Snapshot.OperationId == a.OperationId, "A migration changed metadata");
        SameSnapshot(f.Store.Read(Owner), a, "A replay differs from later read");
        var clean = File.ReadAllBytes(f.Main);
        var side = File.ReadAllBytes(f.Side);
        SameSnapshot(f.Save(a.Content, 0, a.OperationId), a, "migrated A replay failed");
        Conflict(() => f.Save(a.Content! with { Showcases = [] }, 0, a.OperationId));
        Conflict(() => f.Save(a.Content! with { AchievementShowcase = [] }, 0, a.OperationId));
        Check(File.ReadAllBytes(f.Main).SequenceEqual(clean) && File.ReadAllBytes(f.Side).SequenceEqual(side),
            "migrated replay rewrote files");
    }

    private static void InlineChangedReplay(bool achievements)
    {
        using var f = new Fixture();
        var a = SeedInline(f, false, false);
        var main = File.ReadAllBytes(f.Main);
        var changed = achievements ? a.Content! with { AchievementShowcase = [] } : a.Content! with { Showcases = [] };
        Conflict(() => f.Save(changed, 0, a.OperationId));
        // The outer precheck must reject even when the write lock cannot be acquired.
        using (var gate = new FileStream(f.Main + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Conflict(() => f.Save(changed, 0, a.OperationId));
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main) && !File.Exists(f.Side), "conflicting A wrote files");
        SameSnapshot(f.Store.Read(Owner), a, "conflicting A changed read");
    }
}
