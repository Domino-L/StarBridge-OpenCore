using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameplayTimeRuntime
{
    public async Task PublishCurrentGameplayAsync(CancellationToken cancellation = default)
    {
        using var work = _work.Enter(default);
        if (work is null || (_historyRemote is null && _visitorGameplayTime is null) ||
            !await _historyGate.WaitAsync(0, cancellation)) return;
        (BridgeAccountContext? Context, long Generation) owner = default;
        var readCompleted = false;
        VisitorGameplayTime? visitorValue = null;
        // Contract af70120d: with no account total, 104 sends nothing, not even this PC's total (SCM-only
        // accounts, no adapter, an adapter reporting "unsupported"). 0.7.4 decides SCM-only from the Host's own
        // legacy link state (TODO-074); until then a local total could overwrite a linked account's HK copy.
        const bool localAllowed = false;
        try
        {
            lock (_sync)
            {
                var entry = !work.IsCurrent ? null : Resolve();
                if (entry is null) return;
                owner = _active;
            }
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellation, work.Token);
            budget.CancelAfter(TimeSpan.FromSeconds(15));
            bool Current() => OwnerIsCurrent(owner, budget.Token);
            if (!Current() || _historyRemote is null) return;
            var state = await _historyRemote.ReadAsync(owner.Context!, budget.Token).ConfigureAwait(false);
            visitorValue = new(state.PlayTimeSeconds, state.Revision);
            Entry observed;
            lock (_sync)
            {
                if (!Current()) return;
                observed = Resolve()!;
            }
            await ObservePublishedTotalAsync(observed, state, owner, budget.Token).ConfigureAwait(false);
            readCompleted = true;
            StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract update;
            lock (_sync)
            {
                if (!Current()) return;
                var entry = Resolve()!;
                if (entry.Saved is not { } saved) return;
                if (saved.PendingImport is not null || saved.PendingReset is not null ||
                    entry.Desired != GameplayRecordingConsent.Allowed || entry.Error is not null) return;
                var epoch = state.LastExpectedRevision is { } expected ? checked(expected + 1) : 0;
                if (epoch != (saved.AppliedResetRevision ?? 0)) return;
                // Remote history metadata is authoritative, including imports from another device.
                var seconds = Math.Max(saved.Seconds, state.PlayTimeSeconds);
                // User 11-08: "个人页应该统一用个人页的隐私来，游戏时间也不应该单独占一个设置隐私".
                // The total is always published as public; the HK visitor read already admits a page
                // only within its visibility. A saved ShowOnProfile is read and kept, never applied.
                const bool visible = true;
                if (seconds == state.PlayTimeSeconds && visible == state.IsPublic) return;
                update = new(visible, seconds, 0, 0, state.HistoricalPlayTimeSeconds,
                    state.HistoricalSessionCount, state.HistoricalIncompleteSessionCount, state.HistoryImportedAt,
                    state.Revision, state.LastOperationId, state.HistoryImportOperationId);
            }
            // The visitor copy keeps this round's GET pair: the PUT acknowledgement exposes no revision, and the
            // written total under the pre-write revision would let a stale device overwrite it on HK (R4). The new
            // total reaches HK with the next GET, which carries its own revision.
            if (Current()) await _historyRemote.PublishGameplayStatisticsAsync(owner.Context!, update, budget.Token).ConfigureAwait(false);
            // No replay on conflict or unknown outcome. The next tick reads authority afresh.
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync)
            {
                // A failed GET invalidates the previous observation. A later
                // failed PUT cannot erase the total successfully read this round.
                if (!readCompleted && work.IsCurrent && OwnerIsCurrent(owner) && owner.Context is { } context &&
                    _entries.TryGetValue(context, out var entry))
                    SetAccountTotal(entry, new("unavailable"));
            }
        }
        finally
        {
            try { QueueVisitorGameplayTime(owner, visitorValue, cancellation, localAllowed); }
            finally { _historyGate.Release(); }
        }
    }

    private static long? LocalDisplayedSeconds(Entry entry) =>
        entry.Saved is null ? null : entry.Accumulator.PlayTimeSeconds;

    // Without fresh Japanese authority (contract 1, revised 11-21): the last pair Japan reported, with its
    // revision, so a stale total never overwrites a newer reset written by another device. A total without
    // a Japanese revision waits for the next authoritative read. This PC's total (no revision) is reserved for
    // 0.7.4's SCM-only accounts; 104 always passes localAllowed: false.
    private static VisitorGameplayTime? OwnerShownTotal(Entry entry, bool localAllowed) =>
        entry.LastJapanAuthority ??
        (localAllowed && LocalDisplayedSeconds(entry) is { } local ? new VisitorGameplayTime(local, null) : null);

    private void QueueVisitorGameplayTime((BridgeAccountContext? Context, long Generation) owner,
        VisitorGameplayTime? authoritative, CancellationToken cancellation, bool localAllowed)
    {
        if (_visitorGameplayTime is null || owner.Context is not { } context) return;
        try
        {
            lock (_sync)
            {
                // The Japan budget may have expired. Recheck ownership against the caller instead.
                if (!OwnerIsCurrent(owner, cancellation) || _active != owner || !_entries.TryGetValue(context, out var entry)) return;
                if (authoritative is { } fresh) entry.LastJapanAuthority = fresh;
                var value = authoritative ?? OwnerShownTotal(entry, localAllowed);
                if (value is { } snapshot) _visitorGameplayTime.Submit(context, owner.Generation, snapshot);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // Admission to the visitor lane must never affect the Japan result or local accounting.
        }
    }
}
