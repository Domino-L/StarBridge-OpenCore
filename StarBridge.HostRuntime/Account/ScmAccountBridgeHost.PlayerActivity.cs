using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Action<PlayerActivityObservation>? PlayerActivityObserved { get; set; }
    public Func<bool>? ShouldObservePlayerActivity { get; set; }
    private long _playerActivitySequence;
    private readonly object _playerActivityGate = new();
    private long _playerActivityGeneration = -1;
    private readonly Dictionary<string, long> _playerActivityLast = new();

    private bool ObservePlayerActivity()
    {
        try { return !_disposed && PlayerActivityObserved != null && ShouldObservePlayerActivity?.Invoke() == true; }
        catch { return false; }
    }

    private void PublishPlayerActivity(BridgeAccountContext context, long generation, long sequence,
        PlayerActivitySourceSnapshot? snapshot)
    {
        if (snapshot == null || !ObservePlayerActivity()) return;
        var scope = PlayerActivitySources.Opaque("scope", FriendScope(context, generation));
        bool Current()
        {
            if (_disposed || Generation != generation || _reauthorizationRequired || _credentialTemporarilyUnavailable || !ObservePlayerActivity()) return false;
            try { RequireRelaySession(context); return true; } catch { return false; }
        }
        if (!Current()) return;
        bool ObservationCurrent()
        {
            if (!Current()) return false;
            lock (_playerActivityGate)
                return _playerActivityGeneration == generation && _playerActivityLast.GetValueOrDefault(snapshot.Source) == sequence;
        }
        // A newer authoritative source also invalidates pending older delivery,
        // including membership removal or revoked event-sharing eligibility.
        try
        {
            PlayerActivityObservation observation;
            lock (_playerActivityGate)
            {
                if (_disposed || Generation != generation) return;
                if (_playerActivityGeneration != generation) { _playerActivityLast.Clear(); _playerActivityGeneration = generation; }
                if (_playerActivityLast.GetValueOrDefault(snapshot.Source) >= sequence) return;
                _playerActivityLast[snapshot.Source] = sequence;
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var verifiedHandle = OverlayLocalHandle();
                var members = snapshot.Members.Where(member => !string.IsNullOrWhiteSpace(member.AccountId) && seen.Add(member.AccountId))
                    .Select(member => new PlayerActivityObservedMember(PlayerActivitySources.Opaque(scope, "member:" + member.AccountId.ToLowerInvariant()),
                        member.Callsign, member.GameId, member.Presence,
                        string.Equals(member.AccountId, _legacySession?.AccountId, StringComparison.OrdinalIgnoreCase) ||
                            verifiedHandle.Length > 0 && string.Equals(member.GameId, verifiedHandle, StringComparison.OrdinalIgnoreCase),
                        member.AllowsPresenceEvents, member.AvatarImageData, member.PolicySources, member.Organizations)).ToArray();
                observation = new(generation, scope, snapshot.Source,
                    PlayerActivitySources.Opaque(scope, "source:" + snapshot.Source), sequence, snapshot.IsComplete, members, ObservationCurrent);
            }
            // Consumer preferences/notification locks must never run under this source lock.
            if (observation.IsCurrent()) PlayerActivityObserved?.Invoke(observation);
        }
        catch { /* Optional notification observers cannot break ordinary reads. */ }
    }
}
