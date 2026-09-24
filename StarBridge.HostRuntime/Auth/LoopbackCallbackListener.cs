using System.Net;
using System.Net.Sockets;
using System.Text;

namespace StarBridge.HostRuntime.Auth;

public sealed record OAuthCallback(string Code);

public sealed class LoopbackCallbackListener : IAsyncDisposable
{
    private const int MaximumRequestLineBytes = 8192;
    private const int MaximumRequestHeadersBytes = 32768;
    private readonly TcpListener _listener;
    private readonly string _callbackPath;
    private bool _completed;

    private LoopbackCallbackListener(TcpListener listener, string callbackPath)
    {
        _listener = listener;
        _callbackPath = callbackPath;
        RedirectUri = new Uri($"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}{callbackPath}");
    }

    public Uri RedirectUri { get; }

    public static LoopbackCallbackListener Start(string callbackPath)
    {
        if (string.IsNullOrWhiteSpace(callbackPath) || !callbackPath.StartsWith('/'))
        {
            throw new ArgumentException("OAuth callback path must be absolute.", nameof(callbackPath));
        }

        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start(1);
        return new LoopbackCallbackListener(listener, callbackPath);
    }

    public async Task<OAuthCallback> WaitForCallbackAsync(string expectedState, CancellationToken cancellationToken)
    {
        if (_completed)
        {
            throw new InvalidOperationException("OAuth callback listener can only be consumed once.");
        }

        _completed = true;
        using var client = await _listener.AcceptTcpClientAsync(cancellationToken);
        if (client.Client.RemoteEndPoint is not IPEndPoint remote || !IPAddress.IsLoopback(remote.Address))
        {
            throw new InvalidOperationException("OAuth callback was not received from loopback.");
        }

        await using var stream = client.GetStream();
        var requestLine = await ReadRequestLineAsync(stream, cancellationToken);
        await ConsumeRequestHeadersAsync(stream, cancellationToken);
        var parts = requestLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 3 || !parts[0].Equals("GET", StringComparison.Ordinal))
        {
            await WriteResponseAsync(stream, false, cancellationToken);
            throw new InvalidOperationException("OAuth callback must use GET.");
        }

        if (!Uri.TryCreate(RedirectUri, parts[1], out var requestUri) ||
            !requestUri.IsLoopback ||
            requestUri.Port != RedirectUri.Port ||
            !requestUri.AbsolutePath.Equals(_callbackPath, StringComparison.Ordinal))
        {
            await WriteResponseAsync(stream, false, cancellationToken);
            throw new InvalidOperationException("OAuth callback path did not match.");
        }

        var query = ParseQuery(requestUri.Query);
        if (!query.TryGetValue("state", out var state) || !state.Equals(expectedState, StringComparison.Ordinal))
        {
            await WriteResponseAsync(stream, false, cancellationToken);
            throw new InvalidOperationException("OAuth callback state did not match.");
        }

        if (query.TryGetValue("error", out var error))
        {
            await WriteResponseAsync(stream, false, cancellationToken);
            if (error.Equals("access_denied", StringComparison.OrdinalIgnoreCase))
                throw new OAuthAuthorizationDeniedException();
            throw new InvalidOperationException("SCM 授权未完成。");
        }

        if (!query.TryGetValue("code", out var code) || string.IsNullOrWhiteSpace(code))
        {
            await WriteResponseAsync(stream, false, cancellationToken);
            throw new InvalidOperationException("OAuth callback did not contain an authorization code.");
        }

        await WriteResponseAsync(stream, true, cancellationToken);
        return new OAuthCallback(code);
    }

    public ValueTask DisposeAsync()
    {
        _listener.Stop();
        return ValueTask.CompletedTask;
    }

    private static async Task<string> ReadRequestLineAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var bytes = new List<byte>();
        var buffer = new byte[1];
        while (bytes.Count < MaximumRequestLineBytes)
        {
            if (await stream.ReadAsync(buffer, cancellationToken) == 0 || buffer[0] == (byte)'\n')
            {
                break;
            }
            if (buffer[0] != (byte)'\r')
            {
                bytes.Add(buffer[0]);
            }
        }

        if (bytes.Count == 0 || bytes.Count >= MaximumRequestLineBytes)
        {
            throw new InvalidOperationException("OAuth callback request was invalid.");
        }
        return Encoding.ASCII.GetString(bytes.ToArray());
    }

    private static async Task ConsumeRequestHeadersAsync(NetworkStream stream, CancellationToken cancellationToken)
    {
        var buffer = new byte[1];
        var totalBytes = 0;
        var lineBytes = 0;
        while (totalBytes < MaximumRequestHeadersBytes)
        {
            if (await stream.ReadAsync(buffer, cancellationToken) == 0)
            {
                throw new InvalidOperationException("OAuth callback request headers were incomplete.");
            }

            totalBytes++;
            if (buffer[0] == (byte)'\n')
            {
                if (lineBytes == 0)
                {
                    return;
                }
                lineBytes = 0;
            }
            else if (buffer[0] != (byte)'\r')
            {
                lineBytes++;
            }
        }

        throw new InvalidOperationException("OAuth callback request headers were too large.");
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var pair in query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            var name = Uri.UnescapeDataString(parts[0].Replace('+', ' '));
            values[name] = parts.Length == 2 ? Uri.UnescapeDataString(parts[1].Replace('+', ' ')) : "";
        }
        return values;
    }

    private static async Task WriteResponseAsync(NetworkStream stream, bool succeeded, CancellationToken cancellationToken)
    {
        var title = succeeded ? "SCM 授权成功" : "SCM 授权失败";
        var message = succeeded ? "可以关闭此页面并返回星海舰桥。" : "请返回星海舰桥后重试。";
        var body = $"<!doctype html><meta charset=\"utf-8\"><title>{title}</title><body style=\"font-family:sans-serif;padding:40px\"><h1>{title}</h1><p>{message}</p></body>";
        var bodyBytes = Encoding.UTF8.GetBytes(body);
        var headers = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
            $"Content-Length: {bodyBytes.Length}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(headers, cancellationToken);
        await stream.WriteAsync(bodyBytes, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }
}
