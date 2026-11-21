namespace StarBridge.HostRuntime.Achievements;

using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

// Presentation only. Neither this contract nor its Windows sink can grant or reset an award.
public sealed record AchievementCelebration(string AchievementId, DateTimeOffset EarnedAt,
    long Generation, Func<bool> IsCurrent, int Rank = 0, string? DisplayName = null, string? LocalImagePath = null, string? Receipt = null)
{
    public ContractRecordLines? ContractRecord { get; init; }
    // SCM summary card: how many further unlocks it stands for (build 105).
    public int SummaryCount { get; init; }
    public string? RarityTier { get; init; }
    public int? RarityBasisPoints { get; init; }
    internal CelebrationReceiptAcceptance? Acceptance { get; init; }
    internal Action? Presented { get; init; }
    // Native sinks call this synchronously before queue admission. It writes
    // nothing: a receipt already shown, or no longer pending, returns false.
    public bool TryAcceptReceipt() => Acceptance?.TryAccept() ?? true;
    // The receiver calls this once the card has completed its visible dwell.
    // Only then is an SCM unlock recorded as celebrated (user 11-21). It never
    // throws into the receiver and never blocks it on storage.
    public void MarkPresented() { try { Presented?.Invoke(); } catch { /* The unlock stays pending and is shown again. */ } }
    public bool CanPresent => HangarAchievementPolicy.Known(AchievementId) || JourneyAchievementPolicy.IsAward(AchievementId) || ContractAchievementPolicy.IsAward(AchievementId) ||
        AchievementId == ScmAchievementPresentation.SummaryId && SummaryCount is >= 1 and <= 4096 ||
        ScmAchievementPresentation.ValidId(AchievementId) && DisplayName is { Length: > 0 and <= 160 } &&
        !string.IsNullOrWhiteSpace(DisplayName) && !DisplayName.Any(char.IsControl);
}

internal sealed class CelebrationReceiptAcceptance(Func<bool> accept)
{
    internal bool TryAccept() => accept();
}

public interface IAchievementCelebrationSink
{
    // Call notice.TryAcceptReceipt synchronously before admission. A false
    // result is an already accepted receipt, acknowledged without re-enqueueing.
    void Submit(AchievementCelebration notice);
    void Clear();
}

internal sealed class AchievementCelebrationDelivery(
    Func<(BridgeAccountContext? Context, long Generation)> owner, string? receiptRoot = null) : IDisposable
{
    private readonly ScmAchievementUnlockStore? _receiptStore = receiptRoot is null ? null : new(receiptRoot);
    private readonly object _gate = new();
    private readonly HashSet<(long Generation, string Id, int Rank, DateTimeOffset At)> _receipts = [];
    // Every SCM unlock receipt already queued in this generation, whether as a
    // single card or inside a summary (R1 P2): no receipt is queued twice.
    private readonly HashSet<(long Generation, string Receipt)> _queued = [];
    private IAchievementCelebrationSink? _sink;
    private readonly List<AchievementCelebration> _pending = [];
    private volatile bool _disposed;

    internal void Configure(IAchievementCelebrationSink sink)
    {
        ArgumentNullException.ThrowIfNull(sink);
        lock (_gate)
        {
            if (_disposed) return;
            _sink = sink;
            foreach (var pending in _pending.Where(p => p.IsCurrent())) _sink.Submit(pending);
            _pending.Clear();
        }
    }
    internal void FirstEntryEarned(long generation, DateTimeOffset at, (string? Tier, int? BasisPoints) rarity = default) =>
        SeriesEarned(generation, FirstEntryAchievementPolicy.Id, 0, at, rarity: rarity);
    internal void ScmEarned(long generation, string id, DateTimeOffset at, string name, string? image, string? receipt = null, string? rarity = null) =>
        Deliver(generation, id, 0, at, name, image, receipt, rarity: (rarity, null));
    // One card standing for several SCM unlocks; showing it acknowledges all of them.
    internal void ScmSummary(long generation, IReadOnlyList<string> receipts, DateTimeOffset at)
    {
        // Members already queued (as single cards or an earlier summary) are not
        // repeated; the summary stands only for the rest.
        string[] members;
        lock (_gate) members = receipts.Distinct(StringComparer.Ordinal).Where(r => !_queued.Contains((generation, r))).ToArray();
        if (members.Length > 0)
            Deliver(generation, ScmAchievementPresentation.SummaryId, 0, at, receipt: string.Join('|', members), summary: members);
    }
    internal void SeriesEarned(long generation, string id, int rank, DateTimeOffset at, ContractRecordLines? record = null,
        (string? Tier, int? BasisPoints) rarity = default)
        => Deliver(generation, id, rank, at, record: record, rarity: rarity);
    private void Deliver(long generation, string id, int rank, DateTimeOffset at, string? name = null, string? image = null, string? receipt = null,
        ContractRecordLines? record = null, IReadOnlyList<string>? summary = null, (string? Tier, int? BasisPoints) rarity = default)
    {
        lock (_gate)
        {
            var captured = owner();
            if (_disposed || captured.Context is not { IsComplete: true } || captured.Generation != generation ||
                at.Offset != TimeSpan.Zero || !new AchievementCelebration(id, at, generation, () => true, rank, name, image) { SummaryCount = summary?.Count ?? 0 }.CanPresent ||
                (ScmAchievementPresentation.ValidId(id) || id == ScmAchievementPresentation.SummaryId || id == FirstEntryAchievementPolicy.Id || JourneyAchievementPolicy.IsAward(id) || ContractAchievementPolicy.IsAward(id) ? rank != 0 : rank is < 1 or > 5) ||
                _receipts.Contains((generation, id, rank, at)) ||
                (summary ?? (receipt is null ? [] : [receipt])).Any(r => _queued.Contains((generation, r)))) return;
            var notice = new AchievementCelebration(id, at, generation,
                () => !_disposed && owner() == captured, rank, name, image, receipt)
            {
                ContractRecord = record, SummaryCount = summary?.Count ?? 0,
                RarityTier = rarity.Tier, RarityBasisPoints = rarity.BasisPoints
            };
            if (receipt is not null && _receiptStore is not null)
            {
                IReadOnlyList<string> receipts = summary ?? [receipt];
                var store = _receiptStore; var account = captured.Context;
                notice = notice with {
                    Acceptance = new(() => Admissible(store, account, receipts, () => !_disposed && owner() == captured)),
                    // Off the receiver's thread; a lock held by the producer's serial
                    // worker is waited out briefly. A lost write shows the card again.
                    Presented = () => _ = Task.Run(() => Acknowledge(store, account, receipts)) };
            }
            // Only the authenticated newly-earned callback enters here. There is
            // intentionally no DND, notification permission, or client award request.
            if (_sink is { } sink) sink.Submit(notice);
            else
            {
                // An SCM card stays in the durable Pending store and is drained again
                // once the sink exists; caching it here would bypass member reservation.
                if (receipt is not null) throw new InvalidOperationException("Celebration sink is not configured.");
                _pending.Add(notice);
            }
            if (summary is null) _receipts.Add((generation, id, rank, at));
            foreach (var queued in summary ?? (receipt is null ? [] : [receipt])) _queued.Add((generation, queued));
        }
    }
    // Runs inside this class's lock (the receiver admits synchronously), so it
    // waits only briefly (R1 P2). If an acknowledgement still holds the account
    // file, admit: showing a card twice is better than losing it.
    private static bool Admissible(ScmAchievementUnlockStore store, BridgeAccountContext account, IReadOnlyList<string> receipts, Func<bool> current)
    {
        try { return store.CanAdmit(account, receipts, current); }
        catch (IOException error) when (ScmAchievementUnlockStore.IsSharingViolation(error)) { return true; }
    }
    private static void Acknowledge(ScmAchievementUnlockStore store, BridgeAccountContext account, IReadOnlyList<string> receipts)
    {
        for (var attempt = 0; attempt < 40; attempt++)
        {
            try { store.MarkPresented(account, receipts, () => true); return; }
            catch (IOException) { Thread.Sleep(50); }
            catch (Exception error) when (error is UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException) { return; }
        }
    }
    internal void Invalidate(long generation)
    {
        lock (_gate) { _pending.Clear(); _receipts.Clear(); _queued.Clear(); _sink?.Clear(); }
    }
    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true; _pending.Clear(); _receipts.Clear(); _queued.Clear(); _sink?.Clear(); _sink = null;
        }
    }
}
