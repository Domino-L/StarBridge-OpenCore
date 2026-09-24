using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;

internal static class AccountSafetyClientTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-13T12:00:00Z");
    private static byte[] Status() => JsonSerializer.SerializeToUtf8Bytes(new {
        activeSanctions = new[] { new AccountSanctionContract("sanction", "chat_mute", "private-report", "reason", Now, null) },
        chatRestricted = true, socialRestricted = false, accountRestricted = false, updatedAt = Now,
        privateToken = "must-not-cross"
    }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
    private static byte[] Appeals() => JsonSerializer.SerializeToUtf8Bytes(new {
        appeals = new[] { new SanctionAppealRecordContract("appeal", "sanction", "chat_mute", "explanation", "reviewing", Now, Now) },
        updatedAt = Now
    }, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    internal static Task Projection()
    {
        var view = AccountSafetyClient.Parse(Status(), Appeals());
        Check(view.Sanctions.Single().SanctionId == "sanction" && view.Appeals.Single().Status == "reviewing", "S2 contracts retained.");
        Check(view.Restrictions.SequenceEqual(new[] { "chat_mute" }), "Restrictions use server facts.");
        var wire = JsonSerializer.Serialize(view);
        Check(!wire.Contains("private-report") && !wire.Contains("must-not-cross"), "Only user-facing facts cross Bridge.");
        foreach (var malformed in new[] { "{}", "null", "{\"activeSanctions\":[],\"updatedAt\":\"2026-09-13T12:00:00Z\"}",
            Encoding.UTF8.GetString(Status()).Replace("\"chatRestricted\":true", "\"chatRestricted\":true,\"ChatRestricted\":false"),
            Encoding.UTF8.GetString(Status()).Replace("\"chatRestricted\":true", "\"chatRestricted\":null") })
            Reject(() => AccountSafetyClient.Parse(Encoding.UTF8.GetBytes(malformed), Appeals()), "accountSafety.data_invalid");
        Reject(() => AccountSafetyClient.Parse(Status(), Encoding.UTF8.GetBytes("{}")), "accountSafety.data_invalid");
        Reject(() => AccountSafetyClient.Parse(new byte[AccountSafetyClient.MaximumBytes + 1], Appeals()), "accountSafety.data_invalid");
        return Task.CompletedTask;
    }

    internal static async Task Submission()
    {
        var input = new CreateSanctionAppealRequestContract("sanction", "explanation", "stable-request");
        foreach (var mode in new[] { "success", "lost", "rejected", "stale", "existing" })
        {
            var posts = 0;
            using var client = new AccountSafetyClient(new Uri("https://relay.example.test"), new Handler(async (request, token) => {
                if (request.Method == HttpMethod.Get) return new(HttpStatusCode.OK) { Content = new ByteArrayContent(
                    request.RequestUri!.AbsolutePath == "/api/trust-safety/status" ? Status() : mode == "existing" ? Appeals() :
                    JsonSerializer.SerializeToUtf8Bytes(new { appeals = Array.Empty<object>(), updatedAt = Now })) };
                posts++;
                Check(request.RequestUri!.AbsolutePath == "/api/appeals", "Original S2 submit path.");
                var payload = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(payload.RootElement.GetProperty("clientRequestId").GetString() == "stable-request", "Stable intent forwarded.");
                if (mode == "lost") throw new HttpRequestException("Lost response after write.");
                if (mode == "rejected") return new(HttpStatusCode.BadRequest);
                return new(HttpStatusCode.OK) { Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(
                    new SanctionAppealRecordContract("appeal", "sanction", "chat_mute", "explanation", "submitted", Now, Now),
                    new JsonSerializerOptions(JsonSerializerDefaults.Web))) };
            }));
            try
            {
                var result = await client.AppealAsync("test-only", input, () => {
                    if (mode == "stale") throw new AccountBridgeHostException("account.reauthorization_required");
                }, default);
                Check(mode is "success" or "existing", "Only confirmed result succeeds.");
                Check(JsonSerializer.SerializeToElement(result).GetProperty("outcome").GetString() ==
                    (mode == "existing" ? "alreadySubmitted" : "submitted"), "Explicit receipt.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(error.Code == (mode == "stale" ? "account.reauthorization_required" :
                    mode == "lost" ? "accountSafety.outcome_unknown" : "accountSafety.rejected"), "Precise failure class.");
            }
            Check(posts == (mode is "stale" or "existing" ? 0 : 1), "No duplicate or stale write.");
        }
    }

    internal static async Task Transport()
    {
        var paths = new System.Collections.Concurrent.ConcurrentBag<string>();
        using var client = new AccountSafetyClient(new Uri("https://relay.example.test/base"), new Handler((request, _) => {
            Check(request.Method == HttpMethod.Get && request.Content is null, "Read does not submit or create a session.");
            Check(request.Headers.Authorization?.ToString() == "Bearer test-only", "Existing token stays in header.");
            paths.Add(request.RequestUri!.AbsolutePath);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(
                request.RequestUri.AbsolutePath == "/api/appeals/mine" ? Appeals() : Status()) });
        }));
        await client.ReadAsync("test-only", default);
        Check(paths.Count == 2 && paths.Contains("/api/appeals/mine") && paths.Contains("/api/trust-safety/status"), "Exact existing S2 routes.");
        foreach (var pair in new[] { (HttpStatusCode.Unauthorized, "accountSafety.identity_unavailable"),
            (HttpStatusCode.Forbidden, "accountSafety.forbidden"), (HttpStatusCode.Redirect, "accountSafety.read_unavailable"),
            (HttpStatusCode.ServiceUnavailable, "accountSafety.read_unavailable") })
        {
            using var failed = new AccountSafetyClient(new Uri("https://relay.example.test"), new Handler((_, _) =>
                Task.FromResult(new HttpResponseMessage(pair.Item1) { Content = new StringContent("private upstream error") })));
            try { await failed.ReadAsync("test-only", default); throw new Exception("Failure accepted as healthy account."); }
            catch (AccountBridgeHostException error) { Check(error.Code == pair.Item2, "Stable scoped error."); }
        }
        using var cancelled = new AccountSafetyClient(new Uri("https://relay.example.test"), new Handler(async (_, token) => {
            await Task.Delay(Timeout.Infinite, token); return new(HttpStatusCode.OK);
        }));
        using var cts = new CancellationTokenSource();
        var pending = cancelled.ReadAsync("test-only", cts.Token);
        cts.Cancel();
        try { await pending; throw new Exception("Cancellation ignored."); } catch (OperationCanceledException) { }
        foreach (var unsafeOrigin in new[] { "http://relay.example.test", "https://user" + "@relay.example.test", "https://relay.example.test?secret=value" })
        {
            try { using var bad = new AccountSafetyClient(new Uri(unsafeOrigin)); throw new Exception("Unsafe origin accepted."); }
            catch (ArgumentException) { }
        }
    }
    private static void Reject(Action action, string code)
    {
        try { action(); throw new Exception("Invalid response accepted."); }
        catch (AccountBridgeHostException error) { Check(error.Code == code, "Stable invalid response."); }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }
}
