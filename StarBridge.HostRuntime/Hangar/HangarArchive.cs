using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// The account copy of the local hangar (user 11-05: "应该默认云端存吧"). Business fields only: saved ships,
/// their notes, nicknames and bookmarks. Never images, image paths or crops, RSI credentials, cookies, raw
/// pages, sharing choices or anyone else's data. The server treats it as opaque, bounded JSON.
/// </summary>
public static class HangarArchive
{
    public const int SchemaVersion = 1;
    /// <summary>Server bound: 2 MiB of UTF-8 JSON.</summary>
    public const int MaximumBytes = 2 * 1024 * 1024;

    public sealed record Ship(
        [property: JsonRequired] string Id, [property: JsonRequired] string PledgeKey,
        [property: JsonRequired] string Title, string? Liner, string? AcquiredText,
        [property: JsonRequired] DateTimeOffset AddedAt,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? RemovedAt = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool IsFavorite = false,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Nickname = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Notes = null);

    public sealed record Document(
        [property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] bool Partial,
        [property: JsonRequired] IReadOnlyList<Ship> Ships,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<Ship>? FormerShips = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? InventorySavedAt = null);

    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 8
    };

    public static Document FromSnapshot(LocalHangarSnapshot snapshot) => new(SchemaVersion, snapshot.Partial,
        snapshot.Ships.Select(ToShip).ToArray(), snapshot.FormerShips?.Select(ToShip).ToArray(),
        snapshot.InventorySavedAt ?? snapshot.SavedAt);

    private static Ship ToShip(LocalHangarShip ship) => new(ship.Id, ship.PledgeKey, ship.Title, ship.Liner,
        ship.AcquiredText, ship.AddedAt, ship.RemovedAt, ship.IsFavorite, ship.Nickname, ship.Notes);

    public static byte[] Serialize(Document document) => JsonSerializer.SerializeToUtf8Bytes(document, Json);

    /// <summary>Parses the server copy; anything outside the contract is rejected (no partial restore).</summary>
    public static Document Parse(JsonElement archive)
    {
        if (archive.ValueKind != JsonValueKind.Object)
            throw new LocalHangarStoreException("hangar.archive_invalid", "The account hangar copy is not usable.");
        Document? document;
        try { document = archive.Deserialize<Document>(Json); }
        catch (JsonException error)
        { throw new LocalHangarStoreException("hangar.archive_invalid", "The account hangar copy is not usable.", error); }
        var latest = DateTimeOffset.UtcNow.AddMinutes(10);
        bool BadTime(Ship s) => s.AddedAt > latest || s.RemovedAt is { } removed && (removed > latest || removed < s.AddedAt);
        if (document is null || document.SchemaVersion != SchemaVersion || document.Ships is null ||
            document.Ships.Any(s => s is null) || document.FormerShips?.Any(s => s is null) == true ||
            document.Ships.Concat(document.FormerShips ?? []).Any(BadTime) || document.InventorySavedAt > latest)
            throw new LocalHangarStoreException("hangar.archive_invalid", "The account hangar copy is not usable.");
        return document;
    }

    internal static LocalHangarShip ToLocal(Ship ship) => new(ship.Id, ship.PledgeKey, ship.Title, ship.Liner,
        ship.AcquiredText, ship.AddedAt.ToUniversalTime(), RemovedAt: ship.RemovedAt?.ToUniversalTime(), IsFavorite: ship.IsFavorite,
        Nickname: ship.Nickname, Notes: ship.Notes);
}
