using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Realtime;

internal static class ActivityWaitRead
{
    // Shared transport bound only. Domain readers validate their own cursors.
    internal static async Task<JsonElement> JsonAsync(HttpClient http, Uri origin, string bearer,
        string path, Func<HttpStatusCode, AccountBridgeHostException> failure,
        Func<AccountBridgeHostException> invalid, CancellationToken token, TimeSpan? timeout = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(timeout ?? TimeSpan.FromSeconds(12));
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (!response.IsSuccessStatusCode) throw failure(response.StatusCode);
        if (response.Content.Headers.ContentLength > 4096) throw invalid();
        using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
        using var buffer = new MemoryStream();
        var bytes = new byte[1024];
        int count;
        while ((count = await stream.ReadAsync(bytes, deadline.Token)) > 0) {
            if (buffer.Length + count > 4096) throw invalid();
            buffer.Write(bytes, 0, count);
        }
        using var json = JsonDocument.Parse(buffer.ToArray());
        return json.RootElement.Clone();
    }
}
