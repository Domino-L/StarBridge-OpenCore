using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Native-private ownership read through the existing S2 coordinator. It does
    // not link/provision an account, move files, start loops or enable publishing.
    internal sealed class FirstUseBusinessOwnerFacts
    {
        private readonly ScmAccountBridgeHost _owner;
        private readonly FirstUseScmIdentityFacts _identity;
        private readonly LocalOwnerBinding? _binding;
        private FirstUseBusinessOwnerFacts(ScmAccountBridgeHost owner, FirstUseScmIdentityFacts identity,
            BridgeAccountContext storage, LocalOwnerBinding? binding)
        { _owner = owner; _identity = identity; StorageOwner = storage; _binding = binding; }

        internal BridgeAccountContext StorageOwner { get; }
        internal long Generation => _identity.Generation;
        // After activation, pending-review expiry is not an account lifetime.
        // Ordinary same-subject refresh and equivalent storage reconfirmation
        // remain valid, but identity, generation or storage replacement does not.
        internal bool IsInstalledOwnerCurrent
        {
            get
            {
                if (_owner._disposed || _owner._localModeSessionLoopsStopped ||
                    _owner._reauthorizationRequired || _owner._credentialTemporarilyUnavailable ||
                    _owner._legacySession is not null || _owner._session is not { } session ||
                    _owner.Generation != _identity.Generation || _owner.CurrentContext != _identity.Context) return false;
                if (_owner._oauth.ReadInstalledFirstUseSessionOrRefresh(_identity.Session, session) is null) return false;
                // Ownership reads may run inside another lane's refresh. Verify
                // its exact lineage without replacing that lane's Host snapshot.
                // Session adoption belongs to the mutation owner, not a getter.
                if (_owner._compatibilityReader is null) return StorageOwner == _identity.Context;
                var binding = Volatile.Read(ref _owner._localOwnerBinding);
                return binding is not null && binding.Authentication == _identity.Context &&
                    binding.Generation == _identity.Generation && binding.Storage == StorageOwner;
            }
        }
        internal FirstUseBusinessAdmission? StageAdmission(Func<bool> current) =>
            FirstUseBusinessAdmission.Stage(_owner, this, current);
        internal bool IsCurrent
        {
            get
            {
                if (!_owner.IsFirstUseIdentityCurrent(_identity)) return false;
                if (_owner._compatibilityReader is null)
                    return _binding is null && StorageOwner == _identity.Context;
                var binding = Volatile.Read(ref _owner._localOwnerBinding);
                return ReferenceEquals(binding, _binding) && binding is not null &&
                    binding.Authentication == _identity.Context && binding.Generation == _identity.Generation &&
                    binding.Storage == StorageOwner && _owner.LocalOwnerFresh(binding, TimeSpan.FromMinutes(3));
            }
        }

        internal static async Task<FirstUseBusinessOwnerFacts?> ReadAsync(ScmAccountBridgeHost owner,
            FirstUseScmIdentityFacts identity, CancellationToken token)
        {
            if (!await owner._mutationGate.WaitAsync(0, token).ConfigureAwait(false)) return null;
            try
            {
                if (!owner.IsFirstUseIdentityCurrent(identity)) return null;
                if (owner._compatibilityReader is not null)
                    await owner.GetCompatibilityStateAsync(identity.Context, token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                if (!owner.IsFirstUseIdentityCurrent(identity)) return null;
                var storage = owner.ResolveLocalDataOwner(identity.Context);
                var facts = new FirstUseBusinessOwnerFacts(owner, identity, storage,
                    Volatile.Read(ref owner._localOwnerBinding));
                return facts.IsCurrent ? facts : null;
            }
            catch (Exception error) when (error is AccountBridgeHostException or
                Privacy.LocalPrivacyException or HttpRequestException or IOException or
                System.Text.Json.JsonException or InvalidOperationException)
            { return null; }
            finally { if (!owner._disposed) owner._mutationGate.Release(); }
        }
    }

    // Called only after the common mutation gate has acquired its exclusive
    // lease. Resource failure/cancellation may leave OAuth ahead of Host; the
    // next mutation or direct-send snapshot recovers without a resource retry.
    private void RecoverInstalledFirstUseRefresh()
    {
        var installed = _firstUseBusinessAdmission is { IsActive: true } ||
            !IsFirstUseAuthenticationCandidate && _firstUseGameIdentityReady is not null;
        if (!installed || Volatile.Read(ref _session) is not { } original ||
            _oauth.IsInstalledFirstUseSessionCurrent(original)) return;
        var generation = Generation; var context = ToContext(original);
        if (_oauth.ReadInstalledFirstUseRefreshSuccessor(original) is { } successor)
            AdoptInstalledFirstUseRefresh(original, successor, generation, context);
    }

    private bool AdoptInstalledFirstUseRefresh(Auth.ScmOAuthSession original, Auth.ScmOAuthSession successor,
        long generation, BridgeAccountContext context)
    {
        if (_disposed || _localModeSessionLoopsStopped || _reauthorizationRequired || _credentialTemporarilyUnavailable ||
            _legacySession is not null || Generation != generation || CurrentContext != context ||
            original.AuthoritativeGameIdentity != successor.AuthoritativeGameIdentity ||
            _oauth.ReadInstalledFirstUseRefreshSuccessor(original) is not { } actual || actual != successor) return false;
        // Exact old Host version and actual OAuth/vault successor, never expiry
        // ordering or a same-account replacement credential.
        Interlocked.CompareExchange(ref _session, successor, original);
        return Generation == generation && CurrentContext == context && _session is { } installed &&
            _oauth.IsInstalledFirstUseSessionCurrent(installed);
    }
}
