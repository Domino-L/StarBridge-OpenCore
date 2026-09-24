using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Hangar;

namespace StarBridge.HostRuntime.Hangar;

internal sealed record ServerHangarMigrationRead(string State, string? SnapshotSha256, MigrationHangarSource Source);

// Caller binds both the active account generation and its verified server account
// ID. This reader never resolves account aliases or promotes remote data to local.
internal static class ServerHangarMigrationReader
{
    internal static ServerHangarMigrationRead Read(byte[] bytes, MigrationOwner owner, string expectedServerAccountId)
    {
        if (bytes.Length > 4 * 1024 * 1024) throw new InvalidDataException("Snapshot too large.");
        using var document = JsonDocument.Parse(bytes);
        Require(document.RootElement, ["schemaVersion", "state", "accountId", "localCoverage", "snapshotSha256", "ships"]);
        if (document.RootElement.GetProperty("ships").ValueKind != JsonValueKind.Array)
            throw new InvalidDataException("Missing ships.");
        foreach (var row in document.RootElement.GetProperty("ships").EnumerateArray())
        {
            Require(row, ["instanceId", "fields"]);
            Require(row.GetProperty("fields"), ["code", "displayName", "source", "importedAt", "syncedAt",
                "imageMediaId", "cropFocusX", "cropFocusY", "cropZoom"]);
        }
        var snapshot = JsonSerializer.Deserialize<ServerHangarSnapshot>(bytes, new JsonSerializerOptions(JsonSerializerDefaults.Web)
            { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow })
            ?? throw new InvalidDataException("Missing snapshot.");
        if (snapshot.SchemaVersion != 1 || snapshot.AccountId != expectedServerAccountId ||
            string.IsNullOrWhiteSpace(expectedServerAccountId) || snapshot.LocalCoverage != "unknown" ||
            snapshot.Ships is null || snapshot.Ships.Length > 10000 ||
            snapshot.State is not ("available" or "unavailable" or "ambiguous" or "needs-review"))
            throw new InvalidDataException("Invalid snapshot identity or state.");
        if (snapshot.State == "available")
        {
            if (snapshot.SnapshotSha256 is not { Length: 64 } hash || !hash.All(Uri.IsHexDigit))
                throw new InvalidDataException("Missing snapshot fingerprint.");
        }
        else if (snapshot.Ships.Length != 0 || snapshot.SnapshotSha256 is not null)
            throw new InvalidDataException("Unknown source contains unverified records.");
        var source = new MigrationHangarSource(owner, "legacy-instance-v1",
            snapshot.State == "available" ? MigrationSourceState.Partial : MigrationSourceState.Unavailable, snapshot.Ships);
        // Reuse the comparison boundary's owner, row and finite-number checks.
        _ = HangarMigrationPreview.Compare(source, source);
        if (snapshot.Ships.Any(s => s.Fields.Code is null || s.Fields.DisplayName is null || s.Fields.Source is null))
            throw new InvalidDataException("Invalid ship fields.");
        return new(snapshot.State, snapshot.SnapshotSha256, source);
    }

    private static void Require(JsonElement element, string[] required)
    {
        if (element.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected object.");
        var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
            if (!keys.Add(property.Name)) throw new InvalidDataException("Duplicate field.");
        if (required.Any(key => !keys.Contains(key))) throw new InvalidDataException("Incomplete snapshot.");
    }
}
