using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Hangar;

internal static class ServerHangarMigrationReaderTests
{
    internal static void Verify()
    {
        var owner = new MigrationOwner("production", "legacy", "fixture");
        var ship = new MigrationShip("one", new("code", "name", "source", default, default, "image", .5, .5, 1));
        var snapshot = new ServerHangarSnapshot(1, "available", "fixture", "unknown", new string('A', 64), [ship, ship with { InstanceId = "two" }]);
        ServerHangarMigrationRead Read(ServerHangarSnapshot s) => ServerHangarMigrationReader.Read(JsonSerializer.SerializeToUtf8Bytes(s, new JsonSerializerOptions(JsonSerializerDefaults.Web)), owner, "fixture");
        var read = Read(snapshot);
        if (read.Source.Ships.Count != 2 || read.Source.State != MigrationSourceState.Partial)
            throw new Exception("Server snapshot promoted to complete local backup.");
        if (Read(snapshot with { Ships = [] }).State != "available" ||
            Read(snapshot with { State = "unavailable", Ships = [], SnapshotSha256 = null }).Source.State != MigrationSourceState.Unavailable)
            throw new Exception("Empty and unknown conflated.");
        foreach (var invalid in new[] {
            snapshot with { AccountId = "other" }, snapshot with { SchemaVersion = 2 },
            snapshot with { LocalCoverage = "complete" }, snapshot with { SnapshotSha256 = null },
            snapshot with { State = "unavailable" }, snapshot with { Ships = null! } })
        {
            try { Read(invalid); throw new Exception("Invalid response accepted."); }
            catch (InvalidDataException) { }
        }
        var json = JsonSerializer.Serialize(snapshot, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        foreach (var invalidJson in new[] {
            json.Replace("\"state\":\"available\",", ""),
            json.Replace("\"state\":\"available\",", "\"state\":\"available\",\"state\":\"available\","),
            json.Replace("\"schemaVersion\":1", "\"futureField\":true,\"schemaVersion\":1") })
        {
            try { ServerHangarMigrationReader.Read(System.Text.Encoding.UTF8.GetBytes(invalidJson), owner, "fixture"); throw new Exception("Malformed response accepted."); }
            catch (InvalidDataException) { }
            catch (JsonException) { }
        }
        Console.WriteLine("PASS server hangar reader identity, schema, completeness and unknown-state checks");
    }
}
