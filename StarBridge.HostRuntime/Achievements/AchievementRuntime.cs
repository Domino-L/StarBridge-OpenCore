using StarBridge.NativeBridge;
using System.Text.Json;

namespace StarBridge.HostRuntime.Achievements;

internal sealed partial class AchievementRuntime : IDisposable
{
    private readonly AchievementOutbox _store;
    private readonly IAchievementRemote _remote;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _current;
    private readonly Func<FirstEntryEvidence?> _evidence;
    private readonly Action<long> _changed;
    private readonly Action<long, DateTimeOffset>? _earned;
    private readonly Action<BridgeAccountContext, AchievementSnapshot, Func<bool>>? _confirmed;
    private readonly Func<BridgeAccountContext, Func<bool>, Account.OfflineAchievementDisplay?>? _cached;
    private readonly Func<HangarAchievementEvidence?>? _hangarEvidence;
    private readonly HangarAchievementOutbox? _hangarStore;
    private HangarAchievementOutbox.Lease? _hangarLease;
    private readonly Action<long, string, int, DateTimeOffset>? _seriesEarned;
    private readonly SemaphoreSlim _gate = new(1);
    private readonly Lifecycle.AsyncWorkRetirement _retirement = new();
    private readonly Lifecycle.DeferredWorkTimer _timer;
    private readonly TimeProvider _time;
    private AchievementOutbox.Lease? _lease;
    private (BridgeAccountContext? Context, long Generation) _owner;
    private sealed record Published(BridgeAccountContext Owner, long Generation, AchievementSnapshot Snapshot,
        DateTimeOffset ConfirmedAt, bool RefreshFailed = false, bool FromCache = false);
    private Published? _published;
    private FirstEntryEvidence? _observedEvidence;
    private CancellationTokenSource? _active;
    private long _nextAttempt;
    private int _failures;
    private volatile bool _disposed;

    internal AchievementRuntime(AchievementOutbox store, IAchievementRemote remote,
        Func<(BridgeAccountContext? Context, long Generation)> current, Func<FirstEntryEvidence?> evidence,
        Action<long> changed, TimeProvider? time = null, bool startTimer = true,
        Action<long, DateTimeOffset>? earned = null, HangarAchievementOutbox? hangarStore = null,
        Func<HangarAchievementEvidence?>? hangarEvidence = null,
        Action<long, string, int, DateTimeOffset>? seriesEarned = null,
        Action<BridgeAccountContext, AchievementSnapshot, Func<bool>>? confirmed = null,
        Func<BridgeAccountContext, Func<bool>, Account.OfflineAchievementDisplay?>? cached = null, CityAchievementOutbox? cityStore = null)
    {
        _store = store; _remote = remote; _current = current; _evidence = evidence; _changed = changed;
        _earned = earned;
        _confirmed = confirmed;
        _cached = cached; _cityStore = cityStore;
        _hangarStore = hangarStore; _hangarEvidence = hangarEvidence; _seriesEarned = seriesEarned;
        _time = time ?? TimeProvider.System;
        _timer = new(_time, () => TickAsync(), TimeSpan.Zero, TimeSpan.FromSeconds(2));
        if (startTimer) _timer.Start();
    }
    internal bool StartDeferredWork() => !_disposed && !_retirement.IsClosed && _timer.Start();
    internal void Invalidate(long _)
    {
        Volatile.Write(ref _published, null); Volatile.Write(ref _observedEvidence, null); Interlocked.Exchange(ref _nextAttempt, 0);
        try { Volatile.Read(ref _active)?.Cancel(); } catch (ObjectDisposedException) { }
    }
    internal void Wake() { _ = TickAsync(); }
    private Published? ReadPublished((BridgeAccountContext? Context, long Generation) owner)
    {
        if (_disposed || owner.Context is null || _current() != owner) return null;
        var value = Volatile.Read(ref _published);
        if (value is not null && value.Owner == owner.Context && value.Generation == owner.Generation) return value;
        try
        {
            bool Current() => !_disposed && !_retirement.IsClosed && _current() == owner;
            var cached = _cached?.Invoke(owner.Context, Current);
            if (cached is null || !Current()) return null;
            cached.Collection.Validate();
            value = new(owner.Context, owner.Generation, cached.Collection, cached.CachedAtUtc, FromCache: true);
            // A cloud completion may have installed a newer snapshot while the
            // encrypted display file was being read. Never replace it with disk.
            var existing = Interlocked.CompareExchange(ref _published, value, null);
            return Current() && (existing is null || existing.Owner == owner.Context && existing.Generation == owner.Generation)
                ? existing ?? value : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            System.Security.Cryptography.CryptographicException or JsonException or InvalidOperationException or ArgumentException)
        { return null; }
    }
    internal void Observe(FirstEntryEvidence? evidence)
    {
        if (evidence is not null && !_disposed && _current() == (evidence.Owner, evidence.Generation))
            Volatile.Write(ref _observedEvidence, evidence);
    }

    internal async Task TickAsync(bool force = false, CancellationToken token = default)
    {
        using var work = _retirement.Enter(token);
        if (work is null || _disposed || !await _gate.WaitAsync(0, token).ConfigureAwait(false)) return;
        token = work.Token;
        try
        {
            var owner = _current();
            bool Current() => !_disposed && !token.IsCancellationRequested && _current() == owner;
            if (_owner != owner) { _lease?.Dispose(); _lease = null; _hangarLease?.Dispose(); _hangarLease = null; _owner = owner; _failures = 0;
                _cityRetries.Clear();
                var retained = Volatile.Read(ref _published);
                if (retained is null || retained.Owner != owner.Context || retained.Generation != owner.Generation) Volatile.Write(ref _published, null);
                Interlocked.Exchange(ref _nextAttempt, 0); }
            if (owner.Context is null || !Current()) return;
            _lease ??= _store.Open(owner.Context);
            var pending = _lease.Read();
            var published = ReadPublished(owner);
            var alreadyEarned = published is not null && published.Owner == owner.Context && published.Generation == owner.Generation &&
                published.Snapshot.EarnedAt.ContainsKey(Core.Achievements.FirstEntryAchievementPolicy.Id);
            var latched = Volatile.Read(ref _observedEvidence);
            var evidence = latched is not null && latched.Owner == owner.Context && latched.Generation == owner.Generation ? latched : _evidence();
            if (!alreadyEarned && evidence is not null && evidence.Owner == owner.Context && evidence.Generation == owner.Generation &&
                evidence.Observation.IsValid && pending != evidence.Observation)
            { _lease.Save(evidence.Observation, Current); pending = evidence.Observation; Interlocked.Exchange(ref _nextAttempt, 0); }
            CaptureCityPending(owner.Context, owner.Generation, Current);
            CaptureHangarPending(owner.Context, owner.Generation, Current);
            if (!force && _time.GetUtcNow().UtcTicks < Interlocked.Read(ref _nextAttempt)) return;
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
            budget.CancelAfter(TimeSpan.FromSeconds(8)); Volatile.Write(ref _active, budget);
            try
            {
                var snapshot = await _remote.ReadAchievementsAsync(owner.Context, owner.Generation, budget.Token).ConfigureAwait(false);
                var newlyEarned = false;
                budget.Token.ThrowIfCancellationRequested(); if (!Current()) return; snapshot.Validate();
                if (published is not null) snapshot = published.Snapshot.MergeConfirmed(snapshot);
                if (pending is not null && !snapshot.EarnedAt.ContainsKey(Core.Achievements.FirstEntryAchievementPolicy.Id))
                {
                    var receipt = await _remote.ObserveFirstEntryAsync(owner.Context, owner.Generation, pending, budget.Token).ConfigureAwait(false);
                    budget.Token.ThrowIfCancellationRequested(); if (!Current()) return;
                    snapshot = new(receipt.SchemaVersion, receipt.EarnedAt, receipt.Progress ?? snapshot.Progress); snapshot.Validate();
                    newlyEarned = receipt.NewlyEarned;
                    if (!snapshot.EarnedAt.ContainsKey(Core.Achievements.FirstEntryAchievementPolicy.Id)) throw new InvalidDataException();
                }
                // A validated new-grant receipt already owns the celebration.
                // Local outbox cleanup can fail independently; a later cloud read
                // cannot recreate NewlyEarned, so deliver before attempting cleanup.
                if (newlyEarned && Current()) _earned?.Invoke(owner.Generation, snapshot.EarnedAt[Core.Achievements.FirstEntryAchievementPolicy.Id]);
                if (pending is not null && snapshot.EarnedAt.ContainsKey(Core.Achievements.FirstEntryAchievementPolicy.Id))
                { try { _lease.Save(null, Current); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { } }
                snapshot = await UpdateCitiesAsync(owner.Context, owner.Generation, snapshot, Current, budget.Token).ConfigureAwait(false);
                budget.Token.ThrowIfCancellationRequested(); if (!Current()) return;
                snapshot = await UpdateHangarAsync(owner.Context, owner.Generation, snapshot, Current, budget.Token).ConfigureAwait(false);
                if (!Current()) return;
                var previous = ReadPublished(owner);
                if (previous is not null) snapshot = previous.Snapshot.MergeConfirmed(snapshot);
                _confirmed?.Invoke(owner.Context, snapshot, Current);
                if (!Current()) return;
                var next = new Published(owner.Context, owner.Generation, snapshot, _time.GetUtcNow());
                Volatile.Write(ref _published, next);
                _failures = 0; Interlocked.Exchange(ref _nextAttempt, _time.GetUtcNow().AddMinutes(5).UtcTicks);
                if (NextCityAttempt(owner.Context) is { } cityAttempt)
                    Interlocked.Exchange(ref _nextAttempt, Math.Min(Interlocked.Read(ref _nextAttempt), cityAttempt));
                if (previous is null || previous.Owner != next.Owner || previous.Generation != next.Generation ||
                    previous.RefreshFailed || previous.FromCache ||
                    previous.Snapshot.EarnedAt.Count != snapshot.EarnedAt.Count ||
                    snapshot.EarnedAt.Any(p => !previous.Snapshot.EarnedAt.TryGetValue(p.Key, out var at) || at != p.Value) ||
                    !SameProgress(previous.Snapshot.Progress, snapshot.Progress)) _changed(owner.Generation);
            }
            finally { Interlocked.CompareExchange(ref _active, null, budget); }
        }
        catch (Exception) when (!token.IsCancellationRequested)
        {
            var previous = Volatile.Read(ref _published);
            var delay = Math.Min(30, 1 << Math.Min(++_failures, 5));
            Interlocked.Exchange(ref _nextAttempt, _time.GetUtcNow().AddSeconds(delay).UtcTicks);
            if (previous is not null && _current() == (previous.Owner, previous.Generation) && !_disposed)
            {
                Interlocked.CompareExchange(ref _published, previous with { RefreshFailed = true }, previous);
                if (!previous.RefreshFailed) _changed(previous.Generation);
            }
        }
        finally { if (_disposed) { _lease?.Dispose(); _lease = null; _hangarLease?.Dispose(); _hangarLease = null; } _gate.Release(); }
    }

    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _current();
            if (_disposed || owner.Context is null || request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                return Error(request, "achievements.account_changed");
            Profiles.LocalPersonalProfileStore.RejectDuplicates(request.Payload);
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != "achievements.read" ||
                request.Payload.GetRawText().Length > 128 || request.Payload.EnumerateObject().Count() != 1 ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "achievements.invalid_request");
            var value = ReadPublished(owner);
            if (value is null) await TickAsync(force: true, token).ConfigureAwait(false);
            else _ = TickAsync(force: true);
            token.ThrowIfCancellationRequested();
            value = ReadPublished(owner);
            if (_current() != owner) return Error(request, "achievements.account_changed");
            return value is not null && value.Owner == owner.Context && value.Generation == owner.Generation
                ? new(BridgeEnvelope.Response(request, new { schemaVersion = value.Snapshot.SchemaVersion,
                    earnedAt = value.Snapshot.EarnedAt, progress = value.Snapshot.Progress,
                    synchronizedAtUtc = value.ConfirmedAt, refreshFailed = value.RefreshFailed }), []) : Error(request, "achievements.unavailable");
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or BridgeProtocolException or FormatException or OverflowException)
        { return Error(request, "achievements.invalid_request"); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(
        BridgeEnvelope.ErrorResponse(request, new(code, "Achievement collection operation failed.", true)), []);
    internal Task RetireAsync()
    {
        Dispose();
        return Task.WhenAll(_retirement.Close(), _timer.RetireAsync());
    }
    public void Dispose()
    {
        _disposed = true; _timer?.Dispose(); Invalidate(0);
        _ = _retirement.Close();
        // A task already in flight owns the lease until its ownership recheck completes.
        if (_gate.Wait(0)) { try { _lease?.Dispose(); _lease = null; _hangarLease?.Dispose(); _hangarLease = null; } finally { _gate.Release(); } }
    }

    private static bool SameProgress(Dictionary<string, int>? a, Dictionary<string, int>? b) =>
        a is null ? b is null : b is not null && a.Count == b.Count && a.All(p => b.GetValueOrDefault(p.Key, -1) == p.Value);
    private void CaptureHangarPending(BridgeAccountContext owner, long generation, Func<bool> current)
    {
        if (_hangarStore is null) return;
        try
        {
            _hangarLease ??= _hangarStore.Open(owner); var pending = _hangarLease.Read();
            if (_hangarEvidence?.Invoke() is not { } evidence || evidence.Owner != owner || evidence.Generation != generation || !evidence.Observation.IsValid) return;
            var progress = Volatile.Read(ref _published)?.Snapshot.Progress;
            if (pending is null && progress is not null && Core.Achievements.HangarAchievementPolicy.Ids.All(id =>
                progress.TryGetValue(id, out var value) && value >= Core.Achievements.HangarAchievementPolicy.Progress(id, evidence.Observation.Counts))) return;
            var next = pending?.Max(evidence.Observation) ?? evidence.Observation;
            if (pending != next) { _hangarLease.Save(next, current); Interlocked.Exchange(ref _nextAttempt, 0); }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException) { }
    }
    private async Task<AchievementSnapshot> UpdateHangarAsync(BridgeAccountContext owner, long generation,
        AchievementSnapshot snapshot, Func<bool> current, CancellationToken token)
    {
        if (_hangarStore is null) return snapshot;
        try
        {
            _hangarLease ??= _hangarStore.Open(owner);
            var pending = _hangarLease.Read();
            if (pending is null) return snapshot;
            var ids = Core.Achievements.HangarAchievementPolicy.Ids;
            if (snapshot.Progress is { } progress && ids.All(id => progress.TryGetValue(id, out var value) && value >= Core.Achievements.HangarAchievementPolicy.Progress(id, pending.Counts)))
            { _hangarLease.Save(null, current); return snapshot; }
            var receipt = await _remote.ObserveHangarAsync(owner, generation, pending, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested(); if (!current()) return snapshot; receipt.Validate();
            if (!ids.All(id => receipt.Progress.TryGetValue(id, out var value) && value >= Core.Achievements.HangarAchievementPolicy.Progress(id, pending.Counts))) throw new InvalidDataException();
            foreach (var id in ids)
            {
                var rank = Enumerable.Range(1, 5).Where(level => receipt.NewlyEarned.Contains($"{id}-{level}")).DefaultIfEmpty().Max();
                if (rank > 0 && current()) _seriesEarned?.Invoke(generation, id, rank, receipt.EarnedAt[$"{id}-{rank}"]);
            }
            snapshot = snapshot.MergeConfirmed(receipt.Snapshot); // Preserve independently acknowledged city/entry receipts.
            try { _hangarLease.Save(null, current); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            return snapshot;
        }
        catch (Exception) when (!token.IsCancellationRequested && current())
        {
            var journey = Core.Achievements.JourneyAchievementPolicy.StantonId;
            return snapshot with { Progress = snapshot.Progress is { } progress && progress.TryGetValue(journey, out var cities)
                ? new() { [journey] = cities } : null };
        } // Hangar series unknown; retain independently verified city/entry evidence.
    }
}
