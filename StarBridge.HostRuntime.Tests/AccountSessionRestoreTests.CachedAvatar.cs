using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task AuthenticatedCachedAvatarGuards()
    {
        foreach (var kind in new[] { "same-owner", "foreign-owner", "removed", "storage-unavailable" })
        {
            var root = Path.Combine(Path.GetTempPath(), "StarBridge-cached-avatar-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var settings = CreateEnvironmentSettings();
                var options = ScmOAuthOptions.Create(settings);
                var vault = new WindowsTokenVault(Path.Combine(root, "vault.json"));
                vault.SaveRefreshToken(options.AuthorityId + ":synthetic-cold-owner", "synthetic-avatar-refresh");
                var owner = new BridgeAccountContext(settings.EnvironmentName, options.AuthorityId,
                    kind == "foreign-owner" ? "different-synthetic-owner" : "synthetic-cold-owner");
                var cache = new OfflineAccountStore(root);
                const string avatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB";
                if (kind == "storage-unavailable")
                    Directory.CreateDirectory(Path.Combine(root, "offline-account-v1", "snapshot.bin"));
                else
                {
                    cache.Observe(owner, "Synthetic Cached Pilot", () => true);
                    cache.ObserveProfile(owner, JsonSerializer.SerializeToElement(new {
                        schemaVersion = 1, editable = true,
                        profile = new { identity = new { callSign = "Synthetic Cached Pilot", avatarAssetId = avatar }, content = new { } }
                    }), () => true);
                    if (kind == "removed") cache.ClearRemoteProfile(owner, () => true);
                }
                using var handler = new ColdContentHandler(options, "none");
                using var runtime = AccountBridgeRuntime.CreateAccountBusinessRuntime(new ScmAccountBridgeHost(
                    new OAuthPkceClient(new ScmHttpClient(handler), vault, options),
                    new ScmProfileCacheStore(Path.Combine(root, "profile")), settings.EnvironmentName, () => null),
                    root, null, false, null);
                AssertEqual(true, runtime.FirstUseMode is null, "ordinary avatar caching cannot activate onboarding or offline mode");
                var response = (await ReadCurrent(runtime, "synthetic-avatar-root")).Response;
                AssertEqual("signedIn", response.Payload.GetProperty("state").GetString(), "cache cannot change real authentication: " + kind);
                AssertEqual("synthetic-cold-owner", response.AccountContext?.Subject, "the live owner remains authoritative: " + kind);
                AssertEqual("Synthetic Cold Pilot", response.Payload.GetProperty("displayName").GetString(), "cached names cannot override fresh account identity");
                var image = response.Payload.TryGetProperty("avatarImageData", out var value) && value.ValueKind == JsonValueKind.String
                    ? value.GetString() : null;
                AssertEqual(kind == "same-owner" ? avatar : null, image, "only current owner's unretired presentation may be reused: " + kind);
                AssertEqual(false, handler.Kinds.Any(name => name is not ("token" or "identity" or "bootstrap" or "businessIdentity")),
                    "cached avatar enrichment never performs an additional business request");
            }
            finally { Directory.Delete(root, recursive: true); }
        }
    }
}
