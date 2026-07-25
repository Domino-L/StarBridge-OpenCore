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
}
