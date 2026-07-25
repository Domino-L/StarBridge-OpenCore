namespace StarBridge.Core.Identity;

public enum IdentityVerificationState
{
    AwaitingGameIdentity,
    BindingRequired,
    Verified,
    Mismatch
}

public sealed record IdentityBindingAssessment(
    IdentityVerificationState State,
    string? BoundGameName,
    string? DetectedGameName)
{
    public bool CanSynchronize => State == IdentityVerificationState.Verified;
}

public static class IdentityBindingPolicy
{
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
}
