using System.Diagnostics;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

// Per logical Host read, including retries. Only fixed codes and numeric HTTP metadata escape.
internal sealed class OfficialAnnouncementReadObservation : IDisposable
{
    private static readonly AsyncLocal<OfficialAnnouncementReadObservation?> Active = new();
    private readonly OfficialAnnouncementReadObservation? _previous = Active.Value;
    private readonly long _started = Stopwatch.GetTimestamp();
    internal string Code { get; private set; } = "ok";
    internal int? Status { get; private set; }
    internal long ElapsedMs => (long)Stopwatch.GetElapsedTime(_started).TotalMilliseconds;

    internal OfficialAnnouncementReadObservation() => Active.Value = this;
    internal static void Sending()
    {
        try { if (Active.Value is { } read) read.Status = null; }
        catch { /* Observation must not preempt HTTP. */ }
    }
    internal static void Response(HttpStatusCode status)
    {
        try { if (Active.Value is { } read) read.Status = (int)status; }
        catch { /* Observation must not preempt decoding. */ }
    }
    internal void Fail(Exception error)
    {
        Status ??= error switch
        {
            HttpRequestException { StatusCode: { } status } => (int)status,
            AccountBridgeHostException { HttpStatus: { } status } => (int)status,
            _ => null
        };
        Code = error switch
        {
            OperationCanceledException or TimeoutException => "timeout",
            BridgeStaleGenerationException => "stale-generation",
            _ when Status is >= 300 => "http-error",
            AccountBridgeHostException host => host.Code switch
            {
                "communities.notAllowed" => "notAllowed",
                "communities.dataInvalid" => Status is >= 200 and <= 299 ? "parse-failed" : "invalid",
                "communities.identityUnavailable" => "identityUnavailable",
                AccountBridgeStableErrors.ReauthorizationRequired => "reauthorization-required",
                "communities.refreshRequired" => "reference-expired",
                "communities.announcementsChanged" => "conflict",
                "communities.upgradeRequired" => "upgrade-required",
                "communities.notFound" => "not-found",
                "communities.unavailable" => "unavailable",
                _ => "unclassified"
            },
            JsonException or InvalidDataException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException => "parse-failed",
            HttpRequestException or IOException => "network",
            _ => "unclassified"
        };
    }

    public void Dispose() => Active.Value = _previous;
}
