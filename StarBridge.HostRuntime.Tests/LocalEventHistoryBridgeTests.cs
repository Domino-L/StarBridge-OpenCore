using System.Text.Json;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class LocalEventHistoryBridgeTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 10, 12, 0, 0, TimeSpan.Zero);
    public static Task PaginationAndFilter() => Run(async (root, dispatcher) =>
    {
        Write(root, Enumerable.Range(0, 125).Select(i => Entry(i)));
        var before = File.ReadAllBytes(Path.Combine(root, "local-event-log.json"));
        var first = (await dispatcher.DispatchAsync(Request())).Response;
        Require(first.Status == "ok" && first.Payload.GetProperty("entries").GetArrayLength() == 50);
        var revision = first.Payload.GetProperty("revision").GetString();
        var second = (await dispatcher.DispatchAsync(Request(offset: 50, revision: revision))).Response;
        var last = (await dispatcher.DispatchAsync(Request(offset: 100, revision: revision))).Response;
        Require(last.Payload.GetProperty("entries").GetArrayLength() == 25 && !last.Payload.GetProperty("hasMore").GetBoolean());
        var ids = first.Payload.GetProperty("entries").EnumerateArray().Select(e => e.GetProperty("id").GetString())
            .Concat(second.Payload.GetProperty("entries").EnumerateArray().Select(e => e.GetProperty("id").GetString())).ToArray();
        Require(ids.Distinct().Count() == 100);
        var filtered = (await dispatcher.DispatchAsync(Request(category: "life"))).Response;
        Require(filtered.Payload.GetProperty("filteredCount").GetInt32() == 62);
        Require(filtered.Payload.GetProperty("entries").EnumerateArray().All(e => e.GetProperty("category").GetString() == "life"));
        Require(!first.Payload.GetRawText().Contains(root) && !first.Payload.GetRawText().Contains("sourceLine"));
        Require(before.SequenceEqual(File.ReadAllBytes(Path.Combine(root, "local-event-log.json"))));
        Require(first.Payload.GetRawText().Length < 100_000);
    });

    public static Task RevisionChangesNeverMixPages() => Run(async (root, dispatcher) =>
    {
        Write(root, Enumerable.Range(0, 75).Select(i => Entry(i)));
        var first = (await dispatcher.DispatchAsync(Request())).Response;
        Write(root, Enumerable.Range(0, 76).Select(i => Entry(i)));
        var next = (await dispatcher.DispatchAsync(Request(offset: 50, revision: first.Payload.GetProperty("revision").GetString()))).Response;
        Require(next.Error?.Code == "localEvents.historyChanged");
    });

    public static Task MissingCorruptBackupAndRejectedQueries() => Run(async (root, dispatcher) =>
    {
        Require((await dispatcher.DispatchAsync(Request())).Response.Payload.GetProperty("state").GetString() == "missing");
        File.WriteAllText(Path.Combine(root, "local-event-log.json"), "broken");
        Require((await dispatcher.DispatchAsync(Request())).Response.Payload.GetProperty("state").GetString() == "unavailable");
        Write(root, [Entry(0)], backup: true);
        Require((await dispatcher.DispatchAsync(Request())).Response.Payload.GetProperty("state").GetString() == "recovered");
        foreach (var request in new[] { Request(category: "../private"), Request(size: 101), Request(offset: 50),
            Request(offset: 1, revision: new string('A', 64)), Request(revision: "secret"),
            Request() with { AccountContext = new("test", "scm", "synthetic") },
            BridgeEnvelope.Request(LocalEventHistoryBridgeDispatcher.RequestName, "extra", 2,
                new { schemaVersion = 1, category = "all", offset = 0, pageSize = 50, revision = (string?)null, path = root }) })
            Require((await dispatcher.DispatchAsync(request)).Response.Status == "error");
        Require(File.ReadAllText(Path.Combine(root, "local-event-log.json")) == "broken");
        Require(!BridgeRequestPolicy.RequiresAccountContext(LocalEventHistoryBridgeDispatcher.RequestName));
    });

    public static Task CancellationGenerationAndDispose() => Run(async (root, _) =>
    {
        var generation = 2L;
        using var dispatcher = new LocalEventHistoryBridgeDispatcher(new(root, () => { generation++; return Now; }), () => generation);
        Write(root, [Entry(0)]);
        Require((await dispatcher.DispatchAsync(Request())).Response.Status == "error");
        using var cts = new CancellationTokenSource(); cts.Cancel();
        Require((await dispatcher.DispatchAsync(Request(), cts.Token)).Response.Status == BridgeResponseStatuses.Cancelled);
        dispatcher.Dispose();
        Require((await dispatcher.DispatchAsync(Request() with { SessionGeneration = generation })).Response.Status == "error");
    });

    private static BridgeEnvelope Request(string category = "all", int offset = 0, int size = 50, string? revision = null) =>
        BridgeEnvelope.Request(LocalEventHistoryBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 2,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, category, offset, pageSize = size, revision }));
    private static LocalEventEntry Entry(int i) => new(i.ToString(), Now.AddSeconds(-i), i % 2 == 0 ? "ship" : "life", "SyntheticEvent", "event-" + i, "detail");
    private static void Write(string root, IEnumerable<LocalEventEntry> entries, bool backup = false) => File.WriteAllText(
        Path.Combine(root, "local-event-log.json" + (backup ? ".bak" : "")), JsonSerializer.Serialize(entries, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    private static async Task Run(Func<string, LocalEventHistoryBridgeDispatcher, Task> test)
    {
        var root = Directory.CreateTempSubdirectory("starbridge-history-bridge-test-").FullName;
        try { using var dispatcher = new LocalEventHistoryBridgeDispatcher(new(root, () => Now), () => 2); await test(root, dispatcher); }
        finally { Directory.Delete(root, true); }
    }
    private static void Require(bool condition) { if (!condition) throw new Exception("History Bridge boundary failed."); }
}
