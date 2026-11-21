using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

/// <summary>Owns consent, exclusive account files, independent sampling and Bridge projection.</summary>
public sealed partial class GameplayTimeRuntime : IDisposable
{
    private readonly object _sync = new();
    private readonly GameplayTimeStore _store;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _current;
    private readonly Func<LocalGamePresenceSnapshot> _presence;
    // Owner keeps the saved settings readable; this decides whether time is
    // recorded or anything is written. False shows the saved settings with
    // gameplay.account_changed and records nothing.
    private readonly Func<bool> _recordingAllowed;
    private bool RecordingAllowed() { try { return _recordingAllowed(); } catch { return false; } }
    private readonly TimeProvider _time;
    private readonly Lifecycle.DeferredWorkTimer _timer;
    private readonly Lifecycle.DeferredWorkTimer? _resetRecoveryTimer;
    private readonly IGameplayHistoryRemote? _historyRemote;
    private readonly VisitorGameplayTimePublisher? _visitorGameplayTime;
    private readonly Dictionary<BridgeAccountContext, Entry> _entries = [];
    private (BridgeAccountContext? Context, long Generation) _active;
    private volatile bool _disposed;
    private readonly Lifecycle.AsyncWorkRetirement _work = new();
    private bool IsActive => !_disposed && !_work.IsClosed;
    // Every commit, remote write, import and reset checks this, so none of them
    // runs while the identity is unconfirmed; reading the saved settings does not.
    private bool OwnerIsCurrent((BridgeAccountContext? Context, long Generation) owner, CancellationToken cancellation = default) =>
        IsActive && !cancellation.IsCancellationRequested && _current() == owner && RecordingAllowed() && CurrentOwnerAllowsWrite() &&
        IsActive && !cancellation.IsCancellationRequested;
    private sealed class Entry
    {
        internal GameplayTimeStore.Lease? Lease;
        internal GameplayTimeSaved? Saved;
        internal readonly GameplayTimeAccumulator Accumulator = new();
        internal GameplayRecordingConsent Desired;
        internal bool ConsentIdentityPending;
        internal string? Error;
        internal string? PauseReason;
        internal bool RecoveryIdentityRetained;
        internal string GameState = "unknown";
        internal bool ShowOnProfile = true;
        internal DateTimeOffset? FirstRecordedAt;
        internal string HistoryState = "unchecked";
        internal bool StopBeforeLoad;
        internal string AccountTotalState = "unavailable";
        private long? _accountTotalSeconds;
        internal long? LastAccountTotalSeconds;
        // The last total and revision Japan itself reported (a read, or a verified write) for the visitor copy.
        internal VisitorGameplayTime? LastJapanAuthority;
        internal long? AccountTotalSeconds
        {
            get => _accountTotalSeconds;
            set
            {
                _accountTotalSeconds = value;
                if (value is not null || AccountTotalState == "empty") LastAccountTotalSeconds = value;
            }
        }
        internal long? AccountReadGeneration;
        // Storage, read and write failures used to stop recording until a manual
        // retry or a restart, silently. They now reload on a backoff.
        internal DateTimeOffset? RetryAt;
        internal TimeSpan RetryDelay;
        internal GameplayContinuity? RetryOwner;
        internal bool RetryOwnerProbe;
        internal bool RetryOwnerProbeUsed;
    }
    internal static readonly TimeSpan FirstRetryDelay = TimeSpan.FromSeconds(30);
    internal static readonly TimeSpan MaximumRetryDelay = TimeSpan.FromMinutes(10);

    public GameplayTimeRuntime(GameplayTimeStore store,
        Func<(BridgeAccountContext? Context, long Generation)> current,
        Func<LocalGamePresenceSnapshot>? presence = null, TimeProvider? time = null, bool startTimer = true,
        Func<string?>? verifiedHandle = null,
        Func<BridgeAccountContext, CancellationToken, Task<GameplayHistoryEligibility>>? historyEligibility = null,
        IGameplayTimeResetRemote? resetRemote = null, IGameplayHistoryRemote? historyRemote = null,
        Func<string?>? boundLiveLog = null, Func<bool>? recordingAllowed = null, Func<GameplayContinuity>? continuity = null,
        IVisitorGameplayTimeRemote? visitorGameplayTimeRemote = null)
    {
        _store = store; _current = current; _time = time ?? TimeProvider.System;
        _continuity = continuity;
        _recordingAllowed = recordingAllowed ?? (() => true);
        _presence = presence ?? new LocalGamePresenceReader().Read;
        _verifiedHandle = verifiedHandle ?? (() => null);
        _historyEligibility = historyEligibility;
        _historyRemote = historyRemote;
        if (visitorGameplayTimeRemote is not null)
            _visitorGameplayTime = new(visitorGameplayTimeRemote, store.VisitorReceipts, current, _time);
        _boundLiveLog = boundLiveLog ?? (() => null);
        _timer = new(_time, () => { Sample(); return Task.CompletedTask; },
            TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
        if (resetRemote is not null)
            _resetRecoveryTimer = new(_time, () => RecoverResetAsync(resetRemote),
                TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(30));
        if (startTimer) StartDeferredSampling();
    }
    internal bool StartDeferredSampling()
    {
        try { return IsActive && _timer.Start() && IsActive && (_resetRecoveryTimer?.Start() ?? true); }
        catch
        {
            // Recovery timer construction may fail after sampling started. Both
            // original timers belong to this owner; neither may escape a failed
            // constructor or activation and continue as an orphan sampler.
            Dispose();
            throw;
        }
    }

    public void Suspend()
    {
        lock (_sync)
        {
            _visitorGameplayTime?.Invalidate();
            foreach (var entry in _entries.Values)
            {
                DiscardTransient(entry, "account");
                entry.Accumulator.Suspend();
                entry.Lease?.Dispose(); entry.Lease = null;
            }
            foreach (var entry in _entries.Values)
            {
                entry.AccountTotalState = "unavailable";
                entry.AccountTotalSeconds = null; entry.LastAccountTotalSeconds = null; entry.LastJapanAuthority = null;
                entry.AccountReadGeneration = null;
            }
            _active = default;
            _ownerConfirmedAt = null; _hadIdentityMatch = false;
            _confirmedAuthentication = default; _identityRejectionVersion = 0;
        }
    }

    // Timer and commands share this lock; disk IO never overlaps, even under slow storage.
    public void Sample()
    {
        using var work = _work.Enter(default);
        if (work is null) return;
        lock (_sync)
        {
            if (!IsActive) return;
            var entry = Resolve();
            if (entry?.PauseReason is "connection" or "connectionPaused" or "identity") return;
            if (entry is not null && !ConfirmedForWrite()) { entry.Accumulator.Suspend(); return; }
            if (entry is null || entry.Error is not null || entry.Saved?.PendingReset is not null ||
                entry.Saved?.PendingImport is not null ||
                entry.Desired != GameplayRecordingConsent.Allowed) return;
            var owner = _active;
            try
            {
                var presence = _presence();
                entry.GameState = presence.SchemaVersion == 1 && presence.State is "running" or "notRunning"
                    ? presence.State : "unknown";
                if (!RecordingOwnerIsCurrent(owner, work.Token))
                {
                    if (!ResolveContinuity(out _)) entry.Accumulator.Suspend();
                    return;
                }
                var now = _time.GetUtcNow();
                // Old snapshots with positive totals and no start date remain unknown; do not invent a cutoff.
                if (entry.FirstRecordedAt is null && entry.Accumulator.PlayTimeSeconds == 0 && presence.State == "running")
                    entry.FirstRecordedAt = now;
                entry.Accumulator.Observe(owner.Context, owner.Generation, presence, now);
                Persist(entry, () => RecordingOwnerIsCurrent(owner, work.Token));
            }
            catch (Exception e) { Fail(entry, e); }
        }
    }

    private Entry? Resolve()
    {
        if (!IsActive) return null;
        if (ResolveContinuity(out var retained)) return retained;
        var owner = _current();
        if (!IsActive) return null;
        if (_active != owner)
        {
            foreach (var old in _entries.Values)
            {
                old.Accumulator.Suspend();
                old.Lease?.Dispose(); old.Lease = null;
            }
            _active = owner;
            if (owner.Context is not null && _entries.TryGetValue(owner.Context, out var known) && known.Saved is not null)
                known.Accumulator.Restore(owner.Context, owner.Generation, known.Desired, known.Accumulator.PlayTimeSeconds);
        }
        if (owner.Context is null) return null;
        if (_entries.TryGetValue(owner.Context, out var entry))
        {
            try { entry.Lease?.ValidateOwner(); }
            catch (GameplayTimeException error)
            {
                entry.Lease?.Dispose(); entry.Accumulator.Suspend();
                // Same account: keep the switches it showed (see Fail).
                entry = new Entry { Desired = entry.Desired, ShowOnProfile = entry.ShowOnProfile };
                _entries[owner.Context] = entry;
                Fail(entry, error);
                return entry;
            }
            // Storage failures wait out their backoff before any
            // reload, including a reopen after Suspend released the lease of a page
            // that had loaded before (CX-GAMEPLAY-DIAG-073-R #1). Owner recovery can wake a temporary retry.
            RetryWhenOwnerReturns(entry);
            var backingOff = entry.Error is not null && entry.Error != "gameplay.account_changed" &&
                entry.RetryAt is { } retryAt && _time.GetUtcNow() < retryAt;
            if (!backingOff && (
                entry.Lease is null && (entry.Saved is not null || entry.Error is null || entry.Error == "gameplay.account_changed") ||
                // Any other failure (storage, read, write, conflict) reloads once its backoff passes.
                entry.Error is not null && entry.Error != "gameplay.account_changed" && entry.RetryAt is not null ||
                // Pending setup/identity is re-evaluated by the next sample,
                // read or publication, including identity updates in this generation.
                entry.Error is null && entry.Desired == GameplayRecordingConsent.Unknown &&
                    entry.Saved?.Consent == GameplayRecordingConsent.Unknown)) Load(entry);
            return entry;
        }
        entry = new Entry();
        _entries.Add(owner.Context, entry);
        Load(entry);
        return entry;
    }

    private void Load(Entry entry)
    {
        entry.ConsentIdentityPending = false;
        try
        {
            entry.Lease ??= _store.Open(_active.Context!);
            var saved = entry.Lease.Read();
            var owner = _active;
            // Adopting the setup choice is a write; it waits for a confirmed identity.
            // While withheld the guide's settings are not even read (CX-RECORDING-GATE-R1 #1):
            // an unreadable guide file must not hide the saved settings.
            var writable = RecordingAllowed();
            var consent = !writable ? saved.Consent :
                entry.StopBeforeLoad ? GameplayRecordingConsent.Declined :
                saved.Consent == GameplayRecordingConsent.Unknown ?
                    _store.InitialConsent(_verifiedHandle(), out entry.ConsentIdentityPending) : saved.Consent;
            if (writable && consent != GameplayRecordingConsent.Unknown && (saved.Consent != consent || saved.ShowOnProfile is null))
                saved = entry.Lease.Save(saved, saved with {
                    Consent = consent,
                    ShowOnProfile = saved.ShowOnProfile ?? true
                }, () => OwnerIsCurrent(owner));
            entry.Saved = saved;
            entry.PauseReason = null;
            ConfirmLoadedOwner();
            entry.Desired = saved.Consent;
            entry.ShowOnProfile = saved.ShowOnProfile ?? true;
            entry.FirstRecordedAt = saved.FirstRecordedAt;
            entry.HistoryState = saved.HistoryImportedAt is not null || saved.HistoryConsumed == true ? "imported" : "unchecked";
            entry.Accumulator.Restore(_active.Context, _active.Generation, saved.Consent, saved.Seconds);
            entry.StopBeforeLoad = false;
            if (entry.Error is not null) _store.Journal.Record("gameplay-runtime", "code=recovered", "code=recovered");
            entry.Error = null;
            entry.RetryAt = null;
            entry.RetryDelay = TimeSpan.Zero;
            entry.RetryOwner = null;
            entry.RetryOwnerProbeUsed = false;
        }
        catch (Exception e) { Fail(entry, e); }
    }

    private void Persist(Entry entry, Func<bool> canCommit)
    {
        if (entry.Saved is not { } saved || entry.Lease is null) throw new GameplayTimeException("gameplay.read_failed");
        var next = saved with { Consent = entry.Desired, Seconds = entry.Accumulator.PlayTimeSeconds,
            ShowOnProfile = entry.ShowOnProfile, FirstRecordedAt = entry.FirstRecordedAt };
        if (saved == next) return;
        entry.Saved = entry.Lease.Save(saved, next, canCommit);
    }

    public BridgeDispatchBatch Dispatch(BridgeEnvelope request, CancellationToken cancellation = default)
    {
        using var work = _work.Enter(default);
        if (work is null) return Error(request, "gameplay.account_changed");
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                var owner = DispatchOwner();
                if (!IsActive || request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                    request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                {
                    // Build 71: this refusal showed "identity not confirmed" for hours with no
                    // trace. Name which check refused; never the contexts themselves.
                    var reason = !IsActive ? "inactive" : owner.Context is null ? "no-owner"
                        : request.SessionGeneration != owner.Generation ? "generation"
                        : request.AccountContext != owner.Context ? "context" : "message";
                    _store.Journal.Record("gameplay-runtime", "code=refused reason=" + reason, "code=refused reason=" + reason);
                    return Error(request, "gameplay.account_changed");
                }
                var body = request.Payload;
                if (body.GetRawText().Length > 1024 || body.GetProperty("schemaVersion").GetInt32() != 1)
                    return Error(request, "gameplay.invalid_request");
                Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
                var set = request.Name == "gameplayTime.setConsent";
                var visibility = request.Name == "gameplayTime.setVisibility";
                if (request.Name is not ("gameplayTime.read" or "gameplayTime.retry" or "gameplayTime.setConsent" or "gameplayTime.setVisibility") ||
                    body.EnumerateObject().Any(p => p.Name != "schemaVersion" && !(set && p.Name == "allowed") &&
                        !(visibility && p.Name == "showOnProfile")))
                    return Error(request, "gameplay.invalid_request");
                bool? allowed = set ? body.GetProperty("allowed").GetBoolean() : null;
                bool? show = visibility ? body.GetProperty("showOnProfile").GetBoolean() : null;
                cancellation.ThrowIfCancellationRequested();
                var entry = Resolve();
                if (entry is null || _active != owner) return Error(request, "gameplay.account_changed");
                if (entry.PauseReason is "connection" or "connectionPaused")
                    return Projection(request, entry);
                if (!ConfirmedForWrite() || request.Name != "gameplayTime.read" && !RecordingAllowed())
                {
                    // Identity not confirmed: show the saved settings, change nothing.
                    entry.Accumulator.Suspend();
                    if (request.Name == "gameplayTime.retry" && entry.Saved is null) Load(entry);
                    return Projection(request, entry, withheld: true);
                }
                bool CanCommit() => work.IsCurrent && OwnerIsCurrent(owner, cancellation);
                if (set)
                {
                    // Stop is effective before attempting IO. Allow takes effect only after durable save.
                    entry.Accumulator.Suspend();
                    if (allowed == false)
                    {
                        entry.StopBeforeLoad = true;
                        entry.Desired = GameplayRecordingConsent.Declined;
                    }
                    if (entry.Saved is null || entry.Error is not null && allowed == true)
                        return Projection(request, entry);
                    entry.Desired = allowed == true ? GameplayRecordingConsent.Allowed : GameplayRecordingConsent.Declined;
                    try
                    {
                        Persist(entry, CanCommit);
                        entry.Accumulator.ApplyConsent(entry.Desired);
                        entry.StopBeforeLoad = false;
                        entry.Error = null;
                    }
                    catch (Exception e) { Fail(entry, e); }
                }
                else if (visibility)
                {
                    entry.ShowOnProfile = show!.Value;
                    try
                    {
                        Persist(entry, CanCommit);
                        if (entry.Accumulator.Consent != entry.Desired)
                            entry.Accumulator.ApplyConsent(entry.Desired);
                        entry.Error = null;
                    }
                    catch (Exception e) { Fail(entry, e); }
                }
                else if (request.Name == "gameplayTime.retry")
                {
                    entry.Accumulator.Suspend();
                    if (entry.Saved is null || entry.Saved.Consent == GameplayRecordingConsent.Unknown) Load(entry);
                    else
                    {
                        try
                        {
                            Persist(entry, CanCommit);
                            entry.Accumulator.ApplyConsent(entry.Desired);
                            entry.Error = null;
                        }
                        catch (Exception e) { Fail(entry, e); }
                    }
                }
                if (!(request.Name == "gameplayTime.read" ? RecordingOwnerIsCurrent(owner, cancellation) : CanCommit()))
                    return Error(request, "gameplay.account_changed");
                return Projection(request, entry);
            }
            catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException or ArgumentException or OperationCanceledException)
            { return Error(request, "gameplay.invalid_request"); }
        }
    }

    private void Fail(Entry entry, Exception error)
    {
        var temporary = TemporaryOwnerFailure(error);
        if (entry.Saved is not null && entry.Error is null && HasConfirmedLogin() &&
            (temporary || LostOwnerDuringCommit(error)))
        {
            entry.PauseReason = "connection";
            return;
        }
        DiscardTransient(entry, "failure");
        entry.Accumulator.Suspend();
        // Without confirmation, cached values cannot authorize a transient window.
        // Release a partially loaded lease and retry with the ordinary backoff.
        if (temporary) { entry.Lease?.Dispose(); entry.Lease = null; }
        entry.RetryOwner = temporary ? Continuity() : null;
        entry.RetryOwnerProbe = error is Privacy.LocalPrivacyOwnerUnavailableException;
        entry.Error = temporary ? "gameplay.unavailable" :
            error is GameplayTimeException known ? known.Code : "gameplay.unavailable";
        if (entry.Error != "gameplay.account_changed")
        {
            // An owner that is only temporarily unconfirmable retries on a short fixed
            // cycle, so recording resumes soon after the server is back; storage
            // failures keep the growing backoff.
            entry.RetryDelay = temporary || entry.RetryDelay <= TimeSpan.Zero ? FirstRetryDelay
                : TimeSpan.FromTicks(Math.Min(entry.RetryDelay.Ticks * 2, MaximumRetryDelay.Ticks));
            entry.RetryAt = _time.GetUtcNow() + entry.RetryDelay;
        }
        else { entry.RetryAt = null; entry.RetryDelay = TimeSpan.Zero; }
        // Reason code and exception type only; the store already logged the file prefix.
        // First occurrence of each code per run in full, then only counts (GameplayFailureJournal).
        _store.Journal.Record("gameplay-runtime", $"code={entry.Error.Replace("gameplay.", "")}",
            $"code={entry.Error.Replace("gameplay.", "")} " +
            $"exception={(error is GameplayTimeException ? "none" : Support.IdentityGateJournal.Type(error))} " +
            $"retry={(entry.RetryAt is null ? "on-owner" : ((int)entry.RetryDelay.TotalSeconds).ToString(System.Globalization.CultureInfo.InvariantCulture))}");
        if (entry.Error == "gameplay.account_changed")
        {
            // A suspended lease may already be gone; cached data is not proof of current ownership.
            // The entry belongs to this same account, so the last loaded switches stay
            // on screen: showing them off made people think recording had been turned off.
            entry.Lease?.Dispose(); entry.Lease = null;
            entry.Saved = null;
            entry.FirstRecordedAt = null;
            entry.HistoryState = "unchecked";
            entry.GameState = "unknown";
            entry.AccountTotalState = "unavailable";
            entry.AccountTotalSeconds = null; entry.LastAccountTotalSeconds = null; entry.LastJapanAuthority = null;
            entry.AccountReadGeneration = null;
        }
    }
    private static BridgeDispatchBatch Projection(BridgeEnvelope request, Entry entry, bool withheld = false) =>
        new(BridgeEnvelope.Response(request, new
        {
            schemaVersion = 1,
            consent = entry.Desired.ToString().ToLowerInvariant(),
            consentPending = entry.Error is null && entry.Desired == GameplayRecordingConsent.Unknown &&
                entry.ConsentIdentityPending ? "identity" : null,
            seconds = LocalDisplayedSeconds(entry),
            savedSeconds = entry.Saved?.Seconds,
            accountTotalState = entry.AccountTotalState == "unavailable" && entry.LastAccountTotalSeconds is not null
                ? "available" : entry.AccountTotalState,
            accountTotalSeconds = entry.AccountTotalSeconds ?? entry.LastAccountTotalSeconds,
            accountTotalStale = entry.AccountTotalState == "unavailable" && entry.LastAccountTotalSeconds is not null || entry.PauseReason is "connection" or "connectionPaused",
            pauseReason = entry.PauseReason ?? (withheld || entry.Error == "gameplay.account_changed" ? "identity" : null),
            recording = !withheld && entry.Error is null &&
                entry.PauseReason is not ("connectionPaused" or "identity") && entry.Accumulator.IsRecording,
            gameState = entry.GameState,
            showOnProfile = entry.ShowOnProfile,
            historyState = entry.HistoryState,
            historicalSeconds = entry.Saved?.HistoricalSeconds ?? 0,
            historyImportedAt = entry.Saved?.HistoryImportedAt,
            error = entry.PauseReason == "connection" ? null : entry.Error ?? (withheld || entry.PauseReason is not null ? "gameplay.account_changed" : null)
        }), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local gameplay time operation failed.", true)), []);
    // Close admission and invalidate commits before waiting for the state lock.
    // Every sample / network operation retains its lease until actual exit.
    // Pending reset/import journals are left for a later explicitly online owner.
    internal async Task RetireAsync()
    {
        var drained = _work.Close();
        _visitorGameplayTime?.Dispose();
        var timer = _timer.RetireAsync();
        var recovery = _resetRecoveryTimer?.RetireAsync() ?? Task.CompletedTask;
        try { await Task.WhenAll(drained, timer, recovery).ConfigureAwait(false); }
        finally { Dispose(); }
    }

    public void Dispose()
    {
        _work.Close();
        lock (_sync)
        {
            if (_disposed) return;
            // Only confirmed samples are saved, never inferred shutdown/sleep time.
            _disposed = true;
            _visitorGameplayTime?.Dispose();
            _timer?.Dispose();
            _resetRecoveryTimer?.Dispose();
            foreach (var entry in _entries.Values)
            { DiscardTransient(entry, "retired"); entry.Accumulator.Suspend(); entry.Lease?.Dispose(); entry.Lease = null; }
            _historyTicket = null;
            _resetTicket = null;
        }
    }
}
