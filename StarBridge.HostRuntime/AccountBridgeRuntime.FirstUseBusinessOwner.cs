using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly Lifecycle.AsyncWorkRetirement _firstUseBusinessPreparation = new();

    internal sealed class PreparedFirstUseBusinessOwner
    {
        private readonly PreparedFirstUseOnlineCandidate _candidate;
        private readonly ScmAccountBridgeHost.FirstUseBusinessOwnerFacts _facts;
        private PreparedFirstUseBusinessOwner(PreparedFirstUseOnlineCandidate candidate,
            ScmAccountBridgeHost.FirstUseBusinessOwnerFacts facts)
        { _candidate = candidate; _facts = facts; }
        internal static PreparedFirstUseBusinessOwner? Create(PreparedFirstUseOnlineCandidate candidate,
            ScmAccountBridgeHost.FirstUseBusinessOwnerFacts facts)
        {
            var result = new PreparedFirstUseBusinessOwner(candidate, facts);
            return result.IsCurrent ? result : null;
        }
        internal bool IsCurrent => _candidate.IsCurrent && !_candidate.Owner._firstUseBusinessPreparation.IsClosed &&
            _facts.IsCurrent;
        internal AccountBridgeRuntime Owner => _candidate.Owner;
        internal BridgeAccountContext StorageOwner => _facts.StorageOwner;
        internal bool IsFor(PreparedFirstUseOnlineCandidate candidate) => ReferenceEquals(_candidate, candidate);
        private readonly object _installationGate = new();
        private ScmAccountBridgeHost.FirstUseBusinessAdmission? _admission;
        private FirstUseBusinessInstallation? _installation;

        internal FirstUseBusinessInstallation? StageInstallation(
            NativeAccountRuntimeBinding.PreparedNativeCallbacks callbacks, Task localSourcesExit)
        {
            lock (_installationGate)
            {
                if (!IsCurrent || !callbacks.Authorizes(this, localSourcesExit)) return null;
                if (_installation is not null) return _installation;
                if (Owner._firstUseInstallation is not null) return null;
                var scm = StageBusinessAdmission(callbacks, localSourcesExit);
                if (scm is null || scm.IsActive || scm.HasExited) return null;
                _installation = new(this, callbacks, localSourcesExit, scm);
                Volatile.Write(ref Owner._firstUseInstallation, _installation);
                return _installation;
            }
        }

        // Only original Native callback and local sampler exit receipts permit
        // staging. This does not replace the Native slot or complete onboarding.
        internal ScmAccountBridgeHost.FirstUseBusinessAdmission? StageBusinessAdmission(
            NativeAccountRuntimeBinding.PreparedNativeCallbacks callbacks, Task localSourcesExit)
        {
            lock (_installationGate)
            {
                if (!IsCurrent || !callbacks.Authorizes(this, localSourcesExit)) return null;
                return _admission ??= _facts.StageAdmission(() =>
                    IsCurrent && callbacks.Authorizes(this, localSourcesExit));
            }
        }
    }

    internal sealed partial class PreparedFirstUseOnlineCandidate
    {
        private readonly SemaphoreSlim _businessWriter = new(1, 1);
        private volatile PreparedFirstUseBusinessOwner? _businessOwner;

        // Only an actually drained, still-current original candidate can perform
        // this read. Caller cancellation abandons observation, never the physical
        // lease: mode cancellation/credential clear must still await its exit.
        internal async Task<PreparedFirstUseBusinessOwner?> PrepareBusinessOwnerAsync(CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (!IsCurrent || _owner._firstUseBusinessPreparation.IsClosed) return null;
            if (_businessOwner is { IsCurrent: true } ready) return ready;
            if (!_businessWriter.Wait(0)) return null;
            var read = ReadBusinessOwnerCoreAsync(token);
            // Observe a late fault even if an observer has already cancelled.
            _ = read.ContinueWith(task => _ = task.Exception, CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            return await read.WaitAsync(token).ConfigureAwait(false);
        }

        private async Task<PreparedFirstUseBusinessOwner?> ReadBusinessOwnerCoreAsync(CancellationToken token)
        {
            try
            {
                using var work = _owner._firstUseBusinessPreparation.Enter(token);
                if (work is null || !IsCurrent || _owner._host is not ScmAccountBridgeHost scm) return null;
                var facts = await ScmAccountBridgeHost.FirstUseBusinessOwnerFacts.ReadAsync(scm, _facts, work.Token)
                    .ConfigureAwait(false);
                if (facts is null || !work.IsCurrent || !IsCurrent) return null;
                var result = PreparedFirstUseBusinessOwner.Create(this, facts);
                if (result is null || !work.IsCurrent || !result.IsCurrent) return null;
                _businessOwner = result;
                return result;
            }
            catch (OperationCanceledException) { return null; }
            finally { _businessWriter.Release(); }
        }
    }
}
