using StarBridge.Core.Ships;

namespace StarBridge.Core.Tests;

internal static class PolishShipAliasTests
{
    internal static void RunAll()
    {
        var path = Path.Combine(FindSourceRoot(), "StarBridge.Desktop", "Data", "ship-catalog.tsv");
        string source;
        try { source = File.ReadAllText(path); }
        catch (IOException error) when (error is FileNotFoundException or DirectoryNotFoundException)
        {
            Console.WriteLine("SKIP optional source catalog comparison: open-core restricted sample ship-catalog.tsv absent");
            return;
        }
        using var stream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var reader = new StreamReader(stream);
        var names = reader.ReadToEnd();
        var catalog = new ShipPresentationCatalog(names, source);
        foreach (var model in new[] { "Taurus", "Andromeda", "Aquila", "Phoenix" }) {
            var old = catalog.Find("Constellation " + model);
            var current = catalog.Find("Constellation Mk IV " + model);
            Check(current.CatalogId is not null && current == old, "Mk IV alias must retain every presentation field: " + model);
            Print("Constellation Mk IV " + model, current);
        }
        foreach (var alias in new[] { "Dragonfly Star Kitten Edition", "Dragonfly Star Kitten" }) {
            var ship = catalog.Find(alias);
            Check(ship.CatalogId is not null && ship.Category is not null && ship.SizeClass is not null &&
                ship.PriceUsd == 40 && ship.ImageKey == "dragonfly-star-kitten", "Star Kitten identity, metadata and artwork");
            Print(alias, ship);
        }
        foreach (var (name, image) in new[] { ("Constellation Phoenix Emerald", "constellation-phoenix-emerald"),
            ("Dragonfly Black", "dragonfly-black"), ("Dragonfly Yellowjacket", "dragonfly-yellowjacket"),
            ("Constellation Mk V Centaurus", "constellation-mk-v-centaurus") }) {
            var ship = catalog.Find(name);
            Check(ship.CatalogId is not null && ship.ImageKey == image, "Existing edition is unchanged: " + name);
            Print(name, ship);
        }
        Check(catalog.Find("Constellation Mk IV Unknown").CatalogId is null, "Unknown edition stays unknown");
        Check(new ShipPresentationCatalog(names, null).Find("Dragonfly Star Kitten").ImageKey is null,
            "Missing optional catalog invents no artwork");
        Console.WriteLine("PASS CX-POLISH-B 12 ship alias/catalog checks");
    }
    private static string FindSourceRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var root = directory.FullName;
            if (File.Exists(Path.Combine(root, "StarBridge.Core.Tests", "StarBridge.Core.Tests.csproj"))) return root;
            var git = Path.Combine(root, ".git");
            if (Directory.Exists(git) || File.Exists(git) || File.Exists(Path.Combine(root, "StarBridge.sln"))) break;
        }
        throw new InvalidOperationException("Core test source tree not found");
    }

    private static void Print(string name, ShipPresentation ship) => Console.WriteLine(
        $"SHIP {name}|{ship.CatalogId}|{ship.SizeClass}|{ship.Category}|{ship.PriceUsd?.ToString() ?? "unpublished"}|{ship.ImageKey}");
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
