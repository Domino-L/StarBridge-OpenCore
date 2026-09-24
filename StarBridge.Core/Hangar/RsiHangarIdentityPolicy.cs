using StarBridge.Core.Identity;

namespace StarBridge.Core.Hangar;

public enum RsiHangarIdentityState
{
    Matched,
    ApplicationIdentityUnavailable,
    ReaderIdentityUnavailable,
    ReaderIdentityAmbiguous,
    Mismatch
}

public sealed record RsiHangarIdentityAssessment(
    RsiHangarIdentityState State,
    string? ExpectedHandle,
    string? ObservedHandle)
{
    public bool CanContinue => State == RsiHangarIdentityState.Matched;
}

/// <summary>
/// Compares current-account observations, not public citizen profiles or display names.
/// The caller must separately validate document origin and account/navigation lifetime.
/// This is a local import safety check, not proof of asset ownership for a server.
/// </summary>
public static class RsiHangarIdentityPolicy
{
    public const int MaximumHandleClaims = 8;

    public static RsiHangarIdentityAssessment Evaluate(
        ScmGameIdentitySnapshot authoritativeIdentity,
        IReadOnlyList<string?>? currentAccountHandles)
    {
        ArgumentNullException.ThrowIfNull(authoritativeIdentity);
        var expected = authoritativeIdentity.Handle?.Trim();
        var canonical = authoritativeIdentity.CanonicalHandle;
        if (authoritativeIdentity.Status != ScmGameIdentityStatus.Verified ||
            !IdentityBindingPolicy.IsValidGameName(canonical) ||
            (!string.IsNullOrWhiteSpace(expected) &&
             (!IdentityBindingPolicy.IsValidGameName(expected) ||
              !string.Equals(expected, canonical, StringComparison.OrdinalIgnoreCase))))
        {
            return new(RsiHangarIdentityState.ApplicationIdentityUnavailable, null, null);
        }

        expected = string.IsNullOrWhiteSpace(expected) ? canonical : expected;
        if (currentAccountHandles is null || currentAccountHandles.Count == 0 ||
            currentAccountHandles.Count > MaximumHandleClaims ||
            currentAccountHandles.Any(handle => !IdentityBindingPolicy.IsValidGameName(handle)))
        {
            return new(RsiHangarIdentityState.ReaderIdentityUnavailable, expected, null);
        }

        var distinct = currentAccountHandles.Select(handle => handle!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (distinct.Length != 1)
        {
            return new(RsiHangarIdentityState.ReaderIdentityAmbiguous, expected, null);
        }

        // Reuse SCM/game identity normalization, without requiring a running game.
        var match = IdentityBindingPolicy.Evaluate(authoritativeIdentity, distinct[0]);
        return new(match.CanUseIdentitySensitiveNetworkWrites
            ? RsiHangarIdentityState.Matched
            : RsiHangarIdentityState.Mismatch, expected, distinct[0]);
    }

    /// <summary>Returns SCM's verified presentation form; comparison still uses CanonicalHandle.</summary>
    public static string? DisplayHandle(ScmGameIdentitySnapshot identity)
    {
        var assessment = Evaluate(identity, [identity.CanonicalHandle]);
        return assessment.CanContinue ? assessment.ExpectedHandle : null;
    }
}
