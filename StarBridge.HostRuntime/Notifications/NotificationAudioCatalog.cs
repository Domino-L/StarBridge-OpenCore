namespace StarBridge.HostRuntime.Notifications;

using System.Security.Cryptography;
using System.Text.Json;

internal static class NotificationAudioCueIds
{
    internal const string Soft = "notify.soft";
    internal const string Action = "notify.action";
    internal const string Operation = "notify.operation";
    internal const string EmergencyBroadcast = "notify.emergency_broadcast";

    internal static IReadOnlySet<string> All { get; } =
        new HashSet<string>(StringComparer.Ordinal)
        {
            Soft,
            Action,
            Operation,
            EmergencyBroadcast
        };
}

internal enum NotificationAudioAssetTier
{
    Fallback = 1,
    Candidate = 2,
    Approved = 3
}

internal sealed record NotificationAudioAsset(
    string AssetId,
    string CueId,
    string FilePath,
    NotificationAudioAssetTier Tier,
    int Priority,
    string Sha256);

internal sealed class NotificationAudioCatalogException : Exception
{
    internal NotificationAudioCatalogException(string message) : base(message)
    {
    }
}

internal sealed class NotificationAudioCatalog
{
    internal const int SchemaVersion = 1;
    private const int MaximumManifestBytes = 128 * 1024;
    private const long MaximumWaveBytes = 8 * 1024 * 1024;
    private readonly string _root;
    private readonly IReadOnlyList<NotificationAudioAsset> _assets;

    private NotificationAudioCatalog(
        string root,
        IReadOnlyList<NotificationAudioAsset> assets)
    {
        _root = root;
        _assets = assets;
    }

    internal static NotificationAudioCatalog Load(string root)
    {
        if (string.IsNullOrWhiteSpace(root))
        {
            throw new ArgumentException("Audio asset root is required.", nameof(root));
        }

        var normalizedRoot = Path.GetFullPath(root);
        var manifestPath = Path.Combine(normalizedRoot, "cue-catalog.v1.json");
        var manifestInfo = new FileInfo(manifestPath);
        if (!manifestInfo.Exists || manifestInfo.Length is <= 0 or > MaximumManifestBytes)
        {
            throw new NotificationAudioCatalogException(
                "Notification audio catalog is missing or invalid.");
        }

        using var document = JsonDocument.Parse(
            File.ReadAllBytes(manifestPath),
            new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 8
            });
        var rootElement = document.RootElement;
        RequireObject(rootElement, "catalog");
        RejectUnknownProperties(rootElement, "schemaVersion", "assets");
        if (RequireInt32(rootElement, "schemaVersion") != SchemaVersion)
        {
            throw new NotificationAudioCatalogException(
                "Notification audio catalog schema is unsupported.");
        }

        if (!rootElement.TryGetProperty("assets", out var assetsElement) ||
            assetsElement.ValueKind != JsonValueKind.Array ||
            assetsElement.GetArrayLength() == 0)
        {
            throw new NotificationAudioCatalogException(
                "Notification audio catalog must contain assets.");
        }

        var assets = new List<NotificationAudioAsset>();
        var assetIds = new HashSet<string>(StringComparer.Ordinal);
        var fileNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var assetElement in assetsElement.EnumerateArray())
        {
            RequireObject(assetElement, "asset");
            RejectUnknownProperties(
                assetElement,
                "assetId",
                "cueId",
                "fileName",
                "tier",
                "priority",
                "sha256");
            var assetId = RequireString(assetElement, "assetId");
            var cueId = RequireString(assetElement, "cueId");
            var fileName = RequireString(assetElement, "fileName");
            var tier = ParseTier(RequireString(assetElement, "tier"));
            var priority = RequireInt32(assetElement, "priority");
            var sha256 = RequireString(assetElement, "sha256").ToLowerInvariant();

            if (!NotificationAudioCueIds.All.Contains(cueId))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio catalog contains an unknown cue.");
            }
            if (!assetIds.Add(assetId) || !fileNames.Add(fileName))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio catalog contains duplicate assets.");
            }
            if (Path.IsPathRooted(fileName) ||
                !string.Equals(Path.GetFileName(fileName), fileName, StringComparison.Ordinal) ||
                !string.Equals(Path.GetExtension(fileName), ".wav", StringComparison.OrdinalIgnoreCase))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio file name is invalid.");
            }
            if (!IsPriorityValid(tier, priority))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio priority does not match its tier.");
            }
            if (sha256.Length != 64 || sha256.Any(character => !Uri.IsHexDigit(character)))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio hash is invalid.");
            }

            assets.Add(
                new NotificationAudioAsset(
                    assetId,
                    cueId,
                    Path.Combine(normalizedRoot, fileName),
                    tier,
                    priority,
                    sha256));
        }

        return new NotificationAudioCatalog(normalizedRoot, assets);
    }

    internal NotificationAudioAsset? Resolve(string cueId)
    {
        if (!NotificationAudioCueIds.All.Contains(cueId))
        {
            return null;
        }

        foreach (var asset in _assets
                     .Where(candidate => candidate.CueId == cueId)
                     .OrderByDescending(candidate => candidate.Priority)
                     .ThenBy(candidate => candidate.AssetId, StringComparer.Ordinal))
        {
            if (!File.Exists(asset.FilePath))
            {
                continue;
            }
            ValidateWave(asset);
            return asset;
        }

        return null;
    }

    private void ValidateWave(NotificationAudioAsset asset)
    {
        var fullPath = Path.GetFullPath(asset.FilePath);
        if (!fullPath.StartsWith(
                _root + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new NotificationAudioCatalogException(
                "Notification audio path escaped the catalog root.");
        }

        using var stream = new FileStream(
            fullPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        if (stream.Length is < 44 or > MaximumWaveBytes)
        {
            throw new NotificationAudioCatalogException(
                "Notification audio file size is invalid.");
        }

        Span<byte> header = stackalloc byte[12];
        if (stream.Read(header) != header.Length ||
            !header[..4].SequenceEqual("RIFF"u8) ||
            !header[8..12].SequenceEqual("WAVE"u8))
        {
            throw new NotificationAudioCatalogException(
                "Notification audio file is not a wave container.");
        }

        stream.Position = 0;
        var actual = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (!string.Equals(actual, asset.Sha256, StringComparison.Ordinal))
        {
            throw new NotificationAudioCatalogException(
                "Notification audio file failed integrity validation.");
        }
    }

    private static NotificationAudioAssetTier ParseTier(string value) => value switch
    {
        "approved" => NotificationAudioAssetTier.Approved,
        "candidate" => NotificationAudioAssetTier.Candidate,
        "fallback" => NotificationAudioAssetTier.Fallback,
        _ => throw new NotificationAudioCatalogException(
            "Notification audio asset tier is unsupported.")
    };

    private static bool IsPriorityValid(NotificationAudioAssetTier tier, int priority) =>
        tier switch
        {
            NotificationAudioAssetTier.Approved => priority is >= 300 and < 400,
            NotificationAudioAssetTier.Candidate => priority is >= 200 and < 300,
            NotificationAudioAssetTier.Fallback => priority is >= 100 and < 200,
            _ => false
        };

    private static void RequireObject(JsonElement value, string label)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new NotificationAudioCatalogException(
                $"Notification audio {label} must be an object.");
        }
    }

    private static string RequireString(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(property.GetString()))
        {
            throw new NotificationAudioCatalogException(
                $"Notification audio {name} must be a non-empty string.");
        }
        return property.GetString()!.Trim();
    }

    private static int RequireInt32(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.Number ||
            !property.TryGetInt32(out var result))
        {
            throw new NotificationAudioCatalogException(
                $"Notification audio {name} must be an integer.");
        }
        return result;
    }

    private static void RejectUnknownProperties(
        JsonElement value,
        params string[] allowedProperties)
    {
        var allowed = new HashSet<string>(allowedProperties, StringComparer.Ordinal);
        foreach (var property in value.EnumerateObject())
        {
            if (!allowed.Remove(property.Name))
            {
                throw new NotificationAudioCatalogException(
                    "Notification audio catalog contains an unexpected property.");
            }
        }
    }
}
