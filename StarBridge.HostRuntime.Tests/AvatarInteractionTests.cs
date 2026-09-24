using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class AvatarInteractionTests
{
    internal static async Task Verify()
    {
        using var handler = new Handler();
        using var reader = new FriendsReader(new Uri("https://example.invalid/"), handler);
        var directory = await reader.ReadAsync("token", null, default, "scope");
        var row = directory.Friends.Single();
        Check(reader.ResolveAvatarTarget("friend", row.TargetRef!, "token", "scope") == "peer-id", "opaque friend resolves exact account");
        var social = await reader.ReadAvatarSocialAsync("token", "peer-id", "Peer", "scope", () => {}, default);
        Check(social.Results.Single().ChatTargetRef != null && social.Results.Single().Relationship == "friend", "existing friend actions reused");
        Check(reader.ResolveAvatarTarget("friend", row.TargetRef!, "token", "scope") == "peer-id", "menu refresh cannot retire profile target");
        handler.DirectoryId = "different-account";
        var readsBefore = handler.Reads;
        var command = await reader.ExecuteAsync("token", JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, action = "remove", targetRef = row.TargetRef
        }), default, "scope");
        Check(handler.Reads > readsBefore && command.Error == "targetChanged",
            "original friend card remains valid through avatar read and reaches authoritative preflight");
        handler.DirectoryId = "peer-id";
        social = await reader.ReadAvatarSocialAsync("token", "peer-id", "Peer", "scope", () => {}, default);
        var chat = social.Results.Single().ChatTargetRef!;
        Check(reader.ResolveAvatarTarget("conversation", chat, "token", "scope") == "peer-id", "conversation has authoritative profile target");
        await reader.ReadAsync("token", null, default, "scope");
        Check(reader.ResolveAvatarTarget("conversation", chat, "token", "scope") == "peer-id", "conversation profile survives social refresh");
        foreach (var source in new[] { "friend", "conversation" }) {
            try { reader.ResolveAvatarTarget(source, source == "friend" ? row.TargetRef! : chat, "token", "other-scope"); throw new Exception("scope accepted"); }
            catch (AccountBridgeHostException) { }
        }
        handler.DirectoryId = "different-account";
        handler.SearchId = "wrong-same-name";
        social = await reader.ReadAvatarSocialAsync("token", "peer-id", "Peer", "scope", () => {}, default);
        Check(social.Results.Length == 0, "same-name search must never target another account");
        handler.SearchId = "peer-id";
        social = await reader.ReadAvatarSocialAsync("token", "peer-id", "Peer", "scope", () => {}, default);
        Check(social.Results.Single().Actions.Contains("send") && social.Results.Single().ChatTargetRef != null,
            "verified nonfriend can request friendship or open server-guarded conversation");
        Check(reader.ResolveAvatarTarget("conversation", social.Results.Single().ChatTargetRef!, "token", "scope") == "peer-id", "new chat target binds exact account");
        Check(handler.Writes == 0, "opening an avatar never performs a write");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Handler : HttpMessageHandler
    {
        internal string DirectoryId = "peer-id", SearchId = "peer-id";
        internal int Writes;
        internal int Reads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            if (request.Method != HttpMethod.Get) Writes++;
            else Reads++;
            var bytes = request.RequestUri!.AbsolutePath.EndsWith("/search")
                ? JsonSerializer.SerializeToUtf8Bytes(new { results = new[] { FriendsReaderTests.User(SearchId, "none") } })
                : FriendsReaderTests.Directory(FriendsReaderTests.User(DirectoryId));
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) });
        }
    }
}
