namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameplayTimeRuntime
{
    public async Task PublishCurrentGameplayAsync(CancellationToken cancellation = default)
    {
        using var work = _work.Enter(default);
        if (work is null || _historyRemote is null || !await _historyGate.WaitAsync(0, cancellation)) return;
        try
        {
            (StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation) owner;
            lock (_sync)
            {
                var entry = !work.IsCurrent ? null : Resolve();
                if (entry?.Saved is not { Consent: GameplayRecordingConsent.Allowed, PendingReset: null, PendingImport: null } ||
                    entry.Error is not null) return;
                owner = _active;
            }
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellation, work.Token);
            budget.CancelAfter(TimeSpan.FromSeconds(15));
            bool Current() => OwnerIsCurrent(owner, budget.Token);
            if (!Current()) return;
            var state = await _historyRemote.ReadAsync(owner.Context!, budget.Token).ConfigureAwait(false);
            StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract update;
            lock (_sync)
            {
                if (!Current()) return;
                var entry = Resolve()!;
                var saved = entry.Saved!;
                if (saved.PendingImport is not null || saved.PendingReset is not null ||
                    entry.Desired != GameplayRecordingConsent.Allowed || entry.Error is not null) return;
                var epoch = state.LastExpectedRevision is { } expected ? checked(expected + 1) : 0;
                if (epoch != (saved.AppliedResetRevision ?? 0)) return;
                // Remote history metadata is authoritative, including imports from another device.
                var seconds = Math.Max(saved.Seconds, state.PlayTimeSeconds);
                var visible = saved.ShowOnProfile ?? state.IsPublic;
                if (seconds == state.PlayTimeSeconds && visible == state.IsPublic) return;
                update = new(visible, seconds, 0, 0, state.HistoricalPlayTimeSeconds,
                    state.HistoricalSessionCount, state.HistoricalIncompleteSessionCount, state.HistoryImportedAt,
                    state.Revision, state.LastOperationId, state.HistoryImportOperationId);
            }
            if (Current()) await _historyRemote.PublishGameplayStatisticsAsync(owner.Context!, update, budget.Token).ConfigureAwait(false);
            // No replay on conflict or unknown outcome. The next tick reads authority afresh.
        }
        catch (Exception error) when (error is not OutOfMemoryException) { }
        finally { _historyGate.Release(); }
    }
}
