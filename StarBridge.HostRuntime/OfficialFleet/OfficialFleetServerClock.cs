using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.OfficialFleet;

// Display-identity time only: never used for OAuth, permission leases or local caches.
// Samples are request-bound and ephemeral. Nothing from the wire is written to diagnostics.
internal sealed class OfficialFleetServerClock(TimeProvider local, bool enableOffsetEstimation = false) : TimeProvider
{
    // 0.7.3 uses local UTC with symmetric display-only grace. Estimation is deferred to 0.7.4.
    internal static readonly TimeSpan Tolerance = TimeSpan.FromSeconds(10);
    internal static bool IsFuture(DateTimeOffset observed, DateTimeOffset now) => observed - now > Tolerance;
    // Every layer checks the original wire deadline; grace ends at until + 10s.
    internal static bool IsExpired(DateTimeOffset until, DateTimeOffset now) => now - until >= Tolerance;
    internal readonly record struct RequestTime(DateTimeOffset Utc, long Tick);
    private readonly object _gate = new();
    private TimeSpan? _offset;
    private (TimeSpan Offset, TimeSpan Error, string Source)? _candidate;
    private RequestTime? _anchor;
    private long _acceptedAt;
    private RequestTime? _lastServerAnchor;
    internal string DiagnosticCode { get; private set; } = "uninitialized";
    internal bool NeedsConfirmation { get { lock (_gate) return _candidate is not null; } }
    internal RequestTime Start() => new(local.GetUtcNow(), local.GetTimestamp());
    public override long GetTimestamp() => local.GetTimestamp();
    public override long TimestampFrequency => local.TimestampFrequency;

    public override DateTimeOffset GetUtcNow()
    {
        if (!enableOffsetEstimation) return local.GetUtcNow();
        lock (_gate)
        {
            var now = Start();
            if (_anchor is { } anchor && Math.Abs(((now.Utc - anchor.Utc) -
                local.GetElapsedTime(anchor.Tick, now.Tick)).TotalMilliseconds) > 250)
            {
                // A wall-clock adjustment is independently observable using monotonic time.
                Reset("identity-clock-changed");
            }
            if (_offset is not null && local.GetElapsedTime(_acceptedAt, now.Tick) > TimeSpan.FromMinutes(2))
                Reset("identity-time-stale");
            return now.Utc + (_offset ?? TimeSpan.Zero);
        }
    }

    internal AccountBridgeHostException TimeFailure()
    {
        // Called only after a structurally valid proof exceeds the ten-second grace.
        if (!enableOffsetEstimation) return new("official_fleet.identity_clock_skew");
        lock (_gate)
        {
            var now = Start();
            // Only recent, confirmed server evidence can justify the Windows time guidance.
            var skew = _offset is null && _lastServerAnchor is { } anchor &&
                local.GetElapsedTime(anchor.Tick, now.Tick) <= TimeSpan.FromMinutes(2) &&
                (now.Utc - (anchor.Utc + local.GetElapsedTime(anchor.Tick, now.Tick))).Duration() > Tolerance;
            return new(skew ? "official_fleet.identity_clock_skew" : "official_fleet.identity_time_invalid");
        }
    }

    internal static AccountBridgeHostException ErrorFor(TimeProvider clock) => clock is OfficialFleetServerClock corrected
        ? corrected.TimeFailure() : new("official_fleet.identity_clock_skew");

    internal void Observe(RequestTime start, HttpResponseMessage response, JsonElement root, Uri expected)
    {
        if (!enableOffsetEstimation) return;
        lock (_gate)
        {
            var end = Start();
            var elapsed = local.GetElapsedTime(start.Tick, end.Tick);
            var trusted = expected.IsAbsoluteUri && (expected.Scheme == "https" || expected.IsLoopback) &&
                response.StatusCode == HttpStatusCode.OK &&
                response.Headers.Age is not { Ticks: > 0 } &&
                (response.RequestMessage?.RequestUri is not { } actual || actual == expected) &&
                root.ValueKind == JsonValueKind.Object &&
                root.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() == root.EnumerateObject().Count() &&
                (!root.TryGetProperty("code", out var code) || code.ValueKind == JsonValueKind.Number && code.TryGetInt32(out var n) && n == 0);
            if (!trusted) { Reset("identity-time-untrusted"); return; }
            if (Math.Abs(((end.Utc - start.Utc) - elapsed).TotalMilliseconds) > 250)
            {
                Reset("identity-clock-changed"); return;
            }
            DateTimeOffset server;
            var precision = TimeSpan.Zero;
            var hasTime = root.TryGetProperty("serverTime", out var time) ||
                root.TryGetProperty("page", out var page) && page.ValueKind == JsonValueKind.Object && page.TryGetProperty("serverTime", out time);
            if (hasTime)
            {
                // An invalid explicit timestamp must not be hidden by a valid Date header.
                if (time.ValueKind != JsonValueKind.String || !time.TryGetDateTimeOffset(out server) || server.Offset != TimeSpan.Zero)
                { Reset("identity-time-untrusted"); return; }
            }
            else if (response.Headers.Date is { } date)
            {
                // HTTP-date is rounded down to a whole second; include that full quantization interval.
                server = date.AddMilliseconds(500); precision = TimeSpan.FromMilliseconds(500);
            }
            else { Reset("identity-time-missing"); return; }
            var error = elapsed / 2 + precision;
            if (elapsed < TimeSpan.Zero || error > TimeSpan.FromSeconds(1))
            { Reset("identity-time-rtt"); return; }
            var sample = server - (start.Utc + (end.Utc - start.Utc) / 2);
            if (sample.Duration() > TimeSpan.FromMinutes(2))
            { Reset("identity-time-untrusted"); return; }
            var source = expected.GetLeftPart(UriPartial.Authority);
            var allowance = error + TimeSpan.FromMilliseconds(100);
            if (_offset is { } prior && (prior - sample).Duration() <= allowance)
            {
                var smoothed = prior * 0.75 + sample * 0.25;
                // Smoothing cannot move the estimate outside this request's RTT interval.
                _offset = TimeSpan.FromTicks(Math.Clamp(smoothed.Ticks, (sample - error).Ticks, (sample + error).Ticks));
            }
            else if (_candidate is { } pending && pending.Source == source && _anchor is { } candidateAnchor &&
                local.GetElapsedTime(candidateAnchor.Tick, end.Tick) <= TimeSpan.FromMinutes(2) &&
                (pending.Offset - sample).Duration() <= pending.Error + allowance)
            {
                var low = Max(pending.Offset - pending.Error, sample - error);
                var high = Min(pending.Offset + pending.Error, sample + error);
                if (low > high) { _candidate = (sample, error, source); Report("identity-time-pending"); return; }
                _offset = low + (high - low) / 2;
            }
            else
            {
                // Never adopt an initial value or a discontinuity from one response.
                _offset = null; _candidate = (sample, error, source); _anchor = end;
                Report("identity-time-pending"); return;
            }
            _candidate = null; _anchor = end; _acceptedAt = end.Tick;
            _lastServerAnchor = new(end.Utc + _offset.Value, end.Tick);
            Report("identity-time-calibrated");
        }
    }

    private static TimeSpan Min(TimeSpan a, TimeSpan b) => a < b ? a : b;
    private static TimeSpan Max(TimeSpan a, TimeSpan b) => a > b ? a : b;
    private void Reset(string code) { _offset = null; _candidate = null; _anchor = null; Report(code); }
    private void Report(string code)
    {
        if (DiagnosticCode == code) return;
        DiagnosticCode = code;
        ScmAuthDiagnostics.Write("identity-clock", "identity-clock", code);
    }
}
