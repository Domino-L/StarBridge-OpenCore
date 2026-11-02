using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.OfficialFleet;

// A cached projection is display only. Only positively classified transport
// failures permit retention; malformed data and denied reads never do.
internal static class OfficialFleetReadFailures
{
    internal static AccountBridgeOfficialFleetProfileRead ForProfile(Exception error, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var failure = error as AccountBridgeHostException ?? FromException(error, token);
        return new(failure.Code switch {
            AccountBridgeStableErrors.OfficialFleetReadTransient when failure.Retryable => "transientFailure",
            AccountBridgeStableErrors.OfficialFleetReadForbidden or AccountBridgeStableErrors.ReauthorizationRequired => "forbidden",
            AccountBridgeStableErrors.OfficialFleetDataInvalid => "invalid",
            _ => "unavailable"
        });
    }

    internal static AccountBridgeHostException FromStatus(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Unauthorized => new(AccountBridgeStableErrors.ReauthorizationRequired),
        HttpStatusCode.Forbidden => new(AccountBridgeStableErrors.OfficialFleetReadForbidden),
        HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or
            >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599 => new(AccountBridgeStableErrors.OfficialFleetReadTransient, true),
        _ => new(AccountBridgeStableErrors.OfficialFleetReadUnavailable)
    };

    internal static AccountBridgeHostException FromException(Exception error, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        return error switch {
            ScmRefreshTemporarilyUnavailableException => new(AccountBridgeStableErrors.OfficialFleetReadTransient, true),
            HttpRequestException { StatusCode: { } status } => FromStatus(status),
            // Bounded/shape validation failures are distinct from transport IO.
            System.Text.RegularExpressions.RegexMatchTimeoutException or
                InvalidDataException or JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException => new(AccountBridgeStableErrors.OfficialFleetDataInvalid),
            HttpRequestException or IOException or OperationCanceledException or TimeoutException =>
                new(AccountBridgeStableErrors.OfficialFleetReadTransient, true),
            _ => new(AccountBridgeStableErrors.OfficialFleetReadUnavailable)
        };
    }
}
