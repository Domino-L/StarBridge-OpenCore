using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Shared by live trade cards and both existing station-message REST readers.
    // Scoped to this Host lifetime; never persisted or sent to Flutter.
    private readonly Dictionary<string, (long Id, int Type, bool Read)> _stationReceipts = new(StringComparer.Ordinal);
    private long _stationReceiptEpoch, _stationReadRevision;
    private readonly Dictionary<string, int> _stationReadBarriers = new(StringComparer.Ordinal);
    private readonly List<StationReadScope> _stationPendingReads = [];
    private readonly HashSet<string> _stationReconciliations = new(StringComparer.Ordinal);
    // Owners whose first station page has been seen in this Host lifetime. Until then every row is
    // history: the first read only sets the baseline and never raises a card.
    private readonly HashSet<string> _stationPollBaselines = new(StringComparer.Ordinal);
    // Station keys already seen by the periodic inbox read (page 1, all types). Independent of
    // trading-hall page reads, which may browse any page, type or unread filter.
    private readonly HashSet<string> _stationPolled = new(StringComparer.Ordinal);

    /// <summary>A station trade message seen for the first time by a REST read after the owner's
    /// baseline, still unread. Raised outside every lock. Hotfix 10-29: the relay socket carries no
    /// station pushes, so the periodic inbox read is the source of trade cards (at most ~60 s late).</summary>
    /// The third argument re-checks, under the caller's own gate, that the read which found the
    /// message is still current (Host owner/generation and this receipt epoch). Never re-stamp an
    /// old read with the current generation.
    internal event Action<string, TradeNotificationEvent, Func<bool>>? StationTradeDiscovered;
    private sealed record StationReadScope(string Owner, long Epoch, long Revision, int? Type, long[] Ids)
    {
        internal readonly TaskCompletionSource Completed = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
    private static string ReceiptKey(string owner, string key) => owner + "\n" + key;

    internal bool StationNotificationUnread(string owner, TradeNotificationEvent notice)
    {
        if (notice.Chat) return true;
        lock (_notificationTradeGate)
            return _stationReceipts.TryGetValue(ReceiptKey(owner, notice.Key), out var receipt) && !receipt.Read;
    }

    private bool ObserveStationReceipt(string owner, long id, int type, bool read, bool authoritative = false)
    {
        lock (_notificationTradeGate)
        {
            var key = ReceiptKey(owner, TradeNotificationEvent.KeyFor("station", id));
            if (_stationReceipts.TryGetValue(key, out var old)) { read |= old.Read; if (type < 0) type = old.Type; }
            else if (_stationReceipts.Count >= 8192 || !authoritative && NeedsStationReadback(owner, type)) return false;
            _stationReceipts[key] = (id, type, read);
            return !read;
        }
    }

    private bool NeedsStationReadback(string owner, int type) =>
        _stationReadBarriers.TryGetValue(owner, out var mask) && (type < 0 || (mask & (1 << type)) != 0);

    // Lock order is Host lifetime gate -> receipt gate, including stop/clear and WS delivery.
    // The current predicate captures Host owner AND generation; epoch also protects direct callers.
    private StationReadScope CaptureStationRead(string owner, Func<bool> current, object lifetimeGate, int? type = null, bool all = false)
    {
        lock (lifetimeGate)
        lock (_notificationTradeGate)
        {
            if (!current()) throw new Account.AccountBridgeHostException("marketplace.context_changed");
            if (all) _stationReadRevision++;
            var scope = new StationReadScope(owner, _stationReceiptEpoch, _stationReadRevision, type,
                all ? _stationReceipts.Where(x => x.Key.StartsWith(owner + "\n", StringComparison.Ordinal) &&
                    (type is null || x.Value.Type == type)).Select(x => x.Value.Id).ToArray() : []);
            if (all)
            {
                _stationReadBarriers.TryGetValue(owner, out var mask);
                _stationReadBarriers[owner] = mask | (type is { } t ? 1 << t : 7);
                _stationPendingReads.Add(scope);
            }
            return scope;
        }
    }

    private void ConfirmStationRead(StationReadScope scope, long? id, Func<bool> current, object lifetimeGate)
    {
        lock (lifetimeGate)
        lock (_notificationTradeGate)
        {
            if (!current() || scope.Epoch != _stationReceiptEpoch) return;
            if (id is { } value) ObserveStationReceipt(scope.Owner, value, -1, true, authoritative: true);
            else foreach (var knownId in scope.Ids)
            {
                var key = ReceiptKey(scope.Owner, TradeNotificationEvent.KeyFor("station", knownId));
                if (_stationReceipts.TryGetValue(key, out var receipt))
                    _stationReceipts[key] = (receipt.Id, receipt.Type, true);
            }
        }
    }

    private void FinishStationRead(StationReadScope scope)
    {
        lock (_notificationTradeGate)
        {
            if (_stationPendingReads.Remove(scope)) _stationReadRevision++;
            scope.Completed.TrySetResult();
        }
    }

    private void RegisterStationPage(StationReadScope scope, JsonElement list, Func<bool> current, object lifetimeGate,
        bool inboxPoll = false)
    {
        var fresh = new List<TradeNotificationEvent>();
        lock (lifetimeGate)
        lock (_notificationTradeGate)
        {
            if (!current() || scope.Epoch != _stationReceiptEpoch || scope.Revision != _stationReadRevision) return;
            var baselined = _stationPollBaselines.Contains(scope.Owner);
            foreach (var row in list.EnumerateArray().Take(50))
            {
                var id = MarketplaceChat.Id(row, "id");
                var type = MarketplaceTradePolicy.Number(row, "type") ?? -1;
                if (id <= 0 || type is < 0 or > 2 || !StationReadFlag(row, out var read)) continue;
                var polledKey = ReceiptKey(scope.Owner, TradeNotificationEvent.KeyFor("station", id));
                if (_stationPendingReads.Any(x => x.Owner == scope.Owner && (x.Type is null || x.Type == type)))
                {
                    // A mark-read is in flight for this type: no receipt yet, but the poll has now seen
                    // the row, so a failed mark-read can never turn it into a "new" card later.
                    if (inboxPoll && _stationPolled.Count < 8192) _stationPolled.Add(polledKey);
                    continue;
                }
                var unread = ObserveStationReceipt(scope.Owner, id, type, read, authoritative: true);
                if (!inboxPoll) continue;
                var firstSeen = _stationPolled.Count < 8192 && _stationPolled.Add(polledKey);
                if (!unread || !firstSeen || !baselined || !IsStationTradeNotification(row) || fresh.Count >= 10) continue;
                if (ProjectTradeNotification(scope.Owner, row) is { } notice) fresh.Add(notice);
            }
            if (inboxPoll && _stationPollBaselines.Count < 4096) _stationPollBaselines.Add(scope.Owner);
        }
        var epoch = scope.Epoch;
        bool StillCurrent()
        {
            lock (_notificationTradeGate) return epoch == _stationReceiptEpoch && current();
        }
        // Oldest first, so several new messages in one read appear in the order they happened.
        for (var i = fresh.Count - 1; i >= 0; i--)
            try { StationTradeDiscovered?.Invoke(scope.Owner, fresh[i], StillCurrent); } catch { /* A card never breaks the inbox read. */ }
    }

    private static bool StationReadFlag(JsonElement row, out bool read)
    {
        read = false;
        if (row.ValueKind != JsonValueKind.Object || !row.TryGetProperty("isRead", out var flag)) return false;
        if (flag.ValueKind is JsonValueKind.True or JsonValueKind.False) { read = flag.GetBoolean(); return true; }
        if (flag.ValueKind == JsonValueKind.Number && flag.TryGetInt32(out var n) && n is 0 or 1) { read = n == 1; return true; }
        return false;
    }

    // SCM has no verified per-ID read endpoint. Search bounded pages without assuming ID order.
    // Only an explicit authoritative read flag releases a quarantined frame. Missing/failed/bounded
    // lookups stay silent and may be retried by a later duplicate; never retry a write or replay REST history.
    internal async Task<TradeNotificationEvent?> ReconcileStationPushAsync(ScmOAuthSession session, JsonElement row,
        Func<bool> current, object lifetimeGate, CancellationToken token)
    {
        if (!IsStationTradeNotification(row)) return null;
        var owner = ChatOwner(session);
        var id = MarketplaceChat.Id(row, "id");
        var type = MarketplaceTradePolicy.Number(row, "type") ?? -1;
        if (id <= 0 || type is < 0 or > 2) return null;
        var key = ReceiptKey(owner, TradeNotificationEvent.KeyFor("station", id));
        StationReadScope scope;
        Task[] pending;
        lock (lifetimeGate)
        lock (_notificationTradeGate)
        {
            if (!current()) return null;
            if (_stationReceipts.ContainsKey(key) || !NeedsStationReadback(owner, type)) return ProjectTradeNotification(owner, row);
            if (_stationReceipts.Count >= 8192 || _stationReconciliations.Count >= 8192 || !_stationReconciliations.Add(key)) return null;
            scope = CaptureStationRead(owner, current, lifetimeGate);
            pending = _stationPendingReads.Where(x => x.Owner == owner && (x.Type is null || x.Type == type)).Select(x => x.Completed.Task).ToArray();
        }
        try
        {
            await Task.WhenAll(pending).WaitAsync(token).ConfigureAwait(false);
            lock (lifetimeGate)
            lock (_notificationTradeGate)
            {
                if (!current() || scope.Epoch != _stationReceiptEpoch) return null;
                scope = CaptureStationRead(owner, current, lifetimeGate);
            }
            var active = await EnsureActiveSessionAsync(session, token).ConfigureAwait(false);
            if (ChatOwner(active) != owner || !active.Capabilities.Contains("profile.read", StringComparer.Ordinal)) return null;
            // At most 8192 rows, matching the receipt bound. A message outside this window stays silent.
            for (var page = 1; page <= 164; page++)
            {
                var data = await HallSendAsync(active, "marketplace-notices", "page", System.Net.Http.HttpMethod.Get,
                    $"member/message/page?pageNo={page}&pageSize=50&type={type}", null, current, token).ConfigureAwait(false);
                if (data.ValueKind != JsonValueKind.Object || !data.TryGetProperty("list", out var list) || list.ValueKind != JsonValueKind.Array) return null;
                foreach (var found in list.EnumerateArray().Take(Math.Min(50, 8192 - (page - 1) * 50)))
                {
                    if (MarketplaceChat.Id(found, "id") != id || MarketplaceTradePolicy.Number(found, "type") != type || !StationReadFlag(found, out var read)) continue;
                    lock (lifetimeGate)
                    lock (_notificationTradeGate)
                    {
                        if (!current() || scope.Epoch != _stationReceiptEpoch || scope.Revision != _stationReadRevision ||
                            _stationPendingReads.Any(x => x.Owner == owner && (x.Type is null || x.Type == type))) return null;
                        if (!ObserveStationReceipt(owner, id, type, read, authoritative: true)) return null;
                        return ProjectTradeNotification(owner, found);
                    }
                }
                if (list.GetArrayLength() < 50) return null;
            }
            return null;
        }
        catch (Exception e) when (e is System.Net.Http.HttpRequestException or OperationCanceledException or
            ScmApiProtocolException or JsonException or Account.AccountBridgeHostException) { return null; }
        finally
        {
            lock (_notificationTradeGate)
                if (scope.Epoch == _stationReceiptEpoch) _stationReconciliations.Remove(key);
        }
    }

    private static string SafeNotificationText(JsonElement row, string text)
    {
        var order = row.TryGetProperty("orderInfo", out var info) && info.ValueKind == JsonValueKind.Object ? info : default;
        var legacy = TradeNotificationEvent.JavaStationText(row, MarketplaceTradePolicy.Number(row, "subType") ?? 0,
            MarketplaceTradePolicy.Number(row, "type") == 0 && TradeNotificationEvent.TextField(row, "title") == "收货提醒");
        foreach (var id in new[] { TradeNotificationEvent.TextField(row, "transactionId"),
            TradeNotificationEvent.TextField(order, "transactionId"), legacy.Number,
            TradeNotificationEvent.TextField(order, "orderNumber"),
            MarketplaceChat.Id(row, "userId").ToString(), MarketplaceChat.Id(row, "senderId").ToString(),
            MarketplaceChat.Id(order, "traderId").ToString() }.Where(v => v.Length > 0 && v != "0"))
            text = text.Replace(id, "…", StringComparison.OrdinalIgnoreCase);
        return TradeNotificationEvent.SafeText(text);
    }
}
