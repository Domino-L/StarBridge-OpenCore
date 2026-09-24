namespace StarBridge.HostRuntime.Auth;

// Preserve the existing login exception family while allowing individual
// write actions to distinguish a user declining authorization from a fault.
internal sealed class OAuthAuthorizationDeniedException()
    : InvalidOperationException("SCM authorization was declined.");
