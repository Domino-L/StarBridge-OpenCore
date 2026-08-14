using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

internal static partial class ShipMediaManifestCatalog
{
    private const string ManifestFileName = "third-party-media-manifest.json";
    private const string ThumbnailPayloadPrefix = "Data/ShipImages/";

    private static readonly Lazy<IReadOnlyDictionary<string, string>> DefaultIndex = new(
        () => LoadIndex(
            Path.Combine(AppContext.BaseDirectory, ManifestFileName),
            AppContext.BaseDirectory));

    public static string? FindImagePath(string? code, string? displayName)
    {
        return FindImagePath(code, displayName, DefaultIndex.Value);
    }

    internal static string? FindImagePath(
        string? code,
        string? displayName,
        IReadOnlyDictionary<string, string> index)
    {
        if (index.Count == 0)
        {
            return null;
        }

        foreach (var candidate in BuildCodeLookupCandidates(code))
        {
            if (TryFindImagePath(index, candidate, out var imagePath))
            {
                return imagePath;
            }
        }

        if (TryFindImagePath(index, displayName, out var displayNameImagePath))
        {
            return displayNameImagePath;
        }

        return null;
    }

    internal static IReadOnlyDictionary<string, string> LoadIndex(
        string manifestPath,
        string payloadRoot)
    {
        if (!Directory.Exists(payloadRoot))
        {
            return EmptyIndex();
        }

        if (!File.Exists(manifestPath))
        {
            return LoadLegacyThumbnailIndex(payloadRoot);
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            var root = document.RootElement;
            if (!HasExactString(root, "product", "StarBridge") ||
                !HasExactString(root, "distributionScope", "official-binary") ||
                !root.TryGetProperty("files", out var files) ||
                files.ValueKind != JsonValueKind.Array)
            {
                return EmptyIndex();
            }

            // The media-free public package intentionally carries an empty manifest.
            // An in-place upgrade from 0.4 can still have the user's previously installed
            // ship images on disk, so keep those local files usable without redistributing
            // them in the new package.
            if (files.GetArrayLength() == 0)
            {
                return LoadLegacyThumbnailIndex(payloadRoot);
            }

            var payloadRootFull = Path.GetFullPath(payloadRoot)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            var index = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var file in files.EnumerateArray())
            {
                if (!TryGetNonEmptyString(file, "mediaKind", out var mediaKind))
                {
                    return EmptyIndex();
                }

                if (!mediaKind.Equals("ship-thumbnail", StringComparison.Ordinal))
                {
                    continue;
                }

                if (!TryGetNonEmptyString(file, "assetKey", out var assetKey) ||
                    !TryGetNonEmptyString(file, "payloadPath", out var payloadPath) ||
                    !TryResolveThumbnailPath(payloadRootFull, payloadPath, out var resolvedPath) ||
                    !file.TryGetProperty("lookupKeys", out var lookupKeys) ||
                    lookupKeys.ValueKind != JsonValueKind.Array)
                {
                    return EmptyIndex();
                }

                if (!File.Exists(resolvedPath))
                {
                    continue;
                }

                var entryKeys = new List<string> { assetKey };
                foreach (var lookupKey in lookupKeys.EnumerateArray())
                {
                    if (lookupKey.ValueKind != JsonValueKind.String ||
                        string.IsNullOrWhiteSpace(lookupKey.GetString()))
                    {
                        return EmptyIndex();
                    }

                    entryKeys.Add(lookupKey.GetString()!);
                }

                var relativeImagePath = payloadPath.Replace('/', Path.DirectorySeparatorChar);
                foreach (var entryKey in entryKeys)
                {
                    var normalizedKey = NormalizeLookupKey(entryKey);
                    if (string.IsNullOrWhiteSpace(normalizedKey))
                    {
                        return EmptyIndex();
                    }

                    if (index.TryGetValue(normalizedKey, out var existingPath) &&
                        !existingPath.Equals(relativeImagePath, StringComparison.OrdinalIgnoreCase))
                    {
                        return EmptyIndex();
                    }

                    index[normalizedKey] = relativeImagePath;
                }
            }

            return index;
        }
        catch (Exception exception) when (
            exception is IOException or
            UnauthorizedAccessException or
            JsonException or
            ArgumentException or
            NotSupportedException)
        {
            return EmptyIndex();
        }
    }

    private static IReadOnlyDictionary<string, string> LoadLegacyThumbnailIndex(string payloadRoot)
    {
        try
        {
            var thumbnailRoot = Path.GetFullPath(
                Path.Combine(payloadRoot, "Data", "ShipImages"));
            if (!Directory.Exists(thumbnailRoot) ||
                (File.GetAttributes(thumbnailRoot) & FileAttributes.ReparsePoint) != 0)
            {
                return EmptyIndex();
            }

            var index = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var filePath in Directory.EnumerateFiles(
                         thumbnailRoot,
                         "*",
                         SearchOption.TopDirectoryOnly))
            {
                if ((File.GetAttributes(filePath) & FileAttributes.ReparsePoint) != 0)
                {
                    continue;
                }

                var extension = Path.GetExtension(filePath).ToLowerInvariant();
                if (extension is not (".jpg" or ".jpeg" or ".png"))
                {
                    continue;
                }

                var key = NormalizeLookupKey(Path.GetFileNameWithoutExtension(filePath));
                if (string.IsNullOrWhiteSpace(key))
                {
                    continue;
                }

                var relativePath = Path.Combine(
                    "Data",
                    "ShipImages",
                    Path.GetFileName(filePath));
                if (index.TryGetValue(key, out var existingPath) &&
                    !existingPath.Equals(relativePath, StringComparison.OrdinalIgnoreCase))
                {
                    return EmptyIndex();
                }

                index[key] = relativePath;
            }

            return index;
        }
        catch (Exception exception) when (
            exception is IOException or
            UnauthorizedAccessException or
            ArgumentException or
            NotSupportedException)
        {
            return EmptyIndex();
        }
    }

    private static IEnumerable<string> BuildCodeLookupCandidates(string? code)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            yield break;
        }

        yield return code;

        var resolvedCode = ShipNameLocalizer.ResolveCode(code);
        if (!resolvedCode.Equals(code, StringComparison.OrdinalIgnoreCase))
        {
            yield return resolvedCode;
        }

        var normalizedCode = ShipNameLocalizer.NormalizeCode(resolvedCode);
        if (normalizedCode.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            yield break;
        }

        yield return normalizedCode;

        var separatorIndex = normalizedCode.IndexOf('_');
        if (separatorIndex > 0 && separatorIndex < normalizedCode.Length - 1)
        {
            yield return normalizedCode[(separatorIndex + 1)..];
        }

        yield return ShipNameLocalizer.DisplayName(normalizedCode, "zh");
        foreach (var alias in ShipNameLocalizer.GetNameAliases(normalizedCode))
        {
            yield return alias;
        }
    }

    private static bool TryFindImagePath(
        IReadOnlyDictionary<string, string> index,
        string? candidate,
        out string imagePath)
    {
        imagePath = "";
        var key = NormalizeLookupKey(candidate);
        if (string.IsNullOrWhiteSpace(key) ||
            !index.TryGetValue(key, out var resolvedImagePath) ||
            string.IsNullOrWhiteSpace(resolvedImagePath))
        {
            return false;
        }

        imagePath = resolvedImagePath;
        return true;
    }

    private static bool TryResolveThumbnailPath(
        string payloadRootFull,
        string payloadPath,
        out string resolvedPath)
    {
        resolvedPath = "";
        if (!payloadPath.StartsWith(ThumbnailPayloadPrefix, StringComparison.OrdinalIgnoreCase) ||
            payloadPath.Contains('\\') ||
            payloadPath.Contains(':') ||
            payloadPath.StartsWith('/') ||
            payloadPath.Contains("//", StringComparison.Ordinal) ||
            payloadPath.Split('/').Any(segment => segment is "." or ".."))
        {
            return false;
        }

        var extension = Path.GetExtension(payloadPath).ToLowerInvariant();
        if (extension is not (".jpg" or ".jpeg" or ".png"))
        {
            return false;
        }

        resolvedPath = Path.GetFullPath(
            Path.Combine(payloadRootFull, payloadPath.Replace('/', Path.DirectorySeparatorChar)));
        return resolvedPath.StartsWith(payloadRootFull, StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasExactString(JsonElement element, string name, string expected)
    {
        return TryGetNonEmptyString(element, name, out var value) &&
               value.Equals(expected, StringComparison.Ordinal);
    }

    private static bool TryGetNonEmptyString(
        JsonElement element,
        string name,
        out string value)
    {
        value = "";
        if (!element.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = property.GetString()?.Trim() ?? "";
        return !string.IsNullOrWhiteSpace(value);
    }

    private static string NormalizeLookupKey(string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? ""
            : NonAlphaNumericRegex().Replace(value, "").ToLowerInvariant();
    }

    private static IReadOnlyDictionary<string, string> EmptyIndex()
    {
        return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    [GeneratedRegex(@"[^\p{L}\p{N}]+", RegexOptions.CultureInvariant)]
    private static partial Regex NonAlphaNumericRegex();
}
