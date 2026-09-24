using StarBridge.Core.Hangar;
using StarBridge.Core.Identity;

namespace StarBridge.Core.Tests;

internal static class RsiHangarIdentityPolicyTests
{
    public static void RunAll()
    {
        var verified = new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Verified, "Pilot_Alpha", "pilot_alpha");
        if (RsiHangarIdentityPolicy.DisplayHandle(verified) != "Pilot_Alpha")
            throw new InvalidOperationException("Display Handle must preserve SCM casing.");
        if (RsiHangarIdentityPolicy.DisplayHandle(verified with { Handle = null }) != "pilot_alpha")
            throw new InvalidOperationException("Canonical Handle is only a fallback when SCM has no presentation form.");
        Expect(RsiHangarIdentityState.Matched, verified, [" PILOT_ALPHA ", "Pilot_Alpha"]);
        Expect(RsiHangarIdentityState.Mismatch, verified, ["Pilot_Beta"]);
        Expect(RsiHangarIdentityState.Mismatch, verified, ["Pilot-Alpha"]);
        Expect(RsiHangarIdentityState.Mismatch, verified, ["Pilot.Alpha"]);
        Expect(RsiHangarIdentityState.Mismatch, verified, ["Pilot_Alphа"]); // Final letter is Cyrillic.
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, null);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, []);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, ["Pilot_Alpha", ""]);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, ["@Pilot_Alpha"]);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, ["Pilot_Alpha\u200b"]);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, [new string('a', 65)]);
        Expect(RsiHangarIdentityState.ReaderIdentityUnavailable, verified, Enumerable.Repeat<string?>("Pilot_Alpha", 9).ToArray());
        Expect(RsiHangarIdentityState.ReaderIdentityAmbiguous, verified, ["Pilot_Alpha", "Pilot_Beta"]);
        foreach (var status in Enum.GetValues<ScmGameIdentityStatus>().Where(s => s != ScmGameIdentityStatus.Verified))
        {
            Expect(RsiHangarIdentityState.ApplicationIdentityUnavailable, verified with { Status = status }, ["Pilot_Alpha"]);
        }
        Expect(RsiHangarIdentityState.ApplicationIdentityUnavailable, verified with { Handle = "Pilot_Beta" }, ["Pilot_Alpha"]);
        Expect(RsiHangarIdentityState.ApplicationIdentityUnavailable, verified with { Handle = null, NormalizedHandle = null }, ["Pilot_Alpha"]);
        Expect(RsiHangarIdentityState.Matched, verified with { Handle = null }, ["Pilot_Alpha"]);
    }

    private static void Expect(RsiHangarIdentityState expected, ScmGameIdentitySnapshot identity, IReadOnlyList<string?>? claims)
    {
        var result = RsiHangarIdentityPolicy.Evaluate(identity, claims);
        if (result.State != expected || result.CanContinue != (expected == RsiHangarIdentityState.Matched))
            throw new InvalidOperationException($"Hangar identity expected {expected}, actual {result.State}");
    }
}
