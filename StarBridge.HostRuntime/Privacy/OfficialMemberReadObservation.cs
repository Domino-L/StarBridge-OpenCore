using System.Diagnostics;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Privacy;

// Only fixed classifications and a numeric status cross this seam. No request data is retained.
internal sealed class OfficialMemberReadObservation : IDisposable
{
    private static readonly AsyncLocal<OfficialMemberReadObservation?> Active = new();
    private readonly OfficialMemberReadObservation? _previous = Active.Value;
    private readonly long _started = Stopwatch.GetTimestamp();
    internal string Code { get; private set; } = "ok";
    internal int? Status { get; private set; }
    internal long ElapsedMs => (long)Stopwatch.GetElapsedTime(_started).TotalMilliseconds;
    internal OfficialMemberReadObservation() => Active.Value = this;
    internal static void Sending() { if (Active.Value is { } read) read.Status = null; }
    internal static void Response(HttpStatusCode status) { if (Active.Value is { } read) read.Status = (int)status; }
    internal static void Failure(Exception error) => Active.Value?.Fail(error);
    internal void Fail(Exception error)
    {
        if (Code != "ok") return; // Preserve the cause before existing exception mapping.
        Status ??= error switch {
            HttpRequestException { StatusCode: { } status } => (int)status,
            AccountBridgeHostException { HttpStatus: { } status } => (int)status,
            _ => null
        };
        Code = error switch {
            TimeoutException or OperationCanceledException => "timeout",
            AccountBridgeHostException host => host.Code switch {
                AccountBridgeStableErrors.ReauthorizationRequired or "privacy_publication.identity_unavailable" or
                    "privacy_publication.identity_required" => "reauthorization",
                AccountBridgeStableErrors.OfficialFleetReadForbidden or "privacy_publication.forbidden" => "forbidden",
                AccountBridgeStableErrors.OfficialFleetReadTransient or "privacy_publication.temporarily_unavailable" => "transient",
                AccountBridgeStableErrors.OfficialFleetDataInvalid or "privacy_publication.response_invalid" => "data-invalid",
                AccountBridgeStableErrors.OfficialFleetReadUnavailable or "official_fleet.runtime_unavailable" or
                    "privacy_publication.unavailable" => "unavailable",
                "official_fleet.identity_unavailable" => "data-invalid",
                "host.unavailable" => "host-unavailable",
                _ => "unclassified"
            },
            HttpRequestException { StatusCode: HttpStatusCode.Unauthorized } => "reauthorization",
            HttpRequestException { StatusCode: HttpStatusCode.Forbidden } => "forbidden",
            HttpRequestException { StatusCode: HttpStatusCode.RequestTimeout or HttpStatusCode.GatewayTimeout } => "timeout",
            HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests or >= HttpStatusCode.InternalServerError } => "transient",
            HttpRequestException { StatusCode: not null } => "http-error",
            ScmRefreshTemporarilyUnavailableException or HttpRequestException => "transient",
            InvalidDataException or JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException => "data-invalid",
            IOException => "transient",
            _ => "unclassified"
        };
    }
    public void Dispose() => Active.Value = _previous;
}
