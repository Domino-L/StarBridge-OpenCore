namespace StarBridge.HostRuntime.Presence;

// Presentation enrichment of an already-authorized value. Never an identity,
// inventory lookup or a substitute for an absent/withheld ship field.
internal sealed record GameShipLabels(
    [property: System.Text.Json.Serialization.JsonPropertyName("en")] string En,
    [property: System.Text.Json.Serialization.JsonPropertyName("zhHans")] string ZhHans,
    [property: System.Text.Json.Serialization.JsonPropertyName("zhHant")] string? ZhHant)
{
    internal static GameShipLabels? From(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var name = GameShipNames.Find(raw.Trim());
        return name is null ? null : new(name.EnglishName, name.ChineseName, name.TraditionalChineseName);
    }
}
