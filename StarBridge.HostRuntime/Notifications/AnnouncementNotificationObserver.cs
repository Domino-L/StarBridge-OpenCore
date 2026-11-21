using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

internal sealed class AnnouncementNotificationObserver(AnnouncementObservationStore store, TimeProvider? time = null,
    Func<BridgeAccountContext, NotificationPolicySnapshot>? policies = null)
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private sealed record State(DateTimeOffset Server, DateTimeOffset Received, long Timestamp, string Baseline);
    private readonly Dictionary<string, State> _sources = new(StringComparer.Ordinal);
    private readonly HashSet<string> _blocked = new(StringComparer.Ordinal);
    private readonly HashSet<string> _persisted = new(StringComparer.Ordinal);
    private string? _owner;
    private long _generation;
    private readonly object _gate = new();
    private long _membershipRevision;
    internal long MembershipRevision => Interlocked.Read(ref _membershipRevision);
    internal bool Allows(BridgeAccountContext context, CommunityNotificationSource source, DateTimeOffset? occurredAt) {
        try {
            return policies == null || NotificationOrganizationPolicy.AllowsEvent(policies(context).Rule(source.PolicyKey),
                NotificationEventKind.OrganizationAnnouncement, occurredAt, _time.GetUtcNow(), NotificationOrganizationPolicy.LocalZone(_time));
        } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException) { return false; }
    }
    // Reconnect/session invalidation clears continuity, while retaining the
    // account binding and its durable observed membership generations.
    internal void Reset() { lock (_gate) _sources.Clear(); }
    private AnnouncementObservationStore.Snapshot Load(string owner) {
        if (_persisted.Contains(owner) && !File.Exists(store.PathFor(owner))) throw new IOException("Observation file disappeared.");
        try { return store.ReadSnapshot(owner); }
        catch (Exception e) when (e is InvalidDataException or System.Text.Json.JsonException or KeyNotFoundException or InvalidOperationException or FormatException) {
            // Untrusted generations cannot prove a baseline. Replace with a new
            // quiet baseline in the same atomic account transaction.
            Reset();
            return new() { Changed = true };
        }
    }
    internal void BindOwner(BridgeAccountContext? context) {
        lock (_gate) {
            if (context == null) return; // Connectivity/session loss is not an observed account switch.
            var next = AnnouncementObservationStore.Owner(context);
            if (_owner == next) return;
            if (_owner is { } prior) {
                void Retire(AnnouncementObservationStore.Snapshot data) {
                    foreach (var slot in data.Slots.Values.ToArray()) data.Observe(slot.Slot, null, slot.Official);
                }
                Mutate(prior, Retire, () => true);
                // An incoming account can have a baseline from an older process.
                // A live account switch cannot treat that baseline as a restart.
                Mutate(next, Retire, () => true);
            }
            _owner = next; Interlocked.Increment(ref _membershipRevision); Reset();
        }
    }
    private void Mutate(string owner, Action<AnnouncementObservationStore.Snapshot> change, Func<bool> current) {
        if (_blocked.Contains(owner)) return;
        try {
            var data = Load(owner); change(data);
            if (data.Changed) { store.WriteSnapshot(owner, data, current); _persisted.Add(owner); Interlocked.Increment(ref _membershipRevision); }
        } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or OverflowException) {
            _blocked.Add(owner); Interlocked.Increment(ref _membershipRevision); Reset();
        }
    }
    internal void ObserveOfficialMembership(BridgeAccountContext context, string? source, Func<bool> current) {
        lock (_gate) {
            BindOwner(context);
            Mutate(AnnouncementObservationStore.Owner(context), data => data.Observe(AnnouncementObservationStore.Slot("", true),
                source == null ? null : AnnouncementObservationStore.Binding(source, NotificationPolicyStore.OfficialFleet(source)), true), current);
        }
    }
    internal void ConfirmCommunities(BridgeAccountContext context, IEnumerable<string> codes, Func<bool> current, bool revoke = false) {
        lock (_gate) {
            var slots = codes.Select(code => AnnouncementObservationStore.Slot("community:" + code.ToUpperInvariant(), false)).ToHashSet();
            Mutate(AnnouncementObservationStore.Owner(context), data => {
                foreach (var slot in data.Slots.Values.Where(s => !s.Official && (revoke ? slots.Contains(s.Slot) : !slots.Contains(s.Slot))).ToArray())
                    data.Observe(slot.Slot, null, false);
            }, current);
        }
    }
    internal IReadOnlyList<CommunityNotificationCandidate> Observe(BridgeAccountContext context, long generation,
        CommunityNotificationFeed feed, Func<bool> current)
    {
        lock (_gate) return ObserveCore(context, generation, feed, current);
    }
    private IReadOnlyList<CommunityNotificationCandidate> ObserveCore(BridgeAccountContext context, long generation,
        CommunityNotificationFeed feed, Func<bool> current)
    {
        BindOwner(context);
        var owner = AnnouncementObservationStore.Owner(context);
        if (_blocked.Contains(owner)) { Reset(); return []; }
        if (!feed.IsBounded) { Reset(); return []; }
        if (_owner != owner || _generation != generation) Reset();
        var next = new Dictionary<string, State>(StringComparer.Ordinal);
        var candidates = new List<CommunityNotificationCandidate>();
        try {
            var data = Load(owner);
            var consumed = data.Keys;
            var presentSlots = new HashSet<string>(StringComparer.Ordinal);
            foreach (var source in feed.Sources.Where(s => ValidIdentity(s.AnnouncementIdentity) && !string.IsNullOrWhiteSpace(s.PolicyKey))) {
                var official = source.SourceKind == OrganizationNotificationSourceKind.OfficialFleet;
                var slot = AnnouncementObservationStore.Slot(source.AnnouncementIdentity!, official);
                presentSlots.Add(slot);
                data.Observe(slot, AnnouncementObservationStore.Binding(source.AnnouncementIdentity!, source.PolicyKey), official);
            }
            if (feed.OfficialMembershipConfirmed && feed.OfficialMembershipSource == null)
                data.Observe(AnnouncementObservationStore.Slot("", true), null, true);
            if (feed.CommunitiesConfirmed)
                foreach (var slot in data.Slots.Values.Where(s => !s.Official && !presentSlots.Contains(s.Slot)).ToArray())
                    data.Observe(slot.Slot, null, false);
            var rules = policies?.Invoke(context);
            var zone = NotificationOrganizationPolicy.LocalZone(_time);
            if (File.Exists(store.PathFor(owner))) _persisted.Add(owner);
            var changed = false;
            foreach (var source in feed.Sources) {
                if (source.Announcements is not { } page) continue;
                if (source.AnnouncementIdentity is not { Length: > 0 and <= 272 } identity || identity.Any(char.IsControl)) continue;
                if (page.Entries.Length > 100 || page.Entries.Any(e => string.IsNullOrWhiteSpace(e.Id) || e.Id.Length > 128 ||
                        e.PublishedAt > page.ServerTime) || page.Entries.Select(e => e.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != page.Entries.Length)
                    continue;
                if (string.IsNullOrWhiteSpace(source.PolicyKey)) continue;
                var membership = data.Slots[AnnouncementObservationStore.Slot(identity, source.SourceKind == OrganizationNotificationSourceKind.OfficialFleet)];
                var baseline = AnnouncementObservationStore.Baseline(owner, identity, source.PolicyKey, membership.Epoch);
                var historical = consumed.Contains(baseline);
                var previous = _sources.GetValueOrDefault(source.SourceKey);
                var continuous = previous != null && previous.Baseline == baseline && feed.ReceivedAt > previous.Received &&
                    feed.ReceivedAt - previous.Received <= TimeSpan.FromSeconds(30) && page.ServerTime > previous.Server &&
                    page.ServerTime - previous.Server <= TimeSpan.FromSeconds(30) &&
                    _time.GetElapsedTime(previous.Timestamp) <= TimeSpan.FromSeconds(30);
                var unseen = 0;
                foreach (var entry in page.Entries) {
                    var key = AnnouncementObservationStore.Key(owner, identity, entry.Id);
                    if (!consumed.Add(key)) continue;
                    changed = true;
                    // Consume even unknown dates and quiet-hour publications. Recovery
                    // time must never substitute for the first server publication time.
                    var eligible = entry.Published && entry.PublishedAt != default &&
                        !NotificationOrganizationPolicy.Quiet(rules?.Rule(source.PolicyKey).QuietHours, entry.PublishedAt, zone);
                    if (eligible) unseen++;
                    if (continuous && eligible && entry.PublishedAt > previous!.Server)
                        candidates.Add(new(source.SourceKey, NotificationEventKind.OrganizationAnnouncement, entry.PublishedAt));
                }
                if (!continuous && historical && unseen > 0)
                    candidates.Add(new(source.SourceKey, NotificationEventKind.OrganizationAnnouncement, feed.ReceivedAt,
                        Math.Min(unseen, 100)));
                changed |= consumed.Add(baseline);
                next[source.SourceKey] = new(page.ServerTime, feed.ReceivedAt, _time.GetTimestamp(), baseline);
            }
            // No output can escape before all observations, including suppressed
            // and historical records, are durably consumed.
            if (changed || data.Changed) { store.WriteSnapshot(owner, data, current); _persisted.Add(owner); }
            if (data.Changed) Interlocked.Increment(ref _membershipRevision);
            if (!current()) { Reset(); return []; }
            _sources.Clear();
            foreach (var pair in next) _sources.Add(pair.Key, pair.Value);
            _owner = owner; _generation = generation;
            return candidates.GroupBy(c => c.SourceKey).Select(g => g.First()).ToArray();
        } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or OverflowException) {
            _blocked.Add(owner); Reset(); return [];
        }
    }
    private static bool ValidIdentity(string? identity) => identity is { Length: > 0 and <= 272 } && !identity.Any(char.IsControl);
}
