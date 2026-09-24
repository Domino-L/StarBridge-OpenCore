using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;

internal static class GameIdSettingsTests
{
    internal static async Task Run()
    {
        var saved = new GameIdSettingsSnapshot(1, 0, 15, true, new string('a', 64));
        var calls = new List<string>();
        var mode = "ok";
        var current = true;
        using var writer = new PrivacyRelayWriter(new Uri("https://fixture.invalid"), new Handler(async request =>
        {
            calls.Add(request.Method.Method);
            Check(request.Headers.Authorization?.Parameter == "fixture" && request.RequestUri!.Query == "?section=game-id", "trusted scoped route");
            if (mode == "legacy") return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { callsign = "Existing" }) };
            if (request.Method == HttpMethod.Post)
            {
                var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync()).RootElement;
                Check(body.EnumerateObject().Count() == 4 && !body.TryGetProperty("callsign", out _), "no unrelated profile fields");
                saved = saved with { Revision = saved.Revision + 1, Locations = body.GetProperty("locations").GetInt32() };
                if (mode == "lost") throw new HttpRequestException();
                if (mode == "swap") { current = false; throw new HttpRequestException(); }
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(saved, options: LocalPrivacyStore.Json) };
        }));
        void Ensure() { if (!current) throw new AccountBridgeHostException("gameId.account_changed"); }
        async Task Save(int mask) => await writer.SaveGameIdAsync("fixture", saved.Revision, saved.IdentityStamp, mask, Ensure, default);
        await Save(4);
        Check(calls.SequenceEqual(["GET", "POST"]) && saved.Locations == 4, "capability preflight and one write");
        mode = "lost"; calls.Clear(); await Save(0);
        Check(calls.SequenceEqual(["GET", "POST", "GET"]), "lost reply reads once without replay");
        mode = "legacy"; calls.Clear();
        try { await Save(15); throw new Exception("legacy response accepted"); } catch (JsonException) { }
        Check(calls.SequenceEqual(["GET"]), "old server never receives partial profile mutation");
        mode = "swap"; calls.Clear();
        try { await Save(15); throw new Exception("owner swap accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "gameId.account_changed") { }
        Check(calls.SequenceEqual(["GET", "POST"]), "owner change prevents readback with new credentials");
    }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request); }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
