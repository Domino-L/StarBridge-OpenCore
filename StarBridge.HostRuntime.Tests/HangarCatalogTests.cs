using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Hangar;

internal static class HangarCatalogTests
{
    public static void Bundle(string assetsRoot)
    {
        string? Resource(string name) {
            using var stream = typeof(LocalHangarStore).Assembly.GetManifestResourceStream(name);
            if (stream is null) return null;
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd();
        }
        var tsv = Resource("StarBridge.ShipDisplayCatalog.tsv");
        var manifest = Resource("StarBridge.ShipMedia.json");
        var catalog = new StarBridge.Core.Ships.ShipPresentationCatalog(Resource("StarBridge.ShipNamePack.json"), tsv,
            Resource("StarBridge.ShipDisplayReview.json"));
        var media = new ShipBundledMediaCatalog(manifest, assetsRoot);
        if (tsv is null) {
            if (manifest is not null || catalog.Find("Carrack").PriceUsd is not null || media.Find("carrack") is not null)
                throw new Exception("Public build retained optional catalog/media");
            Console.WriteLine("PASS Optional catalog/media absent; display fallback remains available");
            return;
        }
        var rows = tsv.Split('\n').Skip(1).Where(line => !string.IsNullOrWhiteSpace(line)).ToArray();
        int matched = 0, priced = 0, images = 0, thumbnails = 0;
        using var mediaDocument = JsonDocument.Parse(manifest ?? "{}");
        var expectedThumbnails = mediaDocument.RootElement.GetProperty("files").EnumerateArray()
            .Count(row => row.TryGetProperty("thumbnailFile", out _));
        foreach (var row in rows) {
            var entry = catalog.Find(row.Split('\t')[1]);
            var published = catalog.Find(entry.CatalogId ?? "", row.Split('\t')[1]);
            if (published != entry || catalog.Find(entry.CatalogId ?? "") != entry ||
                media.Find(published.ImageKey) is null)
                throw new Exception($"Published catalog identity lost artwork or names on readback: {entry.CatalogId}");
            if (entry.CatalogId is not null) matched++;
            if (entry.PriceUsd is not null) priced++;
            if (media.Find(entry.ImageKey) is not null) images++;
            if (media.FindThumbnail(entry.ImageKey) is not null) thumbnails++;
        }
        if (matched != rows.Length || priced != rows.Length || images != rows.Length ||
            thumbnails != expectedThumbnails || thumbnails == 0)
            throw new Exception($"Catalog bundle mismatch: rows={rows.Length}, matched={matched}, priced={priced}, images={images}");
        Console.WriteLine($"PASS Catalog bundle: {matched} exact models, {priced} historical prices, {images} wide images, {thumbnails} hash-verified square thumbnails");
    }
    public static Task Verify()
    {
        // Disabling custom art is a projection rule, not a storage migration.
        var original = new LocalHangarShip("display-only", "pledge-fixture", "Carrack",
            "Anvil", null, DateTimeOffset.UnixEpoch);
        var legacy = original with { CustomImagePath = "never-read-custom.png",
            CustomImageCrop = new(.1, .2, .5, .5) };
        var storedBefore = JsonSerializer.Serialize(legacy);
        var normalProjection = JsonSerializer.Serialize(HangarShipNames.PresentSaved(original));
        var legacyProjection = JsonSerializer.Serialize(HangarShipNames.PresentSaved(legacy));
        if (normalProjection != legacyProjection ||
            JsonSerializer.Serialize(legacy) != storedBefore ||
            legacyProjection.Contains("never-read-custom", StringComparison.Ordinal))
            throw new Exception("Legacy custom art must not affect catalog projection or stored metadata");
        var root = Path.Combine(Path.GetTempPath(), "sb-catalog-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var image = Path.Combine(root, "catalog-test.png");
            File.WriteAllBytes(image, [1, 2, 3]);
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(image)));
            string Manifest(string file = "catalog-test.png", string? checksum = null) =>
                JsonSerializer.Serialize(new { schemaVersion = 1, distributionScope = "local-test-only",
                    files = new[] { new { key = "test", file, sha256 = checksum ?? hash } } });
            if (new ShipBundledMediaCatalog(Manifest(), root).Find("test") != "assets/ships/catalog-test.png" ||
                new ShipBundledMediaCatalog(Manifest("../catalog-test.png"), root).Find("test") != null ||
                new ShipBundledMediaCatalog(Manifest(checksum: new string('0', 64)), root).Find("test") != null ||
                new ShipBundledMediaCatalog(null, root).Find("test") != null ||
                new ShipBundledMediaCatalog(Manifest("catalog-missing.png"), root).Find("test") != null)
                throw new Exception("Media must be present, scoped and exact-hash validated");
            var square = Path.Combine(root, "catalog-square-test.png");
            File.WriteAllBytes(square, [4, 5, 6]);
            var squareHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(square)));
            string SquareManifest(string file = "catalog-square-test.png", string? checksum = null) =>
                JsonSerializer.Serialize(new { schemaVersion = 1, distributionScope = "local-test-only",
                    files = new[] { new { key = "test", file = "catalog-test.png", sha256 = hash,
                        thumbnailFile = file, thumbnailSha256 = checksum ?? squareHash } } });
            var both = new ShipBundledMediaCatalog(SquareManifest(), root);
            if (both.Find("test") != "assets/ships/catalog-test.png" ||
                both.FindThumbnail("test") != "assets/ships/catalog-square-test.png" ||
                new ShipBundledMediaCatalog(Manifest(), root).FindThumbnail("test") is not null ||
                new ShipBundledMediaCatalog(SquareManifest("../catalog-square-test.png"), root).FindThumbnail("test") is not null ||
                new ShipBundledMediaCatalog(SquareManifest(checksum: new string('0', 64)), root).FindThumbnail("test") is not null)
                throw new Exception("Square thumbnails must be independently scoped and hash checked, never a wide-image fallback.");
            using var test = new HangarLockedScanTests.Harness(new LocalHangarStore(Path.Combine(root, "hangar")));
            test.Send("verify", test.Initial());
            JsonObject Page(int page, int doc) {
                var body = test.Page(page, doc);
                body["observation"]!["page"]!["pledges"]![0]!["items"] = new JsonArray(
                    new JsonObject { ["title"] = "Carrack", ["kind"] = "Ship", ["liner"] = "Anvil" });
                return body;
            }
            foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3), (1, 3) })
                test.Send("observe", Page(page, doc));
            var saved = test.Send("save", new JsonObject { ["expectedRevision"] = 0, ["confirmEmpty"] = false });
            if (saved.Error is not null) throw new Exception("Catalog projection scan failed to save");
            var read = test.Send("inventory", new JsonObject());
            var ship = read.Payload.GetProperty("ships")[0];
            using var resource = typeof(LocalHangarStore).Assembly.GetManifestResourceStream("StarBridge.ShipDisplayCatalog.tsv");
            if (resource is not null) {
                if (ship.GetProperty("catalogId").GetString() != "catalog-carrack" ||
                    ship.GetProperty("sizeClass").GetString() != "large" ||
                    ship.GetProperty("priceUsd").GetDecimal() != 600 ||
                    ship.GetProperty("category").GetString() != "exploration")
                    throw new Exception("Saved inventory did not join the existing catalog");
            } else if (ship.TryGetProperty("priceUsd", out var price) && price.ValueKind != JsonValueKind.Null)
                throw new Exception("Media-free catalog inferred a price");
            if (read.Payload.GetRawText().Contains("CustomImagePath", StringComparison.OrdinalIgnoreCase) ||
                read.Payload.GetRawText().Contains("PledgeKey", StringComparison.OrdinalIgnoreCase))
                throw new Exception("Display projection exposed private storage fields");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
}
