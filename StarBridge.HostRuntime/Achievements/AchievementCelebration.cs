namespace StarBridge.HostRuntime.Achievements;

using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

// Presentation only. Neither this contract nor its Windows sink can grant or reset an award.
public sealed record AchievementCelebration(string AchievementId, DateTimeOffset EarnedAt,
    long Generation, Func<bool> IsCurrent, int Rank = 0, string? DisplayName = null, string? LocalImagePath = null, string? Receipt = null)
{
    internal CelebrationReceiptAcceptance? Acceptance { get; init; }
    // Native sinks must call this synchronously before queue admission. A
    // duplicate returns false; an IO failure leaves the producer retryable.
    public bool TryAcceptReceipt() => Acceptance?.TryAccept() ?? true;
    public bool CanPresent => HangarAchievementPolicy.Known(AchievementId) || JourneyAchievementPolicy.IsKnown(AchievementId) ||
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
    internal void FirstEntryEarned(long generation, DateTimeOffset at) => SeriesEarned(generation, FirstEntryAchievementPolicy.Id, 0, at);
    internal void ScmEarned(long generation, string id, DateTimeOffset at, string name, string? image, string? receipt = null) =>
        Deliver(generation, id, 0, at, name, image, receipt);
    internal void SeriesEarned(long generation, string id, int rank, DateTimeOffset at)
        => Deliver(generation, id, rank, at);
    private void Deliver(long generation, string id, int rank, DateTimeOffset at, string? name = null, string? image = null, string? receipt = null)
    {
        lock (_gate)
        {
            var captured = owner();
            if (_disposed || captured.Context is not { IsComplete: true } || captured.Generation != generation ||
                at.Offset != TimeSpan.Zero || !new AchievementCelebration(id, at, generation, () => true, rank, name, image).CanPresent ||
                (ScmAchievementPresentation.ValidId(id) || id == FirstEntryAchievementPolicy.Id || JourneyAchievementPolicy.IsKnown(id) ? rank != 0 : rank is < 1 or > 5) ||
                _receipts.Contains((generation, id, rank, at))) return;
            var notice = new AchievementCelebration(id, at, generation,
                () => !_disposed && owner() == captured, rank, name, image, receipt);
            if (receipt is not null && _receiptStore is not null)
                notice = notice with { Acceptance = new(() => _receiptStore.TryAccept(captured.Context, receipt,
                    () => !_disposed && owner() == captured)) };
            // Only the authenticated newly-earned callback enters here. There is
            // intentionally no DND, notification permission, or client award request.
            if (_sink is { } sink) sink.Submit(notice);
            else
            {
                if (receipt is null || !_pending.Any(p => p.Receipt == receipt)) _pending.Add(notice);
                if (receipt is not null) throw new InvalidOperationException("Celebration sink is not configured.");
            }
            _receipts.Add((generation, id, rank, at));
        }
    }
    internal void Invalidate(long generation)
    {
        lock (_gate) { _pending.Clear(); _receipts.Clear(); _sink?.Clear(); }
    }
    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true; _pending.Clear(); _receipts.Clear(); _sink?.Clear(); _sink = null;
        }
    }
}
