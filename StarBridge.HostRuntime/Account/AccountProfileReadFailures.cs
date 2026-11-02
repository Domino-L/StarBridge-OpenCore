using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

/// <summary>Only a known transient account-profile read can use a display cache.
/// Unknown internal errors remain the Dispatcher's host_error, never a retry hint.</summary>
internal static class AccountProfileReadFailures
{
    internal static AccountBridgeHostException? Classify(Exception error) => error switch
    {
        ScmRefreshTemporarilyUnavailableException => Transient(),
        HttpRequestException { StatusCode: { } status } => status switch
        {
            HttpStatusCode.Unauthorized => new(AccountBridgeStableErrors.ReauthorizationRequired),
            HttpStatusCode.Forbidden => new(AccountBridgeStableErrors.ProfileReadForbidden),
            HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or
                >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599 => Transient(),
            _ => new(AccountBridgeStableErrors.ProfileReadUnavailable)
        },
        ScmApiProtocolException or JsonException or InvalidDataException or RegexMatchTimeoutException =>
            new(AccountBridgeStableErrors.ProfileDataInvalid),
        HttpRequestException or IOException or OperationCanceledException or TimeoutException => Transient(),
        _ => null
    };

    private static AccountBridgeHostException Transient() => new(AccountBridgeStableErrors.ProfileReadTransient, true);

    internal static AccountBridgeHostException? Directory(Exception error)
    {
        var classified = Classify(error);
        // This endpoint is public. Its 401/403 cannot retire an independently
        // verified private account/profile or be treated as recoverable transport.
        return classified is null ? null : new(AccountBridgeStableErrors.ProfileDirectoryUnavailable,
            classified.Code == AccountBridgeStableErrors.ProfileReadTransient && classified.Retryable);
    }
}
