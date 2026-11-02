using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Account;

// SCM-signed-in users show their RSI avatar (SCM /me avatarUrl, scraped from
// the RSI citizen page). StarBridge no longer stores custom avatars for them;
// changing it happens on the RSI site. Only https RSI hosts are fetched, every
// redirect is re-checked, and the body is bounded and validated as PNG/JPEG.
internal static class RsiAvatarImage
{
    internal const string ProfileSettingsUrl = "https://robertsspaceindustries.com/en/account/settings/profile";
    internal const int MaximumBytes = 512 * 1024;
    private const int MaximumRedirects = 3;
    private static readonly HttpClient Client = new(new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        PooledConnectionLifetime = TimeSpan.FromMinutes(10)
    }) { Timeout = TimeSpan.FromSeconds(15) };

    internal static Uri? Validate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 2048 ||
            !Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttps || !uri.IsDefaultPort || uri.UserInfo.Length > 0) return null;
        var host = uri.IdnHost.ToLowerInvariant();
        return host == "robertsspaceindustries.com" || host.EndsWith(".robertsspaceindustries.com", StringComparison.Ordinal)
            ? uri : null;
    }

    internal static async Task<byte[]?> DownloadAsync(Uri uri, CancellationToken token)
    {
        var current = uri;
        for (var hop = 0; hop <= MaximumRedirects; hop++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            request.Headers.Accept.ParseAdd("image/png");
            request.Headers.Accept.ParseAdd("image/jpeg");
            using var response = await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token)
                .ConfigureAwait(false);
            var status = (int)response.StatusCode;
            if (status is >= 300 and < 400)
            {
                if (response.Headers.Location is not { } location ||
                    Validate(new Uri(current, location).AbsoluteUri) is not { } next) return null;
                current = next;
                continue;
            }
            if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > MaximumBytes) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
            using var buffer = new MemoryStream();
            var chunk = new byte[16 * 1024];
            int read;
            while ((read = await stream.ReadAsync(chunk, token).ConfigureAwait(false)) > 0)
            {
                if (buffer.Length + read > MaximumBytes) return null;
                buffer.Write(chunk, 0, read);
            }
            return buffer.ToArray();
        }
        return null;
    }

    // Validates image magic and dimensions; anything else is no avatar.
    internal static string? ToImageData(byte[]? bytes) =>
        bytes is null || bytes.Length == 0 ? null : RoomAvatarProjection.Normalize(Convert.ToBase64String(bytes), MaximumBytes);
}
