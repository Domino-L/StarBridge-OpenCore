using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record LocalOwnerBinding(BridgeAccountContext Authentication, long Generation, BridgeAccountContext Storage, long CheckedAt);
    private LocalOwnerBinding? _localOwnerBinding;
    private BridgeAccountContext? _previousLocalOwnerAuthentication;
    private LocalOwnerBinding? _localOwnerTransportFailure;
    private readonly object _localOwnerGate = new();
    private long _localOwnerReadSequence;
    private long? _localOwnerOkAt;
    internal TimeProvider LocalDataOwnerClock { get; init; } = TimeProvider.System;

    /// <summary>Owner aliases written after a verified migration (account plan item 8).
    /// Null keeps the pre-0.7.3 behaviour: ownership needs a fresh relay confirmation.</summary>
    internal LocalOwnerAliasStore? LocalOwnerAliases { get; init; }
    private bool LocalOwnerFresh(LocalOwnerBinding binding, TimeSpan maximumAge)
    {
        var elapsed = LocalDataOwnerClock.GetElapsedTime(binding.CheckedAt);
        return elapsed >= TimeSpan.Zero && elapsed < maximumAge;
    }

    private void ObserveLocalDataOwnerFailure(BridgeAccountContext context, long generation, long sequence,
        Auth.ScmOAuthSession session)
    {
        lock (_localOwnerGate)
        {
            if (!_disposed && generation == Generation && context == CurrentContext &&
                sequence == _localOwnerReadSequence && ReferenceEquals(_session, session) &&
                _localOwnerBinding is { } binding && binding.Authentication == context && binding.Generation == generation)
                Volatile.Write(ref _localOwnerTransportFailure, binding);
        }
    }

    // A mutation fences off both earlier reads and reads started during its IO.
    private long InvalidateLocalDataOwnerReads()
    {
        lock (_localOwnerGate)
        {
            _localOwnerRead = null;
            return ++_localOwnerReadSequence;
        }
    }

    // Authentication stays SCM; only verified business file ownership is reused.
    public BridgeAccountContext ResolveLocalDataOwner(BridgeAccountContext authentication)
    {
        if (_disposed || authentication != CurrentContext || _reauthorizationRequired)
            throw new Privacy.LocalPrivacyException("privacy_local.account_changed");
        if (_credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
            throw new Privacy.LocalPrivacyOwnerUnavailableException();
        if (_session is null || _compatibilityReader is null)
            return ResolveTransitionOwner(authentication,
                Volatile.Read(ref _localOwnerBinding)?.Authentication == authentication ||
                Volatile.Read(ref _previousLocalOwnerAuthentication) == authentication,
                TryLocalOwnerAlias(authentication, out _));
        var binding = Volatile.Read(ref _localOwnerBinding);
        if (TryLocalOwnerAlias(authentication, out var aliased))
        {
            // After migration the owner is a local fact: no per-minute relay check.
            // A live answer naming a different legacy owner is never silently ignored.
            if (AliasConflicts(binding, authentication, aliased))
            {
                Support.IdentityGateJournal.Changed("owner-resolve", "code=alias-conflict");
                throw new Privacy.LocalPrivacyOwnerUnavailableException();
            }
            return aliased;
        }
        if (binding is null || binding.Authentication != authentication || binding.Generation != Generation ||
            !LocalOwnerFresh(binding, ReferenceEquals(binding, Volatile.Read(ref _localOwnerTransportFailure))
                ? TimeSpan.FromMinutes(30) : TimeSpan.FromMinutes(3)))
        {
            Support.IdentityGateJournal.Changed("owner-resolve", binding is null ? "code=no-binding" :
                binding.Authentication != authentication ? "code=other-authentication" :
                binding.Generation != Generation ? "code=other-generation" : "code=stale");
            throw new Privacy.LocalPrivacyOwnerUnavailableException();
        }
        return binding.Storage;
    }

    internal static BridgeAccountContext ResolveTransitionOwner(BridgeAccountContext authentication,
        bool hasBinding, bool hasAlias)
    {
        if (hasBinding || hasAlias) throw new Privacy.LocalPrivacyOwnerUnavailableException();
        return authentication;
    }

    // Playtime may retain this owner in memory, but cannot commit using a
    // transport grace binding. A fresh business answer re-enables its lease.
    internal BridgeAccountContext ResolveGameplayDataOwner(BridgeAccountContext authentication)
    {
        var owner = ResolveLocalDataOwner(authentication);
        var binding = Volatile.Read(ref _localOwnerBinding);
        if (binding is not null && binding.Authentication == authentication &&
            binding.Generation == Generation &&
            ReferenceEquals(binding, Volatile.Read(ref _localOwnerTransportFailure)))
            throw new Privacy.LocalPrivacyOwnerUnavailableException();
        return owner;
    }

    internal DateTimeOffset GameplayOwnerConfirmedAt(BridgeAccountContext authentication)
    {
        var binding = Volatile.Read(ref _localOwnerBinding);
        return binding is not null && binding.Authentication == authentication && binding.Generation == Generation &&
            !TryLocalOwnerAlias(authentication, out _)
            ? LocalDataOwnerClock.GetUtcNow() - LocalDataOwnerClock.GetElapsedTime(binding.CheckedAt)
            : LocalDataOwnerClock.GetUtcNow();
    }

    private bool ObserveLocalDataOwner(BridgeAccountContext context, long generation, long sequence,
        AccountBridgeCompatibilityProjection? result, Auth.ScmOAuthSession session)
    {
        BridgeAccountContext? storage = result?.IdentityState switch {
            "unlinked" => context,
            "linked" when result.LegacyFeaturesAvailable && result.RelayState == "ready" &&
                !string.IsNullOrWhiteSpace(result.LegacyAccountId) && _legacyPasswordLogin is not null =>
                new(_environment, _legacyPasswordLogin.AuthorityId, result.LegacyAccountId),
            // SCM's link and the relay's migration answer name the same legacy ID:
            // the same owner the "ready" branch above uses, byte for byte.
            "linked" when result.RelayState == "migrated" &&
                !string.IsNullOrWhiteSpace(result.LegacyAccountId) && _legacyPasswordLogin is not null =>
                new(_environment, _legacyPasswordLogin.AuthorityId, result.LegacyAccountId),
            _ => null
        };
        if (storage is null)
            Support.IdentityGateJournal.Changed("owner-observe",
                $"code=compat-not-ready identity={SafeIdentity(result?.IdentityState)} relay={SafeRelay(result?.RelayState)}");
        lock (_localOwnerGate)
        {
            if (_disposed || generation != Generation || context != CurrentContext || !ReferenceEquals(_session, session))
            {
                Support.IdentityGateJournal.Event("owner-observe", "code=stale");
                return false;
            }
            if (sequence != _localOwnerReadSequence)
            {
                Support.IdentityGateJournal.Event("owner-observe", "code=superseded-write");
                return false;
            }
            // Only a current observation records an alias; the write is one small file.
            // On a conflict the live owner is still bound, so ResolveLocalDataOwner
            // sees two different owners and pauses instead of choosing one.
            if (storage is not null && result?.RelayState == "migrated") RecordLocalOwnerAlias(context, storage);
            if (storage is not null) Volatile.Write(ref _previousLocalOwnerAuthentication, context);
            Volatile.Write(ref _localOwnerBinding, storage is null ? null : new(context, generation, storage, LocalDataOwnerClock.GetTimestamp()));
            if (storage is not null && (_localOwnerOkAt is null ||
                LocalDataOwnerClock.GetElapsedTime(_localOwnerOkAt.Value) >= TimeSpan.FromMinutes(10)))
            {
                _localOwnerOkAt = LocalDataOwnerClock.GetTimestamp();
                Support.IdentityGateJournal.Event("owner-observe", "code=ok");
            }
            return true;
        }
    }

    private bool AliasConflicts(LocalOwnerBinding? binding, BridgeAccountContext authentication, BridgeAccountContext aliased) =>
        binding is not null && binding.Authentication == authentication && binding.Generation == Generation &&
        binding.Storage != authentication && binding.Storage != aliased;

    /// <summary>
    /// For the migration result page (account plan item 9): "none", "written" or
    /// "conflict" for this SCM identity. No account ID leaves this method.
    /// "conflict" is exactly the case ResolveLocalDataOwner pauses on.
    /// </summary>
    internal string LocalDataOwnerAliasState(BridgeAccountContext authentication)
    {
        if (!TryLocalOwnerAlias(authentication, out var aliased)) return "none";
        return AliasConflicts(Volatile.Read(ref _localOwnerBinding), authentication, aliased) ? "conflict" : "written";
    }

    private bool TryLocalOwnerAlias(BridgeAccountContext authentication, out BridgeAccountContext target)
    {
        target = null!;
        return LocalOwnerAliases is { } aliases && aliases.TryGet(authentication, out target);
    }

    // False only when an alias for this SCM identity already names another owner.
    // A failed write keeps the verified binding; the next background round retries.
    private bool RecordLocalOwnerAlias(BridgeAccountContext authentication, BridgeAccountContext storage)
    {
        if (LocalOwnerAliases is not { } aliases) return true;
        var result = aliases.Record(authentication, storage);
        if (result is LocalOwnerAliasStore.RecordResult.Conflict)
        {
            Support.IdentityGateJournal.Changed("owner-observe", "code=alias-conflict");
            return false;
        }
        if (result is LocalOwnerAliasStore.RecordResult.Full or LocalOwnerAliasStore.RecordResult.Failed)
            Support.IdentityGateJournal.Event("owner-observe", $"code=alias-{result.ToString().ToLowerInvariant()}");
        return true;
    }

    private static string SafeIdentity(string? value) => value is "linked" or "unlinked" ? value : "unavailable";
    private static string SafeRelay(string? value) => value is "ready" or "migrated" or "notApplicable" or "notEstablished" or "unavailable" or "accountMismatch" or "authorizationRequired" ? value : "unavailable";

    private async Task EnsureLocalDataOwnerAsync(CancellationToken token, bool force = false)
    {
        if (_session is null || _compatibilityReader is null || CurrentContext is not { } context)
        {
            Support.IdentityGateJournal.Changed("owner-ensure", "code=no-session-or-reader");
            return;
        }
        var binding = Volatile.Read(ref _localOwnerBinding);
        if (!force && binding is not null && binding.Authentication == context && binding.Generation == Generation &&
            LocalOwnerFresh(binding, TimeSpan.FromMinutes(1))) return;
        try { await GetCompatibilityStateAsync(context, token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error)
        {
            // Transport failures preserve the last confirmed owner for at most
            // thirty minutes from confirmation. Without a failed attempt it
            // expires after three minutes; explicit answers replace it at once.
            Support.IdentityGateJournal.Event("owner-ensure", $"code=compat-unavailable exception={Support.IdentityGateJournal.Type(error)}");
        }
    }
}
