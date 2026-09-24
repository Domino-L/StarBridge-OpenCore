using System.Net;
using System.Net.Http.Json;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;

internal static class EventSharingTransportTests
{
    internal static async Task Run()
    {
        await FeedAsync();
        var settings = new SharedEventPreferences(new(true, SharedActivityEventTypes.Server), []);
        var operation = Guid.NewGuid().ToString("N");
        var snapshot = new EventSharingRemoteSnapshot(1, 1, operation, DateTimeOffset.UtcNow, true, settings);
        HttpResponseMessage Response(EventSharingRemoteSnapshot value) => new(HttpStatusCode.OK)
            { Content = JsonContent.Create(value, options: LocalPrivacyStore.Json) };
        var calls = new List<string>();
        var mode = "ok"; var current = true;
        using var writer = new PrivacyRelayWriter(new Uri("https://events.invalid"), new Handler((request, token) =>
        {
            calls.Add(request.Method.Method);
            Check(request.RequestUri!.AbsolutePath == "/api/privacy/events" &&
                request.Headers.Authorization?.Parameter == "fixture", "exact scoped route and per-request bearer");
            if (request.Method == HttpMethod.Get)
                return Task.FromResult(Response(mode == "competing" ? snapshot with { Revision = 2 } : snapshot));
            if (mode == "swap") { current = false; throw new HttpRequestException(); }
            if (mode is "lost" or "competing") throw new HttpRequestException();
            if (mode == "unavailable") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            if (mode == "conflict") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Conflict));
            if (mode == "bad") return Task.FromResult(Response(snapshot with { Settings = SharedEventPreferences.Unconfirmed }));
            return Task.FromResult(Response(snapshot));
        }));
        void EnsureCurrent() { if (!current) throw new AccountBridgeHostException("events.account_changed"); }
        Task<EventSharingRemoteSnapshot> Save() => writer.SaveEventsAsync("fixture", 0, operation, true, settings, EnsureCurrent, default);
        Check((await Save()).Revision == 1 && calls.SequenceEqual(["POST"]), "valid receipt needs one write only");
        calls.Clear(); mode = "lost";
        Check((await Save()).OperationId == operation && calls.SequenceEqual(["POST", "GET"]), "lost receipt uses exactly one readback");
        calls.Clear(); mode = "competing";
        await Expect("events.write_unconfirmed", Save);
        Check(calls.SequenceEqual(["POST", "GET"]), "competing revision is not confirmation or a retry");
        calls.Clear(); mode = "bad";
        Check((await Save()).Revision == 1 && calls.SequenceEqual(["POST", "GET"]), "malformed acknowledgement is checked by authoritative readback");
        calls.Clear(); mode = "conflict";
        await Expect("events.conflict", Save);
        Check(calls.SequenceEqual(["POST"]), "conflict is not silently rebased");
        calls.Clear(); mode = "unavailable";
        await Expect("events.unavailable", Save);
        Check(calls.SequenceEqual(["POST"]), "unavailable endpoint has no legacy fallback");
        calls.Clear(); mode = "swap";
        await Expect("events.account_changed", Save);
        Check(calls.SequenceEqual(["POST"]), "account change prevents readback with old credentials");
        calls.Clear();
        await Expect("events.account_changed", Save);
        Check(calls.Count == 0, "stale account does not send a write");
    }
    private static async Task FeedAsync()
    {
        var session = Guid.NewGuid().ToString("N");
        var calls = 0; var mode = "ok";
        using var writer = new PrivacyRelayWriter(new Uri("https://events.invalid"), new Handler((request, _) =>
        {
            calls++;
            Check(request.RequestUri!.AbsolutePath == "/api/privacy/events/feed", "dedicated data route");
            if (mode == "lost") throw new HttpRequestException();
            if (mode == "missing") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            object body = request.Method == HttpMethod.Get
                ? new { schemaVersion = 1, observedAt = DateTimeOffset.UtcNow, publishers = new[] {
                    new { accountId = "synthetic-owner", callsign = "Pilot", events = new[] {
                        new SharedActivityEvent(Guid.NewGuid().ToString("N"), mode == "bad" ? "Unknown" : "PlayerDied", DateTimeOffset.UtcNow) } } } }
                : new { schemaVersion = 1, sessionId = session, sequence = mode == "bad" ? 2 : 0, expiresAt = DateTimeOffset.UtcNow.AddSeconds(45) };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }));
        Check((await writer.WriteEventFeedAsync("fixture", "start", 1, null, 0, [], () => { }, default)).SessionId == session,
            "feed receipt confirms exact sequence and session");
        Check((await writer.ReadEventFeedAsync("fixture", "organization", "A", default)).Publishers.Length == 1,
            "authorized bounded feed is decoded");
        mode = "bad"; calls = 0;
        try { await writer.WriteEventFeedAsync("fixture", "start", 1, null, 0, [], () => { }, default); throw new InvalidOperationException(); }
        catch (AccountBridgeHostException e) when (e.Code == "events.response_invalid") { }
        Check(calls == 1, "malformed data receipt never retries");
        try { await writer.ReadEventFeedAsync("fixture", "organization", "A", default); throw new InvalidOperationException(); }
        catch (AccountBridgeHostException e) when (e.Code == "events.response_invalid") { }
        mode = "lost"; calls = 0;
        try { await writer.WriteEventFeedAsync("fixture", "start", 1, null, 0, [], () => { }, default); throw new InvalidOperationException(); }
        catch (HttpRequestException) { }
        Check(calls == 1, "lost data receipt never replays a batch");
        mode = "missing"; calls = 0;
        try { await writer.ReadEventFeedAsync("fixture", "room", "A", default); throw new InvalidOperationException(); }
        catch (AccountBridgeHostException e) when (e.Code == "events.unavailable") { }
        Check(calls == 1, "missing feed does not fall back to legacy state");
    }
    private static async Task Expect(string code, Func<Task<EventSharingRemoteSnapshot>> action)
    {
        try { await action(); }
        catch (AccountBridgeHostException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token);
    }
}
