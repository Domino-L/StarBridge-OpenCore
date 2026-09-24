using System.Text.Json;

namespace StarBridge.Core.Ships;

// Shared exact aliases from the original hangar importer. No variant guessing.
internal static class OfficialHangarAliases
{
    internal static readonly (string Alias, string Code)[] Entries = Load();

    private static (string Alias, string Code)[] Load()
    {
        using var stream = typeof(OfficialHangarAliases).Assembly.GetManifestResourceStream("StarBridge.HangarOfficialAliases.json");
        if (stream is null || stream.Length > 64 * 1024) return [];
        using var document = JsonDocument.Parse(stream, new JsonDocumentOptions { MaxDepth = 8 });
        var root = document.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1) return [];
        return root.GetProperty("entries").EnumerateArray()
            .Select(entry => (entry.GetProperty("alias").GetString()!, entry.GetProperty("runtimeId").GetString()!))
            .ToArray();
    }
}
