using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Hangar;

internal static class ProfileHangarPresentationTests
{
    public static Task Verify()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        foreach (var flag in new[] { false, true })
        {
            var ship = JsonSerializer.Deserialize<PersonalProfileHangarShipContract>(
                "{\"code\":\"fixture-model\",\"displayName\":\"Fixture\",\"importedAt\":\"0001-01-01T00:00:00+00:00\",\"isInventoryEntry\":" +
                (flag ? "true" : "false") + "}", options)!;
            var presented = JsonSerializer.SerializeToElement(HangarShipNames.PresentProfile(ship), options);
            if (!presented.TryGetProperty("isInventoryEntry", out var forwarded) || forwarded.GetBoolean() != flag)
                throw new Exception("Host catalog enrichment must preserve inventory/display-only status.");
        }
        return Task.CompletedTask;
    }
}
