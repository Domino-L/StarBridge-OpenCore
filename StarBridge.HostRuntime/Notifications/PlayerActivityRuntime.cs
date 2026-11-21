using System.Diagnostics;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Notifications.Wpf;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed record PlayerActivityEnvironment(bool Known, bool AppBackground, bool GameRunning, bool OverlayRunning);

/// Reuses WPF's pure transition policy and the existing desktop sink. A bounded
/// local retry covers transiently unknown native environment state; it does not
/// poll the server or create a new account session, activation or unread state.
public sealed class PlayerActivityRuntime : IBridgeRequestDispatcher
{
    private static readonly TimeSpan UnknownEnvironmentGrace = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan UnknownEnvironmentRetry = TimeSpan.FromMilliseconds(250);
    private sealed record DeferredActivity(DesktopNotification Notice, long Since);
    internal static TimeSpan OfflineSettle { get; set; } = TimeSpan.FromSeconds(20);
    private sealed record PendingOffline(DesktopNotification Notice, PlayerActivityMemberState? Before,
        long Since, TimeSpan Settle, Func<bool> Valid);
    private readonly Dictionary<string, PendingOffline> _offline = new(StringComparer.Ordinal);
    private readonly Dictionary<string, PendingOffline> _returning = new(StringComparer.Ordinal);
    private readonly Dictionary<string, PlayerActivityMemberState> _lastMembers = new(StringComparer.Ordinal);
    private CancellationTokenSource? _offlineRetry;
    internal Task OfflineSettleWork { get; private set; } = Task.CompletedTask;
    private long? _observedGeneration;
    private readonly object _gate = new();
    private readonly PlayerActivityPreferencesStore _store;
    private readonly PlayerActivityPreferencesBridge _preferences;
    private readonly ApplicationPreferencesStore _appearance;
    private readonly Func<long> _generation;
    private readonly Func<PlayerActivityEnvironment> _environment;
    private readonly Func<long> _timestamp;
    private readonly TimeProvider _time;
    private readonly IDesktopNotificationSink? _sink;
    private readonly NotificationDeliveryJournal _delivery;
    private readonly NotificationPolicyStore _policies;
    private Func<BridgeAccountContext?>? _policyOwner;
    private long _policyRevision = -1;
    public void ConfigurePolicyOwner(Func<BridgeAccountContext?> owner) { lock (_gate) { _policyOwner = owner; ResetLocked(); } }
    private readonly Dictionary<string, PlayerActivityObservation> _sources = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DeferredActivity> _deferred = new(StringComparer.Ordinal);
    private PlayerActivityNotificationTracker _tracker = new();
    private string? _scope, _revision;
    private long _epoch, _lastTest;
    private long? _unknownEnvironmentAt;
    private CancellationTokenSource? _unknownRetry;
    private readonly Lifecycle.AsyncWorkRetirement _accountRetirement = new();
    private volatile bool _accountRetired;
    private volatile bool _disposed;
    public static IReadOnlyList<string> Capabilities { get; } = ["playerActivity.read", "playerActivity.save", "playerActivity.test"];
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public PlayerActivityRuntime(string root, Func<long> generation, IDesktopNotificationSink? sink,
        Func<PlayerActivityEnvironment> environment, Func<long>? timestamp = null, TimeProvider? time = null)
    {
        _store = new(root); _policies = new(root); _appearance = new(root); _generation = generation; _sink = sink; _environment = environment;
        _timestamp = timestamp ?? Stopwatch.GetTimestamp;
        _time = time ?? TimeProvider.System;
        _delivery = new(root);
        _preferences = new(_store, generation, () => !_disposed && _sink is not null);
    }
    public bool ShouldObserve()
    {
        try {
            lock (_gate) {
                var saved = _store.Read();
                if (_revision is not null && (_revision != saved.Revision || _observedGeneration != _generation())) ResetLocked();
                return !_disposed && !_accountRetired && _sink is not null && saved.Value.Enabled && !saved.DoNotDisturb;
            }
        }
        catch { return false; }
    }
    public void Observe(PlayerActivityObservation observation) => _ = ObserveAsync(observation);
    internal async Task ObserveAsync(PlayerActivityObservation observation)
    {
        using var work = _accountRetirement.Enter(default);
        if (work is null) return;
        try
        {
            List<DesktopNotification> output = [];
            NotificationDeliveryStage? observationStage = null;
            lock (_gate)
            {
                if (_disposed || _accountRetired || observation.Generation != _generation() || !observation.IsCurrent()) return;
                if (observation.Source is not ("friends" or "organization" or "room") ||
                    observation.Members.Length > 10000 || !observation.IsComplete) return;
                var saved = _store.Read();
                if (_scope != observation.Scope || _revision != saved.Revision || _observedGeneration != observation.Generation)
                { ResetLocked(); _scope = observation.Scope; _revision = saved.Revision; _observedGeneration = observation.Generation; }
                var policyRevision = Policies()?.Revision ?? -1;
                if (_policyRevision != policyRevision) { _tracker = new(); _epoch++; _held.Clear(); ClearOfflineLocked(); _policyRevision = policyRevision; _unknownEnvironmentAt = null; }
                if (_sources.TryGetValue(observation.SourceKey, out var previous) && previous.Sequence >= observation.Sequence) return;
                var firstSource = previous is null;
                var sourceChanged = firstSource || !SameObservedPresence(previous!.Members, observation.Members);
                _sources[observation.SourceKey] = observation;
                ReconcileOfflineLocked(saved.Value.Scope);
                var env = _environment();
                if (!env.Known)
                {
                    _unknownEnvironmentAt ??= _timestamp();
                    if (sourceChanged) observationStage = NotificationDeliveryStage.EnvironmentSuppressed;
                    EnsureUnknownRetryLocked();
                }
                else
                {
                    _unknownRetry?.Cancel();
                    _unknownRetry = null;
                    (output, observationStage) = EvaluateKnownLocked(observation, saved, env, sourceChanged, firstSource);
                    if (_unknownEnvironmentAt is not null) EnsureUnknownRetryLocked();
                }
            }
            await DeliverAsync(output, observationStage, work.Token).ConfigureAwait(false);
        }
        catch {
            // An unreadable policy cannot leave transition history that would
            // replay suppressed activity after storage becomes available again.
            lock (_gate) ResetLocked();
        }
    }
    private (List<DesktopNotification> Output, NotificationDeliveryStage? Stage) EvaluateKnownLocked(
        PlayerActivityObservation observation, PlayerActivityPreferencesSnapshot saved,
        PlayerActivityEnvironment env, bool sourceChanged, bool firstSource)
    {
        var output = new List<DesktopNotification>();
        NotificationDeliveryStage? stage = null;
        var members = Members(saved.Value.Scope);
        var settings = new NotificationSettings(
            EnablePlayerActivityNotifications: saved.Value.Enabled && !saved.DoNotDisturb,
            PlayerActivityScope: (PlayerActivityNotificationScope)saved.Value.Scope,
            NotifyPlayerOnline: saved.Value.Online, NotifyPlayerOffline: saved.Value.Offline,
            NotifyPlayerStartedGame: saved.Value.StartedGame, NotifyPlayerStoppedGame: saved.Value.StoppedGame,
            PlayerActivityBackgroundOnly: saved.Value.BackgroundOnly,
            ReducePlayerActivityNotificationsInGame: saved.Value.ReduceInGame,
            // State edges are already deduplicated. A shared message-cue cooldown
            // must not swallow a new offline/online/game transition.
            NotificationCooldownSeconds: 0);
        var staleUnknown = _unknownEnvironmentAt is { } started &&
            Stopwatch.GetElapsedTime(started, _timestamp()) > UnknownEnvironmentGrace;
        _unknownEnvironmentAt = null;
        var returns = new List<(PlayerActivityMemberState Before, PlayerActivityMemberState After)>();
        ReconcileOfflineLocked(saved.Value.Scope);
        foreach (var (key, pending) in _returning)
        {
            var member = members.FirstOrDefault(m => m.Key == key);
            if (member is not null && pending.Valid())
                returns.Add((pending.Before!, member));
        }
        _returning.Clear();
        var events = _tracker.Evaluate(members, settings,
            new(env.AppBackground, env.GameRunning, env.OverlayRunning), DateTimeOffset.UtcNow,
            establishBaselineOnly: staleUnknown).ToList();
        // Treat a brief disconnection as continuous presence. Reuse the policy
        // for genuine game changes (including its silent Away transitions).
        foreach (var (before, after) in returns)
        {
            events.RemoveAll(activity => activity.MemberKey == after.Key);
            var continuity = new PlayerActivityNotificationTracker();
            var context = new PlayerActivityNotificationContext(env.AppBackground, env.GameRunning, env.OverlayRunning);
            continuity.Evaluate([before], settings, context, DateTimeOffset.UtcNow, establishBaselineOnly: true);
            events.AddRange(continuity.Evaluate([after], settings, context, DateTimeOffset.UtcNow, establishBaselineOnly: staleUnknown));
        }
        if (events.Count == 0 && sourceChanged)
            stage = firstSource || staleUnknown
                ? NotificationDeliveryStage.BaselineEstablished : NotificationDeliveryStage.NoFreshEvent;
        var offlineSince = _timestamp();
        foreach (var activity in events)
        {
            var epoch = _epoch;
            var revision = saved.Revision;
            var expected = members.Single(m => m.Key == activity.MemberKey).Presence;
            var sources = SourceLabels(activity.MemberKey, saved.Value.Scope);
            var organizationLease = OrganizationLease(activity.MemberKey, saved.Value.Scope);
            var policyRevision = _policyRevision;
            var owner = _policyOwner?.Invoke();
            bool Valid() => !_disposed && !_accountRetired && epoch == _epoch && observation.Generation == _generation() &&
                Equals(_policyOwner?.Invoke(), owner) && organizationLease() && (Policies()?.Revision ?? -1) == policyRevision &&
                _store.Read().Revision == revision && ShouldObserve() &&
                SourceLabels(activity.MemberKey, saved.Value.Scope).SequenceEqual(sources);
            bool Current()
            {
                lock (_gate)
                {
                    if (_disposed || epoch != _epoch || observation.Generation != _generation()) return false;
                    try { return Valid() && EnvironmentAllows(saved.Value) &&
                        Members(saved.Value.Scope).Any(m => m.Key == activity.MemberKey && m.Presence == expected) &&
                        SourceLabels(activity.MemberKey, saved.Value.Scope).SequenceEqual(sources); }
                    catch { return false; }
                }
            }
            var notice = Create(activity, saved.Value, false, Current, sources);
            if (activity.Kind == PlayerActivityNotificationKind.Offline)
            {
                // Without a prior state the card is still held and delivered; it only skips return pairing.
                _offline[activity.MemberKey] = new(notice,
                    _lastMembers.TryGetValue(activity.MemberKey, out var before) ? before : null, offlineSince, OfflineSettle, Valid);
            }
            else output.Add(notice);
        }
        _lastMembers.Clear();
        foreach (var member in members) _lastMembers[member.Key] = member;
        EnsureOfflineRetryLocked(saved.Value.Scope);
        foreach (var (key, pending) in _deferred.ToArray())
        {
            if (Stopwatch.GetElapsedTime(pending.Since, _timestamp()) > UnknownEnvironmentGrace ||
                output.Any(notice => notice.Activity?.MemberKey == key))
            {
                _deferred.Remove(key);
                continue;
            }
            var current = pending.Notice.IsCurrent();
            if (!current)
            {
                var environmentUnknown = false;
                try { environmentUnknown = !_environment().Known; } catch { environmentUnknown = true; }
                if (environmentUnknown)
                {
                    _unknownEnvironmentAt ??= pending.Since;
                    continue;
                }
                // The first guard may have seen a one-read native gap. A
                // recovered environment is not grounds to discard a still-
                // current card, but all identity/privacy guards run again.
                current = pending.Notice.IsCurrent();
            }
            _deferred.Remove(key);
            if (current) output.Add(pending.Notice);
        }
        return (GroupLocked(output, saved.Value.Scope), stage);
    }
    private void ClearOfflineLocked()
    {
        _offlineRetry?.Cancel(); _offlineRetry = null; _offline.Clear(); _returning.Clear(); _lastMembers.Clear();
    }
    private void ReconcileOfflineLocked(int scope)
    {
        if (_offline.Count == 0 && _returning.Count == 0) return;
        var members = Members(scope).ToDictionary(m => m.Key, StringComparer.Ordinal);
        foreach (var (key, pending) in _returning.ToArray())
            if (!members.TryGetValue(key, out var member) || member.Presence == PlayerPresenceKind.Offline || !pending.Valid())
                _returning.Remove(key);
        foreach (var (key, pending) in _offline.ToArray())
        {
            if (!members.TryGetValue(key, out var member) || !pending.Valid()) { _offline.Remove(key); continue; }
            if (member.Presence == PlayerPresenceKind.Offline) continue;
            _offline.Remove(key);
            // Record the arrival time even if native environment detection is
            // temporarily unknown; a later retry must not invent an Online edge.
            if (pending.Before is not null && Stopwatch.GetElapsedTime(pending.Since, _timestamp()) < pending.Settle) _returning[key] = pending;
        }
    }
    private void EnsureOfflineRetryLocked(int scope)
    {
        if (_offline.Count == 0 || _offlineRetry is not null || _disposed || _accountRetired) return;
        var work = _accountRetirement.Enter(default);
        if (work is null) return;
        var retry = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
        _offlineRetry = retry;
        OfflineSettleWork = FlushOfflineAsync(scope, _epoch, retry, work);
    }
    private async Task FlushOfflineAsync(int scope, long epoch, CancellationTokenSource retry,
        Lifecycle.AsyncWorkRetirement.Lease work)
    {
        using var admission = work;
        try
        {
            while (true)
            {
                TimeSpan remaining;
                lock (_gate)
                {
                    if (_disposed || _accountRetired || epoch != _epoch || _offlineRetry != retry || _offline.Count == 0) return;
                    remaining = _offline.Values.Min(p => p.Settle - Stopwatch.GetElapsedTime(p.Since, _timestamp()));
                }
                // Always yield, including a shortened zero-duration test hold.
                await Task.Delay(remaining > TimeSpan.Zero ? remaining : TimeSpan.FromMilliseconds(1), _time, retry.Token).ConfigureAwait(false);
                List<DesktopNotification> output = [];
                lock (_gate)
                {
                    if (_disposed || _accountRetired || epoch != _epoch || _offlineRetry != retry) return;
                    foreach (var (key, pending) in _offline.ToArray())
                    {
                        if (!pending.Valid()) { _offline.Remove(key); continue; }
                        if (Stopwatch.GetElapsedTime(pending.Since, _timestamp()) < pending.Settle) continue;
                        _offline.Remove(key);
                        // DeliverAsync re-checks IsCurrent and parks a card whose native environment is
                        // momentarily unknown, so an expired hold is never silently lost here.
                        output.Add(pending.Notice);
                    }
                    output = GroupLocked(output, scope);
                }
                await DeliverAsync(output, null, retry.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        catch { lock (_gate) { if (_offlineRetry == retry) _offline.Clear(); } }
        finally
        {
            lock (_gate) {
                if (_offlineRetry == retry) { _offlineRetry = null; EnsureOfflineRetryLocked(scope); }
            }
            retry.Dispose();
        }
    }
    // 0.7.3 (user 11-06: "合成一张"): within 60 s the first two members coming online get their own
    // card; from the third on, arrivals are held briefly and shown as one card ("3 位成员上线 · 在线 5/12").
    // Going offline follows the same rule. Cards already shown are never taken back.
    internal static TimeSpan GroupHold { get; set; } = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan GroupWindow = TimeSpan.FromSeconds(60);
    private const int GroupFrom = 3;
    // Who got a card of each kind in the last minute; one member counts once however often they flap.
    private readonly Dictionary<string, List<(long At, string Member)>> _recentCards = new(StringComparer.Ordinal);
    private static string MemberOf(DesktopNotification notice) => notice.Activity?.MemberKey ?? notice.Id.ToString("N");
    private readonly Dictionary<string, List<DesktopNotification>> _held = new(StringComparer.Ordinal);
    private List<DesktopNotification> GroupLocked(List<DesktopNotification> output, int scope)
    {
        var now = _timestamp();
        var held = new HashSet<DesktopNotification>(ReferenceEqualityComparer.Instance);
        foreach (var kind in new[] { "Online", "Offline" })
        {
            var fresh = output.Where(notice => !notice.Test && notice.Activity?.Kind == kind).ToList();
            if (fresh.Count == 0) continue;
            if (!_recentCards.TryGetValue(kind, out var recent)) _recentCards[kind] = recent = [];
            recent.RemoveAll(card => Stopwatch.GetElapsedTime(card.At, now) > GroupWindow);
            if (_held.TryGetValue(kind, out var waiting)) waiting.AddRange(fresh);
            else if (recent.Select(card => card.Member).Concat(fresh.Select(MemberOf)).Distinct(StringComparer.Ordinal).Count() >= GroupFrom)
            {
                if (!ScheduleGroupLocked(kind, scope)) continue;
                _held[kind] = fresh;
            }
            else { recent.AddRange(fresh.Select(notice => (now, MemberOf(notice)))); continue; }
            held.UnionWith(fresh);
        }
        return held.Count == 0 ? output : output.Where(notice => !held.Contains(notice)).ToList();
    }
    private bool ScheduleGroupLocked(string kind, int scope)
    {
        if (_disposed || _accountRetired) return false;
        var work = _accountRetirement.Enter(default);
        if (work is null) return false;
        _ = FlushGroupAsync(kind, scope, _epoch, work);
        return true;
    }
    private async Task FlushGroupAsync(string kind, int scope, long epoch, Lifecycle.AsyncWorkRetirement.Lease work)
    {
        using var admission = work;
        try
        {
            await Task.Delay(GroupHold, work.Token).ConfigureAwait(false);
            List<DesktopNotification> output = [];
            lock (_gate)
            {
                if (_disposed || _accountRetired || epoch != _epoch || !_held.Remove(kind, out var held)) return;
                var live = held.Where(notice => notice.IsCurrent())
                    .GroupBy(MemberOf, StringComparer.Ordinal)
                    .Select(group => group.Last()).ToList();
                if (live.Count == 0) return;
                var now = _timestamp();
                if (!_recentCards.TryGetValue(kind, out var recent)) _recentCards[kind] = recent = [];
                recent.AddRange(live.Select(notice => (now, MemberOf(notice))));
                output.Add(live.Count == 1 ? live[0] : Grouped(live, Members(scope)));
            }
            await DeliverAsync(output, null, work.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { }
        catch { /* A grouped card is optional; ordinary activity keeps working. */ }
    }
    internal static DesktopNotification Grouped(IReadOnlyList<DesktopNotification> live, IReadOnlyCollection<PlayerActivityMemberState> members)
    {
        var first = live[0];
        var names = live.Select(notice => notice.Activity!).Select(activity =>
            string.IsNullOrWhiteSpace(activity.Callsign) ? activity.GameId : activity.Callsign)
            .Where(name => !string.IsNullOrWhiteSpace(name)).ToArray();
        var sources = live.SelectMany(notice => notice.Activity!.Sources ?? []).Distinct(StringComparer.Ordinal)
            .OrderBy(label => label == "friends" ? 0 : label == "room" ? 2 : 1).ThenBy(label => label, StringComparer.Ordinal).ToArray();
        var content = first.Activity! with { Callsign = "", GameId = "", AvatarImageData = null, MemberKey = null, Sources = sources };
        content = content with {
            GroupNames = names,
            OnlineNow = members.Count(member => member.Presence != PlayerPresenceKind.Offline),
            Tracked = members.Count
        };
        // The card names everyone in it, so it stays only while every one of them is still valid
        // (no one went invisible, paused sharing or changed state again).
        return first with { Id = Guid.NewGuid(), Activity = content, IsCurrent = () => live.All(notice => notice.IsCurrent()) };
    }
    private void EnsureUnknownRetryLocked()
    {
        if (_unknownRetry is not null || _disposed || _accountRetired) return;
        var work = _accountRetirement.Enter(default);
        if (work is null) return;
        var retry = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
        _unknownRetry = retry;
        _ = RetryUnknownEnvironmentAsync(retry, _epoch, work);
    }
    private async Task RetryUnknownEnvironmentAsync(CancellationTokenSource retry, long epoch,
        Lifecycle.AsyncWorkRetirement.Lease work)
    {
        using var admission = work;
        try
        {
            while (true)
            {
                await Task.Delay(UnknownEnvironmentRetry, retry.Token).ConfigureAwait(false);
                List<DesktopNotification> output;
                NotificationDeliveryStage? stage;
                lock (_gate)
                {
                    if (_disposed || _accountRetired || _unknownRetry != retry || _epoch != epoch || _unknownEnvironmentAt is not { } started)
                        return;
                    PlayerActivityEnvironment env;
                    try { env = _environment(); }
                    catch { env = new(false, false, false, false); }
                    if (!env.Known)
                    {
                        if (Stopwatch.GetElapsedTime(started, _timestamp()) <= UnknownEnvironmentGrace) continue;
                        _deferred.Clear();
                        return;
                    }
                    var observation = _sources.Values.FirstOrDefault(value => value.Generation == _generation() && value.IsCurrent());
                    if (observation is null) return;
                    var saved = _store.Read();
                    if (saved.Revision != _revision || (Policies()?.Revision ?? -1) != _policyRevision || !ShouldObserve()) return;
                    (output, stage) = EvaluateKnownLocked(observation, saved, env, false, false);
                    if (_unknownEnvironmentAt is null) _unknownRetry = null;
                }
                await DeliverAsync(output, stage, retry.Token).ConfigureAwait(false);
                lock (_gate) { if (_unknownRetry != retry || _unknownEnvironmentAt is null) return; }
            }
        }
        catch (OperationCanceledException) { }
        catch { /* A failed optional retry must not affect ordinary social reads. */ }
        finally
        {
            lock (_gate) { if (_unknownRetry == retry) _unknownRetry = null; }
            retry.Dispose();
        }
    }
    private async Task DeliverAsync(List<DesktopNotification> output, NotificationDeliveryStage? observationStage, CancellationToken token)
    {
        if (_accountRetired || token.IsCancellationRequested) return;
        if (observationStage is { } stage)
            _delivery.Record(NotificationDeliveryChannel.Activity, stage, Guid.NewGuid().ToString("N"),
                result: stage == NotificationDeliveryStage.EnvironmentSuppressed ? "environmentUnknown" : "sourceChanged");
        foreach (var notice in output)
        {
            if (_accountRetired || token.IsCancellationRequested) return;
            var trace = notice.Id.ToString("N");
            _delivery.Record(NotificationDeliveryChannel.Activity, NotificationDeliveryStage.FreshEvent, trace,
                result: notice.Activity?.Kind);
            var sink = _sink;
            var canSubmit = sink is not null && notice.IsCurrent();
            if (!canSubmit) {
                var environmentUnknown = false;
                try { environmentUnknown = !_environment().Known; } catch { environmentUnknown = true; }
                if (sink is not null && environmentUnknown && notice.Activity?.MemberKey is { } key)
                {
                    lock (_gate) {
                        _deferred[key] = new(notice, _timestamp());
                        _unknownEnvironmentAt ??= _timestamp();
                        EnsureUnknownRetryLocked();
                    }
                    _delivery.Record(NotificationDeliveryChannel.Activity, NotificationDeliveryStage.EnvironmentSuppressed,
                        trace, result: "environmentUnknown");
                }
                else if (sink is not null && notice.IsCurrent()) canSubmit = true;
                else _delivery.Record(NotificationDeliveryChannel.Activity, NotificationDeliveryStage.Stale, trace,
                    result: "expired");
            }
            if (!canSubmit) continue;
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            // Uncertain submission never retries or falls through to a second channel.
            try {
                var result = await sink!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
                _delivery.Record(NotificationDeliveryChannel.Activity,
                    result.Submitted ? NotificationDeliveryStage.NativeAccepted : NotificationDeliveryStage.NativeRejected,
                    trace, sink.DiagnosticTransport, result.Reason);
            } catch {
                _delivery.Record(NotificationDeliveryChannel.Activity, NotificationDeliveryStage.Failed,
                    trace, sink!.DiagnosticTransport, "unavailable");
            }
        }
    }
    private static bool SameObservedPresence(PlayerActivityObservedMember[] before, PlayerActivityObservedMember[] after)
    {
        if (before.Length != after.Length) return false;
        return before.OrderBy(member => member.MemberKey, StringComparer.Ordinal)
            .Zip(after.OrderBy(member => member.MemberKey, StringComparer.Ordinal))
            .All(pair => pair.First.MemberKey == pair.Second.MemberKey &&
                pair.First.Presence == pair.Second.Presence &&
                pair.First.AllowsPresenceEvents == pair.Second.AllowsPresenceEvents);
    }
    private PlayerActivityMemberState[] Members(int scope)
    {
        var policies = Policies();
        bool Allowed(PlayerActivityObservation observation, PlayerActivityObservedMember member) => _policyOwner == null || policies != null &&
            (observation.Source == "organization" ? member.PolicySources?.Any(key => OrganizationAllows(policies, key)) == true :
                policies.For(observation.Source == "friends" ? "friends" : "room") == NotificationSourceMode.Normal);
        var valid = _sources.Values.Where(o => o.IsCurrent() &&
            (scope & (o.Source == "friends" ? 4 : o.Source == "organization" ? 2 : 1)) != 0);
        return valid.SelectMany(o => o.Members.Where(m => Allowed(o, m) && !m.IsSelf && m.AllowsPresenceEvents &&
                m.Presence is "online" or "inGame" or "away" or "offline")
            .Select(m => (Member: m, Observation: o)))
            .GroupBy(row => row.Member.MemberKey, StringComparer.Ordinal).Select(group =>
            {
                // Sequence orders reads within a source, not the freshness of
                // different sources. A later legacy organization/room read can
                // still describe an older state than the explicit friend-live
                // projection. Keep the most authoritative visible source for
                // state while retaining all authorized audience labels below.
                var selected = group.OrderByDescending(row => row.Observation.Source switch {
                        "friends" => 3, "room" => 2, _ => 1
                    }).ThenByDescending(row => row.Observation.Sequence).First().Member;
                return new PlayerActivityMemberState(selected.MemberKey, selected.GameId, selected.Callsign,
                    string.IsNullOrWhiteSpace(selected.Callsign) ? selected.GameId : selected.Callsign, "", selected.AvatarImageData,
                    null, selected.Presence switch { "online" => PlayerPresenceKind.AppOnline, "inGame" => PlayerPresenceKind.InGame,
                        "away" => PlayerPresenceKind.Away, _ => PlayerPresenceKind.Offline }, false, true,
                    group.Any(r => r.Observation.Source == "organization"), group.Any(r => r.Observation.Source == "friends"),
                    group.Any(r => r.Observation.Source == "room"));
            }).ToArray();
    }
    private string[] SourceLabels(string memberKey, int scope)
    {
        var labels = new List<string>();
        var policies = Policies();
        bool Allowed(string key) => _policyOwner == null || policies != null && (key.StartsWith("organization:", StringComparison.Ordinal)
            ? OrganizationAllows(policies, key) : policies.For(key) == NotificationSourceMode.Normal);
        foreach (var source in _sources.Values.Where(o => o.IsCurrent()))
        foreach (var member in source.Members.Where(m => m.MemberKey == memberKey && !m.IsSelf && m.AllowsPresenceEvents &&
            m.Presence is "online" or "inGame" or "away" or "offline")) {
            if (source.Source == "friends" && (scope & 4) != 0 && Allowed("friends")) labels.Add("friends");
            if (source.Source == "room" && (scope & 1) != 0 && Allowed("room")) labels.Add("room");
            if (source.Source == "organization" && (scope & 2) != 0)
                foreach (var organization in member.Organizations ?? [])
                    if (Allowed(organization.PolicySource)) labels.Add("organization:" + organization.Name);
        }
        return labels.Distinct(StringComparer.Ordinal).OrderBy(label => label == "friends" ? 0 : label == "room" ? 2 : 1)
            .ThenBy(label => label, StringComparer.Ordinal).ToArray();
    }
    private DesktopNotification Create(PlayerActivityDesktopNotification activity, PlayerActivityPreferences settings, bool test, Func<bool> current, string[]? sources = null)
    {
        var appearance = _appearance.Load().Snapshot;
        var notice = new DesktopNotification(Guid.NewGuid(), test, 0, 0, "fullContent", settings.Position switch {
                0 => "topLeft", 1 => "bottomLeft", 2 => "topRight", _ => "bottomRight" },
            appearance.LocaleOverride ?? System.Globalization.CultureInfo.CurrentUICulture.Name,
            appearance.AppearanceMode, current, appearance.MotionPreference == "reduce", null,
            new(activity.Callsign, activity.GameId, activity.Kind.ToString(), activity.AudienceText, activity.AvatarSource,
                activity.MemberKey, test ? ["friends", "room"] : sources),
            settings.BackgroundOnly);
        if (test) return notice;
        var trace = notice.Id.ToString("N");
        return notice with { Diagnostic = outcome => _delivery.Record(NotificationDeliveryChannel.Activity,
            NotificationDeliveryStage.NativeLifecycle, trace, _sink?.DiagnosticTransport, outcome) };
    }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        if (request.Name != "playerActivity.test") return await _preferences.DispatchAsync(request, token);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.AccountContext is not null || request.MessageType != BridgeMessageTypes.Request ||
                request.SessionGeneration != _generation() || request.Payload.EnumerateObject().Count() != 1 ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
            DesktopNotification notice;
            lock (_gate)
            {
                var now = Stopwatch.GetTimestamp();
                if (_lastTest != 0 && Stopwatch.GetElapsedTime(_lastTest, now) < TimeSpan.FromSeconds(2)) throw new InvalidOperationException();
                _lastTest = now;
                var saved = _store.Read();
                if (saved.DoNotDisturb || _sink is null) throw new InvalidOperationException();
                notice = Create(new(PlayerActivityNotificationKind.StartedGame, "test", "", "", "", "", null, null, "", "", ""),
                    saved.Value, true, () => TestCurrent(request.SessionGeneration, now, saved.Revision, saved.Value));
            }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            var result = await _sink!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, submitted = result.Submitted,
                reason = result.Reason }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return new(BridgeEnvelope.ErrorResponse(request, new("playerActivity.test_unavailable", "Test reminder unavailable.")), []); }
    }
    private bool EnvironmentAllows(PlayerActivityPreferences settings, bool test = false)
    {
        var env = _environment();
        return env.Known && (test || !settings.BackgroundOnly || env.AppBackground) &&
            !(settings.ReduceInGame && env.GameRunning && env.OverlayRunning);
    }
    private bool TestCurrent(long generation, long started, string revision, PlayerActivityPreferences settings)
    {
        try { var saved = _store.Read(); return !_disposed && generation == _generation() &&
            saved.Revision == revision && !saved.DoNotDisturb && EnvironmentAllows(settings, true) &&
            Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(30); }
        catch { return false; }
    }
    public void Reset() { lock (_gate) ResetLocked(); }
    private NotificationPolicySnapshot? Policies() => _policyOwner?.Invoke() is {} owner ? _policies.Read(owner) : null;
    private bool OrganizationAllows(NotificationPolicySnapshot policies, string key) => NotificationOrganizationPolicy.Allows(
        policies.Rule(key), NotificationEventKind.PlayerOnline, _time.GetUtcNow(), NotificationOrganizationPolicy.LocalZone(_time));
    private Func<bool> OrganizationLease(string memberKey, int scope)
    {
        if ((scope & 2) == 0 || _policyOwner?.Invoke() is not { } owner) return () => true;
        var saved = _policies.Read(owner);
        var keys = _sources.Values.Where(o => o.Source == "organization" && o.IsCurrent())
            .SelectMany(o => o.Members.Where(m => m.MemberKey == memberKey).SelectMany(m => m.PolicySources ?? []))
            .Distinct().Where(key => OrganizationAllows(saved, key)).ToArray();
        var at = _time.GetUtcNow(); var zone = NotificationOrganizationPolicy.LocalZone(_time);
        return () => keys.All(key => NotificationOrganizationPolicy.Current(_policies, owner, key, NotificationEventKind.PlayerOnline,
            saved.SuppressionRevision(key), at, zone, _time));
    }
    private void ResetLocked() { _epoch++; ClearOfflineLocked(); _observedGeneration = null; _unknownRetry?.Cancel(); _unknownRetry = null; _sources.Clear(); _deferred.Clear(); _held.Clear(); _recentCards.Clear(); _tracker = new(); _scope = null; _revision = null; _policyRevision = -1; _unknownEnvironmentAt = null; }
    // Retire account observations and their native submissions, not the device
    // settings/test module: those local controls remain usable without a login.
    internal Task RetireAccountActivityAsync()
    {
        lock (_gate) { _accountRetired = true; ResetLocked(); }
        return _accountRetirement.Close();
    }
    public void Dispose()
    {
        lock (_gate) { _disposed = true; _accountRetired = true; ResetLocked(); }
        _ = _accountRetirement.Close();
        _preferences.Dispose();
    }
}
