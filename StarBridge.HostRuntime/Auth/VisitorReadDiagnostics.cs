using System.Globalization;
using System.IO;
using System.Threading;

namespace StarBridge.HostRuntime.Auth;

// Temporary opt-in evidence. Never accepts identities, URLs, response bodies or exception messages.
internal static class VisitorReadDiagnostics
{
    internal const string EnvironmentKey = "STARBRIDGE_VISITOR_READ_DIAGNOSTICS";
    private static readonly AsyncLocal<Observation?> Current = new();
    private static readonly object Gate = new();
    private static long _sequence;
    internal enum Route { Unresolved, LegacyMember, ScmMember, MarketTrader }
    internal enum Phase { Enter, RouteSelected, Sending, Response, Failed, Completed }
    internal static readonly HttpRequestOptionsKey<bool> VisitorRequest = new("StarBridge.VisitorDiagnosticRequest");

    internal static IDisposable Begin()
    {
        var previous = Current.Value;
        var enabled = Environment.GetEnvironmentVariable(EnvironmentKey) == "1";
        Current.Value = enabled ? new(Interlocked.Increment(ref _sequence)) : null;
        Write(Phase.Enter);
        return new Scope(previous);
    }

    internal static void Select(Route route)
    {
        if (Current.Value is { } observation) observation.Route = route;
        Write(Phase.RouteSelected);
    }

    internal static void Write(Phase phase, int status = 0, string? code = null)
    {
        if (Current.Value is not { } observation) return;
        try
        {
            var line = Format(observation.Sequence, observation.Route, phase, status, code);
            Append(Path.Combine(HostDataRoot.CurrentRoot, "visitor-read-diagnostics.log"), line);
        }
        catch { /* Diagnostic IO must not affect product behavior. */ }
    }

    internal static string Format(long sequence, Route route, Phase phase, int status, string? code) =>
        string.Create(CultureInfo.InvariantCulture,
            $"{DateTimeOffset.UtcNow:O} sample={Math.Max(0, sequence)} route={(Enum.IsDefined(route) ? route : Route.Unresolved)} phase={(Enum.IsDefined(phase) ? phase : Phase.Failed)} http={(status is >= 100 and <= 599 ? status : 0)} code={SafeCode(code)}");

    private static string SafeCode(string? code) => code switch
    {
        null => "none",
        "communities.refreshRequired" => "stale_reference",
        "users.invalid_request" => "invalid_request",
        "profile.visitor_not_visible" => "visitor_denied",
        "profile.visitor_rate_limited" => "visitor_rate_limited",
        "profile.visitor_identity_unavailable" => "identity_unavailable",
        "profile.visitor_unavailable" => "visitor_unavailable",
        "transport" => "transport",
        "cancelled" => "cancelled",
        _ => "other"
    };

    internal static void Append(string path, string line)
    {
        lock (Gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            // Retain the latest observations rather than silently stop after a lifetime quota.
            var previous = File.Exists(path) && new FileInfo(path).Length <= 128 * 1024
                ? File.ReadAllLines(path).TakeLast(255) : Enumerable.Empty<string>();
            File.WriteAllLines(path, previous.Append(line));
        }
    }

    private sealed class Observation(long sequence)
    {
        internal long Sequence { get; } = sequence;
        internal Route Route { get; set; }
    }
    private sealed class Scope(Observation? previous) : IDisposable
    {
        public void Dispose() => Current.Value = previous;
    }
}
