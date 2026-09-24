using System.Text.Json.Serialization;

namespace StarBridge.Core.Presence;

/// <summary>Publisher-owned exception for one recipient's current organization membership.</summary>
public sealed record CommunityMemberFieldOverride(
    [property: JsonRequired] string AccountId,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonRequired] PlayerSharedStateFields Fields)
{
    public const int MaximumOverrides = 1000;

    public static CommunityMemberFieldOverride[] ValidateAndCopy(IEnumerable<CommunityMemberFieldOverride> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var rows = values.Take(MaximumOverrides + 1).ToArray();
        if (rows.Length > MaximumOverrides || rows.Any(row => row is null ||
            string.IsNullOrWhiteSpace(row.AccountId) || row.AccountId.Length > 128 ||
            row.AccountId != row.AccountId.Trim() || row.AccountId.Any(char.IsControl) ||
            row.JoinedAt <= DateTimeOffset.UnixEpoch || (row.Fields & ~CommunityRealtimeScope.SupportedFields) != 0) ||
            rows.Select(row => row.AccountId).Distinct(StringComparer.OrdinalIgnoreCase).Count() != rows.Length)
            throw new ArgumentException("Invalid organization member exceptions.", nameof(values));
        return rows.ToArray();
    }
}
