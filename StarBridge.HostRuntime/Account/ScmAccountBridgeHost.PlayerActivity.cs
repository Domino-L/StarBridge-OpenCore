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
    private readonly Dictionary<string, long> _playerActivityContentVersion = new();
    private readonly Dictionary<string, PlayerActivityObservation> _playerActivityPublished = new();
    private readonly CancellationTokenSource _activityLifetime = new();
    private readonly object _backgroundActivityGate = new();
    private bool _backgroundActivityReading;
    private (BridgeAccountContext Context, long Generation, string Bearer)? _backgroundActivityPending;

    private void QueueBackgroundFriendActivity(BridgeAccountContext context, long generation, string bearer)
    {
        if (!ObservePlayerActivity() || _friends is null) return;
        lock (_backgroundActivityGate)
        {
            _backgroundActivityPending = (context, generation, bearer);
            if (_backgroundActivityReading) return;
            _backgroundActivityReading = true;
        }
        _ = ReadBackgroundFriendActivityAsync();
        async Task ReadBackgroundFriendActivityAsync()
        {
            while (true)
            {
                (BridgeAccountContext Context, long Generation, string Bearer) next;
                lock (_backgroundActivityGate)
                {
                    if (_backgroundActivityPending is not { } pending) { _backgroundActivityReading = false; return; }
                    next = pending;
                    _backgroundActivityPending = null;
                }
                try
                {
                    if (_disposed || next.Generation != Generation || !ObservePlayerActivity() ||
                        RequireRelaySession(next.Context).AccessToken != next.Bearer) continue;
                    var sequence = Interlocked.Increment(ref _playerActivitySequence);
                    // One active GET and at most one coalesced follow-up. A wake
                    // during a GET may represent state newer than its response.
                    // Neither read refreshes credentials or issues action targets.
                    var view = await _friends.ReadAsync(next.Bearer, null, _activityLifetime.Token,
                        FriendScope(next.Context, next.Generation), observePresence: true, issueTargets: false);
                    if (_disposed || next.Generation != Generation || !ObservePlayerActivity() ||
                        RequireRelaySession(next.Context).AccessToken != next.Bearer) continue;
                    PublishPlayerActivity(next.Context, next.Generation, sequence, PlayerActivitySources.Friends(view));
                }
                catch { /* Optional presence reads never fail or replay the social wait. */ }
            }
        }
    }

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
        long contentVersion = sequence;
        bool ObservationCurrent()
        {
            if (!Current()) return false;
            lock (_playerActivityGate)
                return _playerActivityGeneration == generation && _playerActivityContentVersion.GetValueOrDefault(snapshot.Source) == contentVersion;
        }
        // Changed authoritative content invalidates old delivery immediately.
        // An identical refresh must not create a revocation gap before the
        // consumer receives it: a native card timer may run in that gap.
        try
        {
            PlayerActivityObservation observation;
            lock (_playerActivityGate)
            {
                if (_disposed || Generation != generation) return;
                if (_playerActivityGeneration != generation) {
                    _playerActivityLast.Clear(); _playerActivityContentVersion.Clear(); _playerActivityPublished.Clear();
                    _playerActivityGeneration = generation;
                }
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
                if (_playerActivityPublished.TryGetValue(snapshot.Source, out var prior) &&
                    prior.Scope == scope && prior.IsComplete == snapshot.IsComplete && SameActivityMembers(prior.Members, members))
                    contentVersion = _playerActivityContentVersion[snapshot.Source];
                _playerActivityContentVersion[snapshot.Source] = contentVersion;
                observation = new(generation, scope, snapshot.Source,
                    PlayerActivitySources.Opaque(scope, "source:" + snapshot.Source), sequence, snapshot.IsComplete, members, ObservationCurrent);
                _playerActivityPublished[snapshot.Source] = observation;
            }
            // Consumer preferences/notification locks must never run under this source lock.
            if (observation.IsCurrent()) PlayerActivityObserved?.Invoke(observation);
        }
        catch { /* Optional notification observers cannot break ordinary reads. */ }
    }

    private static bool SameActivityMembers(PlayerActivityObservedMember[] left, PlayerActivityObservedMember[] right)
    {
        if (left.Length != right.Length) return false;
        return left.OrderBy(m => m.MemberKey, StringComparer.Ordinal)
            .Zip(right.OrderBy(m => m.MemberKey, StringComparer.Ordinal)).All(pair => {
                var (a, b) = pair;
                return a.MemberKey == b.MemberKey && a.Callsign == b.Callsign && a.GameId == b.GameId &&
                    a.Presence == b.Presence && a.IsSelf == b.IsSelf && a.AllowsPresenceEvents == b.AllowsPresenceEvents &&
                    a.AvatarImageData == b.AvatarImageData &&
                    (a.PolicySources ?? []).Order(StringComparer.Ordinal).SequenceEqual((b.PolicySources ?? []).Order(StringComparer.Ordinal)) &&
                    (a.Organizations ?? []).OrderBy(o => o.PolicySource, StringComparer.Ordinal).ThenBy(o => o.Name, StringComparer.Ordinal)
                        .SequenceEqual((b.Organizations ?? []).OrderBy(o => o.PolicySource, StringComparer.Ordinal).ThenBy(o => o.Name, StringComparer.Ordinal));
            });
    }
}
