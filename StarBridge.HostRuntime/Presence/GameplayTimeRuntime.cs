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
    private readonly TimeProvider _time;
    private readonly ITimer? _timer;
    private readonly ITimer? _resetRecoveryTimer;
    private readonly IGameplayHistoryRemote? _historyRemote;
    private readonly Dictionary<BridgeAccountContext, Entry> _entries = [];
    private (BridgeAccountContext? Context, long Generation) _active;
    private bool _disposed;
    private sealed class Entry
    {
        internal GameplayTimeStore.Lease? Lease;
        internal GameplayTimeSaved? Saved;
        internal readonly GameplayTimeAccumulator Accumulator = new();
        internal GameplayRecordingConsent Desired;
        internal string? Error;
        internal string GameState = "unknown";
        internal bool ShowOnProfile = true;
        internal DateTimeOffset? FirstRecordedAt;
        internal string HistoryState = "unchecked";
        internal bool StopBeforeLoad;
    }

    public GameplayTimeRuntime(GameplayTimeStore store,
        Func<(BridgeAccountContext? Context, long Generation)> current,
        Func<LocalGamePresenceSnapshot>? presence = null, TimeProvider? time = null, bool startTimer = true,
        Func<string?>? verifiedHandle = null,
        Func<BridgeAccountContext, CancellationToken, Task<GameplayHistoryEligibility>>? historyEligibility = null,
        IGameplayTimeResetRemote? resetRemote = null, IGameplayHistoryRemote? historyRemote = null)
    {
        _store = store; _current = current; _time = time ?? TimeProvider.System;
        _presence = presence ?? new LocalGamePresenceReader().Read;
        _verifiedHandle = verifiedHandle ?? (() => null);
        _historyEligibility = historyEligibility;
        _historyRemote = historyRemote;
        if (startTimer)
            _timer = _time.CreateTimer(_ => Sample(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
        if (startTimer && resetRemote is not null)
            _resetRecoveryTimer = _time.CreateTimer(_ => _ = RecoverResetAsync(resetRemote), null,
                TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(30));
    }

    public void Suspend()
    {
        lock (_sync)
        {
            foreach (var entry in _entries.Values) entry.Accumulator.Suspend();
            _active = default;
        }
    }

    // Timer and commands share this lock; disk IO never overlaps, even under slow storage.
    public void Sample()
    {
        lock (_sync)
        {
            if (_disposed) return;
            var entry = Resolve();
            if (entry is null || entry.Error is not null || entry.Saved?.PendingReset is not null ||
                entry.Saved?.PendingImport is not null ||
                entry.Desired != GameplayRecordingConsent.Allowed) return;
            var owner = _active;
            try
            {
                var presence = _presence();
                entry.GameState = presence.SchemaVersion == 1 && presence.State is "running" or "notRunning"
                    ? presence.State : "unknown";
                if (_current() != owner) { entry.Accumulator.Suspend(); return; }
                var now = _time.GetUtcNow();
                // Old snapshots with positive totals and no start date remain unknown; do not invent a cutoff.
                if (entry.FirstRecordedAt is null && entry.Accumulator.PlayTimeSeconds == 0 && presence.State == "running")
                    entry.FirstRecordedAt = now;
                entry.Accumulator.Observe(owner.Context, owner.Generation, presence, now);
                Persist(entry, () => _current() == owner);
            }
            catch (Exception e) { Fail(entry, e); }
        }
    }

    private Entry? Resolve()
    {
        var owner = _current();
        if (_active != owner)
        {
            foreach (var old in _entries.Values) old.Accumulator.Suspend();
            _active = owner;
            if (owner.Context is not null && _entries.TryGetValue(owner.Context, out var known) && known.Saved is not null)
                known.Accumulator.Restore(owner.Context, owner.Generation, known.Desired, known.Accumulator.PlayTimeSeconds);
        }
        if (owner.Context is null) return null;
        if (_entries.TryGetValue(owner.Context, out var entry)) return entry;
        entry = new Entry();
        _entries.Add(owner.Context, entry);
        Load(entry);
        return entry;
    }

    private void Load(Entry entry)
    {
        try
        {
            entry.Lease ??= _store.Open(_active.Context!);
            var saved = entry.Lease.Read();
            var owner = _active;
            var consent = entry.StopBeforeLoad ? GameplayRecordingConsent.Declined :
                saved.Consent == GameplayRecordingConsent.Unknown ? GameplayRecordingConsent.Allowed : saved.Consent;
            if (saved.Consent != consent || saved.ShowOnProfile is null)
                saved = entry.Lease.Save(saved, saved with {
                    Consent = consent,
                    ShowOnProfile = saved.ShowOnProfile ?? true
                }, () => _current() == owner);
            entry.Saved = saved;
            entry.Desired = saved.Consent;
            entry.ShowOnProfile = saved.ShowOnProfile ?? true;
            entry.FirstRecordedAt = saved.FirstRecordedAt;
            entry.HistoryState = saved.HistoryImportedAt is not null || saved.HistoryConsumed == true ? "imported" : "unchecked";
            entry.Accumulator.Restore(_active.Context, _active.Generation, saved.Consent, saved.Seconds);
            entry.StopBeforeLoad = false;
            entry.Error = null;
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
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                var owner = _current();
                if (_disposed || request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                    request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                    return Error(request, "gameplay.account_changed");
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
                bool CanCommit() => !cancellation.IsCancellationRequested && _current() == owner;
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
                    if (entry.Saved is null) Load(entry);
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
                if (!CanCommit()) return Error(request, "gameplay.account_changed");
                return Projection(request, entry);
            }
            catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException or ArgumentException or OperationCanceledException)
            { return Error(request, "gameplay.invalid_request"); }
        }
    }

    private static void Fail(Entry entry, Exception error)
    {
        entry.Accumulator.Suspend();
        entry.Error = error is GameplayTimeException known ? known.Code : "gameplay.unavailable";
    }
    private static BridgeDispatchBatch Projection(BridgeEnvelope request, Entry entry) =>
        new(BridgeEnvelope.Response(request, new
        {
            schemaVersion = 1,
            consent = entry.Desired.ToString().ToLowerInvariant(),
            seconds = entry.Saved is null ? (long?)null : entry.Accumulator.PlayTimeSeconds,
            savedSeconds = entry.Saved?.Seconds,
            recording = entry.Error is null && entry.Accumulator.IsRecording,
            gameState = entry.GameState,
            showOnProfile = entry.ShowOnProfile,
            historyState = entry.HistoryState,
            historicalSeconds = entry.Saved?.HistoricalSeconds ?? 0,
            historyImportedAt = entry.Saved?.HistoryImportedAt,
            error = entry.Error
        }), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local gameplay time operation failed.", true)), []);
    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            // Only confirmed samples are saved, never inferred shutdown/sleep time.
            _disposed = true;
            _timer?.Dispose();
            _resetRecoveryTimer?.Dispose();
            foreach (var entry in _entries.Values) { entry.Accumulator.Suspend(); entry.Lease?.Dispose(); }
        }
    }
}
