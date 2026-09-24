namespace StarBridge.HostRuntime.Support;

/// <summary>Only known regenerable cache files; never traverses junctions or
/// touches user assets, account files, unknown images or imported hangar media.</summary>
internal static class ImageCacheMaintenance
{
    internal static int Clear(string dataRoot)
    {
        var root = Path.GetFullPath(dataRoot);
        var images = Path.Combine(root, "Images");
        EnsureNoLinks(root);
        if (!Directory.Exists(images)) return 0;
        EnsureNoLinks(images);
        var candidates = Directory.EnumerateFiles(images, "*.png", SearchOption.TopDirectoryOnly)
            .Where(path => Path.GetFileName(path).StartsWith("fleet-", StringComparison.OrdinalIgnoreCase)).ToList();
        var ships = Path.Combine(images, "ShipMedia");
        if (Directory.Exists(ships))
        {
            EnsureNoLinks(ships);
            candidates.AddRange(Directory.EnumerateFiles(ships, "*.image", SearchOption.TopDirectoryOnly)
                .Where(path => Guid.TryParseExact(Path.GetFileNameWithoutExtension(path), "N", out _)));
        }
        foreach (var path in candidates) EnsureNoLinks(path);
        var removed = 0;
        foreach (var path in candidates)
        {
            // Validate again immediately before deletion, including ancestors.
            EnsureNoLinks(path);
            File.Delete(path);
            removed++;
        }
        return removed;
    }

    private static void EnsureNoLinks(string path)
    {
        for (var current = Path.GetFullPath(path); !string.IsNullOrEmpty(current);
             current = Path.GetDirectoryName(current))
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Cache links are not supported.");
    }
}
