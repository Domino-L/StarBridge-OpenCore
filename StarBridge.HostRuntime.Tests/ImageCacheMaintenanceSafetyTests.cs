using StarBridge.HostRuntime.Support;

internal static class ImageCacheMaintenanceSafetyTests
{
    internal static void PrefixLookalikesArePreserved()
    {
        using var fixture = new CacheFixture();
        var unknown = new[]
        {
            "fleet-holiday.png", "fleet-test-logo.png", "fleet-code-logo-not-a-hash.png",
            "fleet-code-logo-0123456789abc.png", "fleet-code-logo-gg1122334455.png",
            "fleet-ab-cd-logo-012345abcdef.png", "fleet--logo-012345abcdef.png",
            "fleet-code-userpicture-012345abcdef.png"
        };
        foreach (var name in unknown) fixture.Write("Images/" + name, "synthetic user image");
        fixture.Write("Images/fleet-ABC123-logo-012345abcdef.png", "synthetic generated cache");
        Equal(1, ImageCacheMaintenance.Clear(fixture.Root), "only the documented generated namespace is removed");
        foreach (var name in unknown) fixture.Kept("Images/" + name, "synthetic user image");
    }

    internal static void ManagedTypesDoNotIncludeImportedOrUserAssets()
    {
        using var fixture = new CacheFixture();
        var known = new[]
        {
            "Images/fleet-ABC123-logo-012345abcdef.png",
            "Images/fleet-fleet-banner-abcdef012345.png",
            "Images/fleet-中文123-banner-001122aabbcc.png",
            "Images/ShipMedia/00112233445566778899aabbccddeeff.image"
        };
        var retained = new[]
        {
            "UserAssets/fleet-ABC123-logo-012345abcdef.png", "Images/avatar.png",
            "Images/HangarImports/00112233445566778899aabbccddeeff.image",
            "Images/HangarImports/00112233445566778899aabbccddeeff.source",
            "Images/ShipMedia/unknown.image", "Images/ShipMedia/00112233445566778899aabbccddeeff.image.tmp",
            "Images/nested/fleet-ABC123-logo-012345abcdef.png", "account.json", "settings.json"
        };
        foreach (var path in known) fixture.Write(path, "synthetic regenerable cache, possibly damaged");
        foreach (var path in retained) fixture.Write(path, "synthetic retained source");
        Equal(known.Length, ImageCacheMaintenance.Clear(fixture.Root), "managed cache count");
        foreach (var path in retained) fixture.Kept(path, "synthetic retained source");
        Equal(0, ImageCacheMaintenance.Clear(fixture.Root), "second clear is an empty no-op");
    }

    internal static void MissingRootDoesNotCreateData()
    {
        using var fixture = new CacheFixture();
        var missing = Path.Combine(fixture.Root, "not-created");
        Equal(0, ImageCacheMaintenance.Clear(missing), "no cache at an unused data root");
        Equal(false, Directory.Exists(missing), "cleanup is not initialization or migration");
    }

    internal static void InvalidDirectoryShapesAreNotReportedAsEmpty()
    {
        using var fixture = new CacheFixture();
        fixture.Write("root-file", "synthetic source");
        ThrowsIo(() => ImageCacheMaintenance.Clear(Path.Combine(fixture.Root, "root-file")));
        fixture.Kept("root-file", "synthetic source");
        fixture.Write("Images", "synthetic source");
        ThrowsIo(() => ImageCacheMaintenance.Clear(fixture.Root));
        fixture.Kept("Images", "synthetic source");
        ThrowsIo(() => ImageCacheMaintenance.Clear("relative-cache-root"));
    }

    internal static void LinksAreRejectedBeforeAnyCandidateIsRemoved()
    {
        using var fixture = new CacheFixture();
        using var outside = new CacheFixture();
        outside.Write("00112233445566778899aabbccddeeff.image", "synthetic external source");
        fixture.Write("Images/fleet-ABC123-logo-012345abcdef.png", "known local cache");
        var link = Path.Combine(fixture.Root, "Images", "ShipMedia");
        CacheFixtureJunction.Create(fixture.Root, link, outside.Root);
        try
        {
            ThrowsIo(() => ImageCacheMaintenance.Clear(fixture.Root));
            fixture.Kept("Images/fleet-ABC123-logo-012345abcdef.png", "known local cache");
            outside.Kept("00112233445566778899aabbccddeeff.image", "synthetic external source");
        }
        finally { CacheFixtureJunction.Remove(fixture.Root, link); }
    }

    private static void ThrowsIo(Action action)
    {
        try { action(); }
        catch (IOException) { return; }
        throw new InvalidOperationException("Expected a fail-closed cache path error");
    }

    private static void Equal<T>(T expected, T actual, string name)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{name}: expected {expected}, actual {actual}");
    }

    private sealed class CacheFixture : IDisposable
    {
        internal string Root { get; } = Path.GetFullPath(Path.Combine(Path.GetTempPath(),
            "StarBridge-image-cache-safety-" + Guid.NewGuid().ToString("N")));
        internal CacheFixture() => Directory.CreateDirectory(Root);
        internal void Write(string relative, string content)
        {
            var path = Path.GetFullPath(Path.Combine(Root, relative));
            if (!path.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Fixture escaped its root");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, content);
        }
        internal void Kept(string relative, string expected) =>
            Equal(expected, File.ReadAllText(Path.Combine(Root, relative)), "preserve " + relative);
        public void Dispose()
        {
            var full = Path.GetFullPath(Root);
            var parent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
            if (!string.Equals(Path.GetDirectoryName(full), parent, StringComparison.OrdinalIgnoreCase) ||
                !Path.GetFileName(full).StartsWith("StarBridge-image-cache-safety-", StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected cleanup root");
            Directory.Delete(full, true);
        }
    }
}
