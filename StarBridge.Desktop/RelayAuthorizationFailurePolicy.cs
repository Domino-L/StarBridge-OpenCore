using System.Net;

namespace StarBridge.Desktop;

/// <summary>
/// Keeps authentication loss separate from an authenticated permission denial.
/// A 403 response must never retire the SCM or compatibility account session.
/// </summary>
public static class RelayAuthorizationFailurePolicy
{
    public static bool InvalidatesSession(HttpStatusCode? statusCode) =>
        statusCode == HttpStatusCode.Unauthorized;
}
