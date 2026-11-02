using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly object _rootOfflineExitGate = new();
    private Task<bool>? _rootOfflineExit;
    private BridgeAccountContext? _rootOfflineContext;
    private long _rootOfflineGeneration = -1;

    // Ordinary startup is not a staged first-use installation. Keep the root's
    // device owners alive, but permanently seal its original online admissions.
    internal bool CanPreserveRootSession(long generation, BridgeAccountContext context) =>
        !_disposed && !_firstUseCandidate && FirstUseMode is not null && _firstUseRoot is not null &&
        _newDormantGameLog is not null && FirstUseGame is not null &&
        !_localBusinessRetired && !_requestRetirement.IsClosed && !_backgroundConfiguration.IsClosed &&
        _host is ScmAccountBridgeHost scm && scm.Generation == generation && scm.CurrentContext == context;

    internal Task<bool> StopRootOnlinePreservingSessionAsync(NativeAccountRuntimeBinding.RootOfflineCallbacks original)
    {
        var generation = original.Generation; var context = original.Context;
        TaskCompletionSource<bool> completion;
        lock (_rootOfflineExitGate)
        {
            if (_rootOfflineExit is not null)
                return _rootOfflineGeneration == generation && _rootOfflineContext == context
                    ? _rootOfflineExit : Task.FromResult(false);
            // Admission was captured while live. Reentrant cancellation may
            // already have changed the generation or closed Native callbacks;
            // still drain this original root, but never acknowledge that change.
            if (!ReferenceEquals(original.Root, this) || _disposed || _firstUseCandidate ||
                _host is not ScmAccountBridgeHost) return Task.FromResult(false);
            _rootOfflineGeneration = generation; _rootOfflineContext = context;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _rootOfflineExit = completion.Task;
        }
        _ = CompleteRootOfflineExitAsync(generation, context, completion);
        return completion.Task;
    }

    internal bool HasPreservedRootSessionExit(long generation, BridgeAccountContext context) =>
        !_disposed && _rootOfflineGeneration == generation && _rootOfflineContext == context &&
        _rootOfflineExit is { IsCompletedSuccessfully: true, Result: true } &&
        _host is ScmAccountBridgeHost scm && scm.Generation == generation && scm.CurrentContext == context;

    private async Task CompleteRootOfflineExitAsync(long generation, BridgeAccountContext context,
        TaskCompletionSource<bool> completion)
    {
        // No observer token: callers can leave the wait, not this original exit.
        var scm = (ScmAccountBridgeHost)_host;
        var failures = new List<Exception>();
        bool Current() => !_disposed && scm.Generation == generation && scm.CurrentContext == context;
        async Task Drain(Func<Task> stop)
        { try { await stop().ConfigureAwait(false); } catch (Exception error) { failures.Add(error); } }
        bool withdrawn = false, loops = false;
        try
        {
            var requests = _requestRetirement.Close();
            var preparation = _firstUseBusinessPreparation.Close();
            await Drain(scm.CancelLoginAsync).ConfigureAwait(false);
            await Drain(() => Task.WhenAll(requests, preparation)).ConfigureAwait(false);
            await Drain(RetireBusinessBackgroundForLocalMode).ConfigureAwait(false);
            // Even a sibling failure must attempt withdrawal and physical exits.
            try { withdrawn = Current() && await StopPrivacyPublicationAsync().ConfigureAwait(false) && Current(); }
            catch (Exception error) { failures.Add(error); }
            await Drain(RetirePublicationOwnersAsync).ConfigureAwait(false);
            await Drain(scm.RetireSessionLoopsPreservingSessionAsync).ConfigureAwait(false);
            await Drain(async () =>
            {
                loops = await scm.WaitForOriginalSessionLoopsAsync(context, generation, CancellationToken.None).ConfigureAwait(false);
            }).ConfigureAwait(false);
            if (failures.Count != 0) throw new AggregateException(failures);
            completion.TrySetResult(withdrawn && loops && Current());
        }
        catch (Exception error) { completion.TrySetException(error); }
        // No logout, revoke, vault read/write, PublishSession(null), or Dispose.
    }
}
