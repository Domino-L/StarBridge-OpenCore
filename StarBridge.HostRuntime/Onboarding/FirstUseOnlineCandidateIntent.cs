namespace StarBridge.HostRuntime.Onboarding;

// Native-only intent fence, not identity approval or a runtime attachment receipt.
// A cold startup never creates this owner just because it found onlinePending.
internal sealed record FirstUseOnlineCandidateIntent(FirstUseModeStore Store, FirstUseModeChoice Choice,
    Lifecycle.AccountGenerationSequence? Generations = null, bool RetainSession = false)
{
    internal bool IsCurrent
    {
        get
        {
            try { return Choice.Phase == "onlinePending" && Store.Read() == Choice &&
                Store.ReadOnlineOrigin() is { CandidateStarted: true } origin && origin.IsFor(Choice) &&
                RetainSession == (origin.Local.Phase == "offline"); }
            catch (LocalFirstUseException) { return false; }
        }
    }
}
