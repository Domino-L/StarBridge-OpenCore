using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class HelpSupportTests
{
    internal static async Task RunAll()
    {
        var opened = 0;
        using (var links = new HelpSupportBridgeDispatcher(null, () => 2, openScm: () => opened++))
        {
            BridgeEnvelope Link(object payload, long generation = 2) => BridgeEnvelope.Request(
                "helpSupport.openScm", Guid.NewGuid().ToString(), generation, payload);
            var ok = (await links.DispatchAsync(Link(new { schemaVersion = 1 }))).Response;
            Check(ok.Status == "ok" && opened == 1, "SCM website opens without login or service origin");
            await links.DispatchAsync(Link(new { schemaVersion = 1, url = "https://untrusted.example" }));
            await links.DispatchAsync(Link(new { schemaVersion = 1 }, 1));
            Check(opened == 1, "custom URLs and stale requests cannot launch browser");
        }
        var destinations = new List<Uri>();
        using (var website = new HelpSupportBridgeDispatcher(null, () => 2, openRsiOrganization: destinations.Add))
        {
            BridgeEnvelope Link(object payload, long epoch = 2) => BridgeEnvelope.Request(
                "helpSupport.openRsiOrganization", Guid.NewGuid().ToString(), epoch, payload);
            foreach (var sid in new[] { "ASTER", "A", "0123456789" })
            {
                var result = (await website.DispatchAsync(Link(new { schemaVersion = 1, sid }))).Response;
                Check(result.Status == "ok" && result.Payload.GetProperty("opened").GetBoolean(), "RSI launcher confirmed");
                Check(destinations.Last().AbsoluteUri == "https://robertsspaceindustries.com/orgs/" + sid, "fixed official origin and path");
            }
            foreach (var sid in new[] { "", "lower", "ABCDEFGHIJK", "../ASTER", "ASTER?x=1", "ASTER#x", "ASTER/", "A%2FB", "Ａ", "A\n", "A\\B", "https://evil.example" })
                Check((await website.DispatchAsync(Link(new { schemaVersion = 1, sid }))).Response.Status == "error", "invalid SID stays local");
            await website.DispatchAsync(Link(new { schemaVersion = 1, sid = "ASTER", url = "https://evil.example" }));
            await website.DispatchAsync(Link(new { schemaVersion = 1, sid = 1 }));
            await website.DispatchAsync(Link(new { schemaVersion = 1, sid = "ASTER" }, 1));
            await website.DispatchAsync(Link(new { schemaVersion = 1, sid = "ASTER" }) with
                { AccountContext = new BridgeAccountContext("synthetic", "test", "viewer") });
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            await website.DispatchAsync(Link(new { schemaVersion = 1, sid = "ASTER" }), cancelled.Token);
            Check(destinations.Count == 3, "stale, malformed, account and cancelled requests do not open browser");
        }
        using (var offline = new HelpSupportBridgeDispatcher(null, () => 2,
            network: new StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission(() => false), openRsiOrganization: destinations.Add))
        {
            var result = await offline.DispatchAsync(BridgeEnvelope.Request("helpSupport.openRsiOrganization", Guid.NewGuid().ToString(), 2,
                new { schemaVersion = 1, sid = "ASTER" }));
            Check(result.Response.Status == "error" && destinations.Count == 3, "explicit offline does not launch external browser");
        }
        Check(HelpSupportBridgeDispatcher.Capabilities.Contains("helpSupport.openRsiOrganization"), "only actual callable is advertised");
        // SCM users change their avatar on the RSI profile settings page (fixed URL).
        var profilePages = new List<Uri>();
        using (var rsiProfile = new HelpSupportBridgeDispatcher(null, () => 2, openRsiOrganization: profilePages.Add))
        {
            BridgeEnvelope Open(object payload, long epoch = 2) => BridgeEnvelope.Request(
                "helpSupport.openRsiProfileSettings", Guid.NewGuid().ToString(), epoch, payload);
            var profileOpened = (await rsiProfile.DispatchAsync(Open(new { schemaVersion = 1 }))).Response;
            Check(profileOpened.Status == "ok" && profilePages.Single().AbsoluteUri == "https://robertsspaceindustries.com/en/account/settings/profile",
                "RSI profile settings opens the fixed official page");
            Check((await rsiProfile.DispatchAsync(Open(new { schemaVersion = 1, url = "https://evil.example" }))).Response.Status == "error" &&
                (await rsiProfile.DispatchAsync(Open(new { schemaVersion = 1 }, 1))).Response.Status == "error" &&
                profilePages.Count == 1, "no caller URL and no stale request opens a page");
        }
        using (var offlineProfile = new HelpSupportBridgeDispatcher(null, () => 2,
            network: new StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission(() => false), openRsiOrganization: profilePages.Add))
            Check((await offlineProfile.DispatchAsync(BridgeEnvelope.Request("helpSupport.openRsiProfileSettings", Guid.NewGuid().ToString(), 2,
                new { schemaVersion = 1 }))).Response.Status == "error" && profilePages.Count == 1, "explicit offline does not open RSI");
        Check(HelpSupportBridgeDispatcher.Capabilities.Contains("helpSupport.openRsiProfileSettings"), "RSI profile settings is advertised");
        var handler = new Transport();
        long generation = 2;
        var capability = new AppStatsHeartbeatRuntime.RelayCapability();
        Check(capability.Protocol is null, "relay capability starts unknown");
        using var dispatcher = new HelpSupportBridgeDispatcher(new Uri("https://support.example/"), () => generation, handler,
            appStatsCapability: capability);
        BridgeEnvelope Request(string name, object? payload = null) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString(), generation, payload ?? new { schemaVersion = 1 });
        var history = (await dispatcher.DispatchAsync(Request("helpSupport.history"))).Response;
        Check(history.Status == "ok" && history.Payload.GetProperty("edition").GetString() == "starbridge", "embedded product history");
        Check(history.Payload.GetProperty("entries").GetArrayLength() > 0 && handler.Calls == 0, "history is offline");
        var releases = history.Payload.GetProperty("entries").EnumerateArray().ToArray();
        var major = releases.Single(e => e.GetProperty("version").GetString() == "0.7.0");
        Check(major.GetProperty("highlights").GetArrayLength() >= 15 &&
            major.GetProperty("summary").GetString()!.Contains("0.6.6"), "0.7 summarizes the full user-facing upgrade");
        Check(!releases.Any(e => e.GetRawText().Contains("Flutter") || e.GetRawText().Contains("WPF")),
            "release history does not split the product by implementation framework");
        var stats = (await dispatcher.DispatchAsync(Request("helpSupport.stats"))).Response;
        Check(stats.Status == "ok" && stats.Payload.GetProperty("fleetCount").GetInt64() == 3, "stats project real fleet count");
        Check(!handler.HadCredentials && handler.LastMethod == HttpMethod.Get, "stats do not publish telemetry or identity");
        var invalid = await dispatcher.DispatchAsync(Request("helpSupport.feedback", new { schemaVersion = 1, contact = "", message = " " }));
        Check(invalid.Response.Status == "error" && handler.Calls == 1, "invalid feedback stays local");
        var feedback = new { schemaVersion = 1, contact = "synthetic", message = "test only" };
        var sent = await dispatcher.DispatchAsync(Request("helpSupport.feedback", feedback));
        Check(sent.Response.Status == "ok" && handler.Calls == 2 && handler.LastMethod == HttpMethod.Post, "single send");
        using var body = JsonDocument.Parse(handler.LastBody!);
        Check(body.RootElement.EnumerateObject().Count() == 2 && !handler.HadCredentials, "no implicit account or logs");
        handler.Fail = true;
        var failed = await dispatcher.DispatchAsync(Request("helpSupport.feedback", feedback));
        Check(failed.Response.Status == "error" && handler.Calls == 3, "uncertain send not retried");
        var stale = Request("helpSupport.stats") with { SessionGeneration = 1 };
        Check((await dispatcher.DispatchAsync(stale)).Response.Status == "error" && handler.Calls == 3, "stale request rejected");
        handler.Fail = false;
        foreach (var raw in new string?[] { null, "null", "0", "42", "-1", "\"invalid\"", "1.5" })
        {
            handler.AccountCountJson = raw;
            var result = (await dispatcher.DispatchAsync(Request("helpSupport.stats"))).Response;
            Check(result.Status == "ok" && result.Payload.GetProperty("fleetCount").GetInt64() == 3,
                "optional account count must not break existing stats");
            var expected = raw == "0" ? (long?)0 : raw == "42" ? 42 : null;
            var hasCount = result.Payload.TryGetProperty("registeredAccountCount", out var value) && value.ValueKind != JsonValueKind.Null;
            Check(expected.HasValue ? hasCount && value.GetInt64() == expected : !hasCount,
                "missing or invalid count is unknown, valid zero remains zero");
        }
        Check(capability.Protocol == 1, "old GET records legacy capability");
        handler.ProtocolJson = "2";
        await dispatcher.DispatchAsync(Request("helpSupport.stats"));
        Check(capability.Protocol == 2, "home stats GET upgrades shared heartbeat capability");
        handler.ProtocolJson = null;
        await dispatcher.DispatchAsync(Request("helpSupport.stats"));
        Check(capability.Protocol == 1, "old GET revokes shared modern capability");
        Console.WriteLine("PASS help support offline history, stats, feedback validation and no implicit upload/retry");
    }
    private static void Check(bool value, string label) { if (!value) throw new Exception(label); }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Calls;
        internal bool Fail, HadCredentials;
        internal HttpMethod? LastMethod;
        internal string? LastBody;
        internal string? AccountCountJson;
        internal string? ProtocolJson;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; LastMethod = request.Method;
            HadCredentials |= request.Headers.Authorization != null || request.Headers.Contains("X-StarBridge-Key");
            if (request.Content != null) LastBody = await request.Content.ReadAsStringAsync(token);
            if (Fail) throw new HttpRequestException("synthetic transport loss");
            return new(HttpStatusCode.OK) { Content = new StringContent(request.Method == HttpMethod.Get
                ? "{\"downloadCount\":5,\"onlineUserCount\":2,\"fleetCount\":3,\"overlayUsageSeconds\":3600,\"updatedAt\":\"2026-09-15T12:00:00Z\"" +
                    (AccountCountJson is null ? "" : ",\"registeredAccountCount\":" + AccountCountJson) + (ProtocolJson is null ? "" : ",\"heartbeatProtocol\":" + ProtocolJson) + "}" : "{}") };
        }
    }
}
