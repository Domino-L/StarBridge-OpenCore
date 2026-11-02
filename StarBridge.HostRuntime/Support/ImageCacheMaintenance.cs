namespace StarBridge.HostRuntime.Support;

/// <summary>Only known regenerable cache files; never traverses junctions or
/// touches user assets, account selection/credentials, unknown images or imported
/// hangar media. Protected organization documents lose only included images.</summary>
internal static class ImageCacheMaintenance
{
    internal static int Clear(string dataRoot)
    {
        if (!Path.IsPathFullyQualified(dataRoot))
            throw new IOException("Cache root must be absolute.");
        var root = Path.GetFullPath(dataRoot);
        if (!EnsureNoLinks(root, allowMissing: true)) return 0;
        if (!Directory.Exists(root)) throw new IOException("Cache root is not a directory.");
        var candidates = LegacyCandidates(root);
        foreach (var path in candidates) EnsureNoLinks(path);
        var removed = new Account.OfflineAccountStore(root).ClearOrganizationImages();
        removed += new Account.OfflineAccountStore(root).ClearDownloadableRemoteImages();
        foreach (var path in candidates)
        {
            // Validate again immediately before deletion, including ancestors.
            EnsureNoLinks(path);
            File.Delete(path);
            removed++;
        }
        return removed;
    }

    private static List<string> LegacyCandidates(string root)
    {
        var images = Path.Combine(root, "Images");
        if (!EnsureNoLinks(images, allowMissing: true)) return [];
        if (!Directory.Exists(images)) throw new IOException("Image cache is not a directory.");
        var candidates = Directory.EnumerateFiles(images, "*.png", SearchOption.TopDirectoryOnly)
            .Where(IsFleetCacheImage).ToList();
        var ships = Path.Combine(images, "ShipMedia");
        if (EnsureNoLinks(ships, allowMissing: true))
        {
            if (!Directory.Exists(ships)) throw new IOException("Ship cache is not a directory.");
            candidates.AddRange(Directory.EnumerateFiles(ships, "*.image", SearchOption.TopDirectoryOnly)
                .Where(path => Guid.TryParseExact(Path.GetFileNameWithoutExtension(path), "N", out _)));
        }
        return candidates;
    }

    // Existing WPF writers use fleet-<alphanumeric code>-logo/banner-<12 hex>.
    // A prefix alone is not evidence that a file is a regenerable cache copy.
    // Corrupt contents in this managed namespace remain removable.
    private static bool IsFleetCacheImage(string path)
    {
        if (!Path.GetExtension(path).Equals(".png", StringComparison.OrdinalIgnoreCase)) return false;
        var stem = Path.GetFileNameWithoutExtension(path);
        if (!stem.StartsWith("fleet-", StringComparison.OrdinalIgnoreCase)) return false;
        var split = stem.LastIndexOf('-');
        if (split < 0 || stem.Length - split - 1 != 12) return false;
        foreach (var value in stem.AsSpan(split + 1))
            if (!(value is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F')) return false;
        var prefix = stem[..split];
        var roleLength = prefix.EndsWith("-logo", StringComparison.OrdinalIgnoreCase) ? 5
            : prefix.EndsWith("-banner", StringComparison.OrdinalIgnoreCase) ? 7 : 0;
        var codeLength = prefix.Length - 6 - roleLength;
        if (roleLength == 0 || codeLength <= 0) return false;
        foreach (var value in prefix.AsSpan(6, codeLength))
            if (!char.IsLetterOrDigit(value)) return false;
        return true;
    }

    private static bool EnsureNoLinks(string path, bool allowMissing = false)
    {
        var ancestors = new Stack<string>();
        for (var current = Path.GetFullPath(path); !string.IsNullOrEmpty(current);
             current = Path.GetDirectoryName(current))
            ancestors.Push(current);
        while (ancestors.TryPop(out var current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (Exception error) when (allowMissing &&
                current != Path.GetPathRoot(current) &&
                error is FileNotFoundException or DirectoryNotFoundException)
            { return false; }
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Cache links are not supported.");
            if (ancestors.Count > 0 && (attributes & FileAttributes.Directory) == 0)
                throw new IOException("Cache ancestor is not a directory.");
        }
        return true;
    }
}
