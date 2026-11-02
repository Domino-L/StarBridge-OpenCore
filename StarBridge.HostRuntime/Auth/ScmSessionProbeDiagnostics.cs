using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Net.WebSockets;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.HostRuntime.Auth;

// Temporary evidence only. No exception messages, headers, ticket URIs, stamps or session identifiers.
internal enum SessionProbePhase { Ticket, Connect, Heartbeat }
internal enum SessionProbeSnapshot { ValidatedResponse, AcceptedByHost }

internal static class ScmSessionProbeDiagnostics
{
    internal const string Prefix = "[DEBUG-session-probe-20261011]";

    [Conditional("STARBRIDGE_SESSION_PROBE")]
    internal static void Configure(ClientWebSocket socket) => socket.Options.CollectHttpResponseDetails = true;

    [Conditional("STARBRIDGE_SESSION_PROBE")]
    internal static void Snapshot(SessionProbeSnapshot stage, GameIdSettingsSnapshot snapshot) =>
        ScmAuthDiagnostics.Write("session-probe", "session-probe", "snapshot", FormatSnapshot(stage, snapshot));

    [Conditional("STARBRIDGE_SESSION_PROBE")]
    internal static void Realtime(SessionProbePhase phase, Uri endpoint, int status, int attempt, Exception? error) =>
        ScmAuthDiagnostics.Write("session-probe", "session-probe", "realtime", FormatRealtime(phase, endpoint, status, attempt, error));

    internal static string FormatSnapshot(SessionProbeSnapshot stage, GameIdSettingsSnapshot snapshot) =>
        FormattableString.Invariant($"{Prefix} kind=game-id stage={(stage == SessionProbeSnapshot.AcceptedByHost ? "host-accepted" : "response-validated")} schema={snapshot.SchemaVersion} revision={snapshot.Revision} locations={snapshot.Locations} canConfigure={(snapshot.CanConfigure ? "true" : "false")}");

    internal static string FormatRealtime(SessionProbePhase phase, Uri endpoint, int status, int attempt, Exception? error)
    {
        var host = endpoint.Host.ToLowerInvariant() switch
        {
            "scmk.flowcld.com" => "scmk.flowcld.com",
            "flowcld.xyz" => "flowcld.xyz",
            "scms.flowcld.com" => "scms.flowcld.com",
            "origin.flowcld.top" => "origin.flowcld.top",
            _ => "other"
        };
        var phaseName = phase switch { SessionProbePhase.Ticket => "ticket", SessionProbePhase.Connect => "connect", _ => "heartbeat" };
        var errorName = error switch
        {
            null => "none", WebSocketException => "websocket", HttpRequestException => "http",
            OperationCanceledException => "cancelled", TimeoutException => "timeout",
            System.Text.Json.JsonException => "json", InvalidOperationException => "invalid-operation", _ => "other"
        };
        if (status == 0 && error is HttpRequestException { StatusCode: { } code }) status = (int)code;
        var safeStatus = status is >= 100 and <= 599 ? status.ToString(CultureInfo.InvariantCulture) : "none";
        return FormattableString.Invariant($"{Prefix} kind=realtime phase={phaseName} host={host} status={safeStatus} attempt={Math.Max(1, attempt)} error={errorName}");
    }
}
