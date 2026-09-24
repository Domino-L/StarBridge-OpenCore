using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public interface IGameplayHistoryRemote : IGameplayTimeResetRemote
{
    Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner,
        PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token);
}

public sealed partial class GameplayTimeRuntime
{
    // Caller holds the history gate, never the local state lock during network IO.
    private async Task<string> ConfirmRemoteHistoryAsync(BridgeAccountContext owner, long generation,
        string id, string handle, CancellationToken token)
    {
        bool Current() => !_disposed && !token.IsCancellationRequested && _current() == (owner, generation) &&
            string.Equals(handle, _verifiedHandle(), StringComparison.OrdinalIgnoreCase);
        var remote = _historyRemote!;
        var state = await remote.ReadAsync(owner, token).ConfigureAwait(false);
        GameplayPendingImport pending;
        lock (_sync)
        {
            if (!Current()) return "accountChanged";
            var entry = Resolve()!;
            var ticket = _historyTicket;
            if (ticket is null || ticket.Id != id || ticket.Owner != owner || ticket.Generation != generation ||
                ticket.Handle != handle || ticket.ExpiresAt <= _time.GetUtcNow()) return "previewExpired";
            if (state.HistoryImportedAt is not null || state.HistoryImportOperationId is not null) return "imported";
            var saved = entry.Saved!;
            var epoch = state.LastExpectedRevision is { } expected ? checked(expected + 1) : 0;
            if (epoch != (saved.AppliedResetRevision ?? 0)) return "unavailable";
            if (entry.Desired != GameplayRecordingConsent.Allowed) return "recordingRequired";
            Persist(entry, Current);
            if (entry.Error is not null) return "unavailable";
            // Retain the larger known baseline; never lower another device's published total.
            var total = checked(Math.Max(entry.Accumulator.PlayTimeSeconds, state.PlayTimeSeconds) + ticket.Preview.Seconds);
            pending = new(new(entry.ShowOnProfile, total, 0, 0, ticket.Preview.Seconds,
                ticket.Preview.Sessions, ticket.Preview.IncompleteSessions, _time.GetUtcNow(),
                state.Revision, state.LastOperationId, ticket.Id, _time.GetUtcNow().AddMinutes(2)));
            entry.Saved = entry.Lease!.BeginImport(entry.Saved!, pending, Current);
            entry.Accumulator.Suspend();
            _historyTicket = null;
        }
        try
        {
            var accepted = await remote.PublishGameplayStatisticsAsync(owner, pending.Update, token).ConfigureAwait(false);
            if (!accepted)
            {
                lock (_sync)
                {
                    if (!Current()) return "accountChanged";
                    var entry = Resolve()!;
                    entry.Saved = entry.Lease!.FinishImport(entry.Saved!, pending, false, Current);
                }
                return "unavailable";
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // An uncertain write remains journaled. Never send it again.
        }
        return await ReconcileHistoryImportAsync(owner, generation, remote, token).ConfigureAwait(false);
    }

    private async Task<string> ReconcileHistoryImportAsync(BridgeAccountContext owner, long generation,
        IGameplayHistoryRemote remote, CancellationToken token)
    {
        bool Current() => !_disposed && !token.IsCancellationRequested && _current() == (owner, generation);
        var state = await remote.ReadAsync(owner, token).ConfigureAwait(false);
        lock (_sync)
        {
            if (!Current()) return "accountChanged";
            var entry = Resolve()!;
            if (entry.Saved?.PendingImport is not { } pending) return "unavailable";
            var update = pending.Update;
            if (state.HistoryImportOperationId != update.HistoryImportOperationId &&
                update.ExpiresAt is { } expiry && state.ObservedAt is { } observed && observed >= expiry)
            {
                entry.Saved = entry.Lease!.FinishImport(entry.Saved, pending, false, Current);
                return "unavailable";
            }
            if (state.Revision > update.ExpectedGameplayRevision &&
                state.HistoryImportOperationId != update.HistoryImportOperationId &&
                (state.HistoryImportOperationId is not null || state.LastOperationId != update.ResetOperationId))
            {
                // Another accepted import or a newer reset superseded this pending
                // attempt. Do not add its history locally or resend it.
                entry.Saved = entry.Lease!.FinishImport(entry.Saved, pending, false, Current);
                return state.HistoryImportOperationId is not null ? "imported" : "unavailable";
            }
            if (state.HistoryImportOperationId != update.HistoryImportOperationId ||
                state.HistoryImportedAt != update.HistoryImportedAt ||
                state.HistoricalPlayTimeSeconds != update.HistoricalPlayTimeSeconds ||
                state.Revision <= update.ExpectedGameplayRevision) return "busy";
            entry.Saved = entry.Lease!.FinishImport(entry.Saved, pending, true, Current);
            entry.Accumulator.Restore(owner, generation, entry.Desired, entry.Saved.Seconds);
            entry.HistoryState = "imported";
            return "imported";
        }
    }

    public async Task RecoverHistoryImportAsync()
    {
        if (_historyRemote is null || !await _historyGate.WaitAsync(0)) return;
        try
        {
            (BridgeAccountContext? Context, long Generation) owner;
            lock (_sync)
            {
                if (_disposed || Resolve()?.Saved?.PendingImport is null) return;
                owner = _active;
            }
            using var budget = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            await ReconcileHistoryImportAsync(owner.Context!, owner.Generation, _historyRemote, budget.Token).ConfigureAwait(false);
        }
        catch (Exception error) when (error is not OutOfMemoryException) { }
        finally { _historyGate.Release(); }
    }
}
