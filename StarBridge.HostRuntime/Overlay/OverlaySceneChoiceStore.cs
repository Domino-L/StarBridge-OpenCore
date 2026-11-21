using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>
/// Local member-module preferences. The display fields are omitted from the file
/// while they keep their defaults, so an unchanged file stays readable by older hosts.
/// </summary>
public sealed record InformationOverlayRosterPreferences(
    string[] Pinned,
    string[] Excluded,
    // null = summary ("N more"), "rotate" or "truncate".
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] string? Overflow = null,
    // 0 = as many rows as the panel height allows.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] int RowLimit = 0,
    // 0 = the default interval.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] int RotationIntervalSeconds = 0)
{
    public const int DefaultRotationIntervalSeconds = 10;
    public const int MaximumRowLimit = 20;
    public static InformationOverlayRosterPreferences Empty { get; } = new([], []);

    public string EffectiveOverflow => Overflow ?? "summary";
    public int EffectiveRotationIntervalSeconds =>
        RotationIntervalSeconds == 0 ? DefaultRotationIntervalSeconds : RotationIntervalSeconds;

    internal static bool ValidDisplay(string? overflow, int rowLimit, int rotationIntervalSeconds) =>
        overflow is null or "rotate" or "truncate" &&
        rowLimit is >= 0 and <= MaximumRowLimit &&
        (rotationIntervalSeconds == 0 || rotationIntervalSeconds is >= 5 and <= 60);
}
internal sealed record OverlaySceneChoice(long Revision = 0, string Mode = "auto", string? Code = null)
{
    public InformationOverlayRosterPreferences Roster { get; init; } = InformationOverlayRosterPreferences.Empty;
}

/// <summary>Account-local display choice; never part of a shareable preset.</summary>
internal sealed class OverlaySceneChoiceStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "overlay-source-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private sealed record FileData(int SchemaVersion, string OwnerHash, OverlaySceneChoice Choice);
    private sealed record RowsData(int SchemaVersion, string OwnerHash, int RowLimit, long Revision);
    private const int LegacyMaximumRowLimit = 12;
    internal static string Hash(BridgeAccountContext owner) => Convert.ToHexString(
        SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(owner)));
    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");
    private string RowsPathFor(string hash) => Path.Combine(_directory, hash + ".rows.json");
    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) &&
                File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked source settings path.");
    }
    internal OverlaySceneChoice Read(BridgeAccountContext owner)
    {
        var hash = Hash(owner); var path = PathFor(hash);
        Safe(path);
        if (!File.Exists(path)) return new();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 or > 262144) throw new InvalidDataException();
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        using var document = JsonDocument.Parse(bytes);
        // the base file keeps the duplicate check 0.7.2.1 uses (case-sensitive, objects only); the stricter one is for the
        // rows sidecar alone (review CX-EDITOR-M97-073-R1)
        LegacyUnique(document.RootElement);
        var data = JsonSerializer.Deserialize<FileData>(bytes, Json);
        if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Choice is null ||
            data.Choice.Revision < 0 || !Valid(data.Choice.Mode, data.Choice.Code) || data.Choice.Roster is null ||
            data.Choice.Roster.Pinned is null || data.Choice.Roster.Excluded is null ||
            !InformationOverlayRosterPreferences.ValidDisplay(data.Choice.Roster.Overflow, data.Choice.Roster.RowLimit,
                data.Choice.Roster.RotationIntervalSeconds) ||
            data.Choice.Roster.Pinned.Length + data.Choice.Roster.Excluded.Length > 1000 ||
            data.Choice.Roster.Pinned.Concat(data.Choice.Roster.Excluded).Any(key =>
                key is null || key.Length != 71 || !key.StartsWith("member:", StringComparison.Ordinal) || !key[7..].All(Uri.IsHexDigit)))
            throw new InvalidDataException();
        return ReadRows(hash, data.Choice);
    }
    private static void LegacyUnique(JsonElement node)
    {
        if (node.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in node.EnumerateObject())
        { if (!names.Add(property.Name)) throw new InvalidDataException(); LegacyUnique(property.Value); }
    }
    private static void Unique(JsonElement node)
    {
        if (node.ValueKind == JsonValueKind.Array)
        { foreach (var item in node.EnumerateArray()) Unique(item); return; }
        if (node.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in node.EnumerateObject())
        { if (!names.Add(property.Name)) throw new InvalidDataException(); Unique(property.Value); }
    }
    private OverlaySceneChoice ReadRows(string hash, OverlaySceneChoice choice)
    {
        if (choice.Roster.RowLimit != LegacyMaximumRowLimit) return choice;
        try
        {
            var path = RowsPathFor(hash); Safe(path);
            if (!File.Exists(path)) return choice;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (stream.Length is <= 0 or > 4096) return choice;
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            Unique(document.RootElement);
            // Every field is required, including revision (zero is otherwise a valid default).
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                document.RootElement.EnumerateObject().Count() != 4) return choice;
            var data = JsonSerializer.Deserialize<RowsData>(bytes, Json);
            if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash ||
                data.Revision != choice.Revision || data.RowLimit <= LegacyMaximumRowLimit ||
                data.RowLimit > InformationOverlayRosterPreferences.MaximumRowLimit) return choice;
            return choice with { Roster = choice.Roster with { RowLimit = data.RowLimit } };
        }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException)
        { return choice; }
    }
    internal static bool Valid(string mode, string? code) => mode is "auto" or "room" or "fleet" ? code is null :
        mode == "community" && !string.IsNullOrWhiteSpace(code) && code.Length <= 256 && code == code.Trim() && !code.Any(char.IsControl);
    internal OverlaySceneChoice Save(BridgeAccountContext owner, long revision, string mode, string? code, Func<bool> current,
        InformationOverlayRosterPreferences? roster = null)
    {
        if (!Valid(mode, code) || revision < 0 || revision == long.MaxValue) throw new InvalidDataException();
        Safe(_directory); Directory.CreateDirectory(_directory);
        var hash = Hash(owner);
        var path = PathFor(hash); var rowsPath = RowsPathFor(hash);
        Safe(path); Safe(rowsPath); Safe(path + ".lock");
        using var guard = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        if (Read(owner).Revision != revision) throw new InvalidOperationException("Source revision changed.");
        var choice = new OverlaySceneChoice(revision + 1, mode, code) { Roster = roster ?? Read(owner).Roster };
        if (!InformationOverlayRosterPreferences.ValidDisplay(choice.Roster.Overflow, choice.Roster.RowLimit,
            choice.Roster.RotationIntervalSeconds)) throw new InvalidDataException();
        var legacy = choice with { Roster = choice.Roster with { RowLimit = Math.Min(choice.Roster.RowLimit, LegacyMaximumRowLimit) } };
        var temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        var rowsTemporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            Safe(temporary); Safe(rowsTemporary);
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(stream, new FileData(1, hash, legacy), Json); stream.Flush(true); }
            if (choice.Roster.RowLimit > LegacyMaximumRowLimit)
            {
                using var stream = new FileStream(rowsTemporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                JsonSerializer.Serialize(stream, new RowsData(1, hash, choice.Roster.RowLimit, choice.Revision), Json);
                stream.Flush(true);
            }
            if (!current()) throw new OperationCanceledException();
            Safe(path); Safe(rowsPath);
            // Commit the base first. A crash before publishing the extension falls back to 12;
            // never leave a future extension that could match a later legacy-version write.
            File.Move(temporary, path, true);
            // The base is committed: from here the call returns what is on disk, never throws, so the caller keeps the new
            // revision and later saves still work (review CX-EDITOR-M97-073-R1). A sidecar left behind carries an older
            // revision and is ignored, so a failed publish reads 12 and a failed delete changes nothing.
            try
            {
                if (choice.Roster.RowLimit > LegacyMaximumRowLimit) File.Move(rowsTemporary, rowsPath, true);
                else File.Delete(rowsPath);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return choice.Roster.RowLimit > LegacyMaximumRowLimit ? legacy : choice;
            }
            return choice;
        }
        finally
        {
            if (File.Exists(temporary)) { Safe(temporary); File.Delete(temporary); }
            if (File.Exists(rowsTemporary)) { Safe(rowsTemporary); File.Delete(rowsTemporary); }
        }
    }
}
