using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record LocalOwnerRead(BridgeAccountContext Context, long Generation, ScmOAuthSession Session,
        long Sequence, TaskCompletionSource<AccountBridgeCompatibilityProjection> Completion);
    private LocalOwnerRead? _localOwnerRead;

    private Task<AccountBridgeCompatibilityProjection> ReadLocalDataOwnerSingleFlightAsync(
        BridgeAccountContext context, long generation, ScmOAuthSession session, CancellationToken token)
    {
        LocalOwnerRead read;
        lock (_localOwnerGate)
        {
            // A call paused before acquiring this gate must not displace a
            // flight belonging to a replacement session.
            if (_disposed || generation != Generation || context != CurrentContext || !ReferenceEquals(_session, session))
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
            if (_localOwnerRead is { } pending && pending.Context == context && pending.Generation == generation &&
                ReferenceEquals(pending.Session, session)) return JoinLocalDataOwnerReadAsync(pending, token);
            read = new(context, generation, session, ++_localOwnerReadSequence,
                new(TaskCreationOptions.RunContinuationsAsynchronously));
            _localOwnerRead = read;
        }
        // The initiating call retains the original read's cancellation lifetime;
        // joiners may cancel their own wait without cancelling that operation.
        _ = CompleteLocalDataOwnerReadAsync(read, token);
        return read.Completion.Task;
    }

    private static async Task<AccountBridgeCompatibilityProjection> JoinLocalDataOwnerReadAsync(
        LocalOwnerRead read, CancellationToken token)
    {
        try { return await read.Completion.Task.WaitAsync(token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            // The initiating request owns physical IO and its cancellation.
            // An uncancelled joiner can retry rather than inherit that cancellation.
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
    }

    private async Task CompleteLocalDataOwnerReadAsync(LocalOwnerRead read, CancellationToken token)
    {
        AccountBridgeCompatibilityProjection? result = null;
        Exception? failure = null;
        try { result = await ReadLocalDataOwnerAsync(read, token).ConfigureAwait(false); }
        catch (Exception error) { failure = error; }
        lock (_localOwnerGate)
        {
            if (ReferenceEquals(_localOwnerRead, read)) _localOwnerRead = null;
            if (failure is null) read.Completion.TrySetResult(result!);
            else read.Completion.TrySetException(failure);
        }
    }

    private async Task<AccountBridgeCompatibilityProjection> ReadLocalDataOwnerAsync(LocalOwnerRead read, CancellationToken token)
    {
        AccountBridgeCompatibilityProjection result;
        try
        {
            token.ThrowIfCancellationRequested();
            result = await _compatibilityReader!.ReadAsync(read.Session, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or
            System.Text.Json.JsonException or InvalidOperationException or OperationCanceledException or TimeoutException)
        {
            // Some transports report IO/HTTP failure while observing cancellation.
            token.ThrowIfCancellationRequested();
            Support.IdentityGateJournal.Event("owner-compat", $"code=compat-unavailable exception={Support.IdentityGateJournal.Type(error)}");
            ObserveLocalDataOwnerFailure(read.Context, read.Generation, read.Sequence, read.Session);
            _compatibilityReader!.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        if (!ObserveLocalDataOwner(read.Context, read.Generation, read.Sequence, result, read.Session))
        {
            _compatibilityReader!.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        return result;
    }
}
