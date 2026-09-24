using System.Text.Json;
using StarBridge.Core.Presence;

namespace StarBridge.Core.Tests;

internal static class CommunityMemberFieldOverrideTests
{
    internal static void RunAll()
    {
        var joined = DateTimeOffset.Parse("2026-09-01T00:00:00Z");
        var member = new CommunityMemberFieldOverride("member-a", joined, PlayerSharedStateFields.Presence);
        var scope = new CommunityRealtimeScope("org", joined, CommunityRealtimeScope.SupportedFields, true, true, [], [member]);
        Check(scope.ResolveForMember("member-a", joined, true) == PlayerSharedStateFields.Presence, "exception overrides all/admin defaults");
        Check(scope.ResolveForMember("member-a", joined, false) == PlayerSharedStateFields.Presence, "explicit allowance overrides default denial");
        Check((scope with { Fields = PlayerSharedStateFields.Ship }).ResolveForMember("member-a", joined, true) == 0, "organization master switch is the ceiling");
        Check(scope.ResolveForMember("member-a", joined.AddDays(1), false) == 0, "rejoined recipient cannot inherit prior allowance");
        Check(scope.ResolveForMember("member-b", joined, true) == scope.Fields, "untouched members inherit defaults");
        Check((scope with { MemberOverrides = [] }).ResolveForMember("member-a", joined, true) == scope.Fields, "reset restores default");
        Check((scope with { MemberOverrides = [member with { Fields = 0 }] }).ResolveForMember("member-a", joined, true) == 0, "explicit zero denies all four");
        var copy = CommunityRealtimeScope.ValidateAndCopy([scope]);
        scope.MemberOverrides![0] = member with { Fields = 0 };
        Check(copy[0].MemberOverrides![0].Fields == PlayerSharedStateFields.Presence, "validated policy owns its array");
        foreach (var invalid in new[] {
            member with { AccountId = " x" }, member with { JoinedAt = default },
            member with { Fields = PlayerSharedStateFields.PersonalHangar }, member with { Fields = (PlayerSharedStateFields)(-1) }
        }) Reject([invalid]);
        Reject([member, member with { AccountId = "MEMBER-A" }]);
        Reject(Enumerable.Range(0, 1001).Select(i => member with { AccountId = "member-" + i }));
        var legacy = scope with { MemberOverrides = null };
        var json = JsonSerializer.Serialize(legacy, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check(!json.Contains("memberOverrides"), "old signed JSON shape stays unchanged");
    }
    private static void Reject(IEnumerable<CommunityMemberFieldOverride> values)
    {
        try { CommunityMemberFieldOverride.ValidateAndCopy(values); }
        catch (ArgumentException) { return; }
        throw new InvalidOperationException("Invalid member exception accepted.");
    }
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
