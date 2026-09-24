using StarBridge.Core.Presence;

namespace StarBridge.Core.Tests;

internal static class CommunityRealtimeScopeTests
{
    public static void RunAll()
    {
        var scope = new CommunityRealtimeScope("ORG_A", DateTimeOffset.UnixEpoch.AddDays(1),
            PlayerSharedStateFields.Presence, false, true, ["group-a"]);
        var copy = CommunityRealtimeScope.ValidateAndCopy([scope]);
        scope.VisibilityGroupIds[0] = "changed";
        Check(copy[0].VisibilityGroupIds[0] == "group-a", "policy owns its group references");
        Check(CommunityRealtimeScope.ValidateAndCopy([]).Length == 0, "empty explicitly withdraws community sharing");
        foreach (var invalid in new[] {
            scope with { Code = " ORG_A" }, scope with { JoinedAt = default },
            scope with { Fields = PlayerSharedStateFields.PersonalHangar },
            scope with { Fields = PlayerSharedStateFields.SharedEvents },
            scope with { VisibilityGroupIds = ["a", "A"] }, scope with { VisibilityGroupIds = null! }
        }) Reject([invalid]);
        Reject([scope, scope with { Code = "org_a" }]);
        Reject(Enumerable.Range(0, 65).Select(i => scope with { Code = "ORG_" + i }));
    }

    private static void Reject(IEnumerable<CommunityRealtimeScope> values)
    {
        try { CommunityRealtimeScope.ValidateAndCopy(values); }
        catch (ArgumentException) { return; }
        throw new InvalidOperationException("Invalid scope accepted.");
    }
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
