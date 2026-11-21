using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ShowcasePageRoundTrip()
    {
        foreach (var mode in new[] { "saved", "clear", "old-client", "lost-showcases", "lost-achievements", "reordered" })
        {
            using var transport = new ShowcasePageTransport(mode);
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
                new("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new("synthetic", "owner", "Synthetic", "synthetic-read-token", DateTimeOffset.MaxValue, ["profile.read"]),
                profileAuthorization: new ScmBackgroundAuthorization());
            using var dispatcher = new AccountBridgeDispatcher(host);
            var content = mode switch {
                "clear" => ProfileShowcaseTests.Content with { Showcases = [], AchievementShowcase = [] },
                "old-client" => PersonalProfileContentContract.Empty,
                _ => ProfileShowcaseTests.Content
            };
            var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.updatePresentation", "showcase-save", host.Generation,
                ProfileShowcaseTests.BridgeEdit(content), host.CurrentContext));
            if (mode.StartsWith("lost-") || mode == "reordered")
            {
                Check(response.Response.Error?.Code == "personalProfile.write_unconfirmed", "layout readback silently lost fields: " + mode);
                Check(transport.Writes == 1, "unconfirmed write retried");
                continue;
            }
            Check(response.Response.Error is null, "showcase write failed: " + mode);
            var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", "showcase-read", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(read.Response.Error is null, "showcase self read failed");
            var wire = read.Response.Payload.GetProperty("profile").GetProperty("content");
            // Old-client layout edits do not clear additive server-owned fields.
            var expected = mode == "old-client" ? ProfileShowcaseTests.Content : content;
            Check(wire.GetProperty("showcases").GetRawText() == JsonSerializer.Serialize(expected.Showcases, ProfileShowcaseTests.Web) &&
                wire.GetProperty("achievementShowcase").GetRawText() == JsonSerializer.Serialize(expected.AchievementShowcase, ProfileShowcaseTests.Web),
                "remote bridge read lost fields: " + mode);
            Check(!read.Response.Payload.GetProperty("profile").TryGetProperty("publicAchievements", out _), "self synthesized visitor achievements");
            Check(transport.Writes == 1, "remote save replayed");
        }
    }
    internal static async Task ShowcaseVisitorBridge(bool historical)
    {
        using var profile = new ScmVisitorTransport();
        using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(new Uri("https://example.invalid/"),
            new ScmVisitorCommunityTransport { Historical = historical });
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(profile), new ScmBackgroundVault(),
            new("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new("synthetic", "viewer", "Pilot", "synthetic-read-token", DateTimeOffset.MaxValue, ["profile.read"]),
            communities: communities);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!;
        var directory = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var target = directory.Items.Single().TargetRef;
        var workspace = BridgePayload.From(await host.ReadCommunityWorkspaceAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
        var member = workspace.GetProperty("members")[0].GetProperty("memberRef").GetString();
        foreach (var kind in new[] { "valid", "invalid", "absent", "empty" })
        {
            var page = JsonSerializer.SerializeToNode(new PersonalProfileDocumentContract(3,"synthetic-public",false,7,DateTimeOffset.UnixEpoch,
                new("Synthetic",""), ProfileShowcaseTests.Content,null), ProfileShowcaseTests.Web)!.AsObject();
            if (kind != "absent") page["publicAchievements"] = JsonNode.Parse(kind switch {
                "valid" => "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
                "empty" => "[]", _ => "[{\"id\":\"BAD\",\"earnedAt\":\"broken\"}]" });
            profile.WireBody = page.ToJsonString();
            var before = profile.Calls;
            var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", "showcase-visitor-" + kind,
                host.Generation, new { schemaVersion = 1, source = "community", reference = member, contextRef = target },owner))).Response;
            Check(response.Error is null && !response.Payload.GetProperty("editable").GetBoolean(), "visitor bridge failed");
            Check(profile.Calls == before + 1, "visitor read replayed or used another route");
            var wire = response.Payload.GetProperty("profile");
            Check(wire.GetProperty("content").GetProperty("showcases")[0].GetProperty("id").GetString() == "achievements" &&
                (!wire.GetProperty("content").TryGetProperty("achievementShowcase", out var selections) || selections.ValueKind == JsonValueKind.Null),
                "visitor leaked owner achievement selections or lost showcase layout");
            Check(wire.TryGetProperty("publicAchievements",out var achievements) == (kind is "valid" or "empty"), "bridge synthesized or dropped public field");
            if (kind == "valid") Check(achievements.GetArrayLength() == 1 &&
                achievements[0].GetProperty("id").GetString() == "journey-area18", "bridge changed public achievements");
            if (kind == "empty") Check(achievements.GetArrayLength() == 0, "authorized empty list lost");
        }
    }
    private sealed class ShowcasePageTransport(string mode) : HttpMessageHandler
    {
        internal int Writes;
        private PersonalProfileContentContract _content = ProfileShowcaseTests.Content;
        private PersonalProfileDocumentContract Profile()
        {
            var origins = new[] { "introduction", "layout", "favorites", "schedule", "playStyle", "wishlist", "avatarStyle", "wallpaper" }
                .ToDictionary(group => group, group => group == "layout" && Writes > 0 ? "custom" : "default");
            return new(3,"synthetic-public",false,Writes == 0 ? 7 : 8,DateTimeOffset.UnixEpoch,new("Synthetic",""),_content,null,
                Presentation: new(1,origins,new string('a',64)));
        }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
        {
            Check(request.RequestUri!.IsLoopback && request.RequestUri.Port == 9, "non-synthetic showcase endpoint");
            if (request.Method == HttpMethod.Patch)
            {
                Writes++;
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                var wire = body.RootElement.GetProperty("page").GetProperty("content");
                Check(body.RootElement.GetProperty("editedGroups")[0].GetString() == "layout", "wrong edit group");
                var next = wire.Deserialize<PersonalProfileContentContract>(ProfileShowcaseTests.Web)!;
                _content = next with { Showcases = next.Showcases ?? _content.Showcases,
                    AchievementShowcase = next.AchievementShowcase ?? _content.AchievementShowcase };
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(Profile(),options:ProfileShowcaseTests.Web) };
            }
            Check(request.Method == HttpMethod.Get, "unexpected showcase method");
            var profile = Profile();
            if (Writes > 0) profile = profile with { Content = profile.Content with {
                Showcases = mode == "lost-showcases" ? null : mode == "reordered" ? _content.Showcases!.Reverse().ToArray() : _content.Showcases,
                AchievementShowcase = mode == "lost-achievements" ? null : _content.AchievementShowcase } };
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(profile,options:ProfileShowcaseTests.Web) };
        }
    }
}
