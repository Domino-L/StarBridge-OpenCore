using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Friends;

// Read-only classification. Relationship recheck and unknown failures deliberately
// keep their old unavailable code, which never permits cached display retention.
internal static class FriendsReadFailures
{
    internal static AccountBridgeHostException FromStatus(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Unauthorized => new("friends.identity_unavailable"),
        HttpStatusCode.Forbidden => new("friends.forbidden"),
        HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or
            >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599 => new("friends.read_transient", true),
        _ => new("friends.read_unavailable")
    };

    internal static AccountBridgeHostException FromTransport(Exception error, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (error is ScmRefreshTemporarilyUnavailableException) return new("friends.read_transient", true);
        return error is HttpRequestException { StatusCode: { } status }
            ? FromStatus(status) : new("friends.read_transient", true);
    }
}
