using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static partial class CommunityWpfS2ProfileTests
{
    private static async Task Background()
    {
        foreach (var mode in new[] { "owner", "banner", "member", "denied", "legacy" })
        {
            using var handler = new Handler { Owner = mode == "owner", BannerOnly = mode != "legacy",
                Allowed = mode != "member", Denied = mode == "denied" };
            using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
            var target = (await client.ReadWpfS2Async("legacy", new("mine", "", null, null), "background", "self", default)).Items.Single().TargetRef;
            async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadWpfS2ProfileAsync("legacy",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target }), "background", "self", default));
            if (mode is "member" or "denied")
            {
                try { await Read(); throw new Exception("unprivileged profile read accepted"); }
                catch (AccountBridgeHostException e) when (e.Code == "communities.notAllowed") { }
                continue;
            }
            var profile = await Read();
            Check(profile.GetProperty("access").GetProperty("canEditBanner").GetBoolean() &&
                profile.GetProperty("access").GetProperty("canEditProfile").GetBoolean() == (mode != "banner") &&
                profile.GetProperty("access").GetProperty("canEditLogo").GetBoolean() == (mode != "banner"), "independent S2 image permissions");
            foreach (var field in new[] { "bannerImageData", "backgroundImageData", "clearBannerImage", "clearBackgroundImage", "description", "logoImageData" })
            {
                profile = await Read();
                var command = JsonSerializer.SerializeToElement(new { schemaVersion = 1, editRef = profile.GetProperty("editRef").GetString(),
                    requestId = Guid.NewGuid().ToString("N"), changes = new Dictionary<string, object> {
                        [field] = field.StartsWith("clear") ? true : field == "description" ? "Updated" : CommunityImageFixtures.Data(CommunityImageFixtures.Png()) } });
                var result = await client.SaveWpfS2ProfileAsync("legacy", command, "background", "self", () => { }, default);
                if (mode == "banner" && field is "description" or "logoImageData")
                {
                    Check(result.Status == "rejected" && result.Error == "notAllowed", "S2 banner-only editor cannot edit other fields");
                    continue;
                }
                Check(result.Status == "accepted", "S2 image save accepted: " + field);
                Check(field == "bannerImageData" || !handler.Outgoing.TryGetProperty("bannerImageData", out _), "unchanged banner is not echoed");
                Check(field == "backgroundImageData" || !handler.Outgoing.TryGetProperty("backgroundImageData", out _), "unchanged background is not echoed");
                var expected = field.Contains("Background") || field.StartsWith("background") ? "background" :
                    field.Contains("Banner") || field.StartsWith("banner") ? "banner" : field == "description" ? "description" : "logo";
                Check(handler.Outgoing.GetProperty("updatedSections")[0].GetString() == expected, "correct independent section");
            }
        }
    }
}
