using System.Diagnostics;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

// Only aggregate numbers and closed vocabularies cross the diagnostic boundary.
internal sealed record OfficialChatAuthorReadDiagnostic(string Kind, string Code, int? Status, long ElapsedMs,
    int Requested, int Visible, int Hidden, int Unavailable, int InvalidVisible,
    long? ArrivalAgeMs, long? RemainingMs, bool AvatarData, bool VersionMatches);

internal sealed class OfficialChatAuthorReadObservation(string kind, Action<OfficialChatAuthorReadDiagnostic>? record) : IDisposable
{
    private readonly long _started = Stopwatch.GetTimestamp();
    private string _code = "ok";
    private int? _status;
    private int _requested, _visible, _hidden, _unavailable, _invalidVisible;
    private long? _arrivalAgeMs, _remainingMs;
    private bool _avatarData, _versionMatches;

    internal void Response(HttpStatusCode status) { try { _status = (int)status; } catch { } }
    internal void Requested(int count) { try { _requested = count; } catch { } }
    internal void ParseFailed() { try { _code = "parse-failed"; } catch { } }

    internal void Raw(JsonElement root, string? expectedVersion = null)
    {
        try
        {
            if (!root.TryGetProperty("identities", out var rows) || rows.ValueKind != JsonValueKind.Array) return;
            // The transport already bounds bytes; bound diagnostic work independently.
            foreach (var row in rows.EnumerateArray().Take(100))
            {
                if (row.ValueKind != JsonValueKind.Object || !row.TryGetProperty("state", out var state) || state.ValueKind != JsonValueKind.String) continue;
                switch (state.GetString())
                {
                    case "visible":
                        _visible++;
                        _avatarData |= row.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String && avatar.GetString() is { Length: > 0 };
                        _versionMatches |= expectedVersion is not null && row.TryGetProperty("identityVersion", out var version) &&
                            version.ValueKind == JsonValueKind.String && version.GetString() == expectedVersion;
                        break;
                    case "hidden": _hidden++; break;
                    case "unavailable": _unavailable++; break;
                }
            }
        }
        catch { /* Malformed diagnostics never replace the original parser. */ }
    }

    // Reuse the exact time and Current decision made by AuthorIdentities. Never re-read its clock,
    // re-run validation, or retain the identity that the parser may replace with unavailable.
    internal void Visible(DateTimeOffset observed, DateTimeOffset until, DateTimeOffset now, bool current)
    {
        try
        {
            if (!current) _invalidVisible++;
            var age = (long)(now - observed).TotalMilliseconds;
            var remaining = (long)(until - now).TotalMilliseconds;
            _arrivalAgeMs = _arrivalAgeMs is { } previousAge ? Math.Max(previousAge, age) : age;
            _remainingMs = _remainingMs is { } previousRemaining ? Math.Min(previousRemaining, remaining) : remaining;
        }
        catch { }
    }

    internal void Fail(Exception error, bool disabled = false)
    {
        try
        {
            _status ??= error is AccountBridgeHostException host ? (int?)host.HttpStatus :
                error is HttpRequestException http ? (int?)http.StatusCode : null;
            _code = error switch
            {
                _ when disabled => "disabled",
                OperationCanceledException => "cancelled",
                _ when _status is >= 300 => "http-error",
                HttpRequestException or IOException => "http-error",
                AccountBridgeHostException { Code: "communities.unavailable" } => "http-error",
                AccountBridgeHostException { Code: "communities.dataInvalid" } or JsonException or InvalidOperationException or
                    KeyNotFoundException or FormatException or OverflowException => "parse-failed",
                _ => "unclassified"
            };
        }
        catch { }
    }

    public void Dispose()
    {
        try
        {
            record?.Invoke(new(kind, _code, _status, (long)Stopwatch.GetElapsedTime(_started).TotalMilliseconds,
                _requested, _visible, _hidden, _unavailable, _invalidVisible, _arrivalAgeMs, _remainingMs, _avatarData, _versionMatches));
        }
        catch { /* Logging, including a custom observer, cannot change success or the exception instance. */ }
    }
}
