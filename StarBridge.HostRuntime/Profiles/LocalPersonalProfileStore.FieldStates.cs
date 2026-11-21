using System.Text.Json;

namespace StarBridge.HostRuntime.Profiles;

public sealed partial class LocalPersonalProfileStore
{
    private sealed record FieldStateFile(int SchemaVersion, string OwnerHash, string OperationId,
        string[] ExplicitlyEmpty, string Integrity);

    private string FieldStatePath(string hash) => Path.Combine(_directory, hash + ".field-states");

    private static string[] ExplicitlyEmpty(LocalProfileContent content) =>
        content.FieldStates?.Keys.Order(StringComparer.Ordinal).ToArray() ?? [];

    private static bool IsExplicitDefault(LocalProfileContent content, string field) => field switch
    {
        "introduction" => content.Introduction == "",
        "avatarStyle" => content.AvatarStyle == 0,
        "wallpaperId" => content.WallpaperId == "none",
        // Flutter compares the normalized layout against the S2 default shells.
        "modules" => content.Modules is not null,
        "favoriteShipIds" => content.FavoriteShipIds is { Count: 0 },
        "roles" => content.PlayStyle?.Roles is { Count: 0 },
        "interests" => content.PlayStyle?.Interests is { Count: 0 },
        "support" => content.PlayStyle?.Support is { Count: 0 },
        "schedule" => content.Schedule is { TimeZoneId: "", Rhythm: "casual", Windows.Count: 0 },
        _ => false
    };

    private static string FieldStateIntegrity(string ownerHash, string operationId, string[] explicitlyEmpty) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, ownerHash, operationId, explicitlyEmpty }, Json));

    private static byte[] FieldStateBytes(string hash, string operationId, string[] fields) =>
        JsonSerializer.SerializeToUtf8Bytes(new FieldStateFile(1, hash, operationId, fields,
            FieldStateIntegrity(hash, operationId, fields)), Json);

    private string[]? ReadFieldStates(string hash, LocalProfileSnapshot snapshot)
    {
        if (snapshot.Content is not { } content || snapshot.OperationId is not { } operation) return null;
        try
        {
            var path = FieldStatePath(hash);
            if (!CheckPath(path, false)) return null;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > MaximumBytes) return null;
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) return null;
            using var doc = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
            RejectDuplicates(doc.RootElement);
            var file = JsonSerializer.Deserialize<FieldStateFile>(bytes, Json);
            if (file is null || file.SchemaVersion != 1 || file.OwnerHash != hash || file.OperationId != operation ||
                file.ExplicitlyEmpty is not { } fields || fields.Any(field => !IsExplicitDefault(content, field)) ||
                fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
                file.Integrity != FieldStateIntegrity(hash, operation, fields)) return null;
            return fields.Order(StringComparer.Ordinal).ToArray();
        }
        // Auto-import provenance is optional. A read always keeps the saved content.
        catch (Exception e) when (StorageError(e)) { return null; }
    }
}
