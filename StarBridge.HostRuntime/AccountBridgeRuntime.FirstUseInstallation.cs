using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private FirstUseBusinessInstallation? _firstUseInstallation;

    private AsyncWorkRetirement.Lease? EnterAccountBusinessConfiguration()
    {
        if (_disposed || _localBusinessRetired) return null;
        return _firstUseCandidate ? _firstUseInstallation?.EnterConfiguration() : _backgroundConfiguration.Enter(default);
    }
    private bool FirstUseBusinessUnavailable => _firstUseCandidate && _firstUseInstallation?.OwnsLiveGraph != true;

    // Original auth-only construction is immutable. This internal installation
    // owns new configuration/request admissions; it never reopens auth. Native
    // slot replacement and final mode commit must consume this same object.
    internal sealed partial class FirstUseBusinessInstallation : IBridgeRequestDispatcher
    {
        private readonly AccountBridgeRuntime _owner;
        private readonly PreparedFirstUseBusinessOwner _prepared;
        private readonly NativeAccountRuntimeBinding.PreparedNativeCallbacks _callbacks;
        private readonly Task _sources;
        private readonly ScmAccountBridgeHost.FirstUseBusinessAdmission _scm;
        private readonly AsyncWorkRetirement _configuration = new(), _requests = new();
        private readonly object _gate = new();
        private int _state, _configurationThread, _configurationTask; // dormant, configuring, configured, starting, live, closed
        private Task? _drained;
        private NativeAccountRuntimeBinding.InstalledNativeCallbacks? _native;

        internal FirstUseBusinessInstallation(PreparedFirstUseBusinessOwner prepared,
            NativeAccountRuntimeBinding.PreparedNativeCallbacks callbacks, Task sources,
            ScmAccountBridgeHost.FirstUseBusinessAdmission scm)
        {
            _owner = prepared.Owner; _prepared = prepared; _callbacks = callbacks; _sources = sources; _scm = scm;
            _owner.EventReady += ForwardEvent;
        }

        public event Action<BridgeEnvelope>? EventReady;
        private void ForwardEvent(BridgeEnvelope envelope)
        {
            if (!IsActive) return;
            using var work = _requests.Enter(default);
            if (work is null || !IsActive || envelope.SessionGeneration != _owner.Generation) return;
            EventReady?.Invoke(envelope);
        }

        internal AccountBridgeRuntime Owner => _owner;
        internal bool HasCompletedCandidateExit =>
            _owner._firstUseCandidateRetirement is { IsCompletedSuccessfully: true, Result: true };

        internal NativeAccountRuntimeBinding.InstalledNativeCallbacks? AttachNativeCallbacks(NativeAccountRuntimeBinding binding)
        {
            // Always installation -> binding, as in preparation/configuration.
            // No cancellation or user callback runs under either lock. Sealing
            // cannot miss a slot published here: its receipt is registered in
            // this same critical section before retirement captures it.
            lock (_gate)
            {
                if (!IsActive) return null;
                if (_native is not null) return _native.IsFor(binding) && _native.IsCurrent ? _native : null;
                return _native = binding.InstallCore(this, _callbacks, _prepared, _sources);
            }
        }
        // Retain only the original identity for withdrawal after business lanes
        // close. PublicationInput removes write authority in that state; this
        // never authorizes a business read, configuration or replacement login.
        internal bool HasOriginalPublicationOwner =>
            ReferenceEquals(Volatile.Read(ref _owner._firstUseInstallation), this) && !_owner._disposed && _scm.IsActive;
        private bool IsOriginal => ReferenceEquals(Volatile.Read(ref _owner._firstUseInstallation), this) &&
            !_owner._disposed && !_owner._localBusinessRetired;
        private bool PreparationCurrent => IsOriginal && _prepared.IsCurrent && _callbacks.Authorizes(_prepared, _sources);
        internal bool OwnsLiveGraph => Volatile.Read(ref _state) is 3 or 4 && IsOriginal && _scm.IsActive &&
            !_configuration.IsClosed && !_requests.IsClosed;
        internal bool IsActive => Volatile.Read(ref _state) == 4 && OwnsLiveGraph;
        private bool IsConfiguring => Volatile.Read(ref _state) == 1 &&
            Volatile.Read(ref _configurationThread) == Environment.CurrentManagedThreadId &&
            Volatile.Read(ref _configurationTask) == (Task.CurrentId ?? -1) && PreparationCurrent;

        internal AsyncWorkRetirement.Lease? EnterConfiguration()
        {
            if (!IsConfiguring) return null;
            var work = _configuration.Enter(default);
            if (work is not null && !IsConfiguring) { work.Dispose(); return null; }
            return work;
        }

        internal bool Configure(Action<AccountBridgeRuntime> configure)
        {
            ArgumentNullException.ThrowIfNull(configure);
            lock (_gate)
            {
                if (_state == 2) return PreparationCurrent;
                if (_state != 0 || !PreparationCurrent || _configuration.IsClosed) return false;
                _state = 1; _configurationThread = Environment.CurrentManagedThreadId;
                _configurationTask = Task.CurrentId ?? -1;
            }
            using var work = _configuration.Enter(default);
            try
            {
                if (work is null || !IsConfiguring) return false;
                // Synchronous Native composition only. A wait-inlined child
                // task shares the thread, not this original task identity.
                configure(_owner);
                lock (_gate)
                {
                    if (!work.IsCurrent || !IsConfiguring) return false;
                    _state = 2; return true;
                }
            }
            catch { _ = RetireAsync(); throw; }
            finally
            {
                Volatile.Write(ref _configurationThread, 0);
                if (Volatile.Read(ref _state) == 1) _ = RetireAsync();
            }
        }

        internal bool TryActivate()
        {
            using var work = _configuration.Enter(default);
            lock (_gate)
            {
                if (_state == 4) return IsActive;
                if (_state != 2 || work is null || !work.IsCurrent || !PreparationCurrent) return false;
                _state = 3;
            }
            try
            {
                if (!_scm.TryActivate() || !StartGraph(work)) { _ = RetireAsync(); return false; }
                lock (_gate)
                {
                    if (_state != 3 || !work.IsCurrent || !OwnsLiveGraph) return false;
                    _state = 4; return true;
                }
            }
            catch { _ = RetireAsync(); throw; }
            finally { if (Volatile.Read(ref _state) == 3) _ = RetireAsync(); }
        }

        private bool StartGraph(AsyncWorkRetirement.Lease work)
        {
            bool Current() => work.IsCurrent && OwnsLiveGraph;
            if (!Current() || !(_owner._gameLog?.StartDeferredSampling() ?? true) ||
                !Current() || !(_owner._gameplayTime?.StartDeferredSampling() ?? true) ||
                !Current() || !(_owner._achievements?.StartDeferredWork() ?? true) ||
                !Current() || !(_owner._privacyPublication?.StartDeferredWork() ?? true) ||
                !Current() || !(_owner._friendSharing?.StartDeferredWork() ?? true) ||
                !Current() || !(_owner._eventSharing?.StartDeferredWork() ?? true) ||
                !Current() || !(_owner._moduleCommunityDriverEnabled ? _owner._overlayCommunities?.StartDeferredWork() ?? true : true) ||
                !Current() || !(_owner._liveRoomRefresh?.StartDeferredWork() ?? true) ||
                !Current() || !(_owner._liveModuleCommunities?.StartDeferredWork() ?? true)) return false;
            if (!Current()) return false;
            _owner._activityReceiver?.Start();
            if (!Current()) return false;
            _owner._communityNotifications?.Start();
            if (Current()) _owner._scmAchievementUnlocks?.Wake();
            return Current();
        }

        internal Task SealAndDrainAsync()
        {
            TaskCompletionSource completion;
            NativeAccountRuntimeBinding.InstalledNativeCallbacks? native;
            lock (_gate)
            {
                if (_drained is not null) return _drained;
                _state = 5;
                completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _drained = completion.Task;
                native = _native;
            }
            _owner.EventReady -= ForwardEvent;
            _ = CompleteRetirementAsync(completion, () => native is null
                ? Task.WhenAll(_requests.Close(), _configuration.Close())
                : Task.WhenAll(_requests.Close(), _configuration.Close(), native.RetireAsync()));
            return completion.Task;
        }
        // Full candidate exit, not merely these two lane drains. It withdraws,
        // drains the graph and SCM loops. Retained installation failures never
        // convert offline credentials into a fresh-login sign-out obligation.
        internal Task<bool> RetireAsync() => _owner.RetainsFirstUseSession ? _owner.ShutdownFirstUseOnlineCandidateAsync() :
            _owner.RetireFirstUseOnlineCandidateAsync();
        public void Dispose() => _ = RetireAsync();

        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        {
            ArgumentNullException.ThrowIfNull(request);
            if (!IsActive || request.Name is AccountBridgeRequestNames.Login or AccountBridgeRequestNames.CancelLogin or
                AccountBridgeRequestNames.LoginLegacy or AccountBridgeRequestNames.Logout)
                return new(BridgeEnvelope.ErrorResponse(request, new BridgeError("firstUse.candidate_not_attached",
                    "Online business is not installed or this authentication lane has closed.")), []);
            AsyncWorkRetirement.Lease? admitted;
            try { admitted = _requests.Enter(token); }
            catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
            using var work = admitted;
            if (work is null || !IsActive) return new(BridgeEnvelope.CancelledResponse(request), []);
            var generation = _owner.Generation;
            try
            {
                var result = await _owner.DispatchCoreAsync(request, work.Token).ConfigureAwait(false);
                _owner.ObserveOfflineAccount(request, result.Response,
                    () => work.IsCurrent && IsActive && generation == _owner.Generation);
                return work.IsCurrent && IsActive && generation == _owner.Generation
                    ? result : new(BridgeEnvelope.CancelledResponse(request), []);
            }
            catch (OperationCanceledException) when (!work.IsCurrent || !IsActive)
            { return new(BridgeEnvelope.CancelledResponse(request), []); }
        }
    }
}
