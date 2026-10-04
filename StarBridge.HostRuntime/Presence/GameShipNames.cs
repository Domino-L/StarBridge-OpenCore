using StarBridge.Core.Ships;

namespace StarBridge.HostRuntime.Presence;

/// <summary>One read-only vocabulary for local logs, shared rows and native rendering.</summary>
public static class GameShipNames
{
    private static readonly Lazy<ShipNameIndex> Catalog = new(() => ShipNameIndex.Parse(
        Read("StarBridge.ShipNamePack.json"), Read("StarBridge.ShipDisplayCatalog.tsv")));

    public static ShipDisplayName? Find(string? value)
    {
        if (Catalog.Value.FindDisplay(value) is { } exact) return exact;
        // Display input may retain the log entity suffix. Strip only a bounded
        // numeric suffix from an otherwise exact catalog model; this does not
        // participate in runtime identity/ownership or variant comparison.
        if (value is null || value.Length > 256) return null;
        var separator = value.LastIndexOf('_');
        if (separator <= 0 || value.Length - separator - 1 is < 1 or > 20 ||
            !value[(separator + 1)..].All(c => c is >= '0' and <= '9')) return null;
        return Catalog.Value.FindDisplay(value[..separator]);
    }
    internal static ShipDisplayName? FindRuntimeIdentity(string? value) => Catalog.Value.Find(value);

    private static string? Read(string resource)
    {
        using var stream = typeof(GameShipNames).Assembly.GetManifestResourceStream(resource);
        if (stream is null) return null;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
