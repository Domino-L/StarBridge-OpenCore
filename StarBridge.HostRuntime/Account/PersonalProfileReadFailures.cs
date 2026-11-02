using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

/// <summary>Display retention is permitted only for a known transient read failure.
/// This policy does not authorize a write, restore a session or retry a request.</summary>
internal static class PersonalProfileReadFailures
{
    internal static bool IsReadFailure(string code) => code is
        AccountBridgeStableErrors.PersonalProfileReadUnavailable or
        AccountBridgeStableErrors.PersonalProfileReadTransient or
        AccountBridgeStableErrors.PersonalProfileReadForbidden or
        AccountBridgeStableErrors.PersonalProfileDataInvalid or
        AccountBridgeStableErrors.ReauthorizationRequired;

    internal static AccountBridgeHostException FromStatus(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Unauthorized => new(AccountBridgeStableErrors.ReauthorizationRequired),
        HttpStatusCode.Forbidden => new(AccountBridgeStableErrors.PersonalProfileReadForbidden),
        HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or
            >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599 => Unavailable(retryable: true),
        _ => Unavailable(retryable: false)
    };

    internal static AccountBridgeHostException FromException(Exception error, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        return error switch
        {
            ScmRefreshTemporarilyUnavailableException => Unavailable(retryable: true),
            HttpRequestException { StatusCode: { } status } => FromStatus(status),
            HttpRequestException or OperationCanceledException => Unavailable(retryable: true),
            IOException => Unavailable(retryable: true),
            JsonException or InvalidOperationException or InvalidDataException =>
                new(AccountBridgeStableErrors.PersonalProfileDataInvalid),
            _ => Unavailable(retryable: false)
        };
    }

    private static AccountBridgeHostException Unavailable(bool retryable) =>
        new(retryable ? AccountBridgeStableErrors.PersonalProfileReadTransient :
            AccountBridgeStableErrors.PersonalProfileReadUnavailable, retryable);
}
