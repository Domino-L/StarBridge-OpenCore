using System.Net;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Called only for observed HTTP/transport failures of a directory read.
    // A generic retryable flag is not proof that old grants may survive.
    private static AccountBridgeHostException DirectoryReadFailure(HttpStatusCode? status) => status switch {
        HttpStatusCode.Unauthorized => new("communities.identityUnavailable", httpStatus: status),
        HttpStatusCode.Forbidden => new("communities.notAllowed", httpStatus: status),
        null or HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests => new("communities.readTransient", true, status),
        { } value when (int)value is >= 500 and <= 599 => new("communities.readTransient", true, status),
        _ => new("communities.unavailable", httpStatus: status)
    };
}
