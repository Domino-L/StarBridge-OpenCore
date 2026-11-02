using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Realtime;

// Entirely synthetic in-process loopback gateway. HTTP waits use a handler;
// only the real ClientWebSocket handshake/session/reconnect uses loopback TCP.
internal static class DirectMessageGatewayRecoveryTests
{
    internal static async Task Verify()
    {
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var origin = new Uri($"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/");
        var disconnect = Signal();
        var reconnect = Signal();
        var secondReady = Signal();
        var secondHint = Signal();
        var handler = new Handler(reconnect.Task);
        using var reader = new FriendsReader(origin, handler, realtime: true);
        var client = reader.RealtimeClient!;
        var server = Task.Run(async () => {
            for (var round = 0; round < 2; round++) {
                using var connection = await listener.AcceptTcpClientAsync(lifetime.Token);
                using var socket = await Accept(connection, lifetime.Token);
                await Send(socket, "hello", new { heartbeatIntervalMs = 5000 }, lifetime.Token);
                var buffer = new byte[4096];
                await socket.ReceiveAsync(buffer, lifetime.Token); // real identify/resume
                await Send(socket, "ready", new { instance = new string('a', 32), latestSeq = round * 10 }, lifetime.Token);
                if (round == 1) {
                    secondReady.TrySetResult();
                    await secondHint.Task.WaitAsync(lifetime.Token);
                }
                await Send(socket, "events", new { events = new[] { new {
                    seq = round * 10 + 1, type = "dm.message.created",
                    data = new { conversation = "peer", message = new { id = "fixture-" + round, sequence = round + 1 } }
                } } }, lifetime.Token);
                if (round == 0) {
                    await disconnect.Task.WaitAsync(lifetime.Token);
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "fixture", lifetime.Token);
                } else {
                    try { await Task.Delay(Timeout.Infinite, lifetime.Token); }
                    catch (OperationCanceledException) { }
                }
            }
        }, lifetime.Token);
        async Task Until(Func<bool> predicate, string reason) {
            for (var i = 0; i < 600; i++) {
                lifetime.Token.ThrowIfCancellationRequested();
                if (predicate()) return;
                if (server.IsFaulted) await server;
                await Task.Delay(10, lifetime.Token);
            }
            throw new Exception(reason);
        }
        try {
            await reader.ReadChatAsync("fixture", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), lifetime.Token, "scope");
            await DirectMessageRealtimeHintTests.Wait(reader); // starts connection, HTTP fallback
            await Until(() => client.DirectMessagesPushHealthy, "first socket never proved DM support");
            var first = await DirectMessageRealtimeHintTests.Wait(reader);
            Check(first.GetProperty("directMessagesPushHealthy").GetBoolean(), "first socket healthy projection");
            disconnect.TrySetResult();
            await Until(() => client.CurrentState != RelayRealtimeClient.State.Connected, "gateway close did not retire connected state");
            var waits = handler.Waits;
            var degraded = await DirectMessageRealtimeHintTests.Wait(reader);
            Check(handler.Waits > waits && !degraded.GetProperty("directMessagesPushHealthy").GetBoolean(), "gateway disconnect falls back to actual HTTP wait path");
            reconnect.TrySetResult();
            await secondReady.Task.WaitAsync(lifetime.Token);
            await Until(() => client.CurrentState == RelayRealtimeClient.State.Connected, "second socket not connected");
            var unproved = await DirectMessageRealtimeHintTests.Wait(reader);
            Check(!unproved.GetProperty("directMessagesPushHealthy").GetBoolean(), "new socket must prove DM delivery again");
            secondHint.TrySetResult();
            await Until(() => client.DirectMessagesPushHealthy, "second DM did not restore health");
            waits = handler.Waits;
            var restored = await DirectMessageRealtimeHintTests.Wait(reader);
            Check(restored.GetProperty("directMessagesPushHealthy").GetBoolean() && handler.Waits == waits && handler.Tickets == 2,
                "fresh ticket and DM restore healthy push instead of HTTP wait");
            Console.WriteLine("PASS DM real loopback socket -> disconnect -> HTTP wait -> reconnect unproved -> DM healthy");
        } finally {
            client.Stop();
            lifetime.Cancel();
            listener.Stop();
            try { await server; } catch (Exception) when (lifetime.IsCancellationRequested) { }
        }
    }

    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
    private static Task Send(WebSocket socket, string op, object d, CancellationToken token) =>
        socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(new { op, d }), WebSocketMessageType.Text, true, token);

    private sealed class Handler(Task reconnect) : HttpMessageHandler
    {
        internal int Tickets, Waits;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            object body;
            if (request.RequestUri!.AbsolutePath.EndsWith("ticket")) {
                if (Interlocked.Increment(ref Tickets) == 2) await reconnect.WaitAsync(token);
                body = new { protocol = 1, ticket = "fixture", gateway = "/fixture-ws" };
            } else if (request.RequestUri.AbsolutePath.EndsWith("conversations")) {
                body = new { conversations = new[] { new { user = new { accountId = "peer", callsign = "Fixture", gameId = "" },
                    lastMessagePreview = "", lastMessageAt = DateTimeOffset.UtcNow, unreadCount = 0, conversationState = "friend" } },
                    totalUnread = 0, serverTime = DateTimeOffset.UtcNow };
            } else {
                Interlocked.Increment(ref Waits);
                body = new { instanceId = new string('b', 32), version = 0 };
            }
            return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(body)) };
        }
    }

    private static async Task<WebSocket> Accept(TcpClient connection, CancellationToken token)
    {
        var stream = connection.GetStream();
        var header = new List<byte>();
        var next = new byte[1];
        while (header.Count < 8192) {
            if (await stream.ReadAsync(next, token) != 1) throw new IOException("Incomplete fixture handshake");
            header.Add(next[0]);
            if (header.Count >= 4 && header.TakeLast(4).SequenceEqual(new byte[] { 13, 10, 13, 10 })) break;
        }
        var lines = Encoding.ASCII.GetString(header.ToArray()).Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
        var key = lines.Single(line => line.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase)).Split(':', 2)[1].Trim();
        var accept = Convert.ToBase64String(System.Security.Cryptography.SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
        await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n"), token);
        return WebSocket.CreateFromStream(stream, true, null, TimeSpan.FromSeconds(30));
    }
}
