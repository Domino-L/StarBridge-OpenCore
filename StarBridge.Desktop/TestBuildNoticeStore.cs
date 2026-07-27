using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed class TestBuildNoticeStore
{
    internal const string CurrentTermsVersion = "2026-07-27-v2";
    private const int CurrentSchemaVersion = 1;
    private const string LicenseFileName = "OFFICIAL-BINARY-LICENSE.txt";

    private readonly string _acknowledgementPath;
    private readonly string _licensePath;

    public TestBuildNoticeStore(string? baseDirectory = null, string? licensePath = null)
    {
        var root = string.IsNullOrWhiteSpace(baseDirectory)
            ? DesktopAppConfig.ConfigDirectory
            : baseDirectory;
        _acknowledgementPath = Path.Combine(root, "official-binary-license.accepted.json");
        _licensePath = string.IsNullOrWhiteSpace(licensePath)
            ? ResolveLicensePath()
            : Path.GetFullPath(licensePath);
    }

    public bool IsAcknowledged()
    {
        try
        {
            var currentHash = GetCurrentTermsSha256();
            if (string.IsNullOrWhiteSpace(currentHash) ||
                !File.Exists(_acknowledgementPath))
            {
                return false;
            }

            var acknowledgement = JsonSerializer.Deserialize<LicenseAcknowledgement>(
                File.ReadAllText(_acknowledgementPath, Encoding.UTF8));
            return acknowledgement is not null &&
                   acknowledgement.SchemaVersion == CurrentSchemaVersion &&
                   string.Equals(
                       acknowledgement.TermsVersion,
                       CurrentTermsVersion,
                       StringComparison.Ordinal) &&
                   string.Equals(
                       acknowledgement.TermsSha256,
                       currentHash,
                       StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    public bool TryAcknowledge(out string? error)
    {
        var temporaryPath = _acknowledgementPath + ".tmp";
        try
        {
            var termsSha256 = GetCurrentTermsSha256();
            if (string.IsNullOrWhiteSpace(termsSha256))
            {
                throw new FileNotFoundException(
                    "未找到随应用提供的完整客户端许可。",
                    _licensePath);
            }

            var directory = Path.GetDirectoryName(_acknowledgementPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var acknowledgement = new LicenseAcknowledgement(
                CurrentSchemaVersion,
                CurrentTermsVersion,
                DateTimeOffset.UtcNow,
                GetCurrentAppVersion(),
                termsSha256);
            var json = JsonSerializer.Serialize(
                acknowledgement,
                new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(temporaryPath, json, new UTF8Encoding(false));
            File.Move(temporaryPath, _acknowledgementPath, overwrite: true);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            TryDelete(temporaryPath);
            error = ex.Message;
            return false;
        }
    }

    public string ReadCurrentTerms()
    {
        try
        {
            return File.ReadAllText(_licensePath, Encoding.UTF8);
        }
        catch
        {
            return "未能读取随应用提供的完整客户端许可。请重新安装应用，或前往官方发布页查看 OFFICIAL-BINARY-LICENSE.txt。";
        }
    }

    private string GetCurrentTermsSha256()
    {
        if (!File.Exists(_licensePath))
        {
            return string.Empty;
        }

        return Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(_licensePath)))
            .ToLowerInvariant();
    }

    private static string GetCurrentAppVersion()
    {
        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version ??
                              typeof(TestBuildNoticeStore).Assembly.GetName().Version;
        return assemblyVersion?.ToString() ?? "unknown";
    }

    private static string ResolveLicensePath()
    {
        foreach (var candidate in new[]
        {
            Path.Combine(AppContext.BaseDirectory, LicenseFileName),
            Path.Combine(AppContext.BaseDirectory, "Licenses", LicenseFileName)
        })
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        for (var depth = 0; depth < 8 && current is not null; depth++, current = current.Parent)
        {
            var candidate = Path.Combine(current.FullName, "LICENSES", LicenseFileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return Path.Combine(AppContext.BaseDirectory, LicenseFileName);
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A stale temporary acknowledgement is harmless and can be replaced later.
        }
    }

    private sealed record LicenseAcknowledgement(
        int SchemaVersion,
        string TermsVersion,
        DateTimeOffset AcceptedAtUtc,
        string AppVersion,
        string TermsSha256);
}
