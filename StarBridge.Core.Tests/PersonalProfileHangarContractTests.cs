using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.Core.Tests;

internal static class PersonalProfileHangarContractTests
{
    public static void RunAll()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        const string oldWire = """
            {"code":"fixture-model","displayName":"Fixture","importedAt":"0001-01-01T00:00:00+00:00"}
            """;
        var old = JsonSerializer.Deserialize<PersonalProfileHangarShipContract>(oldWire, options)!;
        var oldRoundTrip = JsonSerializer.SerializeToElement(old, options);
        Require(oldRoundTrip.TryGetProperty("isInventoryEntry", out var owned) && owned.GetBoolean(),
            "Older inventory contracts remain inventory, even with unknown import dates.");
        var displayOnly = JsonSerializer.Deserialize<PersonalProfileHangarShipContract>(
            oldWire[..^1] + ",\"isInventoryEntry\":false}", options)!;
        var roundTrip = JsonSerializer.SerializeToElement(displayOnly, options);
        Require(roundTrip.TryGetProperty("isInventoryEntry", out var display) && !display.GetBoolean(),
            "Explicit display-only status survives serialization.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
