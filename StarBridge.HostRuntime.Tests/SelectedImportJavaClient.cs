using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;

// Opt-in cross-language fixture client. Never uses the installed client's storage or tokens.
internal static class SelectedImportJavaClient
{
    public static async Task Run(string address)
    {
        var endpoint = new Uri(address);
        if (endpoint.Scheme != "http" || endpoint.Host != "127.0.0.1" || endpoint.AbsolutePath != "/")
            throw new ArgumentException("Only a loopback fixture root is allowed.");
        var root = Path.Combine(Path.GetTempPath(), "starbridge-java-import-" + Guid.NewGuid().ToString("N"));
        try
        {
            var oauth = new OAuthPkceClient(new ScmHttpClient(new HttpClientHandler { UseProxy = false }), new NoVault(),
                new ScmOAuthOptions("synthetic", endpoint, endpoint, endpoint, "synthetic", "synthetic", "openid profile.read", "/callback"));
            var session = new ScmOAuthSession("synthetic", "owner", "Synthetic", "fixture-read",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(root), "test", () => null,
                session, profileAuthorization: new Grant());
            var owner = host.CurrentContext!;
            var store = new LocalPersonalProfileStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new("Before", "Keep local introduction", 2, "none", [], []), () => true);
            using var runtime = new AccountBridgeRuntime(host, localProfile: store);
            BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name,
                Guid.NewGuid().ToString("N"), host.Generation, payload, owner);
            var preview = await runtime.DispatchAsync(Request("personalProfile.migrationPreview", new {
                schemaVersion = 1, selection = new { modules = Array.Empty<string>(), replaceModules = Array.Empty<string>(),
                    useLegacyCallSign = true, useLegacyAvatar = false } }));
            Check(preview.Response.Error is null, "Preview bridge failed");
            var view = preview.Response.Payload.GetProperty("migration");
            Check(view.GetProperty("state").GetString() == "previewed", "Java preview not received: " + view.GetProperty("state").GetString());
            Check(store.Read(owner).Revision == 1, "Preview must not write local profile");
            var confirm = Request("personalProfile.migrationConfirm", new { schemaVersion = 1,
                previewId = view.GetProperty("previewId").GetString(), replaceExisting = false });
            for (var attempt = 0; attempt < 2; attempt++)
            {
                var result = await runtime.DispatchAsync(confirm);
                Check(result.Response.Error is null && result.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "completed",
                    "Java confirmation or idempotent replay failed");
                var saved = new LocalPersonalProfileStore(root).Read(owner);
                Check(saved.Revision == 2 && saved.Content!.CallSign == "Imported" &&
                    saved.Content.Introduction == "Keep local introduction" && saved.Content.AvatarStyle == 2,
                    "Only selected name may change, exactly once");
                Check(host.CurrentContext == owner, "SCM identity must not change");
            }
            var firstTicket = view.GetProperty("previewId").GetString();
            var current = store.Read(owner);
            store.Save(owner, current.Revision, Guid.NewGuid().ToString("N"),
                current.Content! with { CallSign = "Later local name" }, () => true);
            var next = await runtime.DispatchAsync(Request("personalProfile.migrationPreview", new {
                schemaVersion = 1, selection = new { modules = new[] { "skilled-roles" }, replaceModules = Array.Empty<string>(),
                    useLegacyCallSign = false, useLegacyAvatar = true, previousCompletedPreviewId = firstTicket } }));
            Check(next.Response.Error is null, "Second preview bridge failed");
            var nextView = next.Response.Payload.GetProperty("migration");
            Check(nextView.GetProperty("state").GetString() == "previewed", "Second selected preview failed");
            Check(nextView.GetProperty("avatarPreview").GetString()!.StartsWith("data:image/png;base64,"),
                "Selected avatar must have a bounded preview");
            Check(store.Read(owner).Revision == 3, "Second preview must not alter later local edits");
            var secondConfirm = Request("personalProfile.migrationConfirm", new { schemaVersion = 1,
                previewId = nextView.GetProperty("previewId").GetString(), replaceExisting = false });
            var lost = await runtime.DispatchAsync(secondConfirm);
            Check(lost.Response.Error is null &&
                lost.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "sourceUnavailable" &&
                store.Read(owner).Revision == 3 && lost.Events.Count == 0,
                "Lost Java response must not fabricate local completion");
            for (var attempt = 0; attempt < 2; attempt++)
            {
                var result = await runtime.DispatchAsync(secondConfirm);
                Check(result.Response.Error is null && result.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "completed",
                    "Second confirmation or replay failed");
                var saved = store.Read(owner);
                Check(saved.Revision == 4 && saved.Content!.CallSign == "Later local name" &&
                    saved.Content.Introduction == "Keep local introduction" && saved.Content.AvatarStyle == 2 &&
                    saved.Content.PlayStyle!.Roles!.SequenceEqual(["旧版岗位"]) &&
                    saved.Content.PlayStyle.Interests!.Count == 4 &&
                    saved.Content.Modules.Single().Id == "skilled-roles" && !saved.Content.Modules.Single().IsVisible,
                    "Second round preserves unselected name/style and imports bounded historical module content once");
            }
            var staleReceipt = await runtime.DispatchAsync(confirm);
            Check(staleReceipt.Response.Error is null &&
                staleReceipt.Response.Payload.GetProperty("migration").GetProperty("state").GetString() == "localPreviewRequired" &&
                store.Read(owner).Revision == 4, "Earlier ticket cannot overwrite the completed second round");
            Console.WriteLine("PASS actual Java HTTP name then avatar/module import, preserved edits and receipt replay");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Grant : IProfileWriteAuthorizationClient
    {
        public Task<ScmOAuthSession> AuthorizeProfileWriteAsync(ScmOAuthSession owner, CancellationToken token,
            Action<string>? reportProgress = null) => Task.FromResult(owner with {
                AccessToken = "fixture-write", Capabilities = ["profile.read", "profile.write"] });
    }
    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No token writes");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
}
