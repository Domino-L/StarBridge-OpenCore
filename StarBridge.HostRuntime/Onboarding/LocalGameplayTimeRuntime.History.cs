using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Device bridge projection: aggregate numbers only, never a path, file name,
// Handle or profile ID. Every state is an actual Host observation.
internal sealed record LocalHistoryImport(string State, string? ScanId = null, string? Phase = null,
    int ProcessedFiles = 0, int TotalFiles = 0, long ReadBytes = 0, long TotalBytes = 0,
    string? PreviewId = null, long? Seconds = null, int Sessions = 0, int IncompleteSessions = 0, int SkippedFiles = 0,
    long? ImportedSeconds = null, DateTimeOffset? ImportedAt = null);

// One explicit, one-time history import for the confirmed local profile. It
// mirrors the account owner's preview/confirm contract: scanning writes nothing;
// confirmation adds the previewed seconds and the consumed marker in one atomic
// replace; a failed write consumes nothing; an existing import, including one
// whose reply was lost, is reported and never added again. Nothing starts
// automatically and no account, legacy or sharing state is read or changed.
internal sealed partial class LocalGameplayTimeRuntime
{
    private static readonly TimeSpan HistoryPreviewLifetime = TimeSpan.FromMinutes(5);
    private readonly object _historySync = new();
    private HistoryScan? _historyScan;
    private HistoryTicket? _historyTicket;
    private sealed record HistoryTicket(string Id, Owner Owner, DateTimeOffset? FirstRecordedAt, DateTimeOffset Cutoff,
        DateTimeOffset ExpiresAt, GameplayHistoryPreview Preview);
    private sealed class HistoryScan(Owner owner)
    {
        internal readonly string Id = Guid.NewGuid().ToString("N");
        internal readonly Owner Owner = owner;
        internal readonly CancellationTokenSource Cancellation = new();
        internal GameplayHistoryProgress Progress = new("checking", 0, 0, 0, 0);
        internal LocalHistoryImport? Result;
        internal bool Cancelled;
        internal void Cancel()
        {
            Cancelled = true;
            try { Cancellation.Cancel(); } catch (ObjectDisposedException) { }
        }
    }

    // Listening, baseline and evidence revisions may change while the same
    // confirmed profile keeps the same selected log; those do not retire a preview.
    private static bool SameHistoryOwner(Owner a, Owner b) => a.Generation == b.Generation &&
        a.Source.SourceKey == b.Source.SourceKey && a.Source.LogPath == b.Source.LogPath &&
        a.Source.Version == b.Source.Version && a.Profile.Id == b.Profile.Id &&
        a.Profile.Handle.Equals(b.Profile.Handle, StringComparison.OrdinalIgnoreCase);

    internal LocalHistoryImport ReadHistory(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("inactive");
        lock (_gate) return ReadHistoryCore(scopeCurrent, work.Token, out _, out _);
    }

    private LocalHistoryImport ReadHistoryCore(Func<bool> scopeCurrent, CancellationToken token,
        out Owner? owner, out LocalGameplayTimeSaved? saved)
    {
        owner = null; saved = null;
        token.ThrowIfCancellationRequested();
        if (!Scope(scopeCurrent)) return new("unavailable");
        var resolved = Resolve();
        if (resolved is null) return new(Missing().State);
        var entry = EntryFor(resolved);
        var durable = statistics.Read(resolved.Profile.Id);
        ValidateSaved(resolved, entry);
        if (!IsCurrent(resolved) || !Scope(scopeCurrent)) return new("unavailable");
        token.ThrowIfCancellationRequested();
        if (durable.HistoryImportedAt is not null) return Imported(durable);
        lock (_historySync)
        {
            if (_historyScan is { Result: null } active && SameHistoryOwner(active.Owner, resolved)) return Scanning(active);
            if (_historyTicket is { } ticket && SameHistoryOwner(ticket.Owner, resolved) && ticket.ExpiresAt > _time.GetUtcNow() &&
                ticket.FirstRecordedAt == durable.FirstRecordedAt)
                return Preview(ticket);
        }
        if (entry.Error is not null) return new("unavailable");
        if (entry.PendingChoice || durable.Consent != GameplayRecordingConsent.Allowed) return new("recordingRequired");
        owner = resolved; saved = durable;
        return new("available");
    }

    internal LocalHistoryImport StartHistoryScan(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        HistoryScan scan;
        DateTimeOffset cutoff;
        DateTimeOffset? firstRecorded;
        lock (_gate)
        {
            var state = ReadHistoryCore(scopeCurrent, work.Token, out var owner, out var saved);
            if (state.State != "available" || owner is null || saved is null) return state;
            firstRecorded = saved.FirstRecordedAt;
            // Only time before live recording began can be history; it never overlaps saved samples.
            cutoff = firstRecorded ?? _time.GetUtcNow();
            lock (_historySync)
            {
                _historyScan?.Cancel();
                _historyTicket = null;
                scan = new(owner);
                _historyScan = scan;
            }
        }
        _ = Task.Run(() => RunHistoryScan(scan, cutoff, firstRecorded, scopeCurrent));
        lock (_historySync) return scan.Result ?? Scanning(scan);
    }

    private async Task RunHistoryScan(HistoryScan scan, DateTimeOffset cutoff, DateTimeOffset? firstRecorded, Func<bool> scopeCurrent)
    {
        LocalHistoryImport result;
        using var work = _work.Enter(default);
        if (work is null) result = new("contextChanged");
        else
        {
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(scan.Cancellation.Token, work.Token);
            var token = linked.Token;
            void Report(GameplayHistoryProgress value)
            {
                if (!work.IsCurrent || !Scope(scopeCurrent)) throw new OperationCanceledException(token);
                lock (_historySync) scan.Progress = value;
            }
            try
            {
                var source = scan.Owner.Source;
                var preview = await Task.Run(() => GameplayHistoryScanner.Scan(source.LogPath, scan.Owner.Profile.Handle,
                    cutoff, token, Report), token).ConfigureAwait(false);
                lock (_gate)
                {
                    if (!work.IsCurrent || !Scope(scopeCurrent) || Resolve() is not { } owner || !SameHistoryOwner(owner, scan.Owner) ||
                        !IsCurrent(owner)) result = new("contextChanged");
                    else
                    {
                        var saved = statistics.Read(owner.Profile.Id);
                        if (saved.HistoryImportedAt is not null) result = Imported(saved);
                        else if (saved.Consent != GameplayRecordingConsent.Allowed) result = new("recordingRequired");
                        else if (saved.FirstRecordedAt != firstRecorded) result = new("previewExpired");
                        else
                        {
                            var ticket = new HistoryTicket(Guid.NewGuid().ToString("N"), owner, firstRecorded, cutoff,
                                _time.GetUtcNow().Add(HistoryPreviewLifetime), preview);
                            lock (_historySync)
                            {
                                if (scan.Cancelled || !ReferenceEquals(_historyScan, scan)) result = new("cancelled");
                                else { _historyTicket = ticket; result = Preview(ticket); }
                            }
                        }
                    }
                }
            }
            catch (OperationCanceledException) { result = work.IsCurrent && Scope(scopeCurrent) ? new("cancelled") : new("contextChanged"); }
            catch (GameplayTimeException error)
            {
                result = new(error.Code switch {
                    "gameplay.history_path" => "path", "gameplay.history_empty" => "empty",
                    "gameplay.history_limit" => "limit", _ => "unavailable" });
            }
            catch (Exception) { result = new("unavailable"); }
        }
        lock (_historySync)
        {
            scan.Result = result;
            scan.Cancellation.Dispose();
        }
    }

    internal LocalHistoryImport ReadHistoryScan(string scanId, bool cancel, Func<bool> scopeCurrent, CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(scanId)) throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_historySync)
        {
            var scan = _historyScan;
            if (scan is null || scan.Id != scanId) return new("previewExpired");
            if (!Scope(scopeCurrent) || !IsCurrent(scan.Owner) && scan.Result is null)
            {
                scan.Cancel();
                return new("contextChanged");
            }
            if (cancel && scan.Result is null) scan.Cancel();
            if (scan.Result is { } result)
            {
                if (!scan.Cancelled || result.State != "preview") return result;
                _historyTicket = null;
                return new("cancelled");
            }
            return Scanning(scan);
        }
    }

    internal LocalHistoryImport ConfirmHistory(string previewId, Func<bool> scopeCurrent, CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(previewId)) throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            work.Token.ThrowIfCancellationRequested();
            HistoryTicket? ticket;
            lock (_historySync) ticket = _historyTicket;
            if (!Scope(scopeCurrent) || Resolve() is not { } owner || !IsCurrent(owner)) return new("contextChanged");
            var entry = EntryFor(owner);
            var saved = statistics.Read(owner.Profile.Id);
            // Already consumed, including a retry after a lost reply: report it, never add again.
            if (saved.HistoryImportedAt is not null) return Imported(saved);
            if (ticket is null || ticket.Id != previewId || !SameHistoryOwner(ticket.Owner, owner) ||
                ticket.ExpiresAt <= _time.GetUtcNow() || ticket.FirstRecordedAt != saved.FirstRecordedAt)
                return new("previewExpired");
            ValidateSaved(owner, entry);
            if (entry.Error is not null) return new("unavailable");
            if (entry.PendingChoice || entry.Desired != GameplayRecordingConsent.Allowed ||
                saved.Consent != GameplayRecordingConsent.Allowed)
                return new("recordingRequired");
            bool Valid() => !work.Token.IsCancellationRequested && Scope(scopeCurrent) && IsCurrent(owner);
            try
            {
                var next = saved with {
                    Seconds = checked(Math.Max(saved.Seconds, entry.Counter.Seconds) + ticket.Preview.Seconds),
                    FirstRecordedAt = saved.FirstRecordedAt ?? ticket.Cutoff, HistoryImportedAt = _time.GetUtcNow(),
                    HistoricalSeconds = ticket.Preview.Seconds, ImportReceipt = ticket.Id };
                entry.Lease ??= statistics.Open(owner.Profile.Id, () => IsCurrent(owner));
                entry.Saved = entry.Lease.Save(saved, next, Valid);
            }
            catch (Exception error) when (error is LocalFirstUseException or OverflowException)
            {
                // The store replaces atomically: either the original file is intact or the receipt exists.
                LocalGameplayTimeSaved durable;
                try { durable = statistics.Read(owner.Profile.Id); }
                catch (LocalFirstUseException) { return new("unavailable"); }
                if (durable.ImportReceipt != ticket.Id) return new("unavailable"); // Nothing consumed; the preview stays retryable.
                entry.Saved = durable;
            }
            if (entry.Saved.Seconds >= entry.Counter.Seconds) entry.Counter.Rebase(entry.Saved.Seconds);
            else entry.Counter.Restore(entry.Saved.Seconds);
            lock (_historySync) _historyTicket = null;
            return Imported(entry.Saved);
        }
    }

    private void CancelHistory()
    {
        lock (_historySync)
        {
            _historyScan?.Cancel();
            _historyTicket = null;
        }
        _resetTicket = null;
    }

    private static LocalHistoryImport Imported(LocalGameplayTimeSaved saved) =>
        new("imported", ImportedSeconds: saved.HistoricalSeconds, ImportedAt: saved.HistoryImportedAt);
    private static LocalHistoryImport Scanning(HistoryScan scan) => new("scanning", scan.Id,
        scan.Cancelled ? "cancelling" : scan.Progress.Phase, scan.Progress.ProcessedFiles, scan.Progress.TotalFiles,
        scan.Progress.ReadBytes, scan.Progress.TotalBytes);
    private static LocalHistoryImport Preview(HistoryTicket ticket) => new("preview", PreviewId: ticket.Id,
        Seconds: ticket.Preview.Seconds, Sessions: ticket.Preview.Sessions,
        IncompleteSessions: ticket.Preview.IncompleteSessions, SkippedFiles: ticket.Preview.SkippedFiles);
}
