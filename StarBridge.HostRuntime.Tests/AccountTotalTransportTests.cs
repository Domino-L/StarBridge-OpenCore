using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

internal static class AccountTotalTransportTests
{
    internal static async Task Run()
    {
        foreach (var seconds in new long?[] { null, 0, 7200 })
        {
            var body = JsonSerializer.Serialize(new { schemaVersion = 3,
                gameplayStatistics = seconds is null ? null : (object)new { playTimeSeconds = seconds.Value } });
            using var handler = new Handler(body);
            // This read never consults a credential store. The synthetic handler
            // intercepts every request; no socket or authentication operation exists.
            using var client = new LegacyPasswordLoginClient(new Uri("https://relay.example.invalid/"), null!, handler);
            var total = await client.ReadGameplayAccountTotalAsync("synthetic-test-bearer", default);
            if (total.State != (seconds is null ? "empty" : "available") || total.Seconds != seconds || handler.Calls != 1)
                throw new Exception("Incorrect nullable account total mapping.");
            Console.WriteLine("PASS total transport: " + (seconds?.ToString() ?? "no record") + ", GET only");
        }
        foreach (var body in new[] {
            """{"schemaVersion":3,"gameplayStatistics":{"playTimeSeconds":-1}}""",
            """{"schemaVersion":3}""",
            """{"schemaVersion":1,"gameplayStatistics":null}"""
        })
        {
            using var handler = new Handler(body);
            using var client = new LegacyPasswordLoginClient(new Uri("https://relay.example.invalid/"), null!, handler);
            var rejected = false;
            try { await client.ReadGameplayAccountTotalAsync("synthetic-test-bearer", default); }
            catch (Exception e) when (e is JsonException or KeyNotFoundException) { rejected = true; }
            if (!rejected) throw new Exception("Malformed response cannot claim empty/zero.");
            Console.WriteLine("PASS total transport: malformed response rejected");
        }
    }

    private sealed class Handler(string body) : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            if (request.Method != HttpMethod.Get || request.RequestUri?.AbsolutePath != "/api/profile/me")
                throw new Exception("Read-only account totals may only use the existing own-profile GET.");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            });
        }
    }
}