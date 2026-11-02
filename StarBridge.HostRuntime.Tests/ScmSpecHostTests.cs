using System.Net;
using System.Reflection;
using System.Text.Json;
using System.Threading.Channels;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static class ScmSpecHostTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("CX48: " + message);
    }

    private sealed class Socket : IScmChatTransport
    {
        internal readonly Channel<JsonElement> Sends = Channel.CreateUnbounded<JsonElement>();
        private readonly Channel<string> _replies = Channel.CreateUnbounded<string>();
        internal int Count;
        public Task ConnectAsync(Uri endpoint, CancellationToken token) => Task.CompletedTask;
        public Task SendAsync(string text, CancellationToken token)
        {
            using var frame = JsonDocument.Parse(text);
            if (frame.RootElement.GetProperty("type").GetString() == "chat-send")
            {
                using var body = JsonDocument.Parse(frame.RootElement.GetProperty("content").GetString()!);
                Interlocked.Increment(ref Count);
                Sends.Writer.TryWrite(body.RootElement.Clone());
            }
            return Task.CompletedTask;
        }
        internal void Reply(string id) => _replies.Writer.TryWrite(JsonSerializer.Serialize(new {
            type = "chat-send-result", content = JsonSerializer.Serialize(new {
                clientMessageId = id, success = true, message = new { id = 123 } }) }));
        public async Task<string?> ReceiveAsync(CancellationToken token) => await _replies.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    internal static async Task Chat()
    {
        var socket = new Socket();
        var original = ScmChatConnection.ReplyTimeout;
        ScmChatConnection.ReplyTimeout = TimeSpan.FromSeconds(3);
        try
        {
            await using var connection = new ScmChatConnection(new Uri("wss://fixture.invalid/chat"),
                _ => Task.FromResult("fixture"), () => socket, _ => { });
            foreach (var invalid in new[] { "", "short", "bad_id-123", "12345678\n", "中文12345678", new string('a', 65) })
            {
                try { await connection.SendAsync(9, "hello", null, null, default, invalid); throw new Exception("invalid id accepted"); }
                catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
            }
            Check(socket.Count == 0, "invalid ids sent frames");
            var first = connection.SendAsync(9, "hello", null, null, default, "stable-id-123");
            var second = connection.SendAsync(9, "hello", null, null, default, "stable-id-123");
            var frame = await socket.Sends.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Check(frame.GetProperty("clientMessageId").GetString() == "stable-id-123", "id changed");
            socket.Reply("unmatched-id-123");
            Check(!first.IsCompleted && !second.IsCompleted, "unmatched receipt completed send");
            socket.Reply("stable-id-123");
            var replies = await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(3));
            Check(socket.Count == 1 && ReferenceEquals(replies[0], replies[1]) && replies[0].Status == "sent", "duplicate send/result mismatch");
            var ids = new List<string>();
            for (var i = 0; i < 2; i++)
            {
                var send = connection.SendAsync(9, "new", null, null, default);
                var next = await socket.Sends.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
                var id = next.GetProperty("clientMessageId").GetString()!;
                Check(Guid.TryParseExact(id, "N", out _), "generated id is not N GUID");
                ids.Add(id);
                socket.Reply(id);
                Check((await send).Status == "sent", "generated id receipt mismatch");
            }
            Check(ids[0] != ids[1], "new sends reused an id");
        }
        finally { ScmChatConnection.ReplyTimeout = original; }
        Console.WriteLine("PASS CX48 H1 stable ids, validation, shared pending and receipt matching");
    }

    private sealed class Vault(bool revoke = false) : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => revoke ? "fixture-revoke" : null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }
    private sealed class Handler(string body, HttpStatusCode status = HttpStatusCode.OK, bool jsonContent = false) : HttpMessageHandler
    {
        internal string? Path;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Path = request.RequestUri!.AbsolutePath;
            return Task.FromResult(new HttpResponseMessage(status) { Content = jsonContent
                ? System.Net.Http.Json.JsonContent.Create(JsonSerializer.Deserialize<JsonElement>(body)) : new StringContent(body) });
        }
    }
    private static readonly Uri Endpoint = new("https://fixture.invalid/");
    private static OAuthPkceClient Client(Handler handler, bool revoke = false) => new(new ScmHttpClient(handler),
        new Vault(revoke), new("fixture", Endpoint, Endpoint, Endpoint, "fixture", "starbridge-api", "", "/callback"));
    private static ScmOAuthSession Session() => new("fixture", "owner", "Fixture", "fixture-access",
        DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);

    private static async Task<object?> Invoke(OAuthPkceClient client, string name, Type? generic, params object?[] args)
    {
        var method = typeof(OAuthPkceClient).GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!;
        if (generic is not null) method = method.MakeGenericMethod(generic);
        var supplied = args.Concat(method.GetParameters().Skip(args.Length).Select(parameter =>
            parameter.IsOptional ? parameter.DefaultValue : throw new TargetParameterCountException())).ToArray();
        var task = (Task)method.Invoke(client, supplied)!;
        await task;
        return task.GetType().GetProperty("Result")?.GetValue(task);
    }

    internal static async Task BusinessCodes()
    {
        // Exercise the actual shared read methods, including the bounded streaming variant.
        var routes = new[] { "identity", "game", "game-code", "device-register", "device-status",
            "resource-profile", "resource-bootstrap", "resource-business-identity", "resource-personal-profile",
            "resource-achievements", "resource-handle-privacy", "resource-reputation", "bounded-resource", "ticket", "presence", "revoke" };
        var count = 0;
        foreach (var route in routes)
        foreach (var code in new int?[] { 401, 403, 500, null, 0 })
        {
            var body = code is > 0 ? JsonSerializer.Serialize(new { code, msg = "server-marker" })
                : code == 0 ? "{\"code\":0,\"subject\":\"owner\",\"trusted\":true,\"signInStatus\":2,\"ticket\":\"fixture\"}"
                : "{\"subject\":\"owner\",\"trusted\":true,\"signInStatus\":2,\"ticket\":\"fixture\"}";
            var handler = new Handler(body);
            var client = Client(handler, route == "revoke");
            try
            {
                object? result = route switch
                {
                    "identity" => await Invoke(client, "LoadIdentityAsync", null, "fixture", "fixture", CancellationToken.None),
                    "game" => await Invoke(client, "SendGameIdentityRequestAsync", typeof(JsonElement), new Uri(Endpoint, "app-api/starbridge/v1/game-identity/verify"), Session(), new { }, CancellationToken.None),
                    "game-code" => await Invoke(client, "SendGameIdentityRequestAsync", typeof(JsonElement), new Uri(Endpoint, "app-api/starbridge/v1/game-identity/verification-code"), Session(), new { }, CancellationToken.None),
                    "device-register" => await client.RegisterDesktopDeviceAsync(Session(), "fixture", default),
                    "device-status" => await client.GetDesktopDeviceStatusAsync(Session(), "fixture", default),
                    var r when r.StartsWith("resource-") || r == "bounded-resource" => await Invoke(client,
                        "ReadAccountResourceAsync", typeof(JsonElement), Session(), new Uri(Endpoint, "app-api/starbridge/v1/" +
                            (r == "bounded-resource" ? "achievements/scm" : r == "resource-reputation" ? "profile?view=self" : r[9..])),
                        "fixture", "profile", CancellationToken.None, route == "bounded-resource" ? 4096 : null),
                    "ticket" => await client.IssueWebSocketTicketAsync(Session(), default),
                    "presence" => await client.UpdatePresenceStatusAsync(Session(), 2, default),
                    _ => null
                };
                if (route == "revoke") await client.RevokeAsync(Session(), default);
                Check(code is null or 0, route + " accepted business error " + code);
                if (route != "revoke")
                {
                    var json = JsonSerializer.Serialize(result, new JsonSerializerOptions { IncludeFields = true });
                    Check(json.Contains("owner") || json.Contains("true") || json.Contains("fixture"), route + " lost direct DTO fields");
                }
            }
            catch (Exception e) when (code is > 0)
            {
                if (route == "revoke")
                {
                    Check(e is ScmRemoteRevocationException, "remote revoke must explicitly identify its committed local phase");
                    e = e.InnerException!;
                }
                Check(code switch { 401 => route.StartsWith("resource-", StringComparison.Ordinal) ||
                        route is "bounded-resource" or "ticket" or "presence"
                        ? e is ScmRefreshTemporarilyUnavailableException : e is ScmApiAuthenticationException,
                    403 => e is ScmApiForbiddenException,
                    _ => e is ScmApiUnavailableException }, route + " wrong error for " + code + ": " + e.GetType().Name);
            }
            Check(handler.Path is not null, route + " did not exercise HTTP");
            count++;
        }
        await Client(new Handler(""), true).RevokeAsync(Session(), default);
        Console.WriteLine($"PASS CX48 H2 {count + 1} direct DTO/business-code/revoke cases");
    }

    internal static async Task Diagnostics()
    {
        var prior = HostDataRoot.CurrentRoot;
        var root = Path.Combine(Environment.GetEnvironmentVariable("STARBRIDGE_TEST_WORKSPACE_ROOT") ?? Environment.CurrentDirectory,
            ".cx48-patch", "diagnostics-test-" + Guid.NewGuid().ToString("N"));
        HostDataRoot.UsePreparedRoot(root);
        const string marker = "CX48_SERVER_FREE_TEXT_MARKER";
        try
        {
            foreach (var method in new[] { "ExchangeCodeAsync", "RefreshTokenAsync" })
            foreach (var status in new[] { HttpStatusCode.OK, HttpStatusCode.BadRequest })
            foreach (var jsonContent in new[] { false, true })
            {
                var client = Client(new Handler(JsonSerializer.Serialize(new { code = 500, msg = marker, error = marker, error_description = marker }), status, jsonContent));
                try
                {
                    if (method == "ExchangeCodeAsync") await Invoke(client, method, null, "fixture", "fixture", Endpoint, "fixture", CancellationToken.None, true);
                    else await Invoke(client, method, null, "fixture", "fixture", CancellationToken.None);
                    throw new Exception("token failure accepted");
                }
                catch (Exception e) when (e is InvalidOperationException or HttpRequestException)
                {
                    Check(status == HttpStatusCode.OK ? e.GetType() == typeof(InvalidOperationException)
                        : method == "RefreshTokenAsync"
                            ? e is ScmRefreshTemporarilyUnavailableException { StatusCode: null }
                            : e is HttpRequestException request && request.StatusCode == status, "diagnostic read altered token error");
                }
            }
            foreach (var jsonContent in new[] { false, true })
            {
                var client = Client(new Handler(JsonSerializer.Serialize(new { error = "invalid_grant", error_description = marker }), HttpStatusCode.BadRequest, jsonContent));
                try { await Invoke(client, "RefreshTokenAsync", null, "fixture", "fixture", CancellationToken.None); throw new Exception("invalid_grant accepted"); }
                catch (Exception e) when (e.GetType().Name == "ScmRefreshTokenRejectedException") { }
            }
            var log = File.ReadAllText(Path.Combine(root, "scm-auth-diagnostics.log"));
            Check(!log.Contains(marker), "server free text reached diagnostics");
            Check(log.Contains("status=200 code=500 error=business-error") && log.Contains("status=400 code=500 error=http-error"), "failure metadata missing");
        }
        finally { HostDataRoot.UsePreparedRoot(prior); }
        Console.WriteLine("PASS CX48 H3 token exchange/refresh HTTP and business failure diagnostics");
    }

    internal static async Task Run() { await Chat(); await BusinessCodes(); await Diagnostics(); }
}
