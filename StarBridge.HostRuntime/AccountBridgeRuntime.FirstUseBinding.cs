using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private Func<bool>? _firstUseGameIdentityReady;
    internal bool HasColdFirstUseAccount => !_disposed && !_firstUseCandidate &&
        _host is ScmAccountBridgeHost && _host.CurrentContext is not null && !_requestRetirement.IsClosed;
    internal FirstUseScmIdentityFacts? CurrentColdFirstUseFacts() => HasColdFirstUseAccount && _host is ScmAccountBridgeHost scm
        ? scm.CurrentInstalledFirstUseFacts() : null;
    internal bool IsRestoredColdFirstUseSession(FirstUseScmIdentityFacts facts) =>
        HasColdFirstUseAccount && _host is ScmAccountBridgeHost scm && scm.IsRestoredFirstUseSession(facts);
    private void RequireColdFirstUseGameIdentity(Func<bool> ready)
    {
        _firstUseGameIdentityReady ??= ready;
        if (_host is ScmAccountBridgeHost scm) scm.RequireColdFirstUseGameIdentity(_firstUseGameIdentityReady);
    }

    internal void RequireFirstUseGameIdentity(Func<bool> ready)
    {
        if (!_firstUseCandidate || _host is not ScmAccountBridgeHost scm || _firstUseInstallation is not null)
            throw new InvalidOperationException("Identity admission must be attached before installation.");
        _firstUseGameIdentityReady ??= ready;
        scm.RequireFirstUseGameIdentity(_firstUseGameIdentityReady);
    }

    private bool FirstUseGameIdentityReady
    {
        get { try { return _firstUseGameIdentityReady?.Invoke() ?? true; } catch { return false; } }
    }

    private (StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation) GameplayRecordingOwner()
    {
        // Which gate leaves playtime without an owner (build 71 showed "identity not
        // confirmed" silently). Only a first-use candidate still loses its owner to
        // the guide's review; an installed session keeps its owner, so the saved
        // settings stay readable, and recording waits on GameRecordingIdentityReady.
        if (_firstUseCandidate && !FirstUseGameIdentityReady)
        {
            NoteGameplayOwner("code=none reason=game-identity-not-ready");
            return (null, _host.Generation);
        }
        var owner = GameplayOwner();
        NoteGameplayOwner(owner.Context is null
            ? "code=none reason=" + (FirstUseBusinessUnavailable ? "first-use-business" : _disposed ? "disposed" : "account-state")
            : "code=ok");
        return owner;
    }

    // Whether playtime and log events may be recorded. A first-use candidate keeps
    // the guide's own review. An installed session uses the identity the account
    // page shows: the verified Handle (SCM or old account) matches the Handle the
    // game log reports. The guide's local identity and completion receipt no
    // longer decide this; before the guide arrived (10-21) neither did.
    private bool GameRecordingIdentityReady
    {
        get
        {
            if (_firstUseCandidate || _firstUseGameIdentityReady is null) return FirstUseGameIdentityReady;
            var state = GameRecordingIdentityState();
            NoteGameRecordingIdentity(state);
            return state == "match";
        }
    }

    // Reason code only; never a Handle or an account.
    private string GameRecordingIdentityState()
    {
        try
        {
            var owner = GameplayOwner();
            if (owner.Context is null) return "no-owner";
            if (_host.ReadCurrentGameIdentityPolicy(owner.Context) is not { } policy) return "no-policy";
            if (policy.State != "match" || !policy.SensitiveWritesAllowed) return "account-" + policy.State;
            var check = GameLogIdentityCheckForTests is { } probe ? probe() : _gameLog?.IdentityPolicyState;
            return check switch
            {
                StarBridge.Core.Identity.LocalIdentityCheckState.Match => "match",
                StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch => "log-mismatch",
                null => "no-log",
                _ => "log-not-observed"
            };
        }
        catch { return "unavailable"; }
    }

    private Presence.GameplayContinuity GameplayOwnerContinuity()
    {
        var generation = _host.Generation;
        var authentication = _host.CurrentContext;
        if (_disposed || FirstUseBusinessUnavailable || authentication is null)
            return new(null, generation, false, "identity");
        var available = false;
        DateTimeOffset? confirmedAt = null;
        try
        {
            if (GameplayRecordingOwner().Context is not null)
            {
                if (_host is ScmAccountBridgeHost scm)
                {
                    scm.ResolveGameplayDataOwner(authentication);
                    confirmedAt = scm.GameplayOwnerConfirmedAt(authentication);
                }
                else _host.ResolveLocalDataOwner(authentication);
                available = true;
            }
        }
        catch (Exception error) when (error is Privacy.LocalPrivacyOwnerUnavailableException or IOException or
            TimeoutException or System.Net.Http.HttpRequestException or OperationCanceledException) { }
        catch { return new(authentication, generation, false, "identity"); }
        var identity = "identity";
        try
        {
            if (_firstUseCandidate || _firstUseGameIdentityReady is null)
                identity = FirstUseGameIdentityReady ? "match" : "identity";
            else
            {
                var policy = _host.ReadCurrentGameIdentityPolicy(authentication);
                if (policy is null && !available) identity = "not-observed";
                else if (policy is { State: "match", SensitiveWritesAllowed: true }) identity = "match";
            }
        }
        catch { identity = "not-observed"; }
        return generation == _host.Generation && authentication == _host.CurrentContext
            ? new(authentication, generation, available, identity, confirmedAt)
            : new(null, _host.Generation, false, "identity");
    }

    private Presence.GameplayContinuity GameplayContinuityState()
    {
        var state = GameplayOwnerContinuity();
        if (state.Identity == "identity" || _firstUseCandidate || _firstUseGameIdentityReady is null)
            return state with { IdentityRejectionVersion = _gameLog?.IdentityRejectionVersion ?? 0 };
        var check = GameLogIdentityCheckForTests is { } probe ? probe() : _gameLog?.IdentityPolicyState;
        return state with { IdentityRejectionVersion = _gameLog?.IdentityRejectionVersion ?? 0, Identity = check switch {
            StarBridge.Core.Identity.LocalIdentityCheckState.Match => state.Identity,
            StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch => "identity",
            _ => "not-observed"
        } };
    }

    // Test seam: the game log's published identity check without a real Game.log.
    internal Func<StarBridge.Core.Identity.LocalIdentityCheckState?>? GameLogIdentityCheckForTests { private get; set; }

    private readonly Presence.GameplayFailureJournal _gameRecordingJournal = new();
    private void NoteGameRecordingIdentity(string state) =>
        _gameRecordingJournal.RecordChange("game-recording-identity", "code=" + state);

    // Only a change of state counts, so the per-sample call stays quiet; a gate that
    // keeps flipping back to the same reason is written in full once per run, then
    // only as a count (CX-GAMEPLAY-DIAG-073-R #2).
    private readonly Presence.GameplayFailureJournal _gameplayOwnerJournal = new();

    private void NoteGameplayOwner(string state) => _gameplayOwnerJournal.RecordChange("gameplay-owner", state);

    internal bool InstalledFirstUseIdentityCurrent(FirstUseScmIdentityFacts facts) =>
        (_firstUseInstallation is { IsActive: true } || HasColdFirstUseAccount) && _host is ScmAccountBridgeHost scm &&
        scm.InstalledFirstUseIdentityCurrent(facts);

    internal async Task<FirstUseScmIdentityRead> ReadInstalledFirstUseIdentityAsync(CancellationToken token)
    {
        if (_firstUseInstallation is { } installed) return await installed.ReadIdentityAsync(token).ConfigureAwait(false);
        if (!HasColdFirstUseAccount || _host is not ScmAccountBridgeHost scm) return new("contextChanged");
        using var work = _requestRetirement.Enter(token);
        if (work is null) return new("contextChanged");
        var result = await scm.ReadFirstUseIdentityAsync(work.Token).ConfigureAwait(false);
        return work.IsCurrent && HasColdFirstUseAccount ? result : new("contextChanged");
    }

    internal sealed partial class FirstUseBusinessInstallation
    {
        internal async Task<FirstUseScmIdentityRead> ReadIdentityAsync(CancellationToken token)
        {
            if (!IsActive || _owner._host is not ScmAccountBridgeHost scm) return new("contextChanged");
            using var work = _requests.Enter(token);
            if (work is null || !IsActive) return new("contextChanged");
            var generation = _owner.Generation;
            var result = await scm.ReadFirstUseIdentityAsync(work.Token).ConfigureAwait(false);
            return work.IsCurrent && IsActive && generation == _owner.Generation ? result : new("contextChanged");
        }
    }
}
