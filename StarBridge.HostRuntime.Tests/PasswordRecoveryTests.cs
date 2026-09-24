using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class PasswordRecoveryTests
{
    internal static async Task Verify()
    {
        var transport = new Transport();
        using var client = new LegacyPasswordRecoveryClient(new Uri("http://127.0.0.1:5058/"), transport);
        var send = BridgePayload.From(new { schemaVersion = 1, email = " old@example.invalid " });
        var confirm = BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", verificationCode = " 123456 ", newPassword = " synthetic-new-password " });
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "development", () => null, passwordRecovery: client);
        using var runtime = new AccountBridgeRuntime(host);
        transport.Body = "{\"sent\":true,\"expiresInMinutes\":10}";
        var reply = await runtime.DispatchAsync(BridgeEnvelope.Request("account.sendPasswordResetCode", "send", 0, send));
        Check(reply.Response.Status == BridgeResponseStatuses.Ok && reply.Response.Payload.GetProperty("outcome").GetString() == "codeRequested", "signed-out recovery route");
        Check(transport.Path == "/api/auth/password-reset/send-code" && transport.Authorization is null, "WPF anonymous send endpoint");
        Check(transport.RequestBody!.RootElement.GetProperty("email").GetString() == "old@example.invalid", "email trimmed");
        Check(host.CurrentContext is null && host.Generation == 0, "recovery does not log in");
        transport.Body = "{\"reset\":true,\"token\":\"must-not-escape\"}";
        var reset = await runtime.DispatchAsync(BridgeEnvelope.Request("account.confirmPasswordReset", "confirm", 0, confirm));
        Check(reset.Response.Payload.GetProperty("outcome").GetString() == "reset", "confirmed reset");
        Check(transport.Path == "/api/auth/password-reset/confirm", "WPF confirm endpoint");
        Check(transport.RequestBody!.RootElement.GetProperty("newPassword").GetString() == " synthetic-new-password ", "password not trimmed");
        Check(!reset.Response.Payload.TryGetProperty("token", out _), "server secrets are not projected");
        Check(host.CurrentContext is null && host.Generation == 0, "reset does not replace or create a session");
        var calls = transport.Calls;
        var stale = await runtime.DispatchAsync(BridgeEnvelope.Request("account.sendPasswordResetCode", "stale", 1, send));
        Check(stale.Response.Status == BridgeResponseStatuses.Error && transport.Calls == calls, "stale generation never sends mail");
        var context = new BridgeAccountContext("development", "synthetic", "subject");
        var contextual = await runtime.DispatchAsync(BridgeEnvelope.Request("account.sendPasswordResetCode", "scoped", 0, send, context));
        Check(contextual.Response.Status == BridgeResponseStatuses.Error && transport.Calls == calls, "SCM context must not accompany recovery");
        var invalid = await client.ExecuteAsync("account.confirmPasswordReset", BridgePayload.From(new { schemaVersion = 1, email = "bad", verificationCode = "123456", newPassword = "long-synthetic" }), default);
        Check(invalid.Outcome == "invalidEmail" && transport.Calls == calls, "invalid email rejected locally");
        invalid = await client.ExecuteAsync("account.confirmPasswordReset", BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", verificationCode = "123456", newPassword = "short" }), default);
        Check(invalid.Outcome == "invalidPassword" && transport.Calls == calls, "shared WPF password policy");
        foreach (var item in new[] {
            (HttpStatusCode.TooManyRequests, "{\"retryAfterSeconds\":120}", "throttled"),
            (HttpStatusCode.BadRequest, "{\"error\":\"验证码错误或已过期。\"}", "invalidCode"),
            (HttpStatusCode.BadRequest, "{\"error\":\"该密码过于常见，请使用更长且独特的密码。\"}", "commonPassword"),
            (HttpStatusCode.OK, "{\"reset\":false}", "unavailable"),
            (HttpStatusCode.InternalServerError, "<private diagnostic>", "unavailable"),
            (HttpStatusCode.OK, "[]", "unavailable"),
            (HttpStatusCode.OK, new string('x', 17000), "unavailable") })
        {
            transport.Status = item.Item1; transport.Body = item.Item2;
            var result = await client.ExecuteAsync("account.confirmPasswordReset", confirm, default);
            Check(result.Outcome == item.Item3, "safe recovery outcome");
            if (item.Item3 == "throttled") Check(result.RetryAfterSeconds == 120, "server cooldown retained");
        }
        transport.Pending = true;
        using var cancellation = new CancellationTokenSource();
        var pending = client.ExecuteAsync("account.sendPasswordResetCode", send, cancellation.Token);
        await transport.Started.Task;
        Check((await client.ExecuteAsync("account.sendPasswordResetCode", send, default)).Outcome == "busy", "duplicate send suppressed");
        cancellation.Cancel();
        try { await pending; throw new Exception("Cancellation ignored"); } catch (OperationCanceledException) { }
        transport.Pending = false; transport.Status = HttpStatusCode.OK; transport.Body = "{\"sent\":true}";
        Check((await client.ExecuteAsync("account.sendPasswordResetCode", send, default)).Outcome == "codeRequested", "cancel permits explicit retry");
        try { using var unsafeClient = new LegacyPasswordRecoveryClient(new Uri("http://example.invalid/")); throw new Exception("Insecure endpoint accepted"); }
        catch (ArgumentException) { }
        try { await client.ExecuteAsync("account.register", send, default); throw new Exception("Registration accepted"); }
        catch (AccountBridgeHostException error) { Check(error.Code == "bridge.capability_unavailable", "registration not part of recovery"); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Transport : HttpMessageHandler
    {
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string Body = "{}";
        internal int Calls;
        internal string? Path, Authorization;
        internal JsonDocument? RequestBody;
        internal bool Pending;
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Path = request.RequestUri!.AbsolutePath; Authorization = request.Headers.Authorization?.ToString();
            RequestBody?.Dispose(); RequestBody = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            if (Pending) { Started.TrySetResult(); await Task.Delay(Timeout.Infinite, token); }
            return new(Status) { Content = new StringContent(Body) };
        }
        protected override void Dispose(bool disposing) { if (disposing) RequestBody?.Dispose(); base.Dispose(disposing); }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Recovery cannot save tokens");
        public string? LoadRefreshToken(string a) => throw new Exception("Recovery cannot read tokens");
        public string? LoadActiveAccountKey() => throw new Exception("Recovery cannot read tokens");
        public void DeleteRefreshToken(string a) => throw new Exception("Recovery cannot delete tokens");
    }
}
