using System.Security.Cryptography;
using System.Text;

namespace StarBridge.Desktop;

public static class FleetPassiveRefreshPolicy
{
    public static IReadOnlyList<T> PreserveVisibleOrder<T>(
        IEnumerable<T> refreshedItems,
        IReadOnlyList<string> visibleKeys,
        Func<T, string?> keySelector)
    {
        var rankByKey = visibleKeys
            .Select((key, index) => (Key: key?.Trim(), Index: index))
            .Where(entry => !string.IsNullOrWhiteSpace(entry.Key))
            .GroupBy(entry => entry.Key!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Index, StringComparer.OrdinalIgnoreCase);

        return refreshedItems
            .Select((item, index) =>
            {
                var key = keySelector(item)?.Trim();
                return (
                    Item: item,
                    OriginalIndex: index,
                    PreservedRank: !string.IsNullOrWhiteSpace(key) && rankByKey.TryGetValue(key, out var rank)
                        ? rank
                        : int.MaxValue);
            })
            .OrderBy(entry => entry.PreservedRank)
            .ThenBy(entry => entry.OriginalIndex)
            .Select(entry => entry.Item)
            .ToArray();
    }

    public static bool ShouldMerge(
        string? incomingFleetCode,
        DateTimeOffset incomingUpdatedAt,
        string? currentFleetCode,
        DateTimeOffset currentUpdatedAt)
    {
        return ShouldMerge(
            incomingFleetCode,
            incomingUpdatedAt,
            null,
            currentFleetCode,
            currentUpdatedAt,
            null);
    }

    public static bool ShouldMerge(
        string? incomingFleetCode,
        DateTimeOffset incomingUpdatedAt,
        string? incomingMemberPresenceFingerprint,
        string? currentFleetCode,
        DateTimeOffset currentUpdatedAt,
        string? currentMemberPresenceFingerprint)
    {
        if (!string.Equals(
                incomingFleetCode?.Trim(),
                currentFleetCode?.Trim(),
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (incomingUpdatedAt > currentUpdatedAt)
        {
            return true;
        }

        if (incomingUpdatedAt != default && incomingUpdatedAt < currentUpdatedAt)
        {
            return false;
        }

        return !string.Equals(
            incomingMemberPresenceFingerprint?.Trim(),
            currentMemberPresenceFingerprint?.Trim(),
            StringComparison.Ordinal);
    }

    public static string BuildMemberPresenceFingerprint(
        IEnumerable<NetworkFleetMemberSnapshot>? members)
    {
        var builder = new StringBuilder();
        foreach (var member in (members ?? [])
                     .OrderBy(MemberIdentityKey, StringComparer.OrdinalIgnoreCase)
                     .ThenBy(member => member.GameName, StringComparer.OrdinalIgnoreCase))
        {
            AppendFingerprintValue(builder, member.AccountId);
            AppendFingerprintValue(builder, member.GameName);
            AppendFingerprintValue(builder, member.Online ? "1" : "0");
            AppendFingerprintValue(builder, member.LiveStatus);
            AppendFingerprintValue(builder, member.Ship);
            AppendFingerprintValue(builder, member.Location);
        AppendFingerprintValue(builder, member.LocationConfidence);
        AppendFingerprintValue(builder, member.ArrivalPendingConfirmation ? "arrival-pending" : "arrival-confirmed");
        AppendFingerprintValue(builder, member.ArrivalTargetCode);
            AppendFingerprintValue(builder, member.ServerRegion);
            AppendFingerprintValue(builder, member.ServerShard);
        }

        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(builder.ToString())));
    }

    private static string MemberIdentityKey(NetworkFleetMemberSnapshot member) =>
        !string.IsNullOrWhiteSpace(member.AccountId)
            ? $"account:{member.AccountId.Trim()}"
            : $"game:{member.GameName.Trim()}";

    private static void AppendFingerprintValue(StringBuilder builder, string? value)
    {
        var normalized = value?.Trim() ?? "";
        builder
            .Append(normalized.Length)
            .Append(':')
            .Append(normalized)
            .Append('|');
    }
}
