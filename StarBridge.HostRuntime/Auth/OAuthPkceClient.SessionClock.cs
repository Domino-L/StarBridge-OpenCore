namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // One clock for an OAuth session's lifetime: issuing ExpiresAt and every
    // comparison against it (refresh lead, resume, reauthorization, first-use
    // review). Production keeps the system clock; tests drive it explicitly
    // instead of sleeping past a short real token lifetime.
    internal TimeProvider SessionClock { get; init; } = TimeProvider.System;

    internal DateTimeOffset SessionNow => SessionClock.GetUtcNow();
}
