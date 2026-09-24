namespace StarBridge.Desktop;

public enum AccountAuthenticationStage
{
    SignedOut,
    ScmAuthenticated,
    RelayAuthenticated
}

public readonly record struct AccountRuntimeState(
    bool ScmAuthenticated,
    bool LegacyRelayAuthenticated,
    string? DisplayName,
    bool LegacyRelayAuthenticationExpired)
{
    public AccountAuthenticationStage AuthenticationStage => ScmAuthenticated
        ? AccountAuthenticationStage.ScmAuthenticated
        : LegacyRelayAuthenticated
            ? AccountAuthenticationStage.RelayAuthenticated
            : AccountAuthenticationStage.SignedOut;

    public bool IsAuthenticated => ScmAuthenticated || LegacyRelayAuthenticated;

    public bool HasRelaySession => LegacyRelayAuthenticated;

    public bool AuthenticationExpired => LegacyRelayAuthenticationExpired && !ScmAuthenticated;

    public bool CanPublishPresence => HasRelaySession && !LegacyRelayAuthenticationExpired;

    public static AccountRuntimeState Resolve(
        bool hasScmSession,
        bool hasRelaySession,
        string? scmDisplayName,
        string? relayDisplayName,
        bool authenticationExpired) => new(
            hasScmSession,
            hasRelaySession,
            hasScmSession ? scmDisplayName : hasRelaySession ? relayDisplayName : null,
            authenticationExpired);
}

public sealed class AccountRuntimeStore
{
    public AccountRuntimeState Current { get; private set; }

    public event EventHandler<AccountRuntimeState>? Changed;

    public bool Update(AccountRuntimeState next)
    {
        if (Current == next)
        {
            return false;
        }

        Current = next;
        Changed?.Invoke(this, next);
        return true;
    }
}
