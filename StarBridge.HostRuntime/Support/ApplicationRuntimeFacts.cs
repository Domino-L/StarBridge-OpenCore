namespace StarBridge.HostRuntime.Support;

using System.Diagnostics;
using System.Text.RegularExpressions;

public sealed record ApplicationRuntimeFacts(
    string? ApplicationVersion,
    string DataDirectory,
    string ImageCacheDirectory,
    bool ImageCacheExists,
    string? ServerOrigin);

/// <summary>On-demand metadata only: no directory creation, scan, registration,
/// network probe, update check, account restore or persistent setting write.</summary>
public sealed class ApplicationRuntimeFactsReader
{
    private readonly string _dataRoot;
    private readonly string? _applicationExecutable;
    private readonly Func<string?> _serverAddress;
    private readonly Func<string, string?> _productVersion;

    public ApplicationRuntimeFactsReader(string dataRoot, string? applicationExecutable,
        Func<string?>? serverAddress = null)
        : this(dataRoot, applicationExecutable, serverAddress,
            path => FileVersionInfo.GetVersionInfo(path).ProductVersion) { }

    internal ApplicationRuntimeFactsReader(string dataRoot, string? applicationExecutable,
        Func<string?>? serverAddress, Func<string, string?> productVersion)
    {
        if (!Path.IsPathFullyQualified(dataRoot)) throw new ArgumentException("An absolute data root is required.");
        _dataRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(dataRoot));
        _applicationExecutable = applicationExecutable;
        _serverAddress = serverAddress ?? (() => null);
        _productVersion = productVersion;
    }

    public ApplicationRuntimeFacts Read()
    {
        string? version = null;
        var executable = _applicationExecutable;
        try
        {
            if (executable is not null && Path.IsPathFullyQualified(executable) &&
                Path.GetExtension(executable).Equals(".exe", StringComparison.OrdinalIgnoreCase) &&
                File.Exists(executable))
                version = NormalizeVersion(_productVersion(executable));
        }
        catch { /* Unknown is not the version of Native Host or the WPF assembly. */ }
        string? origin = null;
        try { origin = SafeOrigin(_serverAddress()); }
        catch { /* Other local facts remain readable if account metadata is unavailable. */ }
        // Same image-cache location as WPF GetLocalImageCacheDirectory. This is
        // a location fact, not a claim that the folder exists or is safe to delete.
        var imageCache = Path.Combine(_dataRoot, "Images");
        return new(version, _dataRoot, imageCache, Directory.Exists(imageCache), origin);
    }

    internal static string? NormalizeVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 96) return null;
        var version = value.Trim();
        return Regex.IsMatch(version, @"^[0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9][A-Za-z0-9.+-]*)?$",
            RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(50)) ? version : null;
    }

    internal static string? SafeOrigin(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 4096 ||
            !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || string.IsNullOrEmpty(uri.Host)) return null;
        // Do not disclose credentials, path, query or fragment in status UI.
        return uri.GetComponents(UriComponents.SchemeAndServer, UriFormat.UriEscaped);
    }
}
