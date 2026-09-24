using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Support;

internal static class SharedLocalEventJournalTests
{
    internal static async Task ReusesWpfRulesAndSingleWriter()
    {
        using var f = new Fixture();
        using var first = f.Open();
        Check(first.IsWritable, "writer ready");
        var entry = first.Append("ship", "entered", "ship", "details");
        Check(first.Append("ship", "entered", "ship", "details").Id == entry.Id, "WPF two second dedup");
        first.Append("identity", "online", "online", "player");
        first.Append("identity", "online", "online", "player");
        await first.FlushAsync();
        Check(first.Entries.Length == 2 && f.Reader.Read().Entries.Count == 2, "identity dedup");
        Check(LocalGameEventJournal.Classify(FleetEventType.PlayerDied) == "life", "WPF classification");
        using var second = f.Open();
        Check(!second.IsWritable, "second owner rejected");
        Check(await second.ClearAsync() == LocalJournalClearResult.Failed, "nonowner cannot clear");
        Check(f.Reader.Read().Entries.Count == 2, "no rival mutation");
        first.Dispose();
        second.Load();
        Check(second.IsWritable && second.Entries.Length == 2, "lease released and owner reloads");
    }

    internal static async Task ClearCommitsBothFilesAndNeverResurrects()
    {
        using var f = new Fixture();
        using var journal = f.Open();
        journal.Append("session", "start", "old");
        await journal.FlushAsync();
        journal.Append("ship", "enter", "old ship");
        await journal.FlushAsync();
        Check(await journal.ClearAsync() == LocalJournalClearResult.Cleared, "confirmed clear");
        Check(journal.Entries.Length == 0 && f.Reader.Read().Entries.Count == 0, "memory and disk empty");
        Check(JsonDocument.Parse(File.ReadAllText(f.Path + ".bak")).RootElement.GetArrayLength() == 0, "backup cleared");
        File.WriteAllText(f.Path, "broken");
        Check(f.Reader.Read() is { State: "recovered", Entries.Count: 0 }, "corrupt primary cannot restore old entries");
        journal.Append("ship", "enter", "new only");
        await journal.FlushAsync();
        Check(f.Reader.Read().Entries.Single().Title == "new only", "records after clear preserved");
    }

    internal static async Task FailureAndCancellationKeepReadableHistory()
    {
        using var f = new Fixture();
        using var journal = f.Open();
        journal.Append("session", "start", "keep");
        await journal.FlushAsync();
        var before = File.ReadAllBytes(f.Path);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        Check(await journal.ClearAsync(cancellation: cancellation.Token) == LocalJournalClearResult.Cancelled, "pre-cancel");
        int checks = 0;
        Check(await journal.ClearAsync(() => ++checks < 3) == LocalJournalClearResult.Failed, "changed before final commit");
        Check(File.ReadAllBytes(f.Path).SequenceEqual(before) && journal.Entries.Length == 1, "failed clear keeps primary and memory");
        using (var hold = new FileStream(f.Path + ".bak", FileMode.Open, FileAccess.Read, FileShare.Read))
            Check(await journal.ClearAsync() == LocalJournalClearResult.Failed, "locked backup rejects clear");
        Check(f.Reader.Read().Entries.Count == 1, "failure did not pretend empty");
        Check(await journal.ClearAsync() == LocalJournalClearResult.Cleared, "retry succeeds");
    }

    internal static async Task BackupOnlyAndCorruptionAreHonest()
    {
        using var f = new Fixture();
        File.WriteAllText(f.Path, "bad");
        using var journal = f.Open();
        Check(!journal.IsWritable && journal.LastWriteError != null, "unreadable not writable empty");
        Check(await journal.ClearAsync() == LocalJournalClearResult.Failed, "no implicit data destruction");
        File.WriteAllText(f.Path + ".bak", JsonSerializer.Serialize(new[] {
            new LocalEventEntry("one", DateTimeOffset.Now, "ship", "enter", "backup", "detail")
        }, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        journal.Load();
        Check(journal.IsWritable && journal.Entries.Length == 1, "uses existing backup reader");
        Check(File.ReadAllText(f.Path) == "bad", "Load is read only");
        using (var hold = new FileStream(f.Path + ".bak", FileMode.Open, FileAccess.Read, FileShare.Read))
            Check(await journal.ClearAsync() == LocalJournalClearResult.Failed, "cannot clear backup");
        Check(f.Reader.Read().Entries.Count == 1, "only valid copy remains readable on failure");
        Check(await journal.ClearAsync() == LocalJournalClearResult.Cleared, "backup clear succeeds");
    }

    internal static async Task PendingPersistsCannotRestorePreClearState()
    {
        using var f = new Fixture();
        using var journal = f.Open();
        await Task.WhenAll(Enumerable.Range(0, 30).Select(i => Task.Run(() =>
            journal.Append("ship", "enter", "old " + i))));
        await journal.ClearAsync();
        await journal.FlushAsync();
        Check(f.Reader.Read().Entries.Count == 0, "queued old saves use cleared state");
        journal.Append("ship", "enter", "after", "contains\ttab");
        await journal.FlushAsync();
        Check(f.Reader.Read().Entries.Single().Detail == "contains tab", "new normalized record remains readable");
        journal.Dispose();
        Check(await journal.ClearAsync() == LocalJournalClearResult.Failed, "disposed writes rejected");
        Check(!Directory.EnumerateFiles(f.Root, "*.tmp").Any(), "no orphan temp file");
    }

    private static void Check(bool value, string label)
    { if (!value) throw new InvalidOperationException(label); }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("starbridge-shared-journal-").FullName;
        internal string Path => System.IO.Path.Combine(Root, "local-event-log.json");
        internal LocalEventJournalReader Reader => new(Root);
        internal LocalGameEventJournal Open() { var journal = new LocalGameEventJournal(Path); journal.Load(); return journal; }
        public void Dispose() => Directory.Delete(Root, recursive: true);
    }
}
