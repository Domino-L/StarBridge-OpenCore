namespace StarBridge.Core.Profiles;

public sealed record ProfileTimeZoneResolution(
    string? RequestedId,
    string IanaId,
    string WindowsId,
    TimeZoneInfo TimeZone,
    bool UsedUtcFallback);

/// <summary>
/// Keeps the profile wire format on IANA identifiers while resolving a Windows
/// <see cref="TimeZoneInfo"/> for the desktop. Unknown identifiers fall back to
/// UTC without rewriting or discarding the original server value.
/// </summary>
public static class ProfileTimeZoneContract
{
    public const string UtcIanaId = "Etc/UTC";
    public const string UtcWindowsId = "UTC";

    public static ProfileTimeZoneResolution ResolveIana(string? requestedId)
    {
        if (string.IsNullOrWhiteSpace(requestedId))
        {
            return UtcFallback(requestedId);
        }

        var normalized = NormalizeRequestedId(requestedId);
        if (TryResolveIana(normalized, out var timeZone, out var windowsId))
        {
            return new ProfileTimeZoneResolution(
                requestedId?.Trim(),
                normalized,
                windowsId,
                timeZone,
                UsedUtcFallback: false);
        }

        return UtcFallback(requestedId);
    }

    public static bool TryConvertWindowsToIana(string? windowsId, out string ianaId)
    {
        ianaId = string.Empty;
        if (string.IsNullOrWhiteSpace(windowsId))
        {
            return false;
        }

        var normalized = windowsId.Trim();
        if (normalized.Equals(UtcWindowsId, StringComparison.OrdinalIgnoreCase))
        {
            ianaId = UtcIanaId;
            return true;
        }

        if (!TimeZoneInfo.TryConvertWindowsIdToIanaId(normalized, out var convertedIanaId) ||
            string.IsNullOrWhiteSpace(convertedIanaId))
        {
            return false;
        }

        ianaId = convertedIanaId;
        return true;
    }

    private static string NormalizeRequestedId(string? requestedId)
    {
        var normalized = requestedId?.Trim();
        return normalized is null ||
               normalized.Equals("UTC", StringComparison.OrdinalIgnoreCase) ||
               normalized.Equals("Etc/UTC", StringComparison.OrdinalIgnoreCase)
            ? UtcIanaId
            : normalized;
    }

    private static ProfileTimeZoneResolution UtcFallback(string? requestedId) => new(
        requestedId?.Trim(),
        UtcIanaId,
        UtcWindowsId,
        TimeZoneInfo.Utc,
        UsedUtcFallback: true);

    private static bool TryResolveIana(
        string ianaId,
        out TimeZoneInfo timeZone,
        out string windowsId)
    {
        timeZone = TimeZoneInfo.Utc;
        windowsId = UtcWindowsId;

        if (!IsIanaIdentifier(ianaId))
        {
            return false;
        }

        if (ianaId.Equals(UtcIanaId, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!TimeZoneInfo.TryConvertIanaIdToWindowsId(ianaId, out var convertedWindowsId) ||
            string.IsNullOrWhiteSpace(convertedWindowsId))
        {
            return false;
        }

        try
        {
            timeZone = TimeZoneInfo.FindSystemTimeZoneById(convertedWindowsId);
            windowsId = convertedWindowsId;
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            try
            {
                timeZone = TimeZoneInfo.FindSystemTimeZoneById(ianaId);
                windowsId = convertedWindowsId;
                return true;
            }
            catch (TimeZoneNotFoundException)
            {
                return false;
            }
            catch (InvalidTimeZoneException)
            {
                return false;
            }
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }

    private static bool IsIanaIdentifier(string candidate) =>
        candidate.Equals(UtcIanaId, StringComparison.OrdinalIgnoreCase) ||
        candidate.Contains('/', StringComparison.Ordinal);
}
