using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// Setup "is recognition working" check: a read-only projection of the confirmed
// local log slot. It never enables listening, records time or grants anything.
internal static class LocalRecognitionCheckTests
{
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static BridgeEnvelope Request(long generation = 1, object? payload = null, BridgeAccountContext? owner = null) =>
        BridgeEnvelope.Request(LocalStatisticsChoiceBridgeDispatcher.RecognitionReadRequest, Guid.NewGuid().ToString("N"),
            generation, payload ?? new { schemaVersion = 1 }, owner);
    private static async Task<JsonElement> Read(IBridgeRequestDispatcher d)
    {
        var reply = (await d.DispatchAsync(Request())).Response;
        Check(reply.Status == "ok" && reply.AccountContext is null, "recognition read succeeds without account context");
        return reply.Payload;
    }
    private static string? Text(JsonElement body, string name) =>
        body.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    internal static async Task Run()
    {
        using var f = new LocalGameplayTimeTests.Fixture();
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        Check(LocalStatisticsChoiceBridgeDispatcher.Handles(LocalStatisticsChoiceBridgeDispatcher.RecognitionReadRequest),
            "composite routes the recognition read");

        var before = await Read(d);
        Check(Text(before, "state") != "ready" && Text(before, "handle") is null &&
            before.GetProperty("server").GetProperty("state").GetString() == "unknown" &&
            before.GetProperty("location").GetProperty("state").GetString() == "unknown",
            "listening off: no recognition is claimed");
        Check(f.Identities.Read().Sources.Single().ListeningEnabled != true, "reading never enables listening");

        f.EnableListening(); f.Tick(0);
        var ready = await Read(d);
        Check(Text(ready, "state") == "ready" && Text(ready, "handle") == "Pilot-Example" && Text(ready, "version") == "LIVE",
            "running game with the confirmed Handle reads as ready");
        var raw = ready.GetRawText();
        Check(new[] { f.Root, f.Log, f.Key, f.Profile, "shard", "path", "profileId", "sourceKey" }
            .All(value => !raw.Contains(value, StringComparison.OrdinalIgnoreCase)), "no paths, keys or shard leave the Host");

        f.Process = new GameProcessSession("notRunning"); f.Tick(1);
        var stopped = await Read(d);
        Check(Text(stopped, "state") == "notRunning" && Text(stopped, "handle") is null &&
            stopped.GetProperty("ship").GetProperty("state").GetString() == "unknown", "closed game is reported honestly");

        Check((await d.DispatchAsync(Request(payload: new { schemaVersion = 1, path = "x" }))).Response.Status == "error",
            "extra fields are refused");
        Check((await d.DispatchAsync(Request(generation: 2))).Response.Status == "error", "stale generation is refused");
        Check((await d.DispatchAsync(Request(owner: new BridgeAccountContext("synthetic", "scm", "owner")))).Response.Status == "error",
            "account-scoped requests are refused");
        Check(!Directory.Exists(f.StatisticsDirectory), "the check never records play time");
        Console.WriteLine("PASS first-use recognition check is read-only, honest and leaks no paths");
    }
}
