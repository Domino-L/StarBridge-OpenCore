namespace StarBridge.Desktop;

using StarBridge.Core.Identity;

public sealed class IdentityBindingPromptTracker
{
    private string? _accountId;
    private bool _promptedDuringUnresolvedEpisode;

    public bool ShouldPrompt(
        string? accountId,
        IdentityBindingAssessment assessment,
        bool promptAllowed = true)
    {
        var normalizedAccountId = Normalize(accountId);
        if (!string.Equals(_accountId, normalizedAccountId, StringComparison.OrdinalIgnoreCase))
        {
            _accountId = normalizedAccountId;
            _promptedDuringUnresolvedEpisode = false;
        }

        if (assessment.State == IdentityVerificationState.Verified)
        {
            _promptedDuringUnresolvedEpisode = false;
            return false;
        }

        if (!promptAllowed ||
            assessment.State == IdentityVerificationState.BindingRequired ||
            assessment.State == IdentityVerificationState.AwaitingGameIdentity ||
            _promptedDuringUnresolvedEpisode)
        {
            return false;
        }

        _promptedDuringUnresolvedEpisode = true;
        return true;
    }

    public void Reset()
    {
        _accountId = null;
        _promptedDuringUnresolvedEpisode = false;
    }

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
