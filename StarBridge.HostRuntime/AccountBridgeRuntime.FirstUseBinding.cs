using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private Func<bool>? _firstUseGameIdentityReady;
    internal bool HasColdFirstUseAccount => !_disposed && !_firstUseCandidate &&
        _host is ScmAccountBridgeHost && _host.CurrentContext is not null && !_requestRetirement.IsClosed;
    internal FirstUseScmIdentityFacts? CurrentColdFirstUseFacts() => HasColdFirstUseAccount && _host is ScmAccountBridgeHost scm
        ? scm.CurrentInstalledFirstUseFacts() : null;
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

    private (StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation) GameplayRecordingOwner() =>
        FirstUseGameIdentityReady ? GameplayOwner() : (null, _host.Generation);

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
