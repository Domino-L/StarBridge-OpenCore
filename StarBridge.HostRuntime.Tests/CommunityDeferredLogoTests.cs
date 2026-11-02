using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityDeferredLogoTests
{
    internal static async Task Verify()
    {
        const string pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
        var inline = false;
        var mediaReads = 0;
        using var handler = new Handler(request =>
        {
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-scm", "Only authorized reads");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Json(new {
                    schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "fixture", name = "Fixture", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = "member", joinMode = "direct", actions = Array.Empty<string>(),
                        logoImageData = inline ? "data:image/png;base64," + pixel : null } }
                });
            Check(request.RequestUri.AbsolutePath == "/api/fleets/media", "Use the existing bounded media route");
            mediaReads++;
            return Json(new { schemaVersion = 1, kind = "logo", memberId = (string?)null, version = new string('a', 64),
                mimeType = "image/png", totalBytes = Convert.FromBase64String(pixel).Length, offset = 0, next = (int?)null, data = pixel });
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid/"), handler);
        var page = await client.ReadAsync("synthetic-scm", new("mine", "", null, null), "owner-generation", default);
        Check(page.Items.Single().LogoDeferred, "A directory-omitted logo must be scheduled for media loading, not rendered as permanently absent");
        var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = page.Items.Single().TargetRef, kind = "logo", offset = 0 });
        var chunk = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("synthetic-scm", payload, "owner-generation", default));
        Check(chunk.GetProperty("data").GetString() == pixel && mediaReads == 1, "SCM directory logo is recoverable through its own scoped media reference");
        Check(client.CachedSharingLogo("owner-generation", "fixture") == "data:image/png;base64," + pixel,
            "Sharing cards must reuse the same authorized deferred logo displayed by the directory");
        Check(client.CachedSharingLogo("other-owner", "fixture") is null, "Deferred sharing logos remain owner-scoped");
        await client.ReadAsync("synthetic-scm", new("mine", "", null, null), "owner-generation", default);
        Check(client.CachedSharingLogo("owner-generation", "fixture") is not null && mediaReads == 1,
            "A directory refresh omitting inline media must not erase the hydrated sharing logo or fetch it again");
        try { await client.ReadMediaAsync("synthetic-scm", payload, "other-owner", default); throw new Exception("Cross-owner media accepted"); }
        catch (AccountBridgeHostException error) when (error.Code == "communities.refreshRequired") { }
        Check(mediaReads == 1, "Cross-owner media rejected before HTTP");
        inline = true;
        page = await client.ReadAsync("synthetic-scm", new("mine", "", null, null), "owner-generation", default);
        Check(!page.Items.Single().LogoDeferred && page.Items.Single().LogoImageData is not null, "An inline logo is not downloaded again");
        await VerifyChunkedReuse(pixel);
    }

    private static async Task VerifyChunkedReuse(string pixel)
    {
        var clock = new Clock();
        var bytes = new byte[300 * 1024];
        Convert.FromBase64String(pixel).CopyTo(bytes, 0);
        var invalidImage = false;
        var version = new string('a', 64);
        using var handler = new Handler(request =>
        {
            Check(request.Method == HttpMethod.Get, "Logo reuse never adds writes");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Json(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "chunked", name = "Chunked", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = "member", joinMode = "direct", actions = Array.Empty<string>(), logoImageData = (string?)null } } });
            var offset = int.Parse(request.RequestUri.Query.TrimStart('?').Split('&').Single(p => p.StartsWith("offset="))[7..]);
            var source = invalidImage ? new byte[bytes.Length] : bytes;
            var count = Math.Min(192 * 1024, source.Length - offset);
            return Json(new { schemaVersion = 1, kind = "logo", memberId = (string?)null, version, mimeType = "image/png",
                totalBytes = source.Length, offset, next = offset + count < source.Length ? (int?)(offset + count) : null,
                data = Convert.ToBase64String(source, offset, count) });
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid/"), handler, targetClock: clock);
        async Task<string> Address() => (await client.ReadAsync("synthetic-scm", new("mine", "", null, null), "owner", default)).Items.Single().TargetRef;
        async Task Read(string reference, int offset) => _ = await client.ReadMediaAsync("synthetic-scm",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, kind = "logo", offset,
                version = offset == 0 ? null : version }), "owner", default);
        var reference = await Address();
        await Read(reference, 0);
        Check(client.CachedSharingLogo("owner", "chunked") is null, "Partial logos must not reach sharing cards");
        await Read(reference, 192 * 1024);
        Check(client.CachedSharingLogo("owner", "chunked") == "data:image/png;base64," + Convert.ToBase64String(bytes),
            "Complete multi-chunk logos preserve original bytes");
        Check(client.CachedSharingLogo("other-owner", "chunked") is null, "Large logos cannot cross owners");
        clock.Advance(TimeSpan.FromMinutes(6));
        Check(client.CachedSharingLogo("owner", "chunked") is null, "Deferred logo display cache expires with its scoped read lease");
        reference = await Address();
        invalidImage = true;
        await Read(reference, 0);
        await Read(reference, 192 * 1024);
        Check(client.CachedSharingLogo("owner", "chunked") is null, "Invalid completed media keeps the normal icon fallback");
        invalidImage = false;
        await Read(reference, 0);
        version = new string('b', 64);
        await Read(reference, 192 * 1024);
        Check(client.CachedSharingLogo("owner", "chunked") is null, "Chunks from different versions must not be combined");
        await Read(reference, 0);
        await Read(reference, 192 * 1024);
        Check(client.CachedSharingLogo("owner", "chunked") is not null, "A fresh complete version restores the image");
        client.Dispose();
        Check(client.CachedSharingLogo("owner", "chunked") is null, "Disposal clears completed and partial display caches");
    }

    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(TimeSpan amount) => _now += amount;
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string reason) { if (!condition) throw new InvalidOperationException(reason); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
