using System.Text.Json;
using StarBridge.HostRuntime.Support;

internal static class LocalEventJournalReaderTests
{
    public static Task Utf8BomAndBusyWriterAreHandled() => InDirectory(root =>
    {
        var path = Path.Combine(root, "local-event-log.json");
        File.WriteAllText(path, JsonSerializer.Serialize(new[] { Entry("bom", "life") },
            new JsonSerializerOptions(JsonSerializerDefaults.Web)), new System.Text.UTF8Encoding(true));
        var reader = new LocalEventJournalReader(root, () => Now);
        Equal("ready", reader.Read().State);
        using (var writer = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
            Equal("unavailable", reader.Read().State);
        Equal("bom", reader.Read().Entries.Single().Id);
    });

    private static readonly DateTimeOffset Now = new(2026, 9, 10, 12, 0, 0, TimeSpan.Zero);
    public static Task MissingAndMalformedRemainDistinct() => InDirectory(root =>
    {
        var reader = new LocalEventJournalReader(root, () => Now);
        Equal("missing", reader.Read().State);
        Equal(0, Directory.GetFiles(root).Length);
        var path = Path.Combine(root, "local-event-log.json");
        foreach (var invalid in new[] { "", "null", "{}", "[null]", "[{\"id\":\"broken\"}]", "[" })
        {
            File.WriteAllText(path, invalid);
            Equal("unavailable", reader.Read().State);
            Equal(invalid, File.ReadAllText(path));
        }
        // A path that is a directory is inaccessible, not a missing journal.
        File.Delete(path);
        Directory.CreateDirectory(path);
        Equal("unavailable", reader.Read().State);
    });

    public static Task WpfCompatibilityRetentionFilteringAndNoRewrite() => InDirectory(root =>
    {
        var path = Path.Combine(root, "local-event-log.json");
        var rows = new[] { Entry("old", "ship", -31), Entry("current", "ship"), Entry("life", "life"),
            Entry("future", "session", 1), Entry("unknown", "new-category") };
        Write(path, rows);
        var before = File.ReadAllBytes(path);
        var reader = new LocalEventJournalReader(root, () => Now);
        var result = reader.Read();
        Equal("ready", result.State);
        Equal(3, result.Entries.Count);
        Equal(1, LocalEventJournalReader.Filter(result, "ship").Count);
        Equal(1, LocalEventJournalReader.Filter(result, "other").Count);
        Equal(true, LocalEventJournalReader.FormatExport(result).Contains("title-life"));
        Equal(true, before.SequenceEqual(File.ReadAllBytes(path)));
        Equal(1, Directory.GetFiles(root).Length);
    });

    public static Task BackupIsExplicitAndNeverRestored() => InDirectory(root =>
    {
        var path = Path.Combine(root, "local-event-log.json");
        File.WriteAllText(path, "corrupt");
        Write(path + ".bak", [Entry("backup", "server")]);
        var reader = new LocalEventJournalReader(root, () => Now);
        var result = reader.Read();
        Equal("recovered", result.State);
        Equal("backup", result.Entries.Single().Id);
        Equal("corrupt", File.ReadAllText(path));
        File.Delete(path);
        Equal("recovered", reader.Read().State);
        Equal(false, File.Exists(path));
        Write(path, []);
        Equal("ready", reader.Read().State);
        Equal(0, reader.Read().Entries.Count); // Valid empty primary wins over stale backup.
    });

    public static Task IdentityDedupAndBoundedLatestHistory() => InDirectory(root =>
    {
        var path = Path.Combine(root, "local-event-log.json");
        var first = Entry("one", "identity") with { EventType = "PlayerOnline", Detail = "synthetic-player" };
        var second = first with { Id = "two", OccurredAt = Now.AddSeconds(1) };
        var third = first with { Id = "three", OccurredAt = Now.AddSeconds(2), EventType = "PlayerOffline" };
        Write(path, [first, second, third, third]);
        var reader = new LocalEventJournalReader(root, () => Now);
        Equal(2, reader.Read().Entries.Count);
        var many = Enumerable.Range(0, 3100).Select(i => Entry(i.ToString(), "ship") with { OccurredAt = Now.AddSeconds(-i) });
        Write(path, many);
        var result = reader.Read();
        Equal(3000, result.Entries.Count);
        Equal("0", result.Entries.First().Id);
        Equal("2999", result.Entries.Last().Id);
    });

    public static Task LargeOrUntrustedDataDoesNotBecomeExportable() => InDirectory(root =>
    {
        var path = Path.Combine(root, "local-event-log.json");
        using (var stream = File.Create(path)) stream.SetLength(LocalEventJournalReader.MaximumFileBytes + 1L);
        var reader = new LocalEventJournalReader(root, () => Now);
        Equal("unavailable", reader.Read().State);
        Write(path, [Entry("bad", "ship") with { Detail = "injected\nline" }]);
        var result = reader.Read();
        Equal("unavailable", result.State);
        try { LocalEventJournalReader.FormatExport(result); throw new Exception("Expected unavailable export rejection"); }
        catch (InvalidOperationException) { }
        var valid = JsonSerializer.Serialize(new[] { Entry("known", "life") }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        File.WriteAllText(path, valid.Replace("\"id\":", "\"privateFutureField\":true,\"id\":"));
        Equal("unavailable", reader.Read().State);
    });

    private static LocalEventEntry Entry(string id, string category, int days = 0) => new(id, Now.AddDays(days), category, "SyntheticEvent", "title-" + id, "detail");
    private static void Write(string path, IEnumerable<LocalEventEntry> entries) => File.WriteAllText(path,
        JsonSerializer.Serialize(entries, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    private static Task InDirectory(Action<string> test)
    {
        var root = Directory.CreateTempSubdirectory("starbridge-event-journal-test-").FullName;
        try { test(root); } finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}; actual {actual}");
    }
}
