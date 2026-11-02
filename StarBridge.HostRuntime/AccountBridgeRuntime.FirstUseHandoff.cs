using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal bool FirstUseAuthenticationSealed => _firstUseCandidate && _requestRetirement.IsClosed;

    // The actual candidate's authentication admission is one-way. This is not
    // online activation: an installed business admission and graph must be owned
    // separately, never obtained by reopening this sealed lane.
    internal Task<PreparedFirstUseOnlineCandidate?> PrepareFirstUseOnlineHandoffAsync(
        FirstUseOnlineCandidateIntent intent, FirstUseScmIdentityFacts facts, Func<bool> current,
        CancellationToken token) => PreparedFirstUseOnlineCandidate.PrepareAsync(this, intent, facts, current, token);

    // Native-private live ownership, not a persisted permission, bridge payload
    // or completion receipt. Only this original drain operation can create it.
    internal sealed partial class PreparedFirstUseOnlineCandidate
    {
        private readonly AccountBridgeRuntime _owner;
        private readonly FirstUseOnlineCandidateIntent _intent;
        private readonly FirstUseScmIdentityFacts _facts;
        private readonly Func<bool> _current;
        private readonly Task _drained;
        private PreparedFirstUseOnlineCandidate(AccountBridgeRuntime owner, FirstUseOnlineCandidateIntent intent,
            FirstUseScmIdentityFacts facts, Func<bool> current, Task drained)
        { _owner = owner; _intent = intent; _facts = facts; _current = current; _drained = drained; }

        internal static async Task<PreparedFirstUseOnlineCandidate?> PrepareAsync(AccountBridgeRuntime owner,
            FirstUseOnlineCandidateIntent intent, FirstUseScmIdentityFacts facts, Func<bool> current, CancellationToken token)
        {
            ArgumentNullException.ThrowIfNull(current);
            token.ThrowIfCancellationRequested();
            if (!current() || !owner.IsFirstUseIdentityCurrent(intent, facts) ||
                owner._host is not ScmAccountBridgeHost scm) return null;
            var drained = owner._requestRetirement.Close();
            await scm.CancelLoginAsync().ConfigureAwait(false);
            await drained.WaitAsync(token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            var prepared = new PreparedFirstUseOnlineCandidate(owner, intent, facts, current, drained);
            return prepared.IsCurrent ? prepared : null;
        }

        internal bool IsCurrent => _drained.IsCompletedSuccessfully && _owner.FirstUseAuthenticationSealed &&
            !_owner._disposed && !_owner._localBusinessRetired && _current() &&
            _owner.IsFirstUseOnlineCandidateFor(_intent) &&
            _owner._host is ScmAccountBridgeHost scm && scm.IsFirstUseIdentityCurrent(_facts);
        internal AccountBridgeRuntime Owner => _owner;
    }
}
