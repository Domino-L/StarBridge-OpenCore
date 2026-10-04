using System.Text.Json;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private readonly object _backgroundObservationGate = new();
    private readonly CancellationTokenSource _backgroundObservationStop = new();
    private bool _backgroundObservationRunning;
    private BackgroundObservation? _backgroundObservationPending;
    private Task _backgroundObservationTask = Task.CompletedTask;
    internal Task BackgroundObservationCompletion { get { lock (_backgroundObservationGate) return _backgroundObservationTask; } }
    private sealed record BackgroundObservation(string Bearer, JsonElement[] Fleets,
        Action<PlayerActivitySourceSnapshot> Observed, string ViewerId, DateTimeOffset AcceptedAt);

    // The HUD never waits on a separate optional player feed. Preserve reminders
    // with one active read and one replaceable latest observation, not one task
    // for every roster refresh. The Host callback rechecks account/policy scope.
    private void QueueWpfS2PlayerObservation(string bearer, JsonElement[] fleets,
        Action<PlayerActivitySourceSnapshot>? observed, string viewerId)
    {
        if (observed is null) return;
        lock (_backgroundObservationGate)
        {
            if (_backgroundObservationStop.IsCancellationRequested) return;
            _backgroundObservationPending = new(bearer, fleets, observed, viewerId, DateTimeOffset.UtcNow);
            if (_backgroundObservationRunning) return;
            _backgroundObservationRunning = true;
            _backgroundObservationTask = Task.Run(ReadBackgroundObservationsAsync);
        }
    }

    private async Task ReadBackgroundObservationsAsync()
    {
        while (true)
        {
            BackgroundObservation next;
            lock (_backgroundObservationGate)
            {
                if (_backgroundObservationStop.IsCancellationRequested || _backgroundObservationPending is null)
                { _backgroundObservationPending = null; _backgroundObservationRunning = false; return; }
                next = _backgroundObservationPending;
                _backgroundObservationPending = null;
            }
            try
            {
                if (DateTimeOffset.UtcNow - next.AcceptedAt >= TimeSpan.FromSeconds(40)) continue;
                await ObserveWpfS2Players(next.Bearer, next.Fleets, snapshot =>
                {
                    if (!_backgroundObservationStop.IsCancellationRequested &&
                        DateTimeOffset.UtcNow - next.AcceptedAt < TimeSpan.FromSeconds(40)) next.Observed(snapshot);
                }, _backgroundObservationStop.Token, next.ViewerId).ConfigureAwait(false);
            }
            catch { /* Auxiliary failure never invalidates the authorized roster. */ }
        }
    }

    private void StopBackgroundObservations()
    {
        lock (_backgroundObservationGate) _backgroundObservationPending = null;
        _backgroundObservationStop.Cancel();
    }

    private async Task ObserveWpfS2Players(string bearer, JsonElement[] fleets,
        Action<PlayerActivitySourceSnapshot>? observed, CancellationToken token, string viewerId)
    {
        if (observed is null) return;
        try
        {
            var players = fleets.Length == 0 ? JsonSerializer.SerializeToElement(Array.Empty<object>()) :
                await WorkspaceJson(bearer, "/api/players", token, 8 * 1024 * 1024);
            token.ThrowIfCancellationRequested();
            observed(PlayerActivitySources.Organization(fleets, players, viewerId));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch { /* No observation on a failed, missing or malformed optional source. */ }
    }
}
