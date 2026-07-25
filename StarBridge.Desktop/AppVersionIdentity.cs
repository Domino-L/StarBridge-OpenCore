using System.Reflection;

namespace StarBridge.Desktop;

internal static class AppVersionIdentity
{
    private const string InvalidBuildFallbackVersion = "0.0.0";

    public static string GetCurrentVersion()
    {
        var assembly = Assembly.GetExecutingAssembly();
        return Resolve(
            assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
            assembly.GetCustomAttribute<AssemblyFileVersionAttribute>()?.Version,
            assembly.GetName().Version,
            InvalidBuildFallbackVersion);
    }

    internal static string Resolve(
        string? informationalVersion,
        string? fileVersion,
        Version? assemblyVersion,
        string fallbackVersion)
    {
        return NormalizeProductVersion(informationalVersion)
            ?? NormalizeProductVersion(fileVersion)
            ?? NormalizeProductVersion(assemblyVersion?.ToString())
            ?? fallbackVersion;
    }

    private static string? NormalizeProductVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Trim().TrimStart('v', 'V');
        var metadataStart = normalized.IndexOf('+');
        if (metadataStart >= 0)
        {
            normalized = normalized[..metadataStart];
        }

        return Version.TryParse(normalized, out _) ? normalized : null;
    }
}
