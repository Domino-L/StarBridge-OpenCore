namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    // Both normal startup and the authentication-only candidate use this same
    // graph. The journal is borrowed from device composition, never reopened or
    // disposed here. Candidate timers remain deferred by the actual constructor.
    internal static AccountBridgeRuntime CreateAccountBusinessRuntime(Account.ScmAccountBridgeHost host,
        string dataRoot, Support.LocalGameEventJournal? eventJournal, bool firstUseCandidate,
        Onboarding.FirstUseOnlineCandidateIntent? candidateIntent, TimeProvider? backgroundTime = null)
    {
        var runtime = new AccountBridgeRuntime(host, new Hangar.LocalHangarStore(dataRoot), new Profiles.LocalPersonalProfileStore(dataRoot),
            new Presence.GameplayTimeStore(dataRoot), new Presence.GameLogSettingsStore(dataRoot),
            new Privacy.LocalPrivacyStore(dataRoot), eventJournal, new Settings.PresenceVisibilityStore(dataRoot),
            dataRoot, firstUseCandidate: firstUseCandidate, backgroundTime: backgroundTime, candidateIntent: candidateIntent);
        runtime.InitializeAccountDisplayCache(dataRoot);
        return runtime;
    }

    // Native composition only, not a bridge request or authentication/handoff
    // receipt. Construct additional Native-owned consumers inside the callback
    // so a local cold start or auth-only candidate never allocates those consumers.
    // The dormant Host graph above is separate from these Native consumers. Existing owning
    // modules retain their own configuration checks and disposal contracts.
    public bool TryConfigureAccountBusiness(Action<AccountBridgeRuntime> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        using var work = _backgroundConfiguration.Enter(default);
        if (work is null || _host is not Account.ScmAccountBridgeHost { BusinessStartupDeferred: false } ||
            _firstUseCandidate || _disposed || _localBusinessRetired) return false;
        configure(this);
        bool Current() => work.IsCurrent && !_disposed && !_localBusinessRetired &&
            !_firstUseCandidate && _host is Account.ScmAccountBridgeHost { BusinessStartupDeferred: false };
        // Only this original configuration lease may start the existing owners.
        // Identity review alone does not open business or publication admission.
        if (!Current() || !(_gameLog?.StartDeferredSampling() ?? true) ||
            !Current() || !(_gameplayTime?.StartDeferredSampling() ?? true) ||
            !Current() || !(_achievements?.StartDeferredWork() ?? true) ||
            !Current() || !(_privacyPublication?.StartDeferredWork() ?? true) ||
            !Current() || !(_friendSharing?.StartDeferredWork() ?? true) ||
            !Current() || !(_eventSharing?.StartDeferredWork() ?? true)) return false;
        // Retirement may have raced the synchronous configuration callback; its
        // actual exit lease is drained before the original owner can acknowledge.
        return Current();
    }
}
