using StarBridge.Core.Identity;

namespace StarBridge.Core.Tests;

internal static class RsiIdentityPolicyTests
{
    public static void RunAll()
    {
        VerifiedMatchingHandleAllowsSensitiveWrites();
        VerifiedMismatchedHandleBlocksSensitiveWrites();
        VerifiedIdentitySurvivesWhenTheGameIsNotRunning();
        PersistedMismatchStaysBlockedUntilTheNextMatchingCheck();
        ReverificationAndRevocationFailClosed();
        UnknownAuthorityStateFailsClosed();
        HandleComparisonIsExactAfterDocumentedNormalization();
    }

    private static void VerifiedMatchingHandleAllowsSensitiveWrites()
    {
        var assessment = IdentityBindingPolicy.Evaluate(
            new ScmGameIdentitySnapshot(
                ScmGameIdentityStatus.Verified,
                "Domino_CN",
                "domino_cn"),
            " DOMINO_CN ");

        AssertEqual(IdentityVerificationState.Verified, assessment.State, "matching state");
        AssertTrue(assessment.CanUseIdentitySensitiveNetworkWrites, "matching identity was blocked");
        AssertTrue(assessment.CanUseLocalFeatures, "matching identity disabled local features");
    }

    private static void VerifiedMismatchedHandleBlocksSensitiveWrites()
    {
        var assessment = IdentityBindingPolicy.Evaluate(
            Verified("domino_cn"),
            "another_pilot");

        AssertEqual(IdentityVerificationState.Mismatch, assessment.State, "mismatch state");
        AssertFalse(assessment.CanUseIdentitySensitiveNetworkWrites, "mismatch allowed a sensitive write");
        AssertTrue(assessment.CanUseLocalFeatures, "mismatch disabled local features");
    }

    private static void VerifiedIdentitySurvivesWhenTheGameIsNotRunning()
    {
        var assessment = IdentityBindingPolicy.Evaluate(Verified("domino_cn"), null);

        AssertEqual(IdentityVerificationState.Verified, assessment.State, "persisted verification state");
        AssertTrue(assessment.CanUseIdentitySensitiveNetworkWrites, "stopping the game cleared verified identity");
        AssertTrue(assessment.CanUseLocalFeatures, "stopping the game disabled local features");
        AssertEqual("domino_cn", assessment.BoundGameName, "verified Handle");
        AssertEqual<string?>(null, assessment.DetectedGameName, "inactive game observation");
    }

    private static void PersistedMismatchStaysBlockedUntilTheNextMatchingCheck()
    {
        var mismatch = IdentityBindingPolicy.Evaluate(
            Verified("domino_cn"),
            LocalIdentityCheckState.Mismatch);
        var recovered = IdentityBindingPolicy.Evaluate(
            Verified("domino_cn"),
            LocalIdentityCheckState.Match);

        AssertEqual(IdentityVerificationState.Mismatch, mismatch.State, "persisted mismatch state");
        AssertFalse(mismatch.CanUseIdentitySensitiveNetworkWrites, "persisted mismatch allowed a sensitive write");
        AssertEqual(IdentityVerificationState.Verified, recovered.State, "matching recheck state");
        AssertTrue(recovered.CanUseIdentitySensitiveNetworkWrites, "matching recheck remained blocked");
    }

    private static void ReverificationAndRevocationFailClosed()
    {
        var reverify = IdentityBindingPolicy.Evaluate(
            new ScmGameIdentitySnapshot(ScmGameIdentityStatus.ReverifyRequired, "domino_cn", "domino_cn"),
            "domino_cn");
        var revoked = IdentityBindingPolicy.Evaluate(
            new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Revoked, "domino_cn", "domino_cn"),
            "domino_cn");

        AssertEqual(IdentityVerificationState.ReverificationRequired, reverify.State, "reverify state");
        AssertFalse(reverify.CanUseIdentitySensitiveNetworkWrites, "reverify state allowed a sensitive write");
        AssertEqual(IdentityVerificationState.Revoked, revoked.State, "revoked state");
        AssertFalse(revoked.CanUseIdentitySensitiveNetworkWrites, "revoked state allowed a sensitive write");
    }

    private static void UnknownAuthorityStateFailsClosed()
    {
        var assessment = IdentityBindingPolicy.Evaluate(
            new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Unknown, "domino_cn", "domino_cn"),
            "domino_cn");

        AssertEqual(IdentityVerificationState.Unavailable, assessment.State, "unknown authority state");
        AssertFalse(assessment.CanUseIdentitySensitiveNetworkWrites, "unknown authority state allowed a sensitive write");
    }

    private static void HandleComparisonIsExactAfterDocumentedNormalization()
    {
        var assessment = IdentityBindingPolicy.Evaluate(Verified("domino_cn"), "domino-cn");

        AssertEqual(IdentityVerificationState.Mismatch, assessment.State, "fuzzy handle comparison");
        AssertFalse(assessment.CanUseIdentitySensitiveNetworkWrites, "similar handle was treated as equal");
    }

    private static ScmGameIdentitySnapshot Verified(string handle) => new(
        ScmGameIdentityStatus.Verified,
        handle,
        handle.ToLowerInvariant());

    private static void AssertTrue(bool value, string message)
    {
        if (!value)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void AssertFalse(bool value, string message) => AssertTrue(!value, message);

    private static void AssertEqual<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{message}: expected={expected}, actual={actual}");
        }
    }
}
