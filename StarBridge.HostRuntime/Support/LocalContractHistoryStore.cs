using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

// Contract-only disk operations. Never changes the v1 device journal's format or behavior.
// Construct only on the background writer/clear path, under LocalContractHistory's gate.
internal sealed class LocalContractHistoryStore : IDisposable
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly string _path;
    private readonly Func<DateTimeOffset> _now;
    private readonly FileStream _lease;
    internal LocalContractHistoryStore(string directory, Func<DateTimeOffset> now)
    {
        CheckTree(directory);
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, LocalEventJournalReader.ContractFileName);
        _now = now;
        _lease = new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite,
            FileShare.None, 1, FileOptions.DeleteOnClose);
    }
    internal LocalEventJournalSnapshot Read()
    {
        var disk = new LocalEventJournalReader(Path.GetDirectoryName(_path)!, _now).ReadContract(Path.GetDirectoryName(_path)!);
        if (!disk.Available) throw new IOException("Contract history is unavailable.");
        return disk;
    }
    internal void Save(IEnumerable<LocalEventEntry> entries, LocalEventJournalSnapshot disk, Func<bool> current)
    {
        void Guard() { if (!current()) throw new OperationCanceledException(); }
        var now = _now();
        var rows = entries.Where(e => e.OccurredAt <= now.AddMinutes(5) && now - e.OccurredAt <= LocalEventJournalReader.Retention)
            .DistinctBy(e => e.Id).OrderBy(e => e.OccurredAt).TakeLast(LocalEventJournalReader.MaximumEntries).ToArray();
        CheckTree(Path.GetDirectoryName(_path)!);
        if (disk.State == "ready") WriteAtomic(_path + ".bak", disk.Entries.ToArray(), Guard);
        WriteAtomic(_path, rows, Guard);
    }
    internal void Clear(Action guard)
    {
        // Explicit confirmed clear does not deserialize corrupt primary or backup.
        CheckTree(Path.GetDirectoryName(_path)!);
        WriteAtomic(_path, [], guard);
        guard();
        File.Delete(_path + ".bak");
    }
    private static void WriteAtomic(string path, LocalEventEntry[] rows, Action guard)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            guard();
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, rows, Json);
                if (stream.Length > LocalEventJournalReader.MaximumFileBytes) throw new IOException("Contract history size limit.");
                stream.Flush(true);
            }
            guard();
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try { File.Delete(temporary); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
    private static void CheckTree(string path)
    {
        for (var directory = new DirectoryInfo(path); directory is not null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
    }
    public void Dispose() => _lease.Dispose();
}