using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

public sealed record FlutterPackageIdentity(int SchemaVersion, string ClientKind, string Architecture,
    string Channel, string Version, string Executable);

/// <summary>Validates and stages only. Never executes a package or modifies an installation.</summary>
public static class FlutterUpdateStager
{
    public const string IdentityFile = "starbridge-package.json";
    // Match WindowsNativeHostPlatformPort.resolvePackagedExecutable and the
    // canonical Release bundle. Updating only the Flutter shell is not a package.
    internal static IReadOnlyList<string> RequiredFiles { get; } = Array.AsReadOnly(new[] {
        "starbridge_flutter.exe", "flutter_windows.dll", "data/icudtl.dat", "data/app.so",
        "native_host/StarBridge.NativeHost.exe", "native_host/StarBridge.NativeHost.dll",
        "native_host/StarBridge.NativeHost.deps.json", "native_host/StarBridge.NativeHost.runtimeconfig.json",
        "native_host/StarBridge.HostRuntime.dll", "native_host/StarBridge.NativeBridge.dll",
        "native_host/StarBridge.Core.dll", "native_host/StarBridge.OverlayRuntime.Windows.dll"
    });
    private const long MaximumExpandedBytes = 4L * 1024 * 1024 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };

    public static string Prepare(string packagePath, string ownedStagingRoot, FlutterUpdateManifest manifest,
        FlutterUpdateManifestVerifier verifier, FlutterUpdateTarget target, DateTimeOffset now,
        CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!verifier.Verify(manifest, target, now)) throw new InvalidDataException("Package is not newer.");
        RequirePlainDirectory(ownedStagingRoot);
        using var input = new FileStream(packagePath, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length != manifest.PackageBytes ||
            !CryptographicOperations.FixedTimeEquals(SHA256.HashData(input), Convert.FromHexString(manifest.PackageSha256)))
            throw new InvalidDataException("Package hash or size does not match the signed manifest.");
        input.Position = 0;
        using var archive = new ZipArchive(input, ZipArchiveMode.Read, leaveOpen: true);
        var entries = ValidateEntries(archive);
        var identityEntry = entries.SingleOrDefault(entry => entry.FullName == IdentityFile)
            ?? throw new InvalidDataException("Flutter package identity is missing.");
        if (identityEntry.Length > 4096) throw new InvalidDataException("Package identity is too large.");
        using (var identityStream = identityEntry.Open())
        {
            var identity = JsonSerializer.Deserialize<FlutterPackageIdentity>(identityStream, Json);
            if (identity is null || identity.SchemaVersion != 1 || identity.ClientKind != "flutter" ||
                identity.Architecture != manifest.Architecture || identity.Channel != manifest.Channel ||
                identity.Version != manifest.Version || identity.Executable != "starbridge_flutter.exe")
                throw new InvalidDataException("Embedded Flutter package identity does not match.");
        }
        foreach (var required in RequiredFiles)
            if (!entries.Any(entry => entry.FullName == required && entry.Length > 0))
                throw new InvalidDataException("Flutter runtime package is incomplete.");
        var stage = Path.Combine(Path.GetFullPath(ownedStagingRoot), "flutter-stage-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        try
        {
            foreach (var entry in entries)
            {
                cancellation.ThrowIfCancellationRequested();
                var destination = Path.Combine(stage, entry.FullName.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                using var source = entry.Open();
                using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                var buffer = new byte[81920];
                long written = 0;
                int count;
                while ((count = source.Read(buffer)) > 0)
                {
                    cancellation.ThrowIfCancellationRequested();
                    written += count;
                    if (written > entry.Length) throw new InvalidDataException("Expanded entry exceeds declared size.");
                    output.Write(buffer, 0, count);
                }
                if (written != entry.Length) throw new InvalidDataException("Truncated archive entry.");
                output.Flush(flushToDisk: true);
            }
            return stage;
        }
        catch
        {
            // Keep failed isolated output for diagnostics. No broad cleanup or application writes.
            throw;
        }
    }

    private static ZipArchiveEntry[] ValidateEntries(ZipArchive archive)
    {
        if (archive.Entries.Count is 0 or > 20000) throw new InvalidDataException("Invalid package entry count.");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var files = new List<ZipArchiveEntry>();
        long total = 0;
        foreach (var entry in archive.Entries)
        {
            var name = entry.FullName;
            var segments = name.TrimEnd('/').Split('/');
            if (string.IsNullOrEmpty(name) || name.Length > 240 || name.Contains('\\') ||
                segments.Any(segment => segment.Length == 0 || segment is "." or ".." ||
                    segment.EndsWith('.') || segment.EndsWith(' ') ||
                    segment.Any(character => character < 32 || "<>:\"|?*".Contains(character)) || IsDeviceName(segment)) ||
                !names.Add(name.TrimEnd('/')) ||
                ((entry.ExternalAttributes >> 16) & 0xF000) is 0xA000 ||
                (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Unsafe or duplicate package entry.");
            if (name.EndsWith('/')) continue;
            total = checked(total + entry.Length);
            if (total > MaximumExpandedBytes) throw new InvalidDataException("Package expands beyond its limit.");
            files.Add(entry);
        }
        var fileNames = files.Select(file => file.FullName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var name in names)
            for (var index = name.IndexOf('/'); index >= 0; index = name.IndexOf('/', index + 1))
                if (fileNames.Contains(name[..index]))
                    throw new InvalidDataException("Archive file conflicts with a directory.");
        return files.ToArray();
    }

    private static bool IsDeviceName(string segment)
    {
        var stem = segment.Split('.')[0].ToUpperInvariant();
        return stem is "CON" or "PRN" or "AUX" or "NUL" ||
            (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && char.IsDigit(stem[3]));
    }

    private static void RequirePlainDirectory(string root)
    {
        if (!Path.IsPathFullyQualified(root) || !Directory.Exists(root)) throw new IOException("Staging root unavailable.");
        for (var current = new DirectoryInfo(root); current is not null; current = current.Parent)
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected staging root.");
    }
}
