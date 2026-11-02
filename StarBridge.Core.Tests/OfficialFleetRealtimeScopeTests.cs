using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.Core.Organizations;

namespace StarBridge.Core.Tests;

internal static class OfficialFleetRealtimeScopeTests
{
    internal static void RunAll()
    {
        var target = new OfficialFleetRealtimeTarget("scm-production", 7, "ASTER", "scm-observed-membership-row-v1:30");
        var choice = new OfficialFleetRealtimeChoice(target, CommunityRealtimeScope.SupportedFields, "initial", Guid.NewGuid().ToString("N"));
        Check(target.IsValid && choice.IsValid, "opaque authenticated namespace and canonical observed row epoch are valid");
        foreach (var invalid in new[] { target with { AuthorityNamespace = "" }, target with { AuthorityNamespace = " a" },
            target with { AuthorityNamespace = "a\n" }, target with { OrganizationId = 0 }, target with { OrganizationId = -1 },
            target with { Sid = "aster" }, target with { Sid = "LONGSID12345" }, target with { MembershipEpoch = "30" },
            target with { MembershipEpoch = "scm-observed-membership-row-v1:0" }, target with { MembershipEpoch = "scm-observed-membership-row-v1:030" },
            target with { MembershipEpoch = "scm-observed-membership-row-v1:9223372036854775808" } })
            Check(!invalid.IsValid && !(choice with { Target = invalid }).IsValid, "invalid official target must not authorize a publication");
        foreach (var invalid in new[] { choice with { Fields = PlayerSharedStateFields.All }, choice with { Fields = (PlayerSharedStateFields)(-1) },
            choice with { ExpectedServerRevision = "" }, choice with { ExpectedServerRevision = Guid.NewGuid().ToString() },
            choice with { OperationId = "" }, choice with { OperationId = Guid.NewGuid().ToString() }, choice with { Target = null! } })
            Check(!invalid.IsValid, "invalid field ceiling or CAS identity must fail closed");
        Check((choice with { Fields = PlayerSharedStateFields.None }).IsValid, "explicit zero field choice is a valid authority decrease");
        var json = JsonSerializer.Serialize(choice, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check(!json.Contains("maximumRankValue", StringComparison.Ordinal) &&
            JsonSerializer.Deserialize<OfficialFleetRealtimeChoice>(json,new JsonSerializerOptions(JsonSerializerDefaults.Web))!.MaximumRankValue is null,
            "legacy missing audience keeps original signed serialization shape and all-member meaning");
        foreach(var rank in new int?[]{null,1,2,3,4}) Check((choice with {MaximumRankValue=rank}).IsValid,"valid audience tier");
        foreach(var rank in new[]{-1,0,5,6,99}) Check(!(choice with {MaximumRankValue=rank}).IsValid,"invalid audience tier");
        foreach(var before in new int?[]{null,1,2,3,4}) foreach(var next in new int?[]{null,1,2,3,4})
            Check(OfficialFleetRealtimeChoice.AudienceIsSubset(next,before)==(before is null || next is not null && next<=before),"audience expansion requires authority");
        Check(!json.Contains("isValid", StringComparison.OrdinalIgnoreCase), "local validity helper is not a wire authority field");
        using var document = JsonDocument.Parse(json);
        var missing = string.Join(",", document.RootElement.EnumerateObject().Where(p => p.Name != "fields").Select(p => JsonSerializer.Serialize(p.Name)+":"+p.Value.GetRawText()));
        try { JsonSerializer.Deserialize<OfficialFleetRealtimeChoice>("{"+missing+"}",new JsonSerializerOptions(JsonSerializerDefaults.Web));
            throw new InvalidOperationException("missing explicit field mask was accepted"); }
        catch (JsonException) { }
        var absent = JsonSerializer.Deserialize<OfficialFleetRealtimeChoice>("null");
        var now=DateTimeOffset.UtcNow;
        var scope=new OrganizationAuthorizationScope("synthetic",7,"TEST");
        var member=new OrganizationMembershipEvidence(OrganizationMembershipState.Current,"viewer",scope,"epoch",now,now.AddMinutes(1));
        var proof=new OrganizationRootEligibilityEvidence(OrganizationRootEligibilityState.Eligible,OrganizationRankAuthority.Basis,
            "viewer",scope,"epoch",OrganizationRankAuthority.Definition,now,now.AddMinutes(1),1);
        Check(OrganizationRankAuthority.CurrentValue(proof,member,now)==1,"V2 rank binds current membership");
        foreach(var invalid in new[]{proof with {RankValue=0},proof with {RankValue=7},proof with {Subject="other"},
            proof with {Scope=scope with {OrganizationId=8}},proof with {MembershipEpoch="other"},
            proof with {Basis="rawRank"},proof with {ProofDefinition=OrganizationRankAuthority.LegacyDefinition},
            proof with {ObservedAt=now.AddMinutes(-2),ValidUntil=now.AddMinutes(-1)},
            proof with {ObservedAt=now.AddHours(-49)},proof with {Reason=OrganizationRankAuthority.StaleReason}})
            Check(OrganizationRankAuthority.CurrentValue(invalid,member,now) is null,"unbound/stale/non-V2 rank grants no threshold");
        Check(OrganizationRankAuthority.CurrentValue(proof,member with {State=OrganizationMembershipState.NotCurrent},now) is null,
            "rank cannot bypass current membership");
        Check(absent is null, "absence remains absence; no official choice derives from community or legacy defaults");
        Console.WriteLine("PASS official runtime scope target, epoch, field ceiling, explicit zero and required CAS wire boundaries");
    }
    private static void Check(bool value, string description) { if (!value) throw new InvalidOperationException(description); }
}
