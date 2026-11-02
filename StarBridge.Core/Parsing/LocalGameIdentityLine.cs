using System.Globalization;
using System.Text.RegularExpressions;
using StarBridge.Core.Identity;

namespace StarBridge.Core.Parsing;

public enum LocalGameIdentityLineState { Unrelated, Valid, Invalid }

// PlayerId is transient parser evidence, not a profile field or a wire contract.
public sealed record LocalGameIdentityRecord(string Handle, string PlayerId, DateTimeOffset ObservedAt)
{
    public long ResolutionTicks { get; init; } = TimeSpan.TicksPerSecond;
}

/// <summary>
/// Strict identity-only subset of the canonical PlayerOnline rule. It does not
/// change event parser ordering or infer identity from chat/party/ship records.
/// Callers must supply a complete UTF-8 line and independently verify its file scope.
/// </summary>
public static class LocalGameIdentityLine
{
    private static readonly Regex Marker = new(@"\bnickname\s*=.*\bplayerGEID\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private static readonly Regex Nicknames = new(@"\bnickname\s*=",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private static readonly Regex PlayerIds = new(@"\bplayerGEID\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private static readonly Regex Identity = new(
        """\bnickname="(?<handle>[^"\r\n]{2,64})"\s+playerGEID\b\s*=?\s*(?:"(?<quoted>[0-9]{1,24})"|(?<bare>[0-9]{1,24}))(?=\s|,|$)""",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
    private static readonly string[] Formats =
        ["yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK"];

    public static LocalGameIdentityLineState Parse(string line, DateTimeOffset now,
        out LocalGameIdentityRecord? record)
    {
        record = null;
        if (line.Length > 65536) return LocalGameIdentityLineState.Invalid;
        if (!Marker.IsMatch(line)) return LocalGameIdentityLineState.Unrelated;
        if (Nicknames.Matches(line).Count != 1 || PlayerIds.Matches(line).Count != 1)
            return LocalGameIdentityLineState.Invalid;
        if (line.Any(c => char.IsControl(c) && c != '\t') || line.Length < 22 || line[0] != '<')
            return LocalGameIdentityLineState.Invalid;
        if (!TryTimestamp(line, now, out var at, out var resolution))
            return LocalGameIdentityLineState.Invalid;
        try
        {
            var matches = Identity.Matches(line);
            if (matches.Count != 1) return LocalGameIdentityLineState.Invalid;
            var match = matches[0];
            var handle = match.Groups["handle"].Value;
            var id = match.Groups["quoted"].Success ? match.Groups["quoted"].Value : match.Groups["bare"].Value;
            if (handle != handle.Trim() || !IdentityBindingPolicy.IsValidGameName(handle) ||
                id.All(c => c == '0'))
                return LocalGameIdentityLineState.Invalid;
            // Leading zeroes cannot manufacture a second identity for the same numeric ID.
            record = new(handle, id.TrimStart('0'), at) { ResolutionTicks = resolution };
            return LocalGameIdentityLineState.Valid;
        }
        catch (RegexMatchTimeoutException) { return LocalGameIdentityLineState.Invalid; }
    }

    public static bool TryTimestamp(string line, DateTimeOffset now, out DateTimeOffset at, out long resolution)
    {
        at = default; resolution = TimeSpan.TicksPerSecond;
        if (line.Length < 22 || line[0] != '<') return false;
        var close = line.IndexOf('>');
        if (close is < 20 or > 40 || !DateTimeOffset.TryParseExact(line.AsSpan(1, close - 1), Formats,
                CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out at) ||
            at < DateTimeOffset.UnixEpoch || at > now) return false;
        if (line[20] == '.')
            for (var i = 21; i < close && char.IsAsciiDigit(line[i]); i++) resolution /= 10;
        return true;
    }

    // Log timestamps are quantized. Byte/session proof is still required by the
    // Host; a second-precision timestamp alone cannot prove a fresh game entry.
    public static bool MeetsSessionTime(LocalGameIdentityRecord record, DateTimeOffset capturedAt,
        DateTimeOffset processStartedAt, DateTimeOffset now) =>
        capturedAt.Offset == TimeSpan.Zero && processStartedAt.Offset == TimeSpan.Zero &&
        capturedAt >= DateTimeOffset.UnixEpoch && processStartedAt >= DateTimeOffset.UnixEpoch &&
        capturedAt <= now && processStartedAt <= now && record.ObservedAt.Offset == TimeSpan.Zero &&
        record.ObservedAt >= DateTimeOffset.UnixEpoch && record.ObservedAt <= now &&
        record.ResolutionTicks is 1 or 10 or 100 or 1000 or 10000 or 100000 or 1000000 or 10000000 &&
        AtOrOverlaps(record, capturedAt) && AtOrOverlaps(record, processStartedAt);

    // Difference comparison avoids DateTimeOffset overflow at the maximum date.
    private static bool AtOrOverlaps(LocalGameIdentityRecord record, DateTimeOffset boundary) =>
        record.ObservedAt >= boundary || (boundary - record.ObservedAt).Ticks < record.ResolutionTicks;
}
