using System.Diagnostics;
using System.Globalization;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Friends;

// Temporary opt-in evidence: never records targets, bodies, credentials or exception messages.
internal enum FriendsProbePhase { RelayHttp, RelayProjection, DirectoryInitial, ScmIdentity, RelationshipRecheck, DirectoryProjection, HostBoundary }
internal static class FriendsReadProbeDiagnostics
{
    internal const string Prefix = "[DEBUG-friends-read-20261011]";
    [Conditional("STARBRIDGE_SESSION_PROBE")]
    internal static void Record(FriendsProbePhase phase, int status = 0, Exception? error = null) =>
        ScmAuthDiagnostics.Write("friends-probe", "friends-probe", "observation", Format(phase, status, error));

    [Conditional("STARBRIDGE_SESSION_PROBE")]
    internal static void DispatchFailure(string requestName, Exception error)
    {
        if (requestName == AccountBridgeRequestNames.ReadFriends) Record(FriendsProbePhase.HostBoundary, 0, error);
    }

    internal static string Format(FriendsProbePhase phase, int status, Exception? error)
    {
        var name = phase switch {
            FriendsProbePhase.RelayHttp => "relay-http", FriendsProbePhase.RelayProjection => "relay-projection",
            FriendsProbePhase.DirectoryInitial => "directory-initial", FriendsProbePhase.ScmIdentity => "scm-identity",
            FriendsProbePhase.RelationshipRecheck => "relationship-recheck", FriendsProbePhase.DirectoryProjection => "directory-projection",
            _ => "host-boundary"
        };
        var code = error switch {
            null => "none",
            AccountBridgeHostException host => host.Code switch {
                "friends.read_unavailable" => "friends.read_unavailable", "friends.identity_unavailable" => "friends.identity_unavailable",
                "friends.read_transient" => "friends.read_transient",
                "friends.forbidden" => "friends.forbidden", "friends.data_invalid" => "friends.data_invalid",
                "friends.invalid_request" => "friends.invalid_request", "account.reauthorization_required" => "account.reauthorization_required",
                _ => "other"
            },
            BridgeProtocolException => "bridge-error",
            HttpRequestException or IOException or OperationCanceledException => "friends.read_unavailable",
            _ => "other"
        };
        var category = error switch {
            null => "none", AccountBridgeHostException => "account", BridgeProtocolException => "bridge",
            OperationCanceledException => "cancelled", HttpRequestException => "http", IOException => "io",
            System.Text.Json.JsonException => "json", InvalidOperationException => "invalid-operation", _ => "other"
        };
        if (status == 0 && error is HttpRequestException { StatusCode: { } httpStatus }) status = (int)httpStatus;
        var safeStatus = status is >= 100 and <= 599 ? status.ToString(CultureInfo.InvariantCulture) : "none";
        return $"{Prefix} phase={name} status={safeStatus} code={code} error={category} outcome={(error is null ? "completed" : "failed")}";
    }
}
