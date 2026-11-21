using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

internal interface ICommunityNotificationReader
{
    Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token);
}
internal sealed record CommunityNotificationNotice(BridgeAccountContext Owner, CommunityNotificationSource Source,
    NotificationEventKind Kind, Func<bool> IsCurrent, DateTimeOffset? OccurredAt = null,
    Func<CancellationToken, Task<bool>>? Revalidate = null, int AnnouncementSummaryCount = 0,
    Func<CancellationToken, Task<bool>>? ReauthorizeActivation = null);

// One Host-owned read-only loop. It never depends on an open organization page.
// Feed freshness is consumed before source, channel, foreground and OS gates.
internal sealed class CommunityNotificationRuntime(ICommunityNotificationReader reader,
    Func<(BridgeAccountContext? Context, long Generation)> owner,
    Func<CommunityNotificationNotice, CancellationToken, ValueTask> present, TimeProvider? time = null,
    Action<long, int>? pendingManagement = null, AnnouncementNotificationObserver? announcements = null) : IDisposable
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly CommunityNotificationObserver _observer = new(time);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly Lifecycle.AsyncWorkRetirement _retirement = new();
    private readonly object _stateGate = new();
    private ITimer? _timer;
    private CancellationTokenSource? _request;
    private long _epoch;
    private volatile bool _disposed;
    private int _failures;
    private int _reset;
    private readonly Dictionary<string, (OrganizationNotificationSourceKind Kind, int Count)> _pendingCounts = new(StringComparer.Ordinal);
    private (BridgeAccountContext? Context, long Generation) _pendingOwner;
    private CommunityNotificationSource[] _confirmedSources = [];
    internal void ObserveAccount() => announcements?.BindOwner(owner().Context);
    internal void ObserveOfficialMembership(BridgeAccountContext context, long generation, string? source) {
        lock (_stateGate) {
            if (owner() != (context, generation)) return;
            announcements?.ObserveOfficialMembership(context, source, () => owner() == (context, generation));
        }
    }
    internal void RevokeCommunity(BridgeAccountContext context, long generation, string code)
    {
        lock (_stateGate) {
            if (owner() == (context, generation))
                announcements?.ConfirmCommunities(context, [code], () => owner() == (context, generation), revoke: true);
            if (owner() == (context, generation) && _confirmedSources.Any(s => s.AnnouncementIdentity == "community:" + code.ToUpperInvariant()))
                Invalidate();
        }
    }
    internal void ConfirmCommunityDirectory(BridgeAccountContext context, long generation, IEnumerable<string> codes)
    {
        var identities = codes.Select(code => "community:" + code.ToUpperInvariant()).ToHashSet(StringComparer.Ordinal);
        lock (_stateGate) {
            if (owner() == (context, generation))
                announcements?.ConfirmCommunities(context, codes, () => owner() == (context, generation));
            if (owner() == (context, generation) && _confirmedSources.Any(s =>
                s.SourceKind == OrganizationNotificationSourceKind.Community && s.AnnouncementIdentity != null && !identities.Contains(s.AnnouncementIdentity)))
                Invalidate();
        }
    }
    internal void Start()
    {
        lock (_stateGate)
            if (!_disposed) _timer ??= _time.CreateTimer(_ => _ = TickAsync(), null, TimeSpan.FromSeconds(5), Timeout.InfiniteTimeSpan);
    }
    internal void Invalidate() {
        lock (_stateGate) {
            if (_disposed) return;
            _epoch++; _reset = 1; _request?.Cancel();
            _timer?.Change(TimeSpan.FromSeconds(5), Timeout.InfiniteTimeSpan);
        }
    }
    internal async Task TickAsync()
    {
        using var work = _retirement.Enter(default);
        if (work is null || _disposed || !await _gate.WaitAsync(0)) return;
        CancellationTokenSource? request = null;
        try {
            if (Interlocked.Exchange(ref _reset, 0) != 0) { _observer.Reset(); announcements?.Reset(); }
            var context = owner();
            if (_pendingOwner != context) { _pendingOwner = context; _pendingCounts.Clear(); }
            long epoch;
            request = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
            request.CancelAfter(TimeSpan.FromSeconds(12));
            lock (_stateGate) { epoch = ++_epoch; _request = request; }
            bool Current() => !_disposed && Volatile.Read(ref _epoch) == epoch && owner() == context;
            if (context.Context is null) { _observer.Reset(); announcements?.Reset(); _failures = 0; return; }
            var feed = await reader.ReadNotificationsAsync(context.Context, context.Generation, request.Token);
            if (!Current() || request.IsCancellationRequested) { _observer.Reset(); announcements?.Reset(); return; }
            lock (_stateGate) { if (Current()) _confirmedSources = feed.Sources; }
            var candidates = _observer.Observe(System.Text.Json.JsonSerializer.Serialize(context.Context), context.Generation, feed)
                .Concat(announcements?.Observe(context.Context, context.Generation, feed, Current) ?? []).ToArray();
            // A confirmed authenticated domain snapshot, including history,
            // owns pending work independently of fresh popup/audio delivery.
            if (feed.IsBounded) {
                var keys = feed.Sources.Select(row => row.SourceKey).ToHashSet(StringComparer.Ordinal);
                foreach (var key in _pendingCounts.Keys.Where(key => !keys.Contains(key) &&
                    (feed.CommunitiesConfirmed || _pendingCounts[key].Kind != OrganizationNotificationSourceKind.Community)).ToArray())
                    _pendingCounts.Remove(key);
                foreach (var source in feed.Sources.Where(row => row.ManagementConfirmed))
                    _pendingCounts[source.SourceKey] = (source.SourceKind, source.ManagementAvailable
                        ? source.Tasks.Select(task => task.Key).Distinct(StringComparer.Ordinal).Count() : 0);
                if (Current()) pendingManagement?.Invoke(context.Generation, _pendingCounts.Values.Sum(value => value.Count));
            }
            _failures = 0;
            var started = _time.GetTimestamp();
            var membershipRevision = announcements?.MembershipRevision ?? 0;
            foreach (var candidate in candidates.Take(16)) {
                var source = feed.Sources.Single(row => row.SourceKey == candidate.SourceKey);
                bool Valid() => Current() && (announcements?.MembershipRevision ?? 0) == membershipRevision &&
                    _time.GetElapsedTime(started) < TimeSpan.FromSeconds(30);
                if (!Valid()) return;
                // Observation already consumed the IDs. Disabled announcement rows
                // never reach native/audio queues or any authorization callback.
                if (candidate.Kind == NotificationEventKind.OrganizationAnnouncement &&
                    announcements?.Allows(context.Context, source, candidate.OccurredAt) == false) continue;
                // Native submission is bounded separately from the read deadline.
                using var output = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
                output.CancelAfter(TimeSpan.FromSeconds(1));
                bool Matches(CommunityNotificationFeed fresh) => fresh.IsBounded && fresh.Sources.Any(s => s.SourceKey == source.SourceKey &&
                    s.SourceKind == source.SourceKind && s.PolicyKey == source.PolicyKey &&
                    s.AnnouncementIdentity == source.AnnouncementIdentity && s.JoinedAt == source.JoinedAt &&
                    s.Announcements != null && s.AnnouncementSource == source.AnnouncementSource);
                Task<bool> Revalidate(CancellationToken ct) {
                    lock (_stateGate) return Task.FromResult(!ct.IsCancellationRequested && Valid() &&
                        Matches(feed with { Sources = _confirmedSources }) &&
                        announcements?.Allows(context.Context, source, candidate.OccurredAt) != false);
                }
                // Only an explicit user click may request a fresh authorized feed.
                async Task<bool> ReauthorizeActivation(CancellationToken ct) {
                    if (!Valid()) return false;
                    var fresh = await reader.ReadNotificationsAsync(context.Context, context.Generation, ct);
                    return Valid() && Matches(fresh);
                }
                try {
                    if (candidate.Kind == NotificationEventKind.OrganizationAnnouncement && !await Revalidate(output.Token)) continue;
                    await present(new(context.Context, source, candidate.Kind, Valid, candidate.OccurredAt,
                    candidate.Kind == NotificationEventKind.OrganizationAnnouncement ? Revalidate : null,
                    candidate.AnnouncementSummaryCount,
                    candidate.Kind == NotificationEventKind.OrganizationAnnouncement ? ReauthorizeActivation : null), output.Token); }
                catch { /* A consumed event is never replayed after uncertain output. */ }
            }
        } catch { _observer.Reset(); announcements?.Reset(); Interlocked.Increment(ref _epoch); _failures = Math.Min(_failures + 1, 3); }
        finally {
            lock (_stateGate) _request = null;
            request?.Dispose();
            _gate.Release();
            lock (_stateGate) {
                if (!_disposed) _timer?.Change(TimeSpan.FromSeconds(_reset != 0 ? 5 : _failures == 0 ? 15 : 15 * (1 << _failures)), Timeout.InfiniteTimeSpan);
            }
        }
    }
    internal Task RetireAsync() { Dispose(); return _retirement.Close(); }
    public void Dispose() {
        lock (_stateGate) {
            if (_disposed) return;
            _disposed = true; _epoch++; _timer?.Dispose();
        }
        _ = _retirement.Close();
    }
}
