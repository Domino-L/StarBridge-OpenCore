using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task AvatarUpdate()
    {
        const string image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        using var transport = new AvatarTransport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        var owner = host.CurrentContext!;
        var generation = host.Generation;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var payload = BridgePayload.From(new { schemaVersion = 1, imageData = image });
        var request = BridgeEnvelope.Request("account.updateAvatar", "avatar-one", generation, payload, owner);
        var result = await dispatcher.DispatchAsync(request);
        Check(result.Response.Error is null && result.Response.Payload.GetProperty("imageData").GetString() == image,
            "Avatar update returns only the confirmed account image");
        Check(transport.Posts == 1 && transport.LastPayload?.GetProperty("callsign").GetString() == "Account Name" &&
            transport.LastPayload?.EnumerateObject().Count() == 2, "Avatar update preserves account callsign and omits unrelated preferences");
        Check((await host.GetCurrentAsync(default)).AvatarImageData == image && host.Generation == generation,
            "Account photo changes without changing session generation or cancelling profile drafts");
        Check(result.Events.Count == 1 && result.Events[0].Name == "account.avatarChanged", "Avatar change notifies all projections after response");
        transport.FailWrite = true;
        var failed = await dispatcher.DispatchAsync(request);
        Check(failed.Response.Error is not null && failed.Events.Count == 0 && transport.Posts == 2,
            "Failed writes are neither replayed nor published as success");
        transport.FailWrite = false;
        transport.MismatchAccount = true;
        var mismatch = await dispatcher.DispatchAsync(request);
        Check(mismatch.Response.Error is not null && transport.Posts == 2, "Wrong account response cannot authorize avatar update");
        transport.MismatchAccount = false;
        var invalid = await dispatcher.DispatchAsync(BridgeEnvelope.Request("account.updateAvatar", "avatar-invalid", generation,
            BridgePayload.From(new { schemaVersion = 1, imageData = "https://example.invalid/photo.png" }), owner));
        Check(invalid.Response.Error is not null && transport.Posts == 2, "Reject URL and malformed image before writes");
        using var scm = CreateHost(client, new ScmOAuthSession("scm-development", "synthetic", "Synthetic",
            "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []));
        try { await scm.UpdateAvatarAsync(scm.CurrentContext!, payload, default); throw new Exception("SCM must not use legacy avatar transport"); }
        catch (AccountBridgeHostException error) { Check(error.Code == "account.avatar_managed_by_scm", "SCM authority stays separate"); }
        Check(transport.Posts == 2, "SCM does not fall back to old account writes");
    }

    private sealed class AvatarTransport : HttpMessageHandler
    {
        internal int Posts;
        internal JsonElement? LastPayload;
        internal bool FailWrite, MismatchAccount;
        private string? _avatar;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/api/auth/profile")
            {
                Posts++;
                Check(request.Headers.Authorization?.Parameter == "synthetic-token", "Only active account credential sent");
                if (FailWrite) return new(HttpStatusCode.ServiceUnavailable);
                using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                LastPayload = json.RootElement.Clone();
                _avatar = json.RootElement.GetProperty("avatarImageData").GetString();
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                accountId = MismatchAccount ? "other-account" : "legacy-id", token = "synthetic-token", email = "old@example.invalid",
                callsign = "Account Name", avatarImageData = _avatar
            }) };
        }
    }
}
