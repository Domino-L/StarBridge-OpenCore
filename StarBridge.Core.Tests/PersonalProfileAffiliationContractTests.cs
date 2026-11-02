using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.Core.Tests;

internal static class PersonalProfileAffiliationContractTests
{
    internal static void RunAll()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        const string oldWire = """
            {"fleetName":"Fixture","fleetCode":"FIXTURE","positionTitle":"Member","positionColor":"blue","kind":"officialFleet"}
            """;
        var old = JsonSerializer.Deserialize<PersonalProfileFleetAffiliationContract>(oldWire, options)!;
        if (old.LogoUrl is not null) throw new Exception("Older affiliation must not acquire a logo URL.");
        Console.WriteLine("PASS older affiliation defaults to null logoUrl");
        var updated = old with { LogoUrl = "https://example.invalid/logo.png" };
        var wire = JsonSerializer.SerializeToElement(updated, options);
        if (wire.GetProperty("logoUrl").GetString() != updated.LogoUrl ||
            JsonSerializer.Deserialize<PersonalProfileFleetAffiliationContract>(wire, options) != updated)
            throw new Exception("Affiliation logo URL must survive the web contract.");
        Console.WriteLine("PASS logoUrl survives web contract round trip");
    }
}
