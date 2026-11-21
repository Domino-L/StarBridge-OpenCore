using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayRowsCompatibilityTests
{
    internal static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-rows-fixture-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("fixture", "scm", "example-rows-owner");
            var hash = OverlaySceneChoiceStore.Hash(owner);
            var path = Path.Combine(root, "overlay-source-v1", hash + ".json");
            var rowsPath = Path.Combine(root, "overlay-source-v1", hash + ".rows.json");
            var store = new OverlaySceneChoiceStore(root);
            var pin = "member:" + new string('A', 64);
            var hide = "member:" + new string('B', 64);
            var preferences = new InformationOverlayRosterPreferences([pin], [hide], "rotate", 20, 15);
            var saved = store.Save(owner, 0, "community", "example-community", () => true, preferences);
            Check(Read0721(path, hash) == 12, "0.7.2.1 independently reads the base file as 12");
            Check(store.Read(owner).Roster.RowLimit == 20, "new host reads 20");
            var goodRows = File.ReadAllText(rowsPath);
            foreach (var bad in new[] {
                "\uFFFDgarbled{", goodRows.Replace("\"rowLimit\":20", "\"rowLimit\":25"),
                goodRows.Replace(hash, "wrong-owner"), goodRows.Replace("\"revision\":1", "\"revision\":2"),
                goodRows.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
                goodRows.Replace("\"rowLimit\":20", "\"rowLimit\":20,\"rowLimit\":19"),
                goodRows.Replace("\"rowLimit\":20", "\"rowLimit\":20,\"extra\":0"),
                goodRows.Replace("\"revision\":1", "\"missingRevision\":1"),
                new string(' ', 4097),
            })
            {
                File.WriteAllText(rowsPath, bad);
                var back = store.Read(owner);
                Check(back.Roster.RowLimit == 12 && back.Mode == "community" && back.Code == "example-community" &&
                    back.Roster.Pinned.SequenceEqual([pin]) && back.Roster.Excluded.SequenceEqual([hide]) &&
                    back.Roster.Overflow == "rotate" && back.Roster.RotationIntervalSeconds == 15,
                    "invalid extension preserves base choice and preferences");
            }
            File.WriteAllText(rowsPath, goodRows);
            var legacy = JsonNode.Parse(File.ReadAllText(path))!;
            legacy["choice"]!["revision"] = saved.Revision + 1;
            legacy["choice"]!["roster"]!["rowLimit"] = 6;
            File.WriteAllText(path, legacy.ToJsonString());
            Check(Read0721(path, hash) == 6 && store.Read(owner).Roster.RowLimit == 6,
                "old-version edit wins over stale extension");
            legacy["choice"]!["roster"]!["rowLimit"] = 12;
            File.WriteAllText(path, legacy.ToJsonString());
            Check(store.Read(owner).Roster.RowLimit == 12, "revision mismatch also wins when base is 12");
            saved = store.Save(owner, saved.Revision + 1, "community", "example-community", () => true, preferences);
            saved = store.Save(owner, saved.Revision, "community", "example-community", () => true,
                preferences with { RowLimit = 8 });
            Check(store.Read(owner).Roster.RowLimit == 8 && !File.Exists(rowsPath), "20 then 8 deletes extension");
            try
            {
                store.Save(owner, saved.Revision, "auto", null, () => true, preferences with { RowLimit = 21 });
                throw new Exception("21 must be rejected");
            }
            catch (InvalidDataException) { }
            Check(store.Read(owner).Revision == saved.Revision, "rejected write does not change revision");
            // A future writer may already have a 20 in the base file; the new reader accepts it.
            legacy = JsonNode.Parse(File.ReadAllText(path))!;
            legacy["choice"]!["roster"]!["rowLimit"] = 20;
            File.WriteAllText(path, legacy.ToJsonString());
            Check(store.Read(owner).Roster.RowLimit == 20, "new reader accepts base-file 20");
            PartialCommit(store, owner, rowsPath);
            CaseVariantBase(root);
            return Task.CompletedTask;
        }
        finally { Directory.Delete(root, true); }
    }

    // A failed sidecar publish or delete after the base is committed: the save returns what is on disk, the revision moves
    // on, and the next save works once the file is free (review CX-EDITOR-M97-073-R1 P2).
    private static void PartialCommit(OverlaySceneChoiceStore store, BridgeAccountContext owner, string rowsPath)
    {
        var prefs = new InformationOverlayRosterPreferences([], [], null, 20, 0);
        var saved = store.Save(owner, store.Read(owner).Revision, "auto", null, () => true, prefs);
        Check(store.Read(owner).Roster.RowLimit == 20 && File.Exists(rowsPath), "partial: 20 saved with its sidecar");
        using (new FileStream(rowsPath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var back = store.Save(owner, saved.Revision, "auto", null, () => true, prefs with { RowLimit = 16 });
            Check(back.Revision == saved.Revision + 1 && back.Roster.RowLimit == 12, "partial: a blocked publish returns the 12 on disk");
            var read = store.Read(owner);
            Check(read.Revision == back.Revision && read.Roster.RowLimit == 12, "partial: the old sidecar is ignored, the revision moved on");
            saved = back;
        }
        saved = store.Save(owner, saved.Revision, "auto", null, () => true, prefs with { RowLimit = 16 });
        Check(store.Read(owner).Roster.RowLimit == 16, "partial: once free, the next save works (16)");
        using (new FileStream(rowsPath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var back = store.Save(owner, saved.Revision, "auto", null, () => true, prefs with { RowLimit = 8 });
            Check(back.Roster.RowLimit == 8 && store.Read(owner).Roster.RowLimit == 8, "partial: a blocked delete still reads 8");
            saved = back;
        }
        saved = store.Save(owner, saved.Revision, "auto", null, () => true, prefs with { RowLimit = 8 });
        Check(store.Read(owner).Roster.RowLimit == 8 && !File.Exists(rowsPath), "partial: once free, the stale sidecar is removed");
    }

    // A base file with a case-variant duplicate ("revision" and "Revision") is read by 0.7.2.1; the new reader keeps
    // reading it (review P3: the base keeps the case-sensitive duplicate check).
    private static void CaseVariantBase(string root)
    {
        var owner = new BridgeAccountContext("fixture", "scm", "example-case-owner");
        var hash = OverlaySceneChoiceStore.Hash(owner);
        var path = Path.Combine(root, "overlay-source-v1", hash + ".json");
        File.WriteAllText(path, "{\"schemaVersion\":1,\"ownerHash\":\"" + hash + "\",\"choice\":{\"revision\":3,\"Revision\":3," +
            "\"mode\":\"auto\",\"roster\":{\"pinned\":[],\"excluded\":[],\"rowLimit\":6}}}");
        Check(Read0721(path, hash) == 6, "case variant: 0.7.2.1 reads it");
        var read = new OverlaySceneChoiceStore(root).Read(owner);
        Check(read.Revision == 3 && read.Roster.RowLimit == 6, "case variant: the new reader reads it too");
    }

    // 0.7.2.1 reader, frozen from archive/20261101/release-0.7.2-20261101-02 OverlaySceneChoiceStore.Read: its DTOs, JSON
    // options, case-sensitive duplicate check and validation, with its own row cap of 12. Nothing here calls current code.
    private sealed record Legacy0721Roster(
        string[] Pinned,
        string[] Excluded,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] string? Overflow = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] int RowLimit = 0,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] int RotationIntervalSeconds = 0)
    {
        public string EffectiveOverflow => Overflow ?? "summary";
        public int EffectiveRotationIntervalSeconds => RotationIntervalSeconds == 0 ? 10 : RotationIntervalSeconds;
        internal static bool ValidDisplay(string? overflow, int rowLimit, int rotationIntervalSeconds) =>
            overflow is null or "rotate" or "truncate" &&
            rowLimit is >= 0 and <= 12 &&
            (rotationIntervalSeconds == 0 || rotationIntervalSeconds is >= 5 and <= 60);
    }
    private sealed record Legacy0721Choice(long Revision = 0, string Mode = "auto", string? Code = null)
    {
        public Legacy0721Roster Roster { get; init; } = new([], []);
    }
    private sealed record Legacy0721File(int SchemaVersion, string OwnerHash, Legacy0721Choice Choice);
    private static readonly JsonSerializerOptions Legacy0721Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    private static int Read0721(string path, string hash)
    {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length is <= 0 or > 262144) throw new InvalidDataException();
        using var document = JsonDocument.Parse(bytes);
        static void Unique(JsonElement node)
        {
            if (node.ValueKind != JsonValueKind.Object) return;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in node.EnumerateObject())
            { if (!names.Add(property.Name)) throw new InvalidDataException(); Unique(property.Value); }
        }
        Unique(document.RootElement);
        var data = JsonSerializer.Deserialize<Legacy0721File>(bytes, Legacy0721Json);
        static bool Valid(string mode, string? code) => mode is "auto" or "room" or "fleet" ? code is null :
            mode == "community" && !string.IsNullOrWhiteSpace(code) && code.Length <= 256 && code == code.Trim() && !code.Any(char.IsControl);
        if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Choice is null ||
            data.Choice.Revision < 0 || !Valid(data.Choice.Mode, data.Choice.Code) || data.Choice.Roster is null ||
            data.Choice.Roster.Pinned is null || data.Choice.Roster.Excluded is null ||
            !Legacy0721Roster.ValidDisplay(data.Choice.Roster.Overflow, data.Choice.Roster.RowLimit,
                data.Choice.Roster.RotationIntervalSeconds) ||
            data.Choice.Roster.Pinned.Length + data.Choice.Roster.Excluded.Length > 1000 ||
            data.Choice.Roster.Pinned.Concat(data.Choice.Roster.Excluded).Any(key =>
                key is null || key.Length != 71 || !key.StartsWith("member:", StringComparison.Ordinal) || !key[7..].All(Uri.IsHexDigit)))
            throw new InvalidDataException();
        return data.Choice.Roster.RowLimit;
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new Exception(message); }
}
