using StarBridge.HostRuntime.Lifecycle;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private FirstUseBusinessAdmission? _firstUseBusinessAdmission;

    // Constructor provenance remains immutable. A consumed live installation,
    // not reopening auth or changing that flag, admits the original SCM graph.
    private bool IsBusinessStartupDeferred => _businessStartupDeferred &&
        Volatile.Read(ref _firstUseBusinessAdmission)?.IsActive != true;

    internal Task RetireFirstUseBusinessAdmissionAsync() =>
        Volatile.Read(ref _firstUseBusinessAdmission)?.RetireAsync() ?? Task.CompletedTask;

    internal sealed class FirstUseBusinessAdmission
    {
        private readonly ScmAccountBridgeHost _owner;
        private readonly FirstUseBusinessOwnerFacts _facts;
        private readonly Func<bool> _preparationCurrent;
        private readonly AsyncWorkRetirement _work = new();
        private readonly object _exitGate = new();
        private Task? _exit;
        private int _state; // 0 staged, 1 live, 2 retiring: never reusable.
        private FirstUseBusinessAdmission(ScmAccountBridgeHost owner, FirstUseBusinessOwnerFacts facts,
            Func<bool> preparationCurrent)
        { _owner = owner; _facts = facts; _preparationCurrent = preparationCurrent; }

        internal static FirstUseBusinessAdmission? Stage(ScmAccountBridgeHost owner,
            FirstUseBusinessOwnerFacts facts, Func<bool> preparationCurrent)
        {
            lock (owner._realtimeGate)
            {
                if (!facts.IsCurrent || !preparationCurrent() || owner._localModeSessionLoopsStopped ||
                    owner._firstUseBusinessAdmission is not null) return null;
                var result = new FirstUseBusinessAdmission(owner, facts, preparationCurrent);
                Volatile.Write(ref owner._firstUseBusinessAdmission, result);
                return result;
            }
        }

        internal BridgeAccountContext StorageOwner => _facts.StorageOwner;
        internal bool IsActive => Volatile.Read(ref _state) == 1 && !_work.IsClosed &&
            ReferenceEquals(Volatile.Read(ref _owner._firstUseBusinessAdmission), this) && _facts.IsInstalledOwnerCurrent;
        internal bool HasExited => Volatile.Read(ref _exit)?.IsCompletedSuccessfully == true;

        internal bool TryActivate()
        {
            lock (_owner._realtimeGate)
            {
                if (Volatile.Read(ref _state) == 1) return IsActive;
                if (Volatile.Read(ref _state) != 0 || _work.IsClosed || !_facts.IsCurrent ||
                    !_preparationCurrent() || _owner._localModeSessionLoopsStopped ||
                    !ReferenceEquals(_owner._firstUseBusinessAdmission, this)) return false;
                Volatile.Write(ref _state, 1);
            }
            // Startup belongs to this consumed admission. A concurrent retirement
            // suppresses every actual loop through its effective admission gate.
            _owner.EnsureAccountRealtime();
            _owner.EnsureRoomMembershipKeepalive();
            _owner.EnsureParticipantLoop();
            return IsActive;
        }

        internal AsyncWorkRetirement.Lease? Enter(CancellationToken token)
        {
            if (!IsActive) return null;
            var lease = _work.Enter(token);
            if (lease is not null && !IsActive) { lease.Dispose(); return null; }
            return lease;
        }

        internal Task RetireAsync()
        {
            TaskCompletionSource completion;
            lock (_exitGate)
            {
                if (_exit is not null) return _exit;
                completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _exit = completion.Task;
            }
            // Activation uses the same lifecycle lock. It cannot overwrite the
            // one-way retired state after checking an earlier staged value.
            lock (_owner._realtimeGate) Volatile.Write(ref _state, 2);
            // Reserve once, invoke arbitrary cancellation outside reservation locks.
            _ = ExitAsync(completion);
            return completion.Task;
        }

        private async Task ExitAsync(TaskCompletionSource completion)
        {
            try
            {
                var work = _work.Close();
                Exception? stopFailure = null;
                try { _owner.StopSessionLoopsForLocalMode(_facts.Generation); }
                catch (Exception error) { stopFailure = error; }
                // A cancellation callback fault must not prevent sibling loop
                // stop or let the original admission report before work exits.
                foreach (var stop in new Action[] { _owner.StopAccountRealtime,
                             _owner.StopRoomMembershipKeepalive, _owner.StopParticipantLoop })
                {
                    try { stop(); }
                    catch (Exception error) { stopFailure ??= error; }
                }
                await Task.WhenAll(work, _owner.SessionLoopRetirement()).ConfigureAwait(false);
                if (stopFailure is not null) throw stopFailure;
                completion.TrySetResult();
            }
            catch (Exception error) { completion.TrySetException(error); }
        }
    }
}
