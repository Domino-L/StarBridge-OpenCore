namespace StarBridge.Desktop;

public static class FleetMemberDisplaySanitizer
{
    public static NetworkFleetMemberSnapshot[] Canonicalize(IEnumerable<NetworkFleetMemberSnapshot>? members)
    {
        var source = (members ?? []).ToArray();
        var safeRowsByCallsign = source
            .Where(member => !IsEmail(member.GameName))
            .Select(member => PublicValue(member.Callsign))
            .Where(value => value.Length > 0)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var rows = new Dictionary<string, NetworkFleetMemberSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var member in source)
        {
            var safeGameName = PublicValue(member.GameName);
            var safeCallsign = PublicValue(member.Callsign);
            if (IsEmail(member.GameName) && safeRowsByCallsign.Contains(safeCallsign))
            {
                continue;
            }

            if (safeGameName.Length == 0 && safeCallsign.Length == 0)
            {
                continue;
            }

            var key = !string.IsNullOrWhiteSpace(member.AccountId)
                ? $"account:{member.AccountId.Trim()}"
                : safeGameName.Length > 0 ? safeGameName : safeCallsign;
            var normalized = member with
            {
                GameName = safeGameName.Length > 0 ? safeGameName : safeCallsign,
                Callsign = safeCallsign.Length > 0 ? safeCallsign : safeGameName
            };
            if (!rows.TryGetValue(key, out var existing))
            {
                rows[key] = normalized;
                continue;
            }

            var newest = existing.LastUpdated > normalized.LastUpdated ? existing : normalized;
            var older = ReferenceEquals(newest, existing) ? normalized : existing;
            rows[key] = newest with
            {
                GameName = FirstPublic(newest.GameName, older.GameName, newest.Callsign, older.Callsign),
                Callsign = FirstPublic(newest.Callsign, older.Callsign, newest.GameName, older.GameName),
                AvatarImageData = string.IsNullOrWhiteSpace(newest.AvatarImageData)
                    ? older.AvatarImageData
                    : newest.AvatarImageData,
                Online = newest.Online,
                JoinedAt = EarliestMembershipTimestamp(existing.JoinedAt, normalized.JoinedAt)
            };
        }

        return rows.Values.ToArray();
    }

    private static DateTimeOffset EarliestMembershipTimestamp(
        DateTimeOffset first,
        DateTimeOffset second)
    {
        var candidates = new[] { first, second }
            .Where(value => value != default && value != DateTimeOffset.MinValue)
            .Select(value => value.ToUniversalTime())
            .ToArray();
        return candidates.Length == 0 ? default : candidates.Min();
    }

    public static bool IsEmail(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Contains('@', StringComparison.Ordinal);

    private static string FirstPublic(params string?[] values) =>
        values.Select(PublicValue).FirstOrDefault(value => value.Length > 0) ?? "";

    private static string PublicValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var trimmed = value.Trim();
        return IsEmail(trimmed) ? "" : trimmed;
    }
}
