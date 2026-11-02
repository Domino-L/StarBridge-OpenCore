using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Communities;

internal static partial class CommunityProfileClientTests
{
    private static async Task WideImageCapabilities()
    {
        foreach (var marker in new[] { "missing", "null", "0", "-1", "true", "\"1\"", "1.5", "2147483648", "1", "2" })
        {
            var supported = marker is "1" or "2";
            var calls = 0;
            var revision = 7L;
            JsonNode Mark(JsonNode node)
            {
                node["hasBackground"] = true; // Presence alone must never enable uploads.
                if (marker != "missing") node["mediaProjectionVersion"] = JsonNode.Parse(marker);
                return node;
            }
            using var handler = new Handler(request => {
                calls++;
                if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Task.FromResult(Reply(Directory()));
                if (request.RequestUri.AbsolutePath == "/api/fleets/workspace")
                    return Task.FromResult(Reply(Mark(CommunityWorkspaceClientTests.Workspace())));
                if (request.Method == HttpMethod.Post) revision++;
                var profile = Mark(Profile(revision));
                profile["access"]!["canEditBanner"] = true;
                return Task.FromResult(Reply(profile));
            });
            using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
            var target = (await client.ReadAsync("fixture", new("mine", "", null, null), "capability", default)).Items[0].TargetRef;
            var profile = JsonSerializer.SerializeToElement(await client.ReadProfileAsync("fixture",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target }), "capability", default));
            var workspace = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("fixture",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), "capability", default));
            Check(profile.GetProperty("wideImagesSupported").GetBoolean() == supported &&
                workspace.GetProperty("wideImagesSupported").GetBoolean() == supported, "explicit capability marker: " + marker);
            foreach (var field in new[] { "bannerImageData", "backgroundImageData", "clearBackgroundImage", "clearBannerImage", "description" })
            {
                var before = calls;
                var changes = new Dictionary<string, object> { [field] = field.StartsWith("clear") ? true :
                    field == "description" ? "Changed" : CommunityImageFixtures.Data(CommunityImageFixtures.Png()) };
                var result = await client.SaveProfileAsync("fixture", Command(profile.GetProperty("editRef").GetString()!, changes),
                    "capability", () => { }, default);
                if (!supported && field is "bannerImageData" or "backgroundImageData" or "clearBackgroundImage")
                    Check(result.Status == "rejected" && result.Error == "wideImagesUnsupported" && calls == before,
                        "unsupported edit rejected before HTTP: " + field);
                else Check(result.Status == "accepted" && calls == before + 1, "supported/legacy edit preserved: " + field);
            }
        }
        Console.WriteLine("PASS wide image capability marker matrix: 10 cases, 0 failed");
    }
}
