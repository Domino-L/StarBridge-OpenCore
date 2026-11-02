using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Aggregate numbers only; no path, Handle or profile ID crosses the bridge.
internal sealed record LocalResetView(string State, string? ResetId = null, long? Seconds = null, long? HistoricalSeconds = null);

// Explicit, user-confirmed reset of the confirmed local profile's play time
// (WPF parity): clears live and imported time and restores the one-time import.
// Recording consent is unchanged. Preview writes nothing; confirmation keeps the
// replaced encrypted file as a backup. Nothing calls this automatically.
internal sealed partial class LocalGameplayTimeRuntime
{
    private sealed record ResetTicket(string Id, Owner Owner, DateTimeOffset ExpiresAt);
    private ResetTicket? _resetTicket;

    internal LocalResetView PreviewReset(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("inactive");
        lock (_gate)
        {
            _resetTicket = null;
            work.Token.ThrowIfCancellationRequested();
            if (!Scope(scopeCurrent)) return new("unavailable");
            var owner = Resolve();
            if (owner is null) return new(Missing().State);
            var entry = EntryFor(owner);
            var saved = statistics.Read(owner.Profile.Id);
            ValidateSaved(owner, entry);
            if (!IsCurrent(owner) || !Scope(scopeCurrent)) return new("unavailable");
            if (entry.Error is not null) return new("unavailable");
            if (saved.Revision == 0 || saved.Seconds == 0 && saved.HistoryImportedAt is null) return new("empty", Seconds: 0, HistoricalSeconds: 0);
            var ticket = new ResetTicket(Guid.NewGuid().ToString("N"), owner, _time.GetUtcNow().Add(HistoryPreviewLifetime));
            _resetTicket = ticket;
            return new("ready", ticket.Id, Math.Max(saved.Seconds, entry.Counter.Seconds), saved.HistoricalSeconds ?? 0);
        }
    }

    internal LocalResetView ConfirmReset(string resetId, Func<bool> scopeCurrent, CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(resetId)) throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            work.Token.ThrowIfCancellationRequested();
            var ticket = _resetTicket;
            _resetTicket = null; // One explicit confirmation per preview; never replayed.
            if (!Scope(scopeCurrent) || Resolve() is not { } owner || !IsCurrent(owner)) return new("contextChanged");
            if (ticket is null || ticket.Id != resetId || !SameHistoryOwner(ticket.Owner, owner) || ticket.ExpiresAt <= _time.GetUtcNow())
                return new("previewExpired");
            var entry = EntryFor(owner);
            ValidateSaved(owner, entry);
            if (entry.Error is not null) return new("unavailable");
            var saved = statistics.Read(owner.Profile.Id);
            if (saved.Revision == 0) return new("reset", Seconds: 0);
            CancelHistory();
            bool Valid() => !work.Token.IsCancellationRequested && Scope(scopeCurrent) && IsCurrent(owner);
            try
            {
                entry.Lease ??= statistics.Open(owner.Profile.Id, () => IsCurrent(owner));
                entry.Saved = entry.Lease.Reset(saved, Valid);
            }
            catch (LocalFirstUseException)
            {
                // Atomic replace: the original is intact unless the reset landed.
                LocalGameplayTimeSaved durable;
                try { durable = statistics.Read(owner.Profile.Id); }
                catch (LocalFirstUseException) { return new("unavailable"); }
                if (durable.Revision <= saved.Revision || durable.Seconds != 0 || durable.HistoryImportedAt is not null)
                    return new("unavailable");
                entry.Saved = durable;
            }
            entry.Counter.Restore(0);
            entry.LastEvidenceAt = null;
            return new("reset", Seconds: 0);
        }
    }
}
