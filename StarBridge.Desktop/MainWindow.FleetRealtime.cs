using StarBridge.Core.Friends;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private CancellationTokenSource? _fleetActivityCts;
    private Task? _fleetActivityLoopTask;
    private string _fleetActivityInstanceId = "";
    private long _fleetActivityVersion = -1;

    private void StartFleetActivityLoop()
    {
        if (_fleetActivityLoopTask is { IsCompleted: false })
        {
            return;
        }

        _fleetActivityCts?.Dispose();
        _fleetActivityCts = new CancellationTokenSource();
        _fleetActivityLoopTask = RunFleetActivityLoopAsync(_fleetActivityCts.Token);
    }

    private void StopFleetActivityLoop()
    {
        _fleetActivityCts?.Cancel();
        _fleetActivityCts?.Dispose();
        _fleetActivityCts = null;
        _fleetActivityLoopTask = null;
    }

    private void ResetFleetActivityAccountSession()
    {
        StopFleetActivityLoop();
        _fleetActivityInstanceId = "";
        _fleetActivityVersion = -1;
    }

    private async Task RunFleetActivityLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (!CanSynchronizeUserData || !GetPresenceSharingDecision().CanReceiveRealtime)
            {
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
                continue;
            }

            var session = _accountSessionCoordinator.Capture();
            try
            {
                using var request = new HttpRequestMessage(
                    HttpMethod.Get,
                    _relayClient.BuildUri(
                        $"api/fleets/activity?after={_fleetActivityVersion}" +
                        $"&instance={Uri.EscapeDataString(_fleetActivityInstanceId)}" +
                        "&waitSeconds=20"));
                using var response = await _relayClient.SendAsync(request, cancellationToken);
                if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed)
                {
                    await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
                    continue;
                }

                response.EnsureSuccessStatusCode();
                var activity = await response.Content.ReadFromJsonAsync<RealtimeActivityContract>(
                    cancellationToken: cancellationToken);
                if (activity is null || !_accountSessionCoordinator.IsCurrent(session))
                {
                    continue;
                }

                var instanceChanged =
                    _fleetActivityInstanceId.Length > 0 &&
                    !string.Equals(_fleetActivityInstanceId, activity.InstanceId, StringComparison.Ordinal);
                var previousVersion = instanceChanged ? -1 : _fleetActivityVersion;
                _fleetActivityInstanceId = activity.InstanceId;
                _fleetActivityVersion = activity.Version;
                if (instanceChanged || previousVersion >= 0 && activity.Version > previousVersion)
                {
                    await RefreshFleetAfterRealtimeActivityAsync(session, cancellationToken);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch
            {
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    break;
                }
            }
        }
    }

    private async Task RefreshFleetAfterRealtimeActivityAsync(
        AccountSessionLease session,
        CancellationToken cancellationToken)
    {
        while ((_isNetworkSyncRunning || _isNetworkRealtimePullRunning || _isNetworkRealtimePushRunning) &&
               !cancellationToken.IsCancellationRequested &&
               _accountSessionCoordinator.IsCurrent(session))
        {
            await Task.Delay(TimeSpan.FromMilliseconds(100), cancellationToken);
        }

        if (cancellationToken.IsCancellationRequested ||
            !_accountSessionCoordinator.IsCurrent(session) ||
            !CanSynchronizeUserData)
        {
            return;
        }

        _isNetworkRealtimePullRunning = true;
        try
        {
            await PullNetworkFleetsAsync(
                silent: true,
                refreshBehavior: FleetDirectoryRefreshBehavior.PreserveVisibleOrder);
            await PullNetworkSnapshotsAsync(silent: true);
        }
        finally
        {
            _isNetworkRealtimePullRunning = false;
        }
    }
}
