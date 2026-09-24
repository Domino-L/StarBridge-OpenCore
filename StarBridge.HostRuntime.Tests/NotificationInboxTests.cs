using System.Net;
using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;

internal static class NotificationInboxTests
{
    internal static async Task Verify()
    {
        var posts = 0;
        var now = DateTimeOffset.UtcNow;
        using var client = new AccountSafetyClient(new Uri("https://relay.example.test/"), new Handler(async (r, ct) => {
            if (r.Headers.Authorization?.Parameter != "test-only") throw new Exception("Missing bearer");
            if (r.Method == HttpMethod.Post) {
                posts++;
                if (r.RequestUri!.AbsolutePath != "/api/notifications/read") throw new Exception("Wrong write path");
                using var body = JsonDocument.Parse(await r.Content!.ReadAsStringAsync(ct));
                if (body.RootElement.GetProperty("notificationIds")[0].GetString() != "test-id") throw new Exception("Wrong receipt");
                throw new HttpRequestException("Uncertain receipt");
            }
            if (r.RequestUri!.AbsolutePath != "/api/notifications") throw new Exception("Wrong read path");
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(
                new NotificationInboxContract([
                    new("test-id", "system", "normal", "System", "Body", now, null, "", "", null, "system", "test"),
                    new("test-request", "fleet", "action_required", "Application", "Body", now, null, "Review", "fleet_applications", "private-id", "fleet", "test")
                ], 2, 1, now), new JsonSerializerOptions(JsonSerializerDefaults.Web))) };
        }));
        var inbox = await client.ReadInboxAsync("test-only", default);
        if (inbox.Items.Length != 2 || inbox.Items[1].Priority != "action_required") throw new Exception("Lost notification categories");
        try { await client.MarkInboxReadAsync("test-only", ["test-id"], () => { }, default); throw new Exception("Uncertain write accepted"); }
        catch (HttpRequestException) { }
        if (posts != 1) throw new Exception("Write retried");
    }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request, cancellationToken); }
}
