namespace StarBridge.HostRuntime.Updates;

/// <summary>Read-only offer projection. Installation remains a separate capability.</summary>
public sealed record ApplicationUpdateCheck(string Status, string? Version = null, string? Notes = null);

public interface IApplicationUpdateSource : IDisposable
{
    Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken cancellation = default);
}

internal static class ApplicationUpdateVersion
{
    // Flutter ProductVersion includes +buildNumber; release manifests deliberately
    // do not. Match the existing full-installer package identity, not a fourth
    // release component invented from the build number.
    internal static Version ParseInstalled(string? value)
    {
        if (value is null || value.Length > 96) throw new InvalidDataException("Invalid installed version.");
        var split = value.Split('+');
        if (split.Length > 2 || (split.Length == 2 &&
            (split[1].Length == 0 || split[1].Any(c => c < '0' || c > '9'))))
            throw new InvalidDataException("Invalid installed build number.");
        return Parse(split[0]);
    }

    internal static Version Parse(string? value)
    {
        if (value is null || value.Length > 96 ||
            value.Split('.').Length is not (3 or 4) ||
            value.Any(c => c != '.' && (c < '0' || c > '9')) ||
            !Version.TryParse(value, out var version))
            throw new InvalidDataException("Invalid release version.");
        return new Version(version.Major, version.Minor, version.Build, Math.Max(0, version.Revision));
    }
}
