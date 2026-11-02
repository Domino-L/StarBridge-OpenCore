using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class AccountBridgeDispatcher
{
    private void OnGameIdentityChanged(long generation) => PublishDomainInvalidation("gameIdentity.changed", generation);

    // The host owns short mutation leases and a single-flight marker. Long
    // verification IO must not occupy the dispatch barrier either: account
    // projections, logout and a duplicate-operation rejection remain prompt.
    private async Task<AccountBridgeDispatchResult> DispatchGameIdentityAsync(BridgeEnvelope request, CancellationToken token)
    {
        BeginDispatchEventCollection();
        try { return Result(await DispatchCoreAsync(request, token).ConfigureAwait(false)); }
        catch (AccountBridgeHostException error)
        { return Result(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Account operation failed.", error.Retryable))); }
        catch (BridgeProtocolException error)
        { return Result(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Bridge request was rejected."))); }
        catch (OperationCanceledException)
        { return Result(BridgeEnvelope.CancelledResponse(request)); }
        catch (Exception)
        { return Result(BridgeEnvelope.ErrorResponse(request, new(BridgeErrorCodes.HostError, "Account operation failed."))); }
    }
}
