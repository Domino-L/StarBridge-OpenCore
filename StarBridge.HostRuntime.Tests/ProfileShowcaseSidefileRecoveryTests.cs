using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Profiles;

internal static partial class ProfileShowcaseSidefileTests
{
    private static void Conflict(Action save)
    {
        try { save(); throw new Exception("changed operation content accepted"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.conflict") { }
    }

    private static void HalfCommitReplay(bool changed)
    {
        using var f = new Fixture();
        var operationA = Guid.NewGuid().ToString("N");
        f.Save(operation: operationA);
        var main = File.ReadAllBytes(f.Main);
        var side = File.ReadAllBytes(f.Side);
        var cleared = Content with { Showcases = [], AchievementShowcase = [] };
        using (var block = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { f.Save(cleared, 1); throw new Exception("blocked main save succeeded"); }
            catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        }
        // Assert both directions independently, so the old implementation goes red twice.
        if (changed) Conflict(() => f.Save(cleared, 0, operationA));
        else Check(f.Save(Content, 0, operationA).Revision == 1, "original A replay failed");
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main) && File.ReadAllBytes(f.Side).SequenceEqual(side),
            "failed B or replay changed A's committed files");
    }

    private static void MixedBuild61(bool inlineAchievements)
    {
        using var f = new Fixture(); f.Save();
        var file = JsonNode.Parse(File.ReadAllBytes(f.Main))!.AsObject();
        var inline = Content with {
            Showcases = inlineAchievements ? null : [],
            AchievementShowcase = inlineAchievements ? [] : null
        };
        var snapshot = new LocalProfileSnapshot(2, DateTimeOffset.UnixEpoch, Guid.NewGuid().ToString("N"), inline);
        var owner = file["ownerHash"]!.GetValue<string>();
        file["snapshot"] = JsonSerializer.SerializeToNode(snapshot, OldJson);
        file["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, OldJson));
        File.WriteAllBytes(f.Main, JsonSerializer.SerializeToUtf8Bytes(file, OldJson));
        void Verify(LocalProfileSnapshot value)
        {
            var c = value.Content!;
            Check(inlineAchievements
                ? c.Showcases?.SequenceEqual(Content.Showcases!) == true && c.AchievementShowcase?.Count == 0
                : c.Showcases?.Count == 0 && c.AchievementShowcase?.SequenceEqual(Content.AchievementShowcase!) == true,
                "mixed inline/side fields lost values or revived a clear");
        }
        Verify(f.Store.Read(Owner));
        Verify(f.Save(Content with { Introduction = "ordinary edit", Showcases = null, AchievementShowcase = null }, 2));
        Verify(f.Store.Read(Owner));
        Check(ReadOld(f.Main).Snapshot.Revision == 3, "ordinary save did not split inline format");
    }

    private static void SideRetry()
    {
        using var f = new Fixture(); f.Save();
        var oldSide = File.ReadAllBytes(f.Side);
        var operation = Guid.NewGuid().ToString("N");
        // Omitted achievements must survive PreserveShowcases on the repair path too.
        var requested = Content with { Introduction = "B", Showcases = [], AchievementShowcase = null };
        using (var block = new FileStream(f.Side, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { f.Save(requested, 1, operation); throw new Exception("blocked side save succeeded"); }
            catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        }
        var main = File.ReadAllBytes(f.Main);
        var partial = f.Store.Read(Owner);
        Check(partial.Revision == 2 && partial.OperationId == operation && partial.Content!.Introduction == "B" &&
            partial.Content.Showcases!.SequenceEqual(Content.Showcases!), "main commit plus old side not readable");
        Check(File.ReadAllBytes(f.Side).SequenceEqual(oldSide), "failed side commit changed bytes");
        Conflict(() => f.Save(requested with { Introduction = "changed" }, 1, operation));
        Check(File.ReadAllBytes(f.Side).SequenceEqual(oldSide), "conflicting repair wrote sidefile");
        using (var block = new FileStream(f.Side, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { f.Save(requested, 1, operation); throw new Exception("blocked repair succeeded"); }
            catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        }
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main), "failed repair rewrote main");
        var repaired = f.Save(requested, 1, operation);
        Check(repaired.Revision == 2 && repaired.SavedAt == partial.SavedAt &&
            repaired.Content is { Showcases.Count: 0 } &&
            repaired.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!), "repair lost fields or advanced revision");
        Check(JsonNode.Parse(File.ReadAllBytes(f.Side))!["operationId"]!.GetValue<string>() == operation,
            "sidefile lacks committing operation identity");
        var side = File.ReadAllBytes(f.Side);
        Check(f.Save(requested, 1, operation).Revision == 2, "completed retry advanced revision");
        Conflict(() => f.Save(requested with { Showcases = Content.Showcases }, 1, operation));
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main) && File.ReadAllBytes(f.Side).SequenceEqual(side),
            "replay rewrote committed pair");
        Check(f.Store.Read(Owner).Content!.Showcases!.Count == 0, "repair not persisted");
        Check(!Directory.GetFiles(Path.GetDirectoryName(f.Main)!, "*.tmp").Any(), "repair leaked temporary files");
        ReadOld(f.Main);
    }

    private static void LegacySidefile()
    {
        using var f = new Fixture(); f.Save();
        var side = JsonNode.Parse(File.ReadAllBytes(f.Side))!.AsObject();
        side.Remove("operationId"); RehashSide(side);
        File.WriteAllBytes(f.Side, JsonSerializer.SerializeToUtf8Bytes(side, OldJson));
        var read = f.Store.Read(Owner);
        Check(read.Content!.Showcases!.SequenceEqual(Content.Showcases!) &&
            read.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!), "legacy side checksum rejected");
        f.Save(Content with { Showcases = null, AchievementShowcase = null }, 1);
        Check(f.Store.Read(Owner).Content!.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!),
            "save lost legacy side fields");
    }

    private static void MissingSideRetry()
    {
        using var f = new Fixture();
        var operation = Guid.NewGuid().ToString("N");
        // Stop after the first atomic rename, before the sidefile is created.
        try { f.Save(operation: operation, canCommit: () => !Directory.Exists(Path.Combine(f.Root, "personal-profile-local-v1")) ||
            !Directory.GetFiles(Path.Combine(f.Root, "personal-profile-local-v1"), "*.json").Any());
            throw new Exception("account guard did not interrupt side commit"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.account_changed") { }
        Check(!File.Exists(f.Side) && f.Store.Read(Owner).Revision == 1, "expected main-only first commit");
        var main = File.ReadAllBytes(f.Main);
        Check(f.Save(operation: operation).Revision == 1 && File.ReadAllBytes(f.Main).SequenceEqual(main),
            "first-save repair advanced or rewrote main");
        Check(f.Store.Read(Owner).Content!.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!),
            "first-save repair lost side data");
    }
}
