using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;

internal static class PagePresentationClientTests
{
    internal static async Task Verify()
    {
        var options = new ScmOAuthOptions("synthetic", new("https://web.example.invalid/"),
            new("https://auth.example.invalid/"), new("https://resource.example.invalid/"),
            "synthetic-client", "starbridge-api", "openid profile.read", "/oauth/callback");
        var origins = new[] { "introduction", "layout", "favorites", "schedule", "playStyle", "wishlist", "avatarStyle", "wallpaper" }
            .ToDictionary(group => group, _ => "default");
        origins["introduction"] = "custom";
        var reply = new PersonalProfileDocumentContract(3, "synthetic-public", false, 8, DateTimeOffset.UnixEpoch,
            new("Synthetic", ""), PersonalProfileContentContract.Empty, null,
            Presentation: new(1, origins, new string('a', 64)));
        var calls = 0;
        var responseStatus = HttpStatusCode.OK;
        var handler = new Handler(async request =>
        {
            calls++;
            Check(request.Method == HttpMethod.Patch && request.RequestUri!.AbsolutePath.EndsWith("/personal-profile/presentation"), "wrong endpoint");
            Check(request.Headers.Authorization?.Parameter == "synthetic-write", "wrong grant");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
            var root = body.RootElement;
            Check(root.EnumerateObject().Count() == 5 && root.GetProperty("schemaVersion").GetInt32() == 1, "unexpected write fields");
            Check(root.GetProperty("sourceVersion").GetString() == new string('a', 64), "source lease lost");
            var page = root.GetProperty("page");
            Check(page.EnumerateObject().Count() == 3 && !page.GetProperty("content").TryGetProperty("presenceIntent", out _), "unrelated data leaked");
            Check(page.GetProperty("content").GetProperty("introduction").GetString() == "", "explicit clear lost");
            return new HttpResponseMessage(responseStatus) { Content = JsonContent.Create(reply) };
        });
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options);
        var session = new ScmOAuthSession("synthetic", "owner", "Synthetic", "synthetic-write", DateTimeOffset.MaxValue, ["profile.write"]);
        var edit = new PersonalProfilePageEditContract(7, new string('a', 64), ["introduction"], 0, "none", PersonalProfileContentContract.Empty);
        var bridgeContent = JsonSerializer.SerializeToNode(edit.Content, new JsonSerializerOptions(JsonSerializerDefaults.Web))!.AsObject();
        bridgeContent.Remove("presenceIntent");
        var bridgeJson = JsonSerializer.Serialize(new { schemaVersion = 1, expectedRevision = 7, sourceVersion = edit.SourceVersion,
            editedGroups = edit.EditedGroups, avatarStyle = 0, wallpaperId = "none", content = bridgeContent });
        using (var valid = JsonDocument.Parse(bridgeJson))
            Check(PageEditBridgeContract.Read(valid.RootElement).SourceVersion == edit.SourceVersion, "bridge source lease lost");
        foreach (var invalidJson in new[] {
            bridgeJson.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            bridgeJson.Replace("\"introduction\":\"\"", "\"introduction\":\"\",\"Introduction\":\"injected\""),
            bridgeJson.Replace("\"content\":{", "\"subject\":\"other\",\"content\":{"),
            bridgeJson.Replace("\"content\":{", "\"content\":{\"presenceIntent\":\"busy\","),
            bridgeJson.Replace("\"schemaVersion\":1", "\"schemaVersion\":2") })
        {
            using var invalidDocument = JsonDocument.Parse(invalidJson);
            await Reject<AccountBridgeHostException>(() => { PageEditBridgeContract.Read(invalidDocument.RootElement); return Task.CompletedTask; });
        }
        var result = await client.UpdatePagePresentationAsync(session, edit, default);
        Check(result.Presentation!.Origins["introduction"] == "custom" && result.Revision == 8, "metadata lost");
        await Reject<ScmApiForbiddenException>(() => client.UpdatePagePresentationAsync(session with { Capabilities = ["profile.read"] }, edit, default));
        await Reject<ArgumentException>(() => client.UpdatePagePresentationAsync(session, edit with { EditedGroups = ["visibility"] }, default));
        await Reject<ArgumentException>(() => client.UpdatePagePresentationAsync(session, edit with { EditedGroups = ["layout", "layout"] }, default));
        await Reject<ArgumentException>(() => client.UpdatePagePresentationAsync(session, edit with { Content = edit.Content with { PresenceIntent = "busy" } }, default));
        await Reject<ArgumentException>(() => client.UpdatePagePresentationAsync(session, edit with { Content = edit.Content with { Introduction = new string('x', 65536) } }, default));
        Check(calls == 1, "invalid input made a request");
        reply = reply with { Revision = 9 };
        await Reject<ScmApiProtocolException>(() => client.UpdatePagePresentationAsync(session, edit, default));
        reply = reply with { Revision = 8, Presentation = null };
        await Reject<ScmApiProtocolException>(() => client.UpdatePagePresentationAsync(session, edit, default));
        responseStatus = HttpStatusCode.Conflict;
        await Reject<HttpRequestException>(() => client.UpdatePagePresentationAsync(session, edit, default));
        Check(calls == 4, "write was replayed");
        // Ordinary reads retain the source lease and do not normalize away
        // fields that a future versioned page source can represent.
        reply = reply with { Presentation = new(1, origins, new string('a', 64)),
            Content = reply.Content with { Introduction = "  exact source text  " } };
        var reader = new OAuthPkceClient(new ScmHttpClient(new Handler(request =>
        {
            Check(request.Method == HttpMethod.Get && request.RequestUri == options.PersonalProfileEndpoint, "unexpected read endpoint");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(reply) });
        })), new Vault(), options);
        var read = await reader.LoadPersonalProfileAsync(session with { Capabilities = ["profile.read"] }, default);
        Check(read.Profile.Content.Introduction == "  exact source text  " && read.Profile.Presentation!.SourceVersion == edit.SourceVersion,
            "versioned source was normalized or lost");
        reply = reply with { Presentation = new(2, origins, null) };
        await Reject<ScmApiProtocolException>(() => reader.LoadPersonalProfileAsync(session, default));
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Reject<T>(Func<Task> action) where T : Exception
    {
        try { await action(); } catch (T) { return; }
        throw new InvalidOperationException("Expected " + typeof(T).Name);
    }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) => throw new InvalidOperationException("Write grant persisted");
        public void DeleteRefreshToken(string key) => throw new InvalidOperationException("Read session changed");
    }
}
