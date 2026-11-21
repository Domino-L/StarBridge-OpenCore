using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

// Percentages are basis points, calculated by the backend over active accounts.
public sealed record AchievementRarity(int SchemaVersion, int WindowDays, int ActiveAccounts,
    DateTimeOffset ComputedAt, Dictionary<string, int> Percentages, [property: System.Text.Json.Serialization.JsonRequired] Dictionary<string, string> Tiers)
{
    internal (string? Tier, int? BasisPoints) ForCelebration(string id, int rank)
    {
        var key = rank > 0 ? FormattableString.Invariant($"{id}-{rank}") : id;
        return (Tiers.GetValueOrDefault(key), Percentages.TryGetValue(key, out var value) ? value : null);
    }

    public void Validate()
    {
        if (SchemaVersion != 1 || WindowDays != 30 || ActiveAccounts < 0 ||
            ComputedAt <= DateTimeOffset.UnixEpoch || ComputedAt.Offset != TimeSpan.Zero ||
            ComputedAt > DateTimeOffset.UtcNow.AddMinutes(5) || Percentages is null || Percentages.Count > 256 ||
            ActiveAccounts < 50 && Percentages.Count != 0 || Percentages.Any(p =>
                p.Key.Length is < 1 or > 64 || p.Key.Any(c => !(char.IsAsciiLetterOrDigit(c) || c == '-')) ||
                p.Value is < 0 or > 10000) || Tiers is null || Tiers.Count > 256 || Tiers.Any(t => !Percentages.ContainsKey(t.Key) || t.Value is not ("rare" or "veryRare"))) throw new InvalidDataException("Invalid achievement rarity.");
    }
}

internal sealed partial class AchievementRuntime
{
    private sealed record RarityPublication(BridgeAccountContext Owner, long Generation, AchievementRarity Value);
    private RarityPublication? _rarity;
    private readonly SemaphoreSlim _rarityGate = new(1);
    private (BridgeAccountContext? Context, long Generation) _rarityOwner;
    private long _rarityNextAttempt;

    internal AchievementRarity? ReadRarity((BridgeAccountContext? Context, long Generation) owner)
    {
        var value = Volatile.Read(ref _rarity);
        return _current() == owner && value is not null && value.Owner == owner.Context && value.Generation == owner.Generation ? value.Value : null;
    }

    // Independent budget and lifecycle: a slow/old backend never delays collection reads.
    internal async Task RefreshRarityAsync((BridgeAccountContext? Context, long Generation) owner)
    {
        using var work = _retirement.Enter(default);
        if (work is null || _disposed || owner.Context is null || !await _rarityGate.WaitAsync(0)) return;
        try
        {
            bool Current() => !_disposed && !work.Token.IsCancellationRequested && _current() == owner;
            if (!Current()) return;
            if (_rarityOwner != owner) { _rarityOwner = owner; _rarityNextAttempt = 0; }
            if (_time.GetUtcNow().UtcTicks < _rarityNextAttempt) return;
            _rarityNextAttempt = _time.GetUtcNow().AddHours(1).UtcTicks;
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
            budget.CancelAfter(TimeSpan.FromSeconds(8));
            AchievementRarity? value = null;
            try
            {
                value = await _remote.ReadRarityAsync(owner.Context, owner.Generation, budget.Token).ConfigureAwait(false);
                value?.Validate();
            }
            catch (Exception) when (!work.Token.IsCancellationRequested) { value = null; }
            if (!Current()) return;
            var previous = ReadRarity(owner);
            Volatile.Write(ref _rarity, value is null ? null : new(owner.Context, owner.Generation, value));
            if (previous is not null || value is not null) _changed(owner.Generation);
        }
        catch (OperationCanceledException) when (work.Token.IsCancellationRequested) { }
        finally { _rarityGate.Release(); }
    }
}
