namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // One clock for an OAuth session's lifetime: issuing ExpiresAt and every
    // comparison against it (refresh lead, resume, reauthorization, first-use
    // review). Production keeps the system clock; tests drive it explicitly
    // instead of sleeping past a short real token lifetime.
    internal TimeProvider SessionClock { get; init; } = TimeProvider.System;

    internal DateTimeOffset SessionNow => SessionClock.GetUtcNow();

    // A resource caller may hold an older metadata copy. Check the installed
    // session too: a rejected access token can be expired without a version
    // change while its refresh is pending. This performs no authorization.
    internal bool CanReuseResourceSession(ScmOAuthSession session)
    {
        var current = Volatile.Read(ref _currentSession);
        return current is not null && SameCredential(current, session) &&
            Volatile.Read(ref _retainedRefresh) is null &&
            current.ExpiresAt == session.ExpiresAt && current.ExpiresAt > SessionNow.AddMinutes(1);
    }
}
