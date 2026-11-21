using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IVisitorGameplayTimeRemote
{
    bool IVisitorGameplayTimeRemote.Supports(BridgeAccountContext owner, long generation) => Supports(owner, generation);

    async Task<VisitorGameplayTimeResult> IVisitorGameplayTimeRemote.WriteAsync(
        BridgeAccountContext owner, long generation, VisitorGameplayTime value, CancellationToken token)
    {
        try
        {
            // Same SCM owner, shared admission and session adoption as the hangar copy.
            return await WithHangarArchiveSession(owner, generation,
                (session, ready, ct) => _oauth.WriteVisitorGameplayTimeAsync(session, value, ct, ready), token)
                .ConfigureAwait(false);
        }
        catch (HttpRequestException error) when (error is ScmApiAuthenticationException or ScmApiForbiddenException)
        {
            return new(VisitorGameplayTimeOutcome.AuthorizationRejected);
        }
    }
}
