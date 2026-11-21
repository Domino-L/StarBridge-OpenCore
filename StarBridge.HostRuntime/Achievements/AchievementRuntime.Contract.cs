using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

internal sealed partial class AchievementRuntime
{
    private readonly ContractAchievementStore? _contractStore;
    private readonly ContractRecordStore? _contractRecords;
    private Dictionary<string, ContractRecordLines>? ReadContractRecords(BridgeAccountContext owner, AchievementSnapshot? snapshot)
    {
        if (_contractRecords is null || snapshot is null) return null;
        try { return _contractRecords.ReadLines(owner, snapshot); }
        catch (Exception error) when (ContractRecordStore.IsStorageError(error)) { return null; }
    }
    private sealed record ContractRetry(int Failures, long NextAttempt, ContractAchievementReceipt? Receipt);
    private readonly Dictionary<string, ContractRetry> _contractRetries = [];
    private long _contractStoreRetryAt;

    // Sampling already atomically persisted the completed run and pending observation.
    internal void ContractQueued() { Interlocked.Exchange(ref _nextAttempt, 0); Wake(); }

    private async Task<AchievementSnapshot> UpdateContractsAsync(BridgeAccountContext owner, long generation,
        AchievementSnapshot snapshot, Func<bool> current, CancellationToken token)
    {
        if (_contractStore is null) return snapshot;
        var pending = ReadContractPending(owner);
        foreach (var observation in pending)
        {
            token.ThrowIfCancellationRequested(); if (!current()) return snapshot;
            var retry = _contractRetries.GetValueOrDefault(observation.MissionId);
            if (retry is not null && _time.GetUtcNow().UtcTicks < retry.NextAttempt) continue;
            ContractAchievementReceipt? acknowledged = retry?.Receipt;
            try
            {
                // Every mission requires an acknowledgement even when contract-first is already earned.
                var receipt = acknowledged ?? await _remote.ObserveContractAsync(owner, generation, observation, token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested(); if (!current()) return snapshot;
                receipt.Validate();
                if (!receipt.EarnedAt.ContainsKey("contract-first")) throw new InvalidDataException("Contract acknowledgement is missing.");
                if (acknowledged is null)
                {
                    try { _contractRecords?.Confirm(owner, observation, receipt, current); }
                    catch (Exception error) when (ContractRecordStore.IsStorageError(error)) { }
                    foreach (var id in receipt.NewlyEarned)
                        if (ContractAchievementPolicy.IsAward(id) && current()) _seriesEarned?.Invoke(generation, id, 0, receipt.EarnedAt[id]);
                }
                acknowledged = receipt;
                snapshot = snapshot.MergeConfirmed(receipt.Snapshot);
                using var lease = _contractStore.Open(owner); var state = lease.Read();
                lease.Save(new(state.Runs.Select(r => r.MissionId == observation.MissionId && r.Pending == observation
                    ? r with { Pending = null, Confirmed = true } : r).ToArray()), current);
                _contractRetries.Remove(observation.MissionId);
            }
            catch (Exception error) when (error is not OperationCanceledException and not Account.AccountBridgeHostException && !token.IsCancellationRequested && current())
            {
                var failures = Math.Min(5, (retry?.Failures ?? 0) + 1);
                var delay = AchievementObservationRetry.DelaySeconds(error, failures);
                _contractRetries[observation.MissionId] = new(failures, _time.GetUtcNow().AddSeconds(delay).UtcTicks, acknowledged);
            }
        }
        return snapshot;
    }
    private long? NextContractAttempt(BridgeAccountContext owner)
    {
        if (_contractStore is null) return null;
        var pending = ReadContractPending(owner);
        if (_contractStoreRetryAt > _time.GetUtcNow().UtcTicks) return _contractStoreRetryAt;
        return pending.Select(r => (long?)(_contractRetries.GetValueOrDefault(r.MissionId)?.NextAttempt ?? 0)).Min();
    }
    private ContractObservation[] ReadContractPending(BridgeAccountContext owner)
    {
        if (_contractStore is null || _contractStoreRetryAt > _time.GetUtcNow().UtcTicks) return [];
        try
        {
            using var lease = _contractStore.Open(owner);
            var pending = lease.Read().Runs.Where(r => r.Pending is not null).Select(r => r.Pending!).ToArray();
            _contractStoreRetryAt = 0; return pending;
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            _contractStoreRetryAt = _time.GetUtcNow().AddSeconds(error is InvalidDataException or System.Text.Json.JsonException ? 300 : 30).UtcTicks;
            return []; // Contract storage cannot suppress independently confirmed journey/hangar snapshots.
        }
    }
}
