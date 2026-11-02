using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    // 2026-10-20 policy: SCM-signed-in users show their RSI avatar (SCM /me
    // avatarUrl). StarBridge no longer stores a custom avatar for them; legacy
    // accounts keep theirs (covered by LegacyPasswordLoginTests.Avatar).
    internal static async Task ScmAvatarWrite()
    {
        const string uploaded = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        const string rsiBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
        var rsi = "data:image/png;base64," + rsiBase64;
        const string rsiUrl = "https://robertsspaceindustries.com/media/synthetic/heap_infobox/avatar.png";

        foreach (var (url, expected) in new (string?, bool)[] {
            (rsiUrl, true), ("https://cdn.robertsspaceindustries.com/a.jpg", true),
            ("http://robertsspaceindustries.com/a.png", false), ("https://robertsspaceindustries.com:8443/a.png", false),
            ("https://user" + "@robertsspaceindustries.com/a.png", false), ("https://robertsspaceindustries.com.example.net/a.png", false),
            ("https://evilrobertsspaceindustries.com/a.png", false), ("/media/a.png", false), (null, false) })
            Check(RsiAvatarImage.Validate(url) is not null == expected, "RSI avatar host allow-list: " + url);
        Check(RsiAvatarImage.ToImageData([1, 2, 3, 4]) is null, "non-image bytes are no avatar");

        var cacheRoot = Path.Combine(Path.GetTempPath(), "starbridge-rsi-avatar-" + Guid.NewGuid().ToString("N"));
        try
        {
            var profiles = new ScmProfileCacheStore(cacheRoot);
            var route = AccountRouteIdentity.Create("integration", "synthetic", "owner", legacyAccountId: null);
            void SelfAvatar(string? value) =>
                profiles.Save(route, new StarBridge.Core.Profiles.ScmSelfProfileContract("owner", "Pilot", value, null, null, null), DateTimeOffset.UtcNow);
            SelfAvatar(rsiUrl);

            var downloads = new List<Uri>();
            Func<Uri, Task<byte[]?>> serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(rsiBase64));
            using var transport = new ScmAvatarTransport(uploaded);
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth, profiles, "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: new ScmBackgroundAuthorization(),
                rsiAvatarDownload: (target, _) => { downloads.Add(target); return serve(target); });
            using var dispatcher = new AccountBridgeDispatcher(host);
            var owner = host.CurrentContext!; var generation = host.Generation;
            async Task<JsonElement> Read() => (await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                "account.readAvatar", Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner))).Response.Payload;

            static bool NoImage(JsonElement body) =>
                !body.TryGetProperty("imageData", out var value) || value.ValueKind == JsonValueKind.Null;
            var first = await Read();
            Check(first.GetProperty("imageData").GetString() == rsi && downloads.Count == 1 && downloads[0].AbsoluteUri == rsiUrl,
                "SCM avatar is the RSI image from /me avatarUrl, not the stored upload");
            Check(first.GetProperty("callSign").GetString() == "Pilot", "nickname still comes from the profile");
            Check((await Read()).GetProperty("imageData").GetString() == rsi && downloads.Count == 1, "RSI avatar is cached per URL");
            Check((await host.GetCurrentAsync(default)).AvatarImageData == rsi, "account chrome shows the RSI avatar");
            async Task<string?> SelfProfileAvatar()
            {
                var self = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf",
                    Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner))).Response;
                Check(self.Status == "ok", "self profile read succeeds");
                var identity = self.Payload.GetProperty("profile").GetProperty("identity");
                return identity.TryGetProperty("avatarAssetId", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
            }
            Check(await SelfProfileAvatar() == rsi && downloads.Count == 1,
                "self profile page and offline snapshot get the RSI avatar, not the stored upload");

            var write = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                "account.updateAvatar", "scm-avatar", generation, new { schemaVersion = 1, imageData = uploaded }, owner));
            Check(write.Response.Error?.Code == "account.avatar_managed_by_scm" && transport.Writes == 0 && write.Events.Count == 0,
                "SCM users cannot upload a custom avatar and nothing is written");

            SelfAvatar("https://evil.example.net/avatar.png");
            Check(NoImage(await Read()) && downloads.Count == 1,
                "non-RSI avatar URL is never fetched and the old upload is not used instead");
            Check(await SelfProfileAvatar() is null, "self profile never falls back to the old upload");

            SelfAvatar("https://robertsspaceindustries.com/media/synthetic/heap_infobox/changed.png");
            serve = _ => throw new HttpRequestException("synthetic outage");
            Check(NoImage(await Read()) && downloads.Count == 2,
                "download failure with nothing to keep shows no avatar");
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(rsiBase64));
            Check((await Read()).GetProperty("imageData").GetString() == rsi && downloads.Count == 3, "failures are not cached; retry succeeds");

            // A failed download keeps the last image; a later read still retries.
            const string nextUrl = "https://robertsspaceindustries.com/media/synthetic/heap_infobox/next.png";
            SelfAvatar(nextUrl);
            var failures = new Func<Uri, Task<byte[]?>>[] {
                _ => throw new HttpRequestException("synthetic outage"),
                _ => throw new TaskCanceledException("synthetic timeout"),
                _ => Task.FromResult<byte[]?>(null),
                _ => Task.FromResult<byte[]?>([1, 2, 3, 4]) };
            var attempts = downloads.Count;
            foreach (var failure in failures)
            {
                serve = failure;
                Check((await Read()).GetProperty("imageData").GetString() == rsi && downloads.Count == ++attempts,
                    "failed or unusable download keeps the last image and retries");
            }
            serve = _ => throw new HttpRequestException("synthetic outage");
            Check(await SelfProfileAvatar() == rsi, "self profile and offline snapshot keep the last image through an outage");
            Check((await host.GetCurrentAsync(default)).AvatarImageData == rsi, "account chrome keeps the last image through an outage");
            var next = "data:image/png;base64," + uploaded["data:image/png;base64,".Length..];
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(next["data:image/png;base64,".Length..]));
            Check((await Read()).GetProperty("imageData").GetString() == next, "recovery replaces the kept image");
            Check(host.IsKeptAvatarImage(rsi) && !host.IsKeptAvatarImage(next),
                "a late write of the old kept image cannot replace the recovered one");
            // Downloading the kept image again is a real confirmation, by content and not by instance.
            SelfAvatar("https://robertsspaceindustries.com/media/synthetic/heap_infobox/back.png");
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(rsiBase64));
            Check((await Read()).GetProperty("imageData").GetString() == rsi && !host.IsKeptAvatarImage(rsi),
                "changing back to the kept image is saved again");
            SelfAvatar(nextUrl);
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(next["data:image/png;base64,".Length..]));
            Check((await Read()).GetProperty("imageData").GetString() == next, "the next image is back for the checks below");

            // Confirmed no avatar clears it, and an outage afterwards does not bring it back.
            SelfAvatar(null);
            Check(NoImage(await Read()) && (await host.GetCurrentAsync(default)).AvatarImageData is null, "no avatar URL clears the avatar");
            SelfAvatar(nextUrl);
            serve = _ => throw new HttpRequestException("synthetic outage");
            Check(NoImage(await Read()), "a cleared avatar does not return through an outage");

            // A hard read failure clears it too; the stored copy is not used while profile display is denied.
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(rsiBase64));
            Check((await Read()).GetProperty("imageData").GetString() == rsi, "avatar is back before the denial");
            var storedReads = 0;
            host.StoredAvatarImage = (_, _) => { storedReads++; return rsi; };
            var deniedFor = new List<BridgeAccountContext>();
            host.AvatarDenied += (who, _) => deniedFor.Add(who);
            transport.ProfileStatus = HttpStatusCode.Forbidden;
            var denied = await dispatcher.DispatchAsync(BridgeEnvelope.Request("account.readAvatar",
                Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner));
            Check(denied.Response.Status == "error" && (await host.GetCurrentAsync(default)).AvatarImageData is null, "denied read clears the avatar");
            Check(deniedFor.Count == 1 && deniedFor[0] == owner, "denied read reports the owner so the stored copy is dropped");
            transport.ProfileStatus = null;
            SelfAvatar("https://robertsspaceindustries.com/media/synthetic/heap_infobox/after-denial.png");
            serve = _ => throw new HttpRequestException("synthetic outage");
            Check(NoImage(await Read()) && storedReads == 0, "a denied avatar does not return through memory or the stored copy");

            // Internal profile reads count too, and kept is tied to the image itself.
            serve = _ => Task.FromResult<byte[]?>(Convert.FromBase64String(rsiBase64));
            Check((await Read()).GetProperty("imageData").GetString() == rsi && !host.IsKeptAvatarImage(rsi), "fresh image is not marked as kept");
            SelfAvatar("https://robertsspaceindustries.com/media/synthetic/heap_infobox/kept.png");
            serve = _ => throw new HttpRequestException("synthetic outage");
            Check((await Read()).GetProperty("imageData").GetString() == rsi && host.IsKeptAvatarImage(rsi) && !host.IsKeptAvatarImage(uploaded),
                "kept image is marked as kept, and a different image is not");
            transport.ProfileStatus = HttpStatusCode.Forbidden;
            try { await host.GetPersonalProfileAsync(owner, default); Check(false, "internal denied read throws"); }
            catch (AccountBridgeHostException) { }
            transport.ProfileStatus = null;
            Check(deniedFor.Count == 2 && (await host.GetCurrentAsync(default)).AvatarImageData is null, "internal denied read clears the avatar and the stored copy");
            Check(NoImage(await Read()) && storedReads == 0 && !host.IsKeptAvatarImage(rsi), "an internal denial also blocks the stored copy");
            var absentFor = new List<BridgeAccountContext>();
            host.AvatarConfirmedAbsent += (who, _) => absentFor.Add(who);
            SelfAvatar(null);
            Check(NoImage(await Read()) && absentFor.Count == 1 && absentFor[0] == owner, "confirmed no avatar reports the owner");
            host.StoredAvatarImage = null;

            await host.LogoutAsync(owner, default);
            Check((await host.GetCurrentAsync(default)).AvatarImageData is null, "logout clears the avatar");
            Check(transport.Writes == 0, "no avatar write at any point");
        }
        finally
        {
            if (Directory.Exists(cacheRoot)) Directory.Delete(cacheRoot, recursive: true);
        }
        Console.WriteLine("PASS SCM avatar: RSI image only, host allow-list, no custom upload, failures uncached, logout clears");
    }

    private sealed class ScmAvatarTransport(string uploaded) : HttpMessageHandler
    {
        internal int Writes;
        internal HttpStatusCode? ProfileStatus;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/business-identity")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            if (request.Method != HttpMethod.Get)
            {
                Writes++;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.InternalServerError));
            }
            Check(request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/personal-profile", "only the normal profile read is used");
            if (ProfileStatus is { } status) return Task.FromResult(new HttpResponseMessage(status));
            // The stored upload is still present server-side; the client must ignore it for SCM users.
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(
                new StarBridge.Core.Profiles.PersonalProfileDocumentContract(3, "fixture-public", false, 7, DateTimeOffset.UnixEpoch,
                    new("Pilot", "", uploaded), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty, null)) });
        }
    }
}
