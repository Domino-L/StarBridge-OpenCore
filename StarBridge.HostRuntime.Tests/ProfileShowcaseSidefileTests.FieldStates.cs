using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Profiles;

internal static partial class ProfileShowcaseSidefileTests
{
    // The SideFile contract from de78b9e6.
    private sealed record M101SideFile(int SchemaVersion, string OwnerHash,
        IReadOnlyList<PersonalProfileShowcaseContract>? Showcases, IReadOnlyList<string>? AchievementShowcase, string Integrity,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? OperationId = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? MainRole = null);

    private static void M101ReadsShowcasesAfterExplicitClear()
    {
        using var fixture = new Fixture();
        var clear = Content with { Introduction = "", FieldStates = new Dictionary<string, bool> { ["introduction"] = true } };
        var saved = fixture.Save(clear);
        var bytes = File.ReadAllBytes(fixture.Side);
        var side = JsonSerializer.Deserialize<M101SideFile>(bytes, OldJson)!;
        var expectedIntegrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new {
            schemaVersion = 1, side.OwnerHash, side.Showcases, side.AchievementShowcase, side.OperationId
        }, OldJson));
        Check(side.SchemaVersion == 1 && side.OwnerHash == ReadOld(fixture.Main).OwnerHash &&
            side.OperationId == saved.OperationId && side.Integrity == expectedIntegrity &&
            side.Showcases!.SequenceEqual(clear.Showcases!) && side.AchievementShowcase!.SequenceEqual(clear.AchievementShowcase!) &&
            bytes.SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(side, OldJson)), "m101 reads the original showcase bytes and checksum");
        Check(fixture.Store.Read(Owner).Content!.FieldStates!["introduction"], "Matching explicit clear survives reopening");
    }

    private static void OldSaveInvalidatesFieldStates()
    {
        using var fixture = new Fixture();
        fixture.Save(Content with { FieldStates = new Dictionary<string, bool> { ["avatarStyle"] = true, ["wallpaperId"] = true } });
        var statesPath = Path.ChangeExtension(fixture.Main, ".field-states");
        var states = File.ReadAllBytes(statesPath);
        var previous = ReadOld(fixture.Main);
        var snapshot = previous.Snapshot with {
            Revision = 2, OperationId = Guid.NewGuid().ToString("N"),
            Content = previous.Snapshot.Content! with { Introduction = "旧版简介", PreserveEmptyFields = true }
        };
        File.WriteAllBytes(fixture.Main, JsonSerializer.SerializeToUtf8Bytes(previous with {
            Snapshot = snapshot, Integrity = OldIntegrity(previous.OwnerHash, snapshot)
        }, OldJson));
        var read = fixture.Store.Read(Owner);
        Check(read.OperationId == snapshot.OperationId && read.Content is {
            Introduction: "旧版简介", AvatarStyle: 0, WallpaperId: "none", PreserveEmptyFields: true, FieldStates: null
        } && read.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!) &&
            states.SequenceEqual(File.ReadAllBytes(statesPath)), "An old save retains content but its default fields have no import provenance");
    }

    private static void FieldStateInterruption()
    {
        using var fixture = new Fixture();
        var first = fixture.Save(Content with { FieldStates = new Dictionary<string, bool> { ["avatarStyle"] = true } });
        var mainPath = fixture.Main;
        var statesPath = Path.ChangeExtension(mainPath, ".field-states");
        var firstMain = File.ReadAllBytes(mainPath);
        var firstStates = File.ReadAllBytes(statesPath);
        var clear = Content with { Introduction = "", AvatarStyle = 2, FieldStates = new Dictionary<string, bool> { ["introduction"] = true } };
        var second = fixture.Save(clear, first.Revision);
        var secondMain = File.ReadAllBytes(mainPath);
        var secondStates = File.ReadAllBytes(statesPath);

        File.WriteAllBytes(statesPath, firstStates);
        var newer = fixture.Store.Read(Owner);
        Check(newer.OperationId == second.OperationId && newer.Content is {
            Introduction: "", AvatarStyle: 2, FieldStates: null
        }, "New main and old explicit defaults read the new main");
        var repaired = fixture.Save(clear, first.Revision, second.OperationId);
        Check(repaired.Revision == second.Revision && repaired.Content!.FieldStates!["introduction"] &&
            secondMain.SequenceEqual(File.ReadAllBytes(mainPath)) && secondStates.SequenceEqual(File.ReadAllBytes(statesPath)),
            "Same operation repairs only the missing field state write");

        File.WriteAllBytes(mainPath, firstMain);
        var older = fixture.Store.Read(Owner);
        Check(older.OperationId == first.OperationId && older.Content is { Introduction: "简介", AvatarStyle: 0, FieldStates: null },
            "Old main and new explicit defaults read the old main");
    }

    private static void UnusableFieldStates()
    {
        using var fixture = new Fixture();
        var saved = fixture.Save(Content with { AvatarStyle = 2, FieldStates = new Dictionary<string, bool> { ["wallpaperId"] = true } });
        var path = Path.ChangeExtension(fixture.Main, ".field-states");
        const int schemaVersion = 1;
        var ownerHash = new string('A', 64);
        var operationId = saved.OperationId;
        string[] explicitlyEmpty = ["wallpaperId"];
        var integrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion, ownerHash, operationId, explicitlyEmpty }, OldJson));
        foreach (var state in new[] { null, "{broken", JsonSerializer.Serialize(
            new { schemaVersion, ownerHash, operationId, explicitlyEmpty, integrity }, OldJson) })
        {
            if (state is null) File.Delete(path);
            else File.WriteAllText(path, state);
            var read = fixture.Store.Read(Owner);
            Check(read.Content is { Introduction: "简介", AvatarStyle: 2, WallpaperId: "none", FieldStates: null } &&
                read.Content.Showcases!.SequenceEqual(Content.Showcases!) &&
                read.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!),
                "Missing, malformed and correctly checksummed wrong-owner files all leave content intact");
        }
    }
}
