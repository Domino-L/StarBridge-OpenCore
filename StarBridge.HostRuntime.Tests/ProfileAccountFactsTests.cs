using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class ProfileAccountFactsTests
{
    private const string Subject = "synthetic-owner";
    private static readonly string BusinessId = "scm-v1:" + new string('a', 64);
    private static int _passed;
    private static void Check(bool condition, string reason)
    {
        if (!condition) throw new Exception("FAIL owner facts: " + reason);
    }

    internal static async Task Run()
    {
        _passed = 0;
        await Case("normal read, own route, bridge timezone projection", async () =>
        {
            using var fixture = new Fixture();
            var payload = await fixture.Read();
            var facts = payload.GetProperty("facts");
            Check(payload.GetProperty("schemaVersion").GetInt32() == 1, "schema");
            Check(facts.GetProperty("completedTrades").GetInt32() == 31, "trade count");
            Check(facts.GetProperty("lastOnlineDay").GetString() == "2026-11-08", "last online");
            Check(facts.GetProperty("utcOffsetMinutes").GetInt32() == 480, "IANA offset wins over stale directory offset");
            Check(!facts.TryGetProperty("timezoneId", out _) && !facts.TryGetProperty("lastOnlineVisible", out _), "Host-only fields");
            Check(fixture.Transport.Paths.SequenceEqual(new[] {
                "/app-api/starbridge/v1/business-identity",
                "/app-api/starbridge/v1/personal-profile/account-facts/" + BusinessId,
                "/app-api/member/timezone/list" }), "target comes only from authenticated business identity");
        });
        foreach (var body in new[] {
            """{"schemaVersion":1,"facts":null}""",
            """{"schemaVersion":2,"facts":{}}""",
            """{"schemaVersion":"1","facts":{}}""",
            """{"schemaVersion":1,"facts":{},"extra":true}""",
            """{"schemaVersion":1,"schemaVersion":1,"facts":{}}""",
            """{"schemaVersion":1}""",
            """{"schemaVersion":1,"facts":[]}""",
            """{"schemaVersion":1,"facts":{"extra":1}}""",
            """{"schemaVersion":1,"facts":{"lastOnlineVisible":"false"}}""",
            """{"schemaVersion":1,"facts":{"lastOnlineVisible":true,"lastOnlineVisible":false}}""",
            """{"schemaVersion":1,"facts":{"language":7}}""",
            """{"schemaVersion":1,"facts":{"completedTrades":-1}}""",
            """{"schemaVersion":1,"facts":{"lastOnlineDay":"2026-02-31"}}""",
            "<html>Not Found</html>", "null", "[]", "{"
        })
        {
            await Case("null or invalid response " + _passed, async () =>
            {
                using var fixture = new Fixture();
                fixture.Transport.Body = body;
                Check((await fixture.Read()).GetProperty("facts").ValueKind == JsonValueKind.Null, "optional facts are explicitly null");
            });
        }
        await Case("hidden last online is cleared", async () =>
        {
            using var fixture = new Fixture();
            fixture.Transport.Body = """{"schemaVersion":1,"facts":{"lastOnlineVisible":false,"lastOnlineDay":"2026-11-08","language":"zh"}}""";
            var facts = (await fixture.Read()).GetProperty("facts");
            Check(!facts.TryGetProperty("lastOnlineDay", out var day) || day.ValueKind == JsonValueKind.Null, "hidden day removed");
            Check(facts.GetProperty("language").GetString() == "zh", "other facts preserved");
        });
        await Case("last online without the server's yes is cleared", async () =>
        {
            using var fixture = new Fixture();
            fixture.Transport.Body = """{"schemaVersion":1,"facts":{"lastOnlineDay":"2026-11-08","language":"zh"}}""";
            var facts = (await fixture.Read()).GetProperty("facts");
            Check(!facts.TryGetProperty("lastOnlineDay", out var day) || day.ValueKind == JsonValueKind.Null,
                "a missing lastOnlineVisible hides the day (user 2026-11-05)");
            Check(facts.GetProperty("language").GetString() == "zh", "other facts preserved");
        });
        foreach (var status in new[] { 404, 405, 501, 503 })
        {
            await Case("HTTP " + status + " degrades", async () =>
            {
                using var fixture = new Fixture();
                fixture.Transport.Status = (HttpStatusCode)status;
                fixture.Transport.Body = "<html>Error</html>";
                Check((await fixture.Read()).GetProperty("facts").ValueKind == JsonValueKind.Null, "optional endpoint status");
            });
        }
        foreach (var error in new Exception[] { new HttpRequestException("synthetic network failure"), new TimeoutException(), new TaskCanceledException() })
        {
            await Case("transport " + error.GetType().Name + " degrades", async () =>
            {
                using var fixture = new Fixture();
                fixture.Transport.Failure = error;
                Check((await fixture.Read()).GetProperty("facts").ValueKind == JsonValueKind.Null, "network or timeout");
            });
        }
        await Case("unknown timezone stays unknown", async () =>
        {
            using var fixture = new Fixture();
            fixture.Transport.Body = """{"schemaVersion":1,"facts":{"timezoneId":78,"reputation":0}}""";
            var facts = (await fixture.Read()).GetProperty("facts");
            Check(!facts.TryGetProperty("utcOffsetMinutes", out var offset) || offset.ValueKind == JsonValueKind.Null, "unknown zone");
            Check(facts.GetProperty("reputation").GetInt32() == 0, "known zero preserved");
        });
        await Case("directory failure keeps other facts", async () =>
        {
            using var fixture = new Fixture();
            fixture.Transport.ZoneFailure = true;
            var facts = (await fixture.Read()).GetProperty("facts");
            Check(facts.GetProperty("reputation").GetInt32() == 128, "directory is optional");
            Check(!facts.TryGetProperty("utcOffsetMinutes", out var offset) || offset.ValueKind == JsonValueKind.Null, "failed zone stays unknown");
        });
        await Case("target parameters rejected before transport", async () =>
        {
            using var fixture = new Fixture();
            try
            {
                await fixture.Host.ReadAccountFactsAsync(fixture.Context,
                    BridgePayload.From(new { schemaVersion = 1, businessSubjectId = "other" }), default);
                throw new Exception("FAIL target accepted");
            }
            catch (AccountBridgeHostException error) when (error.Code == "profile.account_facts_invalid") { }
            Check(fixture.Transport.Paths.Count == 0, "no caller-selected target");
        });
        foreach (var failure in new[] { false, true })
        {
            await Case("account switch rejects late " + (failure ? "failure" : "success"), async () =>
            {
                using var fixture = new Fixture();
                fixture.Transport.BeforeFacts = () => typeof(ScmAccountBridgeHost)
                    .GetField("_generation", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .SetValue(fixture.Host, fixture.Host.Generation + 1);
                if (failure) fixture.Transport.Failure = new HttpRequestException("synthetic failure");
                try { await fixture.Read(); throw new Exception("FAIL stale accepted"); }
                catch (BridgeStaleGenerationException) { }
            });
        }
        await Case("public header whitelist unchanged", () =>
        {
            var facts = BridgePayload.From(new { lastOnlineVisible = false, lastOnlineDay = "2026-11-08" });
            try { PersonalProfilePublicFacts.Parse(facts); throw new Exception("FAIL visitor flag accepted"); }
            catch (JsonException) { }
            var header = BridgePayload.From(new {
                schemaVersion = 2, restricted = true, visibility = "private",
                publicHeader = new { callsign = "Synthetic", defaulted = true, nameMasked = false, facts }
            });
            try { PersonalProfilePublicHeader.Parse(header, null); throw new Exception("FAIL public header flag accepted"); }
            catch (JsonException) { }
            return Task.CompletedTask;
        });
        await Case("legacy-only session does not request SCM facts", async () =>
        {
            using var fixture = new Fixture();
            typeof(ScmAccountBridgeHost).GetField("_session", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(fixture.Host, null);
            typeof(ScmAccountBridgeHost).GetField("_legacySession", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(fixture.Host,
                new LegacyMigrationCredential("synthetic-legacy", "Synthetic", "synthetic-legacy-access", DateTimeOffset.UtcNow));
            Check((await fixture.Read()).GetProperty("facts").ValueKind == JsonValueKind.Null, "legacy facts unknown");
            Check(fixture.Transport.Paths.Count == 0, "legacy account never calls SCM facts");
        });
        await Case("401 keeps existing reauthorization flow", async () =>
        {
            using var fixture = new Fixture();
            fixture.Transport.Status = HttpStatusCode.Unauthorized;
            try { await fixture.Read(); throw new Exception("FAIL unauthorized response accepted"); }
            catch (AccountBridgeHostException error) when (error.Code == AccountBridgeStableErrors.ReauthorizationRequired) { }
        });
        await Case("dispatcher routes owner request", async () =>
        {
            using var fixture = new Fixture();
            using var dispatcher = new AccountBridgeDispatcher(fixture.Host);
            var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.readAccountFacts",
                Guid.NewGuid().ToString("N"), fixture.Host.Generation, new { schemaVersion = 1 }, fixture.Context), default);
            Check(result.Response.Payload.GetProperty("facts").GetProperty("reputation").GetInt32() == 128, "bridge response");
        });
        Console.WriteLine($"Owner facts: {_passed} passed, 0 failed");
        await VisitorAccountFactsTests.Run();
    }

    private static async Task Case(string name, Func<Task> run)
    {
        await run();
        _passed++;
        Console.WriteLine("PASS owner facts: " + name);
    }

    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("Read-only test");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class Transport : HttpMessageHandler
    {
        internal List<string> Paths { get; } = [];
        internal string Body = """{"schemaVersion":1,"facts":{"reputation":128,"completedTrades":31,"sellOrders":5,"buyOrders":3,"lastOnlineDay":"2026-11-08","lastOnlineVisible":true,"language":"zh","timezoneId":77,"banned":false,"banCount":0}}""";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal Exception? Failure;
        internal bool ZoneFailure;
        internal Action? BeforeFacts;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = Uri.UnescapeDataString(request.RequestUri!.AbsolutePath);
            Paths.Add(path);
            if (path.EndsWith("/business-identity", StringComparison.Ordinal))
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, issuer = "synthetic", subject = Subject, businessSubjectId = BusinessId, scopes = new[] { "profile.read" }
                }) });
            if (path.EndsWith("/timezone/list", StringComparison.Ordinal))
            {
                if (ZoneFailure) throw new HttpRequestException("synthetic directory failure");
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    code = 0, data = new[] { new { id = 77, value = "Asia/Shanghai", label = "Synthetic zone", offset = "+08:00", offsetMinutes = -360 } }
                }) });
            }
            Check(path == "/app-api/starbridge/v1/personal-profile/account-facts/" + BusinessId, "unexpected test route");
            Check(request.Method == HttpMethod.Get, "GET only");
            BeforeFacts?.Invoke();
            if (Failure is not null) throw Failure;
            return Task.FromResult(new HttpResponseMessage(Status) { Content = new StringContent(Body, Encoding.UTF8, "application/json") });
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal Transport Transport { get; } = new();
        internal ScmAccountBridgeHost Host { get; }
        internal BridgeAccountContext Context => Host.CurrentContext!;
        private readonly string _root = Path.Combine(Path.GetTempPath(), "StarBridge-OwnerFacts-" + Guid.NewGuid().ToString("N"));
        internal Fixture()
        {
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(Transport), new Vault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read", "/callback"));
            Host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(_root), "synthetic", () => null,
                initialSession: new ScmOAuthSession("synthetic", Subject, "Synthetic", "synthetic-access",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), initialGeneration: 7);
        }
        internal async Task<JsonElement> Read() => BridgePayload.From(
            await Host.ReadAccountFactsAsync(Context, BridgePayload.From(new { schemaVersion = 1 }), default));
        public void Dispose()
        {
            Host.Dispose();
            var full = Path.GetFullPath(_root);
            if (!full.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Unexpected test root");
            if (Directory.Exists(full)) Directory.Delete(full, true);
        }
    }
}
