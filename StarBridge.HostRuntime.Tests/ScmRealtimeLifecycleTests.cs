using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.PartyRooms;

internal static class ScmRealtimeLifecycleTests
{
    internal static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-scm-realtime-").FullName;
        try
        {
            var endpoint = new Uri("http://127.0.0.1:1/");
            var options = new ScmOAuthOptions("synthetic-scm", endpoint, endpoint, endpoint,
                "test-client", "test-resource", "profile.read presence.write", "/callback");
            var ticketRequested = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var handler = new Handler(request =>
            {
                if (request.RequestUri != options.WebSocketTicketEndpoint)
                    throw new InvalidOperationException("Unexpected request in realtime lifecycle test.");
                ticketRequested.TrySetResult();
                return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}", Encoding.UTF8, "application/json") };
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options, () => "synthetic-device");
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(root), "test", () => null,
                initialSession: new("synthetic-scm", "synthetic-subject", "Pilot", "synthetic-access",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write"]));
            await host.GetCurrentAsync(default);
            try { await ticketRequested.Task.WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (TimeoutException)
            {
                throw new InvalidOperationException("SCM signed-in Host never starts authoritative presence: no realtime ticket request.");
            }
            Console.WriteLine("PASS SCM signed-in Host starts authoritative presence without legacy account");
        }
        finally { Directory.Delete(root, true); }
        await VerifySocketLifecycle();
        await VerifySocketLifecycle(corruptVault: true);
    }

    private static async Task VerifySocketLifecycle(bool corruptVault = false)
    {
        var root = Directory.CreateTempSubdirectory("starbridge-scm-socket-").FullName;
        // Managed loopback transport preserves the real WebSocket lifecycle without
        // requiring HTTP.sys request-queue handles or machine URL reservations.
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var endpoint = new Uri($"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/");
        using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        var sockets = new List<WebSocket>();
        var disconnect = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var revoke = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var ticketCount = 0;
        const string accountKey = "synthetic-scm:subject";
        var vaultPath = Path.Combine(root, "synthetic-vault.json");
        var vault = new WindowsTokenVault(vaultPath);
        vault.SaveRefreshToken(accountKey, "synthetic-refresh");
        var httpRequests = 0;
        var options = new ScmOAuthOptions("synthetic-scm", endpoint, endpoint, endpoint,
            "test-client", "test-resource", "profile.read presence.write", "/callback");
        var handler = new Handler(request =>
        {
            Interlocked.Increment(ref httpRequests);
            if (request.RequestUri != options.WebSocketTicketEndpoint || request.Method != HttpMethod.Post)
                throw new InvalidOperationException("Realtime attempted legacy login or changed presence mode.");
            Interlocked.Increment(ref ticketCount);
            return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new
            {
                ticket = "synthetic-ticket", expiresAt = DateTimeOffset.UtcNow.AddMinutes(1)
            }), Encoding.UTF8, "application/json") };
        });
        using var host = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(handler), vault, options, () => "synthetic-device"),
            new ScmProfileCacheStore(root), "test", () => null,
            initialSession: new("synthetic-scm", "subject", "Pilot", "synthetic-access",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write"]));
        using var runtime = new AccountBridgeRuntime(host, privacy: new LocalPrivacyStore(root),
            visibility: new PresenceVisibilityStore(root));
        var invalidations = 0;
        var marketInvalidations = 0;
        runtime.EventReady += envelope => { if (envelope.Name == "marketplace.changed") Interlocked.Increment(ref marketInvalidations); };
        runtime.EventReady += envelope => { if (envelope.Name == "presence.changed") Interlocked.Increment(ref invalidations); };
        async Task CheckBridge(int expected)
        {
            var reply = (await runtime.DispatchAsync(BridgeEnvelope.Request("presence.read",
                Guid.NewGuid().ToString("N"), host.Generation, new { schemaVersion = 1 }, host.CurrentContext))).Response;
            if (reply.Payload.GetProperty("realtimeStatus").GetInt32() != expected ||
                reply.Payload.GetProperty("state").GetString() != "unconfirmed")
                throw new InvalidOperationException("Heartbeat did not reach Bridge or granted sharing preference confirmation.");
            var member = new RoomMemberView("Pilot", "", true, "离线", "Unknown", "Unknown", "Unknown");
            var projected = host.ProjectRoomSelfPresence(member, host.CurrentContext!, host.Generation, true);
            if (projected.PresenceKey != (expected == 1 ? "presence.online" : "presence.invisible"))
                throw new InvalidOperationException("Room self card ignored current SCM realtime authority.");
            if (host.ProjectRoomSelfPresence(member, host.CurrentContext!, host.Generation, false) != member)
                throw new InvalidOperationException("Self realtime authority leaked into another room member.");
            if (projected.LocationText != member.LocationText || projected.ShipText != member.ShipText ||
                projected.ShardText != member.ShardText || projected.GameId != member.GameId)
                throw new InvalidOperationException("Self presence projection invented game sharing fields.");
            try
            {
                host.ProjectRoomSelfPresence(member, host.CurrentContext!, host.Generation - 1, true);
                throw new InvalidOperationException("Old room generation retained self authority.");
            }
            catch (BridgeStaleGenerationException) { }
        }
        var transitions = new List<int?>();
        var roomInvalidated = false;
        host.RealtimePresenceChanged += _ => {
            lock (transitions) transitions.Add(host.ReadObservedPublicationVisibility()?.Observation);
            if (host.ReadObservedPublicationVisibility()?.Observation is null && host.CurrentContext is { } current)
            {
                var member = new RoomMemberView("Pilot", "", true, "应用在线", "Unknown", "Unknown", "Unknown");
                roomInvalidated = host.ProjectRoomSelfPresence(member, current, host.Generation, true).PresenceKey == "presence.unknown";
            }
        };
        async Task Send(WebSocket socket, object payload) =>
            await socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(payload), WebSocketMessageType.Text, true, lifetime.Token);
        var server = Task.Run(async () =>
        {
            for (var index = 0; index < 2; index++)
            {
                using var connection = await listener.AcceptTcpClientAsync(lifetime.Token);
                var socket = await AcceptSocket(connection, lifetime.Token);
                sockets.Add(socket);
                var buffer = new byte[4096];
                // Hotfix 10-29: the first frame on the relay socket must be the device heartbeat
                // (the relay closes on message-subscribe before the device is registered).
                var received = await socket.ReceiveAsync(buffer, lifetime.Token);
                using var heartbeat = JsonDocument.Parse(buffer.AsMemory(0, received.Count));
                if (heartbeat.RootElement.GetProperty("type").GetString() != "member-online-heartbeat" ||
                    heartbeat.RootElement.GetProperty("deviceId").GetString() != "synthetic-device")
                    throw new InvalidOperationException("Missing account-scoped device heartbeat.");
                await Send(socket, new { type = "member-status-update", content = new { signInStatus = index == 0 ? 1 : 3 } });
                if (index == 0)
                {
                    var tradeEvent = JsonSerializer.SerializeToUtf8Bytes(new { type = "transaction-event", content = new { transactionNumber = "fixture", padding = new string('x', 5000) } });
                    await socket.SendAsync(tradeEvent.AsMemory(0, 2000), WebSocketMessageType.Text, false, lifetime.Token);
                    await socket.SendAsync(tradeEvent.AsMemory(2000), WebSocketMessageType.Text, true, lifetime.Token);
                    await disconnect.Task.WaitAsync(lifetime.Token);
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "synthetic disconnect", lifetime.Token);
                }
                else
                {
                    await revoke.Task.WaitAsync(lifetime.Token);
                    await Send(socket, new { type = "device-force-logout", content = new { deviceId = "other-device" } });
                    await Task.Delay(100, lifetime.Token);
                    if (host.CurrentContext is null) throw new InvalidOperationException("Foreign-device logout revoked this session.");
                    await Send(socket, new { type = "device-force-logout", content = new { deviceId = "synthetic-device" } });
                }
            }
        }, lifetime.Token);
        async Task Until(Func<bool> condition, string failure)
        {
            for (var i = 0; i < 400; i++)
            {
                if (condition()) return;
                if (server.IsFaulted) await server;
                await Task.Delay(15, lifetime.Token);
            }
            throw new InvalidOperationException(failure);
        }
        var unobserved = 0;
        EventHandler<UnobservedTaskExceptionEventArgs> onUnobserved = (_, args) =>
        {
            if (args.Exception.Flatten().InnerExceptions.Any(error =>
                error is InvalidDataException or ScmLocalCredentialRetirementException))
            {
                Interlocked.Increment(ref unobserved);
                args.SetObserved();
            }
        };
        TaskScheduler.UnobservedTaskException += onUnobserved;
        try
        {
            if (host.ReadObservedPublicationVisibility()?.Observation is not null) throw new InvalidOperationException("Invented initial online state.");
            await host.GetCurrentAsync(default);
            await Until(() => host.ReadObservedPublicationVisibility()?.Observation == 1, "Online acknowledgement never reached signed-in Host.");
            await CheckBridge(1);
            var tradeInvalidated = false;
            for (var attempt = 0; attempt < 100; attempt++)
            {
                var result = BridgePayload.From(await host.MarketplaceTradeAsync(host.CurrentContext!, BridgePayload.From(new { operation = "revision" }), lifetime.Token));
                if (result.GetProperty("data").GetProperty("revision").GetInt64() == 2) { tradeInvalidated = true; break; }
                await Task.Delay(15, lifetime.Token);
            }
            if (!tradeInvalidated) throw new InvalidOperationException("Fragmented transaction event did not invalidate marketplace exactly once.");
            await Until(() => marketInvalidations == 2, "Connect and transaction event did not reach Flutter bridge.");
            Console.WriteLine("PASS fragmented SCM transaction event invalidates signed-in marketplace revision");
            disconnect.TrySetResult();
            await Until(() => { lock (transitions) return transitions.Contains(null); }, "Disconnect retained online confirmation.");
            await Until(() => roomInvalidated, "Disconnected room self projection retained online state.");
            await Until(() => marketInvalidations >= 3, "Disconnect did not immediately reconcile marketplace state.");
            await Until(() => host.ReadObservedPublicationVisibility()?.Observation == 3, "Reconnect did not preserve SCM invisible acknowledgement.");
            await CheckBridge(3);
            await Until(() => marketInvalidations == 4, "Reconnect did not reconcile missed marketplace events.");
            if (vault.LoadRefreshToken(accountKey) != "synthetic-refresh" || vault.LoadActiveAccountKey() != accountKey)
                throw new InvalidOperationException("Realtime disconnect deleted the refresh credential or active account.");
            if (invalidations < 3) throw new InvalidOperationException("Realtime transitions did not invalidate Flutter presence.");
            if (ticketCount != 2) throw new InvalidOperationException("Reconnect did not obtain one fresh ticket.");
            // A different writer may have rotated this account since the socket
            // was opened. Explicit device revocation still deletes that version.
            new WindowsTokenVault(vaultPath).SaveRefreshToken(accountKey, "synthetic-refresh-rotated");
            var requestsBeforeRevocation = Volatile.Read(ref httpRequests);
            var diagnostics = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
            var previousDiagnostics = File.Exists(diagnostics) ? File.ReadAllText(diagnostics).Length : 0;
            if (corruptVault) File.WriteAllText(vaultPath, "{synthetic-invalid-json");
            revoke.TrySetResult();
            await Until(() => host.CurrentContext is null, "Device revocation retained session.");
            if (corruptVault)
            {
                await server;
                // The production callback discards its Task. Finalize it too,
                // rather than merely awaiting the private deletion helper.
                for (var attempt = 0; attempt < 5; attempt++)
                {
                    await Task.Delay(100, lifetime.Token);
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                }
                if (Volatile.Read(ref unobserved) != 0)
                    throw new InvalidOperationException("Corrupt-vault remote logout produced an unobserved task exception.");
                var added = File.Exists(diagnostics) ? File.ReadAllText(diagnostics)[previousDiagnostics..] : "";
                if (!added.Contains("step=credential-clear outcome=unavailable storageFailure=true", StringComparison.Ordinal))
                    throw new InvalidOperationException("Corrupt-vault remote logout did not diagnose credential deletion failure.");
                if (host.CurrentContext is not null || host.ReadObservedPublicationVisibility()?.Observation is not null)
                    throw new InvalidOperationException("Corrupt-vault remote logout revived the signed-out Host.");
                if (Volatile.Read(ref httpRequests) != requestsBeforeRevocation)
                    throw new InvalidOperationException("Corrupt-vault remote logout issued an HTTP request.");
                Console.WriteLine("PASS corrupt Windows vault remote logout diagnoses deletion failure, stays signed out, no unobserved task exception; 0 HTTP");
                return;
            }
            await Until(() => vault.LoadRefreshToken(accountKey) is null && vault.LoadActiveAccountKey() is null,
                "Device force-logout retained the local refresh credential or active account.");
            var restarted = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(vaultPath), options);
            if (await restarted.TryRestoreSessionAsync(lifetime.Token) is not null ||
                restarted.LastSessionRestoreOutcome != ScmSessionRestoreOutcome.NoStoredCredential)
                throw new InvalidOperationException("Device force-logout restored a credential after restart.");
            if (Volatile.Read(ref httpRequests) != requestsBeforeRevocation)
                throw new InvalidOperationException("Device force-logout or restart issued an HTTP request.");
            Console.WriteLine("PASS Host force-logout deletes rotated Windows credential and active account; restart stays signed out; 0 HTTP");
            if (host.ReadObservedPublicationVisibility()?.Observation is not null) throw new InvalidOperationException("Revoked session retained status.");
            await server;
            Console.WriteLine("PASS SCM socket acknowledgement, disconnect invalidation, fresh-ticket reconnect, invisible mode and device revocation");
        }
        finally
        {
            TaskScheduler.UnobservedTaskException -= onUnobserved;
            runtime.Dispose();
            lifetime.Cancel();
            listener.Stop();
            foreach (var socket in sockets) socket.Dispose();
            try { await server; } catch (Exception) when (lifetime.IsCancellationRequested) { }
            await DeleteTemporaryRoot(root);
        }
    }

    // Cleanup runs in finally: a throw here would replace the test's real failure
    // (10-30 logs only showed a .tmp/.lock delete error). An unfinished credential
    // clear or a file scanner may still hold a file; a leftover temp dir proves nothing.
    private static async Task DeleteTemporaryRoot(string root)
    {
        for (var attempt = 0; ; attempt++)
        {
            try { Directory.Delete(root, true); return; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                if (attempt >= 20)
                {
                    Console.WriteLine($"WARN SCM realtime temp cleanup left {Path.GetFileName(root)}: {error.GetType().Name} 0x{error.HResult:X8}");
                    return;
                }
            }
            await Task.Delay(100);
        }
    }

    private static async Task<WebSocket> AcceptSocket(TcpClient connection, CancellationToken token)
    {
        var stream = connection.GetStream();
        var header = new List<byte>();
        var next = new byte[1];
        while (header.Count < 8192)
        {
            if (await stream.ReadAsync(next, token) != 1) throw new IOException("Incomplete WebSocket handshake.");
            header.Add(next[0]);
            if (header.Count >= 4 && header.TakeLast(4).SequenceEqual(new byte[] { 13, 10, 13, 10 })) break;
        }
        var lines = Encoding.ASCII.GetString(header.ToArray()).Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
        var request = lines[0].Split(' ');
        var fields = lines.Skip(1).Select(line => line.Split(':', 2))
            .ToDictionary(pair => pair[0], pair => pair[1].Trim(), StringComparer.OrdinalIgnoreCase);
        if (header.Count >= 8192 || request.Length != 3 || request[0] != "GET" || request[2] != "HTTP/1.1" ||
            request[1].Split('?')[0] != "/infra/ws/starbridge" ||
            !fields.TryGetValue("Upgrade", out var upgrade) || !upgrade.Equals("websocket", StringComparison.OrdinalIgnoreCase) ||
            !fields.TryGetValue("Connection", out var connectionHeader) || !connectionHeader.Split(',').Any(v => v.Trim().Equals("Upgrade", StringComparison.OrdinalIgnoreCase)) ||
            !fields.TryGetValue("Sec-WebSocket-Version", out var version) || version != "13" ||
            !fields.TryGetValue("Sec-WebSocket-Key", out var key) || Convert.FromBase64String(key).Length != 16)
            throw new InvalidOperationException("Wrong realtime endpoint or WebSocket handshake.");
        var accept = Convert.ToBase64String(System.Security.Cryptography.SHA1.HashData(
            Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
        await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n"), token);
        return WebSocket.CreateFromStream(stream, isServer: true, subProtocol: null, keepAliveInterval: TimeSpan.FromSeconds(30));
    }

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            return Task.FromResult(respond(request));
        }
    }

    private sealed class Vault : ITokenVault
    {
        internal bool Deleted;
        public void SaveRefreshToken(string key, string token) { }
        public string? LoadRefreshToken(string key) => !Deleted && key == "synthetic-scm:subject" ? "synthetic-refresh" : null;
        public string? LoadActiveAccountKey() => Deleted ? null : "synthetic-scm:subject";
        public void DeleteRefreshToken(string key) { Deleted = true; }
    }
}
