using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Support;

public sealed record LocalMissionRecord(string MissionId, string? DefinitionId, string? ContractCode,
    DateTimeOffset? AcceptedAt, DateTimeOffset CompletedAt, string Source,
    bool? Joined = null, bool? Team = null, bool? JoinedFromStart = null, int? Teammates = null);
public sealed record LocalMissionGroup(string Key, string? DefinitionId, string? ContractCode,
    int Count, double? FastestSeconds, DateTimeOffset LastCompletedAt,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? SoloFastestSeconds = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? TeamFastestSeconds = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? JoinedFullFastestSeconds = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] double? JoinedPartialFastestSeconds = null);
internal sealed record MissionRecordsSnapshot(LocalMissionRecord[] Records, long Dropped = 0);
public sealed record MissionRecordsMergeResult(int Added, int AlreadyKnown);

// Same account-directory lease and atomic replace discipline as LocalContractHistoryStore.
internal sealed class LocalMissionRecordsStore : IDisposable
{
    internal const string FileName = "records.json";
    internal const int MaximumRecords = 20000;
    private const long MaximumBytes = 16 * 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly string _path;
    private readonly FileStream _lease;

    internal LocalMissionRecordsStore(string directory)
    {
        CheckTree(directory);
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, FileName);
        CheckFiles();
        _lease = new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite,
            FileShare.None, 1, FileOptions.DeleteOnClose);
    }

    internal MissionRecordsSnapshot Read()
    {
        CheckFiles();
        return TryRead(_path) ?? TryRead(_path + ".bak") ?? new([]);
    }

    private static MissionRecordsSnapshot? TryRead(string path)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > MaximumBytes) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var value = JsonSerializer.Deserialize<MissionRecordsSnapshot>(stream, Json);
            if (value is null || value.Records is null || value.Dropped < 0 || value.Records.Length > MaximumRecords ||
                value.Records.Any(r => r is null || Normalize(r) is null) ||
                value.Records.Select(r => Normalize(r)!.MissionId).Distinct().Count() != value.Records.Length) return null;
            return value with { Records = value.Records.Select(r => Normalize(r)!).ToArray() };
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or ArgumentException)
        { return null; }
    }

    internal MissionRecordsMergeResult Merge(IEnumerable<LocalMissionRecord> incoming, Func<bool> current)
    {
        var disk = Read();
        var rows = disk.Records.ToDictionary(r => r.MissionId, StringComparer.Ordinal);
        var input = incoming.Select(Normalize).OfType<LocalMissionRecord>()
            .GroupBy(r => r.MissionId).Select(g => g.OrderBy(r => r.CompletedAt)
                .ThenBy(r => r.Source, StringComparer.Ordinal).Aggregate(MergeFields)).ToArray();
        var added = input.Count(r => !rows.ContainsKey(r.MissionId));
        foreach (var row in input)
            rows[row.MissionId] = rows.TryGetValue(row.MissionId, out var previous) ? MergeFields(previous, row) : row;
        var dropped = Math.Max(0, rows.Count - MaximumRecords);
        var next = new MissionRecordsSnapshot(rows.Values.OrderBy(r => r.CompletedAt)
            .ThenBy(r => r.MissionId, StringComparer.Ordinal).TakeLast(MaximumRecords).ToArray(), disk.Dropped + dropped);
        CheckFiles();
        // Back up the last readable snapshot, including one recovered from backup.
        if (TryRead(_path) is not null) WriteAtomic(_path + ".bak", disk, current);
        WriteAtomic(_path, next, current);
        return new(added, input.Length - added);
    }

    // Completion is immutable after the first committed record. Batch duplicates are
    // sorted by completion above; empty enrichment and acceptance are order independent.
    internal static LocalMissionRecord MergeFields(LocalMissionRecord first, LocalMissionRecord next)
    {
        var joined = MergeFlag(first.Joined, next.Joined);
        var firstFull = first.Joined == true ? first.JoinedFromStart : null;
        var nextFull = next.Joined == true ? next.JoinedFromStart : null;
        return first with {
            DefinitionId = Choose(first.DefinitionId, next.DefinitionId),
            ContractCode = Choose(first.ContractCode, next.ContractCode),
            // When only one side saw the share push, its time is bounded by the share (an earlier
            // import may have missed that archive and kept a pre-share marker); otherwise earliest.
            AcceptedAt = first.Joined == true != (next.Joined == true) &&
                (first.Joined == true ? first.AcceptedAt : next.AcceptedAt) is { } shared ? shared :
                first.AcceptedAt is not { } a ? next.AcceptedAt : next.AcceptedAt is not { } b ? a : a < b ? a : b,
            Joined = joined,
            // Known limit (scheduler 11-13): live evidence pauses while the session is not
            // identified/connected, so a PlayerJoined seen only during a disconnect can leave
            // a live row solo until the next log import; OR here then promotes it to team.
            Team = MergeFlag(first.Team, next.Team),
            JoinedFromStart = joined != true ? null : firstFull is { } full && nextFull is { } other ?
                full && other : firstFull ?? nextFull,
            Teammates = first.Teammates is { } count && next.Teammates is { } otherCount ?
                Math.Max(count, otherCount) : first.Teammates ?? next.Teammates
        };
    }
    private static bool? MergeFlag(bool? a, bool? b) => a == true || b == true ? true : a ?? b;
    private static string? Choose(string? a, string? b) => a is null ? b : b is null ? a :
        string.CompareOrdinal(a, b) <= 0 ? a : b;

    internal static LocalMissionRecord? Normalize(LocalMissionRecord row)
    {
        if (!Guid.TryParse(row.MissionId, out var mission) || mission == Guid.Empty ||
            row.CompletedAt == default || row.Source is not ("live" or "import")) return null;
        string? Text(string? text) => string.IsNullOrWhiteSpace(text) ? null :
            text.Length > 256 || text.Any(char.IsControl) ? null : text.Trim();
        var definition = Text(row.DefinitionId);
        if (Guid.TryParse(definition, out var id)) definition = id == Guid.Empty ? null : id.ToString("D");
        return row with { MissionId = mission.ToString("D"), DefinitionId = definition,
            ContractCode = Text(row.ContractCode), AcceptedAt = row.AcceptedAt?.ToUniversalTime(),
            CompletedAt = row.CompletedAt.ToUniversalTime() };
    }

    private static void WriteAtomic(string path, MissionRecordsSnapshot rows, Func<bool> current)
    {
        void Guard() { if (!current()) throw new OperationCanceledException(); }
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Guard();
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, rows, Json);
                if (stream.Length > MaximumBytes) throw new IOException("Mission records size limit.");
                stream.Flush(true);
            }
            Guard();
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try { File.Delete(temporary); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private void CheckFiles()
    {
        CheckTree(Path.GetDirectoryName(_path)!);
        foreach (var file in new[] { _path, _path + ".bak", _path + ".lock" })
        {
            try { if (File.GetAttributes(file).HasFlag(FileAttributes.ReparsePoint)) throw new IOException(); }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
    private static void CheckTree(string path)
    {
        for (var directory = new DirectoryInfo(path); directory is not null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
    }
    public void Dispose() => _lease.Dispose();
}
