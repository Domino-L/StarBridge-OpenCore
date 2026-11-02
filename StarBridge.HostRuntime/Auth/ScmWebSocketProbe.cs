using System.Net.WebSockets;

namespace StarBridge.HostRuntime.Auth;

internal sealed record ScmWebSocketProbeResult(string? Failure)
{
    internal static ScmWebSocketProbeResult FromHttpStatus(int status) =>
        // 101, or the backend's own refusal of an anonymous handshake (400/401/426), proves the path is
        // forwarded. 403/404/429 and others can come from the CDN itself, so they count as unavailable.
        new(status is 101 or 400 or 401 or 426 ? null : $"ws-http status={status}");
}

internal static class ScmWebSocketProbe
{
    internal static async Task<ScmWebSocketProbeResult> ConnectAsync(Uri endpoint, CancellationToken token)
    {
        using var socket = new ClientWebSocket();
        socket.Options.CollectHttpResponseDetails = true;
        // A fresh socket has no cookies, authorization headers, credentials or account data.
        try
        {
            await socket.ConnectAsync(endpoint, token).ConfigureAwait(false);
        }
        catch (WebSocketException)
        {
            token.ThrowIfCancellationRequested();
            var status = (int)socket.HttpStatusCode;
            return status > 0 ? ScmWebSocketProbeResult.FromHttpStatus(status) : new("ws-transport");
        }
        // Send the normal close frame immediately; do not wait for the peer's close reply.
        try { await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, string.Empty, token).ConfigureAwait(false); }
        catch (Exception exception) when (exception is WebSocketException or OperationCanceledException) { }
        return new(null);
    }
}
