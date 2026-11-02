using System.Text.Json;

internal static partial class MarketplaceWriteTests
{
    private static async Task<int> VerifyTicketConnectionRejections()
    {
        var passed = 0;
        foreach (var mode in new[] { "specific", "unknownSpecific", "businessKnown", "businessUnknown", "business403", "business401", "scopeHeader" })
        {
            using var handler = new TicketRejection(mode);
            var uri = new Uri("https://fixture.invalid/");
            var client = new StarBridge.HostRuntime.Auth.OAuthPkceClient(
                new StarBridge.HostRuntime.Auth.ScmHttpClient(handler), new Vault(),
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
            var session = new StarBridge.HostRuntime.Auth.ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
                DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
            await using var connection = new StarBridge.HostRuntime.Auth.ScmChatConnection(
                new("wss://fixture.invalid/infra/ws/chat"),
                async token => (await client.IssueChatTicketAsync(session, token)).Ticket,
                () => new Socket("ok"), _ => { });
            for (var i = 0; i < 100 && !connection.Faulted; i++) await Task.Delay(10);
            Check(connection.Faulted && handler.Calls == 1, "ticket rejection stops outer reconnect: " + mode);
            if (mode is "businessUnknown" or "business403")
            {
                await Task.Delay(2100);
                Check(handler.Calls == 1, "terminal refusal stays stopped past first backoff: " + mode);
            }
            passed++;
        }
        Console.WriteLine($"PASS ticket rejection stops connection retries: {passed}");
        return passed + await VerifyTicketRecoveryAndHtml();
    }

    private static async Task<int> VerifyTicketRecoveryAndHtml()
    {
        var passed = 0;
        foreach (var mode in new[] { "unavailable", "network", "html", "htmlScope" })
        {
            using var handler = new RecoveryTicketHandler(mode);
            var uri = new Uri("https://fixture.invalid/");
            var client = new StarBridge.HostRuntime.Auth.OAuthPkceClient(
                new StarBridge.HostRuntime.Auth.ScmHttpClient(handler), new Vault(),
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
            var session = new StarBridge.HostRuntime.Auth.ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
                DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
            if (mode.StartsWith("html", StringComparison.Ordinal))
            {
                string? code = null;
                try { await client.IssueChatTicketAsync(session, default); }
                catch (StarBridge.HostRuntime.Account.AccountBridgeHostException e) { code = e.Code; }
                Check(code == (mode == "htmlScope" ? "marketplace.reauthorize_required" : "marketplace.forbidden"),
                    "HTML 403 mapping: " + mode);
                Check(handler.Calls == 1, "HTML 403 sends ticket POST once");
            }
            else
            {
                var attempts = 0;
                var recovered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                await using var connection = new StarBridge.HostRuntime.Auth.ScmChatConnection(
                    new("wss://fixture.invalid/infra/ws/chat"),
                    async token =>
                    {
                        var attempt = Interlocked.Increment(ref attempts);
                        try { return (await client.IssueChatTicketAsync(session, token)).Ticket; }
                        finally { Check(handler.Calls == attempt, "one POST per connection attempt"); }
                    },
                    () => new Socket("ok"), push => { if (push.Kind == "resync") recovered.TrySetResult(); });
                await recovered.Task.WaitAsync(TimeSpan.FromSeconds(8));
                Check(!connection.Faulted && attempts == 2 && handler.Calls == 2,
                    "transient ticket failure recovers on next attempt: " + mode);
                Check(handler.RetryDelay >= TimeSpan.FromSeconds(1.9), "retry preserves two-second backoff");
            }
            passed++;
        }
        Console.WriteLine($"PASS ticket transient recovery and HTML 403: {passed}");
        return passed;
    }

    private sealed class RecoveryTicketHandler(string mode) : HttpMessageHandler
    {
        internal int Calls;
        internal TimeSpan RetryDelay;
        private readonly System.Diagnostics.Stopwatch watch = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid" && request.Method == HttpMethod.Post &&
                request.RequestUri.AbsolutePath == "/app-api/member/chat/ws-ticket", "only synthetic ticket POST");
            var call = Interlocked.Increment(ref Calls);
            Check(call <= 2, "no extra ticket POST");
            if (call == 1) watch.Start();
            else RetryDelay = watch.Elapsed;
            if (mode == "network" && call == 1) throw new HttpRequestException("synthetic network failure");
            var html = mode.StartsWith("html", StringComparison.Ordinal);
            var response = new HttpResponseMessage(html ? System.Net.HttpStatusCode.Forbidden : System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent(html ? "<html><body>Access denied</body></html>"
                    : call == 1 ? "{}" : """{"code":0,"data":"fixture-ticket"}""",
                    System.Text.Encoding.UTF8, html ? "text/html" : "application/json"),
            };
            if (mode == "htmlScope") response.Headers.WwwAuthenticate.ParseAdd("Bearer error=\"insufficient_scope\"");
            return Task.FromResult(response);
        }
    }

    // Explicit HTTP status in every label: the old unknownSpecific ticket case is HTTP 403.
    private static IEnumerable<string> EnvelopeModes()
    {
        foreach (var status in new[] { 200, 403 })
        foreach (var sample in new[] { "zero", "401", "403", "known", "unknown", "missing", "string", "null", "array", "fraction",
            "negative", "large", "listingLimit", "sameItem", "manifest", "account", "timezone", "contact", "day", "time" })
            yield return $"envelope-{status}-{sample}";
    }

    private static (string Body, string Expected) EnvelopeCase(Case c, string mode)
    {
        var sample = mode.Split('-')[2];
        var result = sample switch
        {
            "401" => ("{\"code\":401}", "marketplace.sign_in_required"),
            "403" => ("{\"code\":403}", "marketplace.forbidden"),
            "known" => ("{\"code\":1011009001}", "marketplace.not_owner"),
            "unknown" => ("{\"code\":1002}", "marketplace.trade_rejected"),
            "missing" => ("{}", "marketplace.unavailable"),
            "string" => ("{\"code\":\"1002\"}", "marketplace.unavailable"),
            "null" => ("{\"code\":null}", "marketplace.unavailable"),
            "array" => ("[]", "marketplace.unavailable"),
            "fraction" => ("{\"code\":1.5}", "marketplace.unavailable"),
            "negative" => ("{\"code\":-1}", "marketplace.trade_rejected"),
            "large" => ("{\"code\":9223372036854775807}", "marketplace.trade_rejected"),
            "listingLimit" => ("{\"code\":1011011002}", "marketplace.listing_limit"),
            "sameItem" => ("{\"code\":1011011004}", "marketplace.listing_same_item_limit"),
            "manifest" => ("{\"code\":1011011005}", "marketplace.listing_manifest_limit"),
            "account" => ("{\"code\":1004001009}", "marketplace.account_unbound"),
            "timezone" => ("{\"code\":1002,\"msg\":\"\u65f6\u533a\"}", "trade_profile.timezone_invalid"),
            "contact" => ("{\"code\":1002,\"msg\":\"\u8054\u7cfb\u65b9\u5f0f\"}", "trade_profile.contact_invalid"),
            "day" => ("{\"code\":1002,\"msg\":\"\u9009\u62e9\u4e00\u5929\"}", "trade_profile.no_day"),
            "time" => ("{\"code\":1002,\"msg\":\"\u4ea4\u6613\u65f6\u95f4\"}", "trade_profile.time_range"),
            "zero" => (JsonSerializer.Serialize(new { code = 0, data =
                c.Area == "ticket" ? (object)"fixture-ticket" :
                c.Area == "trade" && c.Op == "create" ? (object)"T1" :
                c.Area == "contracts" ? 19L : c.Area == "chat" && c.Op is "open" or "openOrder"
                    ? new { id = 31, otherUserId = 909 } : true }), ""),
            _ => throw new Exception("Unknown envelope fixture"),
        };
        return c.Area != "profile" && sample is "timezone" or "contact" or "day" or "time"
            ? (result.Item1, "marketplace.trade_rejected") : result;
    }
}
