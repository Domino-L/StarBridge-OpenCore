using System.Text.Json;
using System.Text.Json.Nodes;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static partial class CommunityProfileClientTests
{
    private static async Task Background()
    {
        foreach (var kind in new[] { "bannerImageData", "backgroundImageData" })
        {
            foreach (var image in new[] { CommunityImageFixtures.Data(CommunityImageFixtures.Png()),
                CommunityImageFixtures.Data(CommunityImageFixtures.Jpeg(), "jpeg"), CommunityImageFixtures.Boundary() })
                CommunityClient.ValidateProfileSave(Command(new string('a', 32), new Dictionary<string, object> { [kind] = image }));
            foreach (var image in CommunityImageFixtures.Invalid())
            {
                try { CommunityClient.ValidateProfileSave(Command(new string('a', 32), new Dictionary<string, object> { [kind] = image })); throw new Exception("invalid image accepted"); }
                catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
            }
        }
        foreach (var mode in new[] { "owner", "banner", "member", "denied" })
        {
            var revision = 7L;
            JsonElement outgoing = default;
            JsonNode Snapshot()
            {
                var result = Profile(revision);
                result["mediaProjectionVersion"] = 1;
                result["hasBackground"] = true;
                result["access"] = JsonSerializer.SerializeToNode(new { canEditProfile = mode == "owner", canEditLogo = mode == "owner",
                    canEditBanner = mode is "owner" or "banner" });
                return result;
            }
            using var handler = new Handler(async request => {
                if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
                if (request.Method == HttpMethod.Get) return Reply(Snapshot());
                outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
                revision++;
                return Reply(Snapshot());
            });
            using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
            var target = (await client.ReadAsync("fixture", new("mine", "", null, null), "background", default)).Items[0].TargetRef;
            async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadProfileAsync("fixture",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target }), "background", default));
            if (mode is "member" or "denied")
            {
                try { await Read(); throw new Exception("unauthorized profile accepted"); }
                catch (AccountBridgeHostException) { }
                continue;
            }
            foreach (var field in new[] { "bannerImageData", "backgroundImageData", "clearBannerImage", "clearBackgroundImage", "description", "logoImageData" })
            {
                var profile = await Read();
                Check(profile.GetProperty("hasBackground").GetBoolean(), "background metadata forwarded");
                var change = new Dictionary<string, object> { [field] = field.StartsWith("clear") ? true :
                    field == "description" ? "Updated" : CommunityImageFixtures.Data(CommunityImageFixtures.Png()) };
                var result = await client.SaveProfileAsync("fixture", Command(profile.GetProperty("editRef").GetString()!, change), "background", () => { }, default);
                if (mode == "banner" && field is "description" or "logoImageData")
                    Check(result.Status == "rejected" && result.Error == "notAllowed", "banner-only fields enforced before HTTP");
                else
                {
                    Check(result.Status == "accepted", "normal image save accepted");
                    Check(field == "bannerImageData" || !outgoing.TryGetProperty("bannerImageData", out _), "banner not echoed");
                    Check(field == "backgroundImageData" || !outgoing.TryGetProperty("backgroundImageData", out _), "background not echoed");
                }
            }
        }
    }
}
