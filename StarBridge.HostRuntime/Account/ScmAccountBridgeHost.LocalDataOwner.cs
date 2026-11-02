using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record LocalOwnerBinding(BridgeAccountContext Authentication, long Generation, BridgeAccountContext Storage, long CheckedAt);
    private LocalOwnerBinding? _localOwnerBinding;
    private readonly object _localOwnerGate = new();
    private long _localOwnerReadSequence;
    internal TimeProvider LocalDataOwnerClock { get; init; } = TimeProvider.System;
    private bool LocalOwnerFresh(LocalOwnerBinding binding, TimeSpan maximumAge)
    {
        var elapsed = LocalDataOwnerClock.GetElapsedTime(binding.CheckedAt);
        return elapsed >= TimeSpan.Zero && elapsed < maximumAge;
    }

    private long BeginLocalDataOwnerRead()
    {
        lock (_localOwnerGate) return ++_localOwnerReadSequence;
    }

    // Authentication stays SCM; only verified business file ownership is reused.
    public BridgeAccountContext ResolveLocalDataOwner(BridgeAccountContext authentication)
    {
        if (_disposed || authentication != CurrentContext || _reauthorizationRequired ||
            _credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
            throw new Privacy.LocalPrivacyException("privacy_local.account_changed");
        if (_session is null || _compatibilityReader is null) return authentication;
        var binding = Volatile.Read(ref _localOwnerBinding);
        if (binding is null || binding.Authentication != authentication || binding.Generation != Generation ||
            !LocalOwnerFresh(binding, TimeSpan.FromMinutes(3)))
            throw new Privacy.LocalPrivacyOwnerUnavailableException();
        return binding.Storage;
    }

    private bool ObserveLocalDataOwner(BridgeAccountContext context, long generation, long sequence,
        AccountBridgeCompatibilityProjection? result)
    {
        BridgeAccountContext? storage = result?.IdentityState switch {
            "unlinked" => context,
            "linked" when result.LegacyFeaturesAvailable && result.RelayState == "ready" &&
                !string.IsNullOrWhiteSpace(result.LegacyAccountId) && _legacyPasswordLogin is not null =>
                new(_environment, _legacyPasswordLogin.AuthorityId, result.LegacyAccountId),
            _ => null
        };
        lock (_localOwnerGate)
        {
            if (_disposed || generation != Generation || context != CurrentContext || sequence != _localOwnerReadSequence)
                return false;
            Volatile.Write(ref _localOwnerBinding, storage is null ? null : new(context, generation, storage, LocalDataOwnerClock.GetTimestamp()));
            return true;
        }
    }

    private async Task EnsureLocalDataOwnerAsync(CancellationToken token)
    {
        if (_session is null || _compatibilityReader is null || CurrentContext is not { } context) return;
        var binding = Volatile.Read(ref _localOwnerBinding);
        if (binding is not null && binding.Authentication == context && binding.Generation == Generation &&
            LocalOwnerFresh(binding, TimeSpan.FromMinutes(1))) return;
        try { await GetCompatibilityStateAsync(context, token).ConfigureAwait(false); }
        catch (AccountBridgeHostException) { /* Authentication survives; business reads stay closed. */ }
    }
}
