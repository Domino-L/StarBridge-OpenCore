using System.Net;

namespace StarBridge.Desktop;

internal enum RelayServiceHealthState
{
    Unknown,
    Healthy,
    Degraded,
    Unhealthy,
    Unreachable
}

internal sealed record RelayHealthResponseContract(
    string? Status,
    string[]? Issues = null);

internal sealed record RelayHealthProbeResult(
    RelayServiceHealthState State,
    long LatencyMilliseconds,
    HttpStatusCode? StatusCode = null,
    Exception? Error = null)
{
    internal bool IsConnected =>
        State is RelayServiceHealthState.Healthy or RelayServiceHealthState.Degraded &&
        StatusCode is >= HttpStatusCode.OK and < HttpStatusCode.MultipleChoices;
}

internal sealed record RelayHealthPresentationDecision(
    RelayServiceHealthState State,
    int ConsecutiveProbeFailures,
    bool ShouldRequestProbe);

internal static class RelayHealthPresentationPolicy
{
    internal const int ConsecutiveFailuresBeforeNotice = 2;

    internal static RelayServiceHealthState Resolve(string? status, HttpStatusCode statusCode)
    {
        var normalized = (status ?? "").Trim().ToLowerInvariant();
        if (normalized == "unhealthy" || statusCode == HttpStatusCode.ServiceUnavailable)
        {
            return RelayServiceHealthState.Unhealthy;
        }

        if (normalized == "degraded")
        {
            return RelayServiceHealthState.Degraded;
        }

        return statusCode is >= HttpStatusCode.OK and < HttpStatusCode.MultipleChoices
            ? RelayServiceHealthState.Healthy
            : RelayServiceHealthState.Unreachable;
    }

    internal static bool ShouldShowUnavailable(int consecutiveFailures) =>
        consecutiveFailures >= ConsecutiveFailuresBeforeNotice;

    internal static RelayHealthPresentationDecision ObserveDataSynchronizationFailure(
        RelayServiceHealthState currentState,
        int consecutiveProbeFailures) =>
        new(
            currentState,
            consecutiveProbeFailures,
            ShouldRequestProbe: true);

    internal static RelayHealthPresentationDecision ObserveHealthProbe(
        RelayServiceHealthState currentState,
        int consecutiveProbeFailures,
        RelayServiceHealthState observedState)
    {
        if (observedState == RelayServiceHealthState.Unreachable)
        {
            var failures = Math.Min(consecutiveProbeFailures + 1, int.MaxValue);
            return new RelayHealthPresentationDecision(
                ShouldShowUnavailable(failures)
                    ? RelayServiceHealthState.Unreachable
                    : currentState,
                failures,
                ShouldRequestProbe: false);
        }

        return new RelayHealthPresentationDecision(
            observedState,
            ConsecutiveProbeFailures: 0,
            ShouldRequestProbe: false);
    }
}
