using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Ships;

internal static class PolishShipThumbnailTests
{
    internal static async Task Run()
    {
        foreach (var (hd, small, expected) in new (string?, string?, string?)[] {
            ("https://img.flowcld.com/hd.png", "https://cdn.flowcld.xyz/small.png", "https://img.flowcld.com/hd.png"),
            (null, "https://cdn.flowcld.top/small.png", "https://cdn.flowcld.top/small.png"),
            ("https://untrusted.invalid/hd.png", "https://img.flowcld.com/small.png", "https://img.flowcld.com/small.png"),
            (null, null, null), (null, "http://img.flowcld.com/no.png", null),
            (null, "https://flowcld.com.evil.invalid/no.png", null),
            (null, "https://fixture-userinfo:@img.flowcld.com/no.png", null),
            (null, "https://img.flowcld.com:444/no.png", null),
            (null, "https://img.flowcld.com/no.png#fragment", null)
        })
        {
            var handler = new Handler(hd, small);
            using var reader = new ScmShipSpecificationReader(new("https://catalog.invalid/"), handler);
            var first = await reader.ReadAsync("ANVL_Carrack", false, default);
            var second = await reader.ReadAsync("Carrack", false, default);
            Check(first.ThumbnailUrl == expected && second.ThumbnailUrl == expected, "thumbnail projection and cache");
            Check(handler.Reads == 3, "only existing catalogue reads, no image download");
            Check((await reader.ReadAsync("Carrack unknown edition", false, default)).ThumbnailUrl is null,
                "unknown edition has no inherited image");
        }
        using var changed = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Handler(null, "https://img.flowcld.com/ship.png") { Changed = true });
        try { await changed.ReadAsync("ANVL_Carrack", false, default); throw new Exception("Changed identity accepted"); }
        catch (HttpRequestException) { }
        Console.WriteLine("PASS polish ship thumbnails: 9 URL cases, cache, exact edition and changed identity");
    }

    private static void Check(bool ok, string label) { if (!ok) throw new Exception(label); }
    private sealed class Handler(string? hd, string? small) : HttpMessageHandler
    {
        internal int Reads;
        internal bool Changed;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Reads++;
            var path = request.RequestUri!.AbsolutePath;
            object data = path.EndsWith("search-list") ? new { total = 1, list = new[] { new { id = 1 } } } :
                path.EndsWith("warehouse-profiles") ? new[] { new { id = 1, itemNameEn = "Carrack", keyWord = "ANVL_Carrack" } } :
                path.EndsWith("/get") ? new { id = 1, itemType = 1, itemNameEn = "Carrack", keyWord = Changed ? "ANVL_Carrack_Expedition" : "ANVL_Carrack",
                    thumbnailUrlHd = hd, thumbnailUrl = small, extendedAttrs = new { cargo = 1 } } :
                throw new Exception("Unexpected transport route");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) });
        }
    }
}
