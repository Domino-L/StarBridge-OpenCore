using System.Net.Http.Headers;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private const int MaximumTokenResponseBytes = 64 * 1024;

    // Headers-only transport prevents HttpClient buffering an unbounded token
    // response first. Bound both successful and error bodies, even without a
    // Content-Length. At most one byte beyond the budget is requested/observed.
    private static async Task BoundTokenResponseAsync(HttpResponseMessage response, CancellationToken token)
    {
        var content = response.Content;
        if (content.Headers.ContentLength > MaximumTokenResponseBytes)
            throw new ScmRefreshTemporarilyUnavailableException("Token response exceeded the read budget.");
        await using var stream = await content.ReadAsStreamAsync(token).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var block = new byte[8192];
        while (true)
        {
            var count = await stream.ReadAsync(block.AsMemory(0,
                (int)Math.Min(block.Length, MaximumTokenResponseBytes + 1 - buffer.Length)), token).ConfigureAwait(false);
            if (count == 0) break;
            if (buffer.Length + count > MaximumTokenResponseBytes)
                throw new ScmRefreshTemporarilyUnavailableException("Token response exceeded the read budget.");
            buffer.Write(block, 0, count);
        }
        var bounded = new ByteArrayContent(buffer.ToArray());
        bounded.Headers.ContentType = content.Headers.ContentType ?? new MediaTypeHeaderValue("application/json");
        response.Content = bounded;
        content.Dispose();
    }
}
