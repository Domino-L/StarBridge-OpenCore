namespace StarBridge.Core.Presence;

/// <summary>
/// A public shard id such as <c>pub_use1b_12326004_040</c>: region token, a
/// build/instance number everyone on the same game version shares, and the
/// shard number players read. Two shards are the same only when the whole id
/// matches; the trailing number alone repeats across regions and versions.
/// </summary>
public readonly record struct PublicShardId(string Id, string Region, string Instance, string Tail)
{
    public static bool TryParse(string? value, out PublicShardId shard)
    {
        shard = default;
        if (string.IsNullOrWhiteSpace(value)) return false;
        var id = value.Trim();
        if (id.Length > 128 || !id.StartsWith("pub_", StringComparison.OrdinalIgnoreCase)) return false;
        var parts = id.Split('_');
        if (parts.Length < 4 || parts.Any(part => part.Length == 0 || part.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-'))) return false;
        var tail = parts[^1];
        if (!tail.All(char.IsAsciiDigit)) return false;
        shard = new(id, parts[1].ToLowerInvariant(), string.Join('_', parts[2..^1]), tail);
        return true;
    }

    public static bool IsValid(string? value) => TryParse(value, out _);
}
