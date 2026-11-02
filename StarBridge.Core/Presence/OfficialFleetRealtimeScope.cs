using System.Globalization;
using System.Text.Json.Serialization;

namespace StarBridge.Core.Presence;

// SCM-observed membership facts; not a community membership or permission.
public sealed record OfficialFleetRealtimeTarget([property: JsonRequired] string AuthorityNamespace, [property: JsonRequired] long OrganizationId,
    [property: JsonRequired] string Sid, [property: JsonRequired] string MembershipEpoch)
{
    [JsonIgnore]
    public bool IsValid {
        get {
            const string prefix = "scm-observed-membership-row-v1:";
            return AuthorityNamespace is { Length: > 0 and <= 256 } && AuthorityNamespace == AuthorityNamespace.Trim() &&
                !AuthorityNamespace.Any(char.IsControl) && OrganizationId > 0 &&
                Sid is { Length: > 0 and <= 10 } && Sid.All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9') &&
                MembershipEpoch is not null && MembershipEpoch.StartsWith(prefix, StringComparison.Ordinal) &&
                long.TryParse(MembershipEpoch.AsSpan(prefix.Length), NumberStyles.None, CultureInfo.InvariantCulture, out var row) && row > 0 &&
                MembershipEpoch == prefix + row.ToString(CultureInfo.InvariantCulture);
        }
    }
}

// An absent choice never inherits legacy Fleet/Community choices.
public sealed record OfficialFleetRealtimeChoice([property: JsonRequired] OfficialFleetRealtimeTarget Target, [property: JsonRequired] PlayerSharedStateFields Fields,
    [property: JsonRequired] string ExpectedServerRevision, [property: JsonRequired] string OperationId,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull), JsonNumberHandling(JsonNumberHandling.Strict)]
    int? MaximumRankValue = null)
{
    [JsonIgnore]
    public bool IsValid => Target is { IsValid: true } && (Fields & ~CommunityRealtimeScope.SupportedFields) == 0 &&
        (ExpectedServerRevision == "initial" || Guid.TryParseExact(ExpectedServerRevision, "N", out _)) &&
        Guid.TryParseExact(OperationId, "N", out _) && (MaximumRankValue is null or >= 1 and <= 4);

    // Null includes every member, including members without rank proof.
    public static bool AudienceIsSubset(int? next, int? before) =>
        before is null || next is not null && next <= before;
}
