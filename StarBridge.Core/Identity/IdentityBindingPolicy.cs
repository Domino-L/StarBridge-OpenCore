namespace StarBridge.Core.Identity;

public enum IdentityVerificationState
{
    AwaitingGameIdentity,
    BindingRequired,
    VerificationPending,
    Verified,
    Mismatch,
    ReverificationRequired,
    Revoked,
    Unavailable
}

public enum ScmGameIdentityStatus
{
    Unverified,
    Pending,
    Verified,
    ReverifyRequired,
    Revoked,
    Unknown
}

public enum LocalIdentityCheckState
{
    NotObserved,
    Match,
    Mismatch
}

public sealed record ScmGameIdentitySnapshot(
    ScmGameIdentityStatus Status,
    string? Handle,
    string? NormalizedHandle)
{
    public string? CanonicalHandle =>
        IdentityBindingPolicy.NormalizeForComparison(NormalizedHandle) ??
        IdentityBindingPolicy.NormalizeForComparison(Handle);
}

public sealed record IdentityBindingAssessment(
    IdentityVerificationState State,
    string? BoundGameName,
    string? DetectedGameName,
    ScmGameIdentityStatus AuthoritativeStatus = ScmGameIdentityStatus.Unknown)
{
    public bool CanUseLocalFeatures => true;

    public bool CanUseIdentitySensitiveNetworkWrites =>
        State == IdentityVerificationState.Verified;

    // Compatibility alias for the legacy identity-binding call sites.
    public bool CanSynchronize => CanUseIdentitySensitiveNetworkWrites;
}

public static class IdentityBindingPolicy
{
    public static IdentityBindingAssessment Evaluate(
        ScmGameIdentitySnapshot authoritativeIdentity,
        string? detectedGameName)
    {
        ArgumentNullException.ThrowIfNull(authoritativeIdentity);

        var bound = Normalize(authoritativeIdentity.Handle) ??
                    Normalize(authoritativeIdentity.NormalizedHandle);
        var canonicalBound = authoritativeIdentity.CanonicalHandle;
        var detected = Normalize(detectedGameName);
        var canonicalDetected = NormalizeForComparison(detectedGameName);

        return authoritativeIdentity.Status switch
        {
            ScmGameIdentityStatus.Verified when canonicalBound is null =>
                Assessment(IdentityVerificationState.Unavailable),
            ScmGameIdentityStatus.Verified when canonicalDetected is null =>
                Assessment(IdentityVerificationState.Verified),
            ScmGameIdentityStatus.Verified =>
                Assessment(canonicalBound.Equals(canonicalDetected, StringComparison.Ordinal)
                    ? IdentityVerificationState.Verified
                    : IdentityVerificationState.Mismatch),
            ScmGameIdentityStatus.Pending =>
                Assessment(IdentityVerificationState.VerificationPending),
            ScmGameIdentityStatus.Unverified =>
                Assessment(IdentityVerificationState.BindingRequired),
            ScmGameIdentityStatus.ReverifyRequired =>
                Assessment(IdentityVerificationState.ReverificationRequired),
            ScmGameIdentityStatus.Revoked =>
                Assessment(IdentityVerificationState.Revoked),
            _ => Assessment(IdentityVerificationState.Unavailable)
        };

        IdentityBindingAssessment Assessment(IdentityVerificationState state) => new(
            state,
            bound,
            detected,
            authoritativeIdentity.Status);
    }

    public static IdentityBindingAssessment Evaluate(
        ScmGameIdentitySnapshot authoritativeIdentity,
        LocalIdentityCheckState localCheck)
    {
        ArgumentNullException.ThrowIfNull(authoritativeIdentity);

        var bound = Normalize(authoritativeIdentity.Handle) ??
                    Normalize(authoritativeIdentity.NormalizedHandle);
        var canonicalBound = authoritativeIdentity.CanonicalHandle;

        return authoritativeIdentity.Status switch
        {
            ScmGameIdentityStatus.Verified when canonicalBound is null =>
                Assessment(IdentityVerificationState.Unavailable),
            ScmGameIdentityStatus.Verified when localCheck == LocalIdentityCheckState.Mismatch =>
                Assessment(IdentityVerificationState.Mismatch),
            ScmGameIdentityStatus.Verified =>
                Assessment(IdentityVerificationState.Verified),
            ScmGameIdentityStatus.Pending =>
                Assessment(IdentityVerificationState.VerificationPending),
            ScmGameIdentityStatus.Unverified =>
                Assessment(IdentityVerificationState.BindingRequired),
            ScmGameIdentityStatus.ReverifyRequired =>
                Assessment(IdentityVerificationState.ReverificationRequired),
            ScmGameIdentityStatus.Revoked =>
                Assessment(IdentityVerificationState.Revoked),
            _ => Assessment(IdentityVerificationState.Unavailable)
        };

        IdentityBindingAssessment Assessment(IdentityVerificationState state) => new(
            state,
            bound,
            null,
            authoritativeIdentity.Status);
    }

    public static IdentityBindingAssessment Evaluate(
        string? boundGameName,
        DateTimeOffset? bindingConfirmedAt,
        string? detectedGameName)
    {
        var bound = Normalize(boundGameName);
        var detected = Normalize(detectedGameName);

        if (detected is null)
        {
            return new IdentityBindingAssessment(
                IdentityVerificationState.AwaitingGameIdentity,
                bound,
                null);
        }

        if (bindingConfirmedAt is null || bound is null)
        {
            return new IdentityBindingAssessment(
                IdentityVerificationState.BindingRequired,
                bound,
                detected);
        }

        return new IdentityBindingAssessment(
            bound.Equals(detected, StringComparison.OrdinalIgnoreCase)
                ? IdentityVerificationState.Verified
                : IdentityVerificationState.Mismatch,
            bound,
            detected);
    }

    public static bool IsValidGameName(string? gameName)
    {
        var value = Normalize(gameName);
        return value is not null &&
               value.Length is >= 2 and <= 64 &&
               value.All(character => char.IsLetterOrDigit(character) || character is '_' or '-' or '.');
    }

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    internal static string? NormalizeForComparison(string? value) =>
        Normalize(value)?.ToLowerInvariant();
}
