using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

/// <summary>Transport must bind both methods to the supplied authenticated owner; it must never replay POST.</summary>
public interface IGameplayTimeResetRemote
{
    Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken cancellation);
    Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request,
        CancellationToken cancellation);
}

public sealed partial class GameplayTimeRuntime
{
    public async Task RecoverResetAsync(IGameplayTimeResetRemote remote)
    {
        await RecoverHistoryImportAsync().ConfigureAwait(false);
        try
        {
            (BridgeAccountContext? Context, long Generation) owner;
            bool pending;
            lock (_sync)
            {
                if (_disposed) return;
                var entry = Resolve();
                if (entry?.Saved is null) return;
                pending = entry.Saved.PendingReset is not null;
                owner = _active;
            }
            if (pending) await ResetAsync(owner.Context!, owner.Generation, null, remote).ConfigureAwait(false);
            else await ObserveAccountResetAsync(owner.Context!, owner.Generation, remote).ConfigureAwait(false);
            await PublishCurrentGameplayAsync().ConfigureAwait(false);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // Background recovery preserves pending state; never turn a timer failure into a second POST.
        }
    }

    private async Task ObserveAccountResetAsync(BridgeAccountContext context, long generation, IGameplayTimeResetRemote remote)
    {
        if (!await _historyGate.WaitAsync(0)) return;
        try
        {
            using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            bool Current() => !_disposed && !budget.IsCancellationRequested && _current() == (context, generation);
            if (!Current()) return;
            var state = await remote.ReadAsync(context, budget.Token).ConfigureAwait(false);
            if (state.SchemaVersion != 1 || state.LastOperationId is null ||
                !Guid.TryParseExact(state.LastOperationId, "N", out _) || state.LastExpectedRevision is not { } expected ||
                expected < 0 || expected >= state.Revision) return;
            var epoch = checked(expected + 1);
            lock (_sync)
            {
                if (!Current()) return;
                var entry = Resolve();
                if (entry?.Saved is not { } saved || entry.Error is not null || saved.PendingReset is not null ||
                    epoch <= (saved.AppliedResetRevision ?? 0)) return;
                entry.Accumulator.Suspend();
                entry.Saved = entry.Lease!.ApplyAccountReset(saved, epoch, Current);
                entry.FirstRecordedAt = null;
                entry.HistoryState = "unchecked";
                _historyTicket = null;
                entry.Accumulator.Restore(context, generation, entry.Desired, 0);
            }
        }
        finally { _historyGate.Release(); }
    }

    /// <summary>Internal orchestration, not yet exposed as a Bridge capability. A null revision only recovers an existing operation.</summary>
    public async Task<string> ResetAsync(BridgeAccountContext context, long generation,
        long? confirmedRevision, IGameplayTimeResetRemote remote, CancellationToken cancellation = default)
    {
        if (!await _historyGate.WaitAsync(0, cancellation)) return "busy";
        try
        {
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            budget.CancelAfter(TimeSpan.FromSeconds(20));
            var token = budget.Token;
            var owner = (Context: (BridgeAccountContext?)context, Generation: generation);
            bool Current() => !_disposed && !token.IsCancellationRequested && _current() == owner;
            Entry entry;
            GameplayPendingReset pending;
            bool submit;
            lock (_sync)
            {
                if (!Current()) return "accountChanged";
                entry = Resolve()!;
                if (entry.Saved is null || entry.Error is not null) return "unavailable";
                submit = entry.Saved.PendingReset is null;
                if (submit && confirmedRevision is null) return "idle";
                if (submit)
                {
                    if (confirmedRevision < 0) return "invalid";
                    entry.Accumulator.Suspend();
                    Persist(entry, Current);
                    pending = new(Guid.NewGuid().ToString("N"), confirmedRevision!.Value, _time.GetUtcNow().AddMinutes(2));
                    // Journal before the single remote write. A crash must never cause that write to be replayed.
                    entry.Saved = entry.Lease!.BeginReset(entry.Saved!, pending, Current);
                    _historyTicket = null;
                }
                else pending = entry.Saved.PendingReset!;
            }

            GameplayTimeResetState? state = null;
            bool rejected = false;
            if (submit)
            {
                try
                {
                    if (!Current()) return "accountChanged";
                    var result = await remote.ResetAsync(context,
                        new(1, pending.ExpectedRevision, pending.OperationId, pending.ExpiresAt), token).ConfigureAwait(false);
                    state = result.State;
                    rejected = result.Outcome == "conflict";
                }
                catch (Exception e) when (e is not OutOfMemoryException)
                {
                    // The outcome is unknown. Only a read may follow; never retry the destructive request.
                }
            }
            if (!Current()) return "accountChanged";
            if (!Matches(state, pending) && !rejected)
            {
                try { state = await remote.ReadAsync(context, token).ConfigureAwait(false); }
                catch (Exception e) when (e is not OutOfMemoryException) { return Current() ? "pending" : "accountChanged"; }
            }
            lock (_sync)
            {
                if (!Current()) return "accountChanged";
                // A later account-wide reset also supersedes this device's pending operation.
                // Observing it is safe even when this operation's response was lost.
                var superseded = state is { SchemaVersion: 1, LastExpectedRevision: { } resetExpected } &&
                    resetExpected >= pending.ExpectedRevision && resetExpected < state.Revision &&
                    resetExpected + 1 > (entry.Saved!.AppliedResetRevision ?? 0) &&
                    Guid.TryParseExact(state.LastOperationId, "N", out _);
                var confirmed = Matches(state, pending) || superseded;
                // GET shares the server's write gate. After its observed deadline,
                // a request without a matching receipt can no longer commit late.
                rejected |= !confirmed && pending.ExpiresAt is { } expiry &&
                    state?.ObservedAt is { } observed && observed >= expiry;
                if (!confirmed && !rejected) return "pending";
                entry.Saved = entry.Lease!.FinishReset(entry.Saved!, pending, confirmed, Current,
                    confirmed ? checked(state!.LastExpectedRevision!.Value + 1) : null);
                entry.FirstRecordedAt = entry.Saved.FirstRecordedAt;
                entry.HistoryState = entry.Saved.HistoryImportedAt is not null || entry.Saved.HistoryConsumed == true
                    ? "imported" : "unchecked";
                entry.Accumulator.Restore(context, generation, entry.Desired, entry.Saved.Seconds);
                return confirmed ? "completed" : "conflict";
            }
        }
        catch (GameplayTimeException) { return "unavailable"; }
        finally { _historyGate.Release(); }
    }

    private static bool Matches(GameplayTimeResetState? state, GameplayPendingReset pending) =>
        state is { SchemaVersion: 1 } && state.Revision > pending.ExpectedRevision &&
        state.LastOperationId == pending.OperationId && state.LastExpectedRevision == pending.ExpectedRevision;
}
