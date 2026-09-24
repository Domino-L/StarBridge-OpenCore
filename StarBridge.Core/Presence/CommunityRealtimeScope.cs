using System.Text.Json.Serialization;

namespace StarBridge.Core.Presence;

/// <summary>A choice for one organization membership, not a membership grant.</summary>
public sealed record CommunityRealtimeScope(
    [property: JsonRequired] string Code,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonRequired] PlayerSharedStateFields Fields,
    [property: JsonRequired] bool AdministratorsCanView,
    [property: JsonRequired] bool AllMembersCanView,
    // Kept only to read old signed preference files without changing their hash.
    [property: JsonRequired] string[] VisibilityGroupIds,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    CommunityMemberFieldOverride[]? MemberOverrides = null)
{
    public const int MaximumScopes = 64;
    public const PlayerSharedStateFields SupportedFields = PlayerSharedStateAudiencePolicy.PartyRoomLiveStateFields;

    // An upload ceiling, not a grant: the recipient's current membership is
    // checked independently by ResolveForMember at the service boundary.
    [JsonIgnore]
    public PlayerSharedStateFields PotentialFields => Fields & SupportedFields &
        (AllMembersCanView || AdministratorsCanView ? SupportedFields :
            (MemberOverrides ?? []).Aggregate(PlayerSharedStateFields.None, (result, row) => result | row.Fields));

    public PlayerSharedStateFields ResolveForMember(string accountId, DateTimeOffset joinedAt, bool defaultCanView)
    {
        var choice = MemberOverrides?.SingleOrDefault(row =>
            string.Equals(row.AccountId, accountId, StringComparison.OrdinalIgnoreCase) && row.JoinedAt == joinedAt);
        return Fields & SupportedFields & (choice?.Fields ?? (defaultCanView ? SupportedFields : PlayerSharedStateFields.None));
    }

    public static CommunityRealtimeScope[] ValidateAndCopy(IEnumerable<CommunityRealtimeScope> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        var rows = values.Take(MaximumScopes + 1).ToArray();
        if (rows.Length > MaximumScopes || rows.Any(row => row is null || !ValidKey(row.Code, 256) ||
            row.JoinedAt <= DateTimeOffset.UnixEpoch || (row.Fields & ~SupportedFields) != 0 ||
            row.VisibilityGroupIds is null || row.VisibilityGroupIds.Length > 12 ||
            row.VisibilityGroupIds.Any(id => !ValidKey(id, 128)) ||
            row.VisibilityGroupIds.Distinct(StringComparer.OrdinalIgnoreCase).Count() != row.VisibilityGroupIds.Length) ||
            rows.Select(row => row.Code).Distinct(StringComparer.OrdinalIgnoreCase).Count() != rows.Length)
            throw new ArgumentException("Invalid organization realtime scopes.", nameof(values));
        return rows.Select(row => row with {
            VisibilityGroupIds = row.VisibilityGroupIds.ToArray(),
            MemberOverrides = row.MemberOverrides is null ? null : CommunityMemberFieldOverride.ValidateAndCopy(row.MemberOverrides)
        }).ToArray();
    }

    private static bool ValidKey(string? value, int maximum) => !string.IsNullOrWhiteSpace(value) &&
        value.Length <= maximum && value == value.Trim() && !value.Any(char.IsControl);
}
