using StarBridge.Core.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

internal sealed partial class AchievementRuntime
{
    private readonly CityAchievementOutbox? _cityStore;
    private readonly object _citySync = new();
    private readonly Dictionary<string, CityArrivalEvidence> _cityEvidence = [];
    private sealed record CityRetry(int Failures, long NextAttempt, bool Cleanup);
    // Owned by TickAsync's gate and cleared on account/generation changes. Reads and other cities
    // cannot reset a rejected city's deadline, including forced page refreshes and newly queued evidence.
    private readonly Dictionary<string, CityRetry> _cityRetries = [];

    internal void ObserveCity(CityArrivalEvidence evidence)
    {
        if (_cityStore is null || _disposed || !evidence.Observation.IsValid ||
            _current() != (evidence.Owner, evidence.Generation)) return;
        lock (_citySync)
        {
            if (_disposed || _current() != (evidence.Owner, evidence.Generation)) return;
            _cityEvidence[evidence.Observation.City] = evidence;
            // Persist before any remote request; a network outage cannot erase an arrival.
            try
            {
                CaptureCityPending(evidence.Owner, evidence.Generation,
                    () => !_disposed && _current() == (evidence.Owner, evidence.Generation));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                System.Text.Json.JsonException or OperationCanceledException)
            { /* Keep the candidate for the next tick; storage failure must not invalidate Game.log presence. */ }
        }
    }

    private void CaptureCityPending(BridgeAccountContext owner, long generation, Func<bool> current)
    {
        if (_cityStore is null) return;
        lock (_citySync)
        {
            using var lease = _cityStore.Open(owner);
            var state = lease.Read();
            foreach (var (city, evidence) in _cityEvidence.ToArray())
            {
                if (!current()) return;
                if (evidence.Owner == owner && evidence.Generation == generation && !state.Contains(city))
                {
                    var next = state with { Pending = [.. state.Pending, evidence.Observation] };
                    lease.Save(next, current); state = next;
                    Interlocked.Exchange(ref _nextAttempt, 0);
                }
                _cityEvidence.Remove(city);
            }
        }
    }

    private async Task<AchievementSnapshot> UpdateCitiesAsync(BridgeAccountContext owner, long generation,
        AchievementSnapshot snapshot, Func<bool> current, CancellationToken token)
    {
        if (_cityStore is null) return snapshot;
        CityObservation[] pending;
        lock (_citySync) { using var lease = _cityStore.Open(owner); pending = lease.Read().Pending; }
        foreach (var observation in pending)
        {
            token.ThrowIfCancellationRequested(); if (!current()) return snapshot;
            var id = JourneyAchievementPolicy.Id(observation.City);
            var cleaning = false;
            try
            {
                // A cloud confirmation ends an upload's wait at once; a failing local cleanup keeps its own deadline.
                if (_cityRetries.TryGetValue(observation.City, out var retry) && _time.GetUtcNow().UtcTicks < retry.NextAttempt &&
                    (retry.Cleanup || !snapshot.EarnedAt.ContainsKey(id))) continue;
                if (!snapshot.EarnedAt.ContainsKey(id))
                {
                    var receipt = await _remote.ObserveCityAsync(owner, generation, observation, token).ConfigureAwait(false);
                    token.ThrowIfCancellationRequested(); if (!current()) return snapshot;
                    receipt.Validate();
                    if (!receipt.EarnedAt.ContainsKey(id)) throw new InvalidDataException("City acknowledgement is missing.");
                    // Receipt admission precedes local cleanup, as in first-entry. Never infer stanton locally.
                    foreach (var earned in receipt.NewlyEarned)
                        if (current()) _seriesEarned?.Invoke(generation, earned, 0, receipt.EarnedAt[earned]);
                    snapshot = snapshot.MergeConfirmed(receipt.Snapshot);
                }
                cleaning = true;
                lock (_citySync)
                {
                    if (!current()) return snapshot;
                    using var lease = _cityStore.Open(owner);
                    var state = lease.Read();
                    lease.Save(new(state.Pending.Where(p => p.City != observation.City).ToArray(),
                        state.Confirmed.Append(observation.City).Distinct().ToArray()), current);
                }
                _cityRetries.Remove(observation.City); // Only a finished cleanup resets the failures.
            }
            catch (Exception error) when (error is not OperationCanceledException and not Account.AccountBridgeHostException &&
                !token.IsCancellationRequested && current())
            {
                var failures = Math.Min(5, (_cityRetries.GetValueOrDefault(observation.City)?.Failures ?? 0) + 1);
                // Same exponential rule as read failures, with a four-second floor: 4/8/16/30/30.
                // A lasting answer waits a full normal read period: any 4xx but 401 (an unverified or
                // mismatched identity is a 403), 429, or a receipt this client cannot accept.
                // Never remove the original observation on rejection.
                var rejected = error is Auth.ScmApiRateLimitException or Auth.ScmApiProtocolException or InvalidDataException ||
                    error is HttpRequestException { StatusCode: >= System.Net.HttpStatusCode.BadRequest and < System.Net.HttpStatusCode.InternalServerError }
                        and not HttpRequestException { StatusCode: System.Net.HttpStatusCode.Unauthorized };
                var delay = rejected ? 300 : Math.Min(30, 1 << Math.Min(failures + 1, 5));
                _cityRetries[observation.City] = new(failures, _time.GetUtcNow().AddSeconds(delay).UtcTicks, cleaning);
            }
        }
        return snapshot;
    }

    private long? NextCityAttempt(BridgeAccountContext owner)
    {
        if (_cityStore is null) return null;
        lock (_citySync)
        {
            using var lease = _cityStore.Open(owner);
            return lease.Read().Pending.Select(p => (long?)(_cityRetries.GetValueOrDefault(p.City)?.NextAttempt ?? 0)).Min();
        }
    }
}
