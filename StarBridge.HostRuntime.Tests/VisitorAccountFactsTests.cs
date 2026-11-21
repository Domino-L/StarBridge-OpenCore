using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

// Every request is intercepted in memory; no sockets or user data are used.
internal static class VisitorAccountFactsTests
{
    private static readonly string Target = "scm-v1:" + new string('a', 64);
    private const string Base = "/app-api/starbridge/v1/personal-profile";
    private static int passed;
    private static void Check(bool value, string reason)
    { if (!value) throw new Exception("FAIL visitor facts: " + reason); }
    private static async Task Case(string name, Func<Task> run)
    { await run(); passed++; Console.WriteLine("PASS visitor facts: " + name); }

    internal static async Task Run()
    {
        passed = 0;
        foreach (var route in new[] { "users.profile", "communities.memberPersonalProfile" })
            await Case("full authorized page via " + route, async () =>
            {
                using var f = new Fixture();
                var result = await f.Read(route);
                Check(result.Error is null && !result.Payload.GetProperty("editable").GetBoolean(), "full page survives");
                var facts = result.Payload.GetProperty("accountFacts");
                Check(facts.GetProperty("reputation").GetInt32() == 128 &&
                    facts.GetProperty("utcOffsetMinutes").GetInt32() == 480, "facts and resolved offset");
                Check(facts.GetProperty("lastOnlineDay").GetString() == "2026-11-08", "explicit visible day");
                Check(!facts.TryGetProperty("timezoneId", out _) && !facts.TryGetProperty("lastOnlineVisible", out _), "Host-only fields stripped");
                Check(f.Http.Paths.IndexOf(Base + "/visitor/" + Target) <
                    f.Http.Paths.IndexOf(Base + "/account-facts/" + Target), "page authorization precedes facts");
            });
        foreach (var visibility in new[] { "private", "friendsOnly", "friendsAndMainFleet" })
            foreach (var defaulted in visibility == "private" ? new[] { false, true } : new[] { false })
                await Case("restricted skips facts " + visibility + " defaulted=" + defaulted, async () =>
                {
                    using var f = new Fixture();
                    f.Http.Restricted = true; f.Http.Visibility = visibility; f.Http.Defaulted = defaulted;
                    var result = await f.Read();
                    Check(result.Error is null && result.Payload.GetProperty("restricted").GetBoolean(), "header preserved");
                    Check(!result.Payload.TryGetProperty("accountFacts", out _), "no extra facts");
                    Check(!f.Http.Paths.Any(p => p.Contains("account-facts")), "no facts request");
                });
        // 11-08 (option c): a never-saved page's last online only from account-facts' explicit yes.
        foreach (var (name, factsBody, factsStatus, expected) in new (string, string, HttpStatusCode, string?)[] {
            ("visible", "{\"schemaVersion\":1,\"facts\":{\"lastOnlineDay\":\"2026-11-07\",\"lastOnlineVisible\":true}}", HttpStatusCode.OK, "2026-11-07"),
            ("hidden", "{\"schemaVersion\":1,\"facts\":{\"lastOnlineDay\":\"2026-11-07\",\"lastOnlineVisible\":false}}", HttpStatusCode.OK, null),
            ("unknown", "{\"schemaVersion\":1,\"facts\":{\"lastOnlineDay\":\"2026-11-07\"}}", HttpStatusCode.OK, null),
            ("unavailable", "{}", HttpStatusCode.NotFound, null),
        })
            await Case("never-saved header last online " + name, async () =>
            {
                using var f = new Fixture();
                f.Http.Restricted = true; f.Http.Visibility = "private"; f.Http.Defaulted = true;
                f.Http.HeaderLastOnline = "2026-11-08"; f.Http.FactsBody = factsBody; f.Http.FactsStatus = factsStatus;
                var result = await f.Read();
                Check(result.Error is null && result.Payload.GetProperty("restricted").GetBoolean(), "header preserved");
                var facts = result.Payload.GetProperty("publicHeader").GetProperty("facts");
                Check(facts.GetProperty("language").GetString() == "zh", "other header facts kept");
                var day = facts.TryGetProperty("lastOnlineDay", out var value) && value.ValueKind == JsonValueKind.String
                    ? value.GetString() : null;
                Check(day == expected, "last online " + (day ?? "none"));
                Check(!result.Payload.TryGetProperty("accountFacts", out _), "no visitor account band");
            });
        await Case("a saved private header never requests facts for last online", async () =>
        {
            using var f = new Fixture();
            f.Http.Restricted = true; f.Http.Visibility = "private"; f.Http.Defaulted = false;
            f.Http.HeaderLastOnline = "2026-11-08";
            var result = await f.Read();
            Check(!f.Http.Paths.Any(p => p.Contains("account-facts")), "no facts request");
        });
        foreach (var status in new[] { 403, 404, 503 })
            await Case("failed page skips facts " + status, async () =>
            {
                using var f = new Fixture(); f.Http.PageStatus = (HttpStatusCode)status;
                Check((await f.Read()).Error is not null, "page error preserved");
                Check(!f.Http.Paths.Any(p => p.Contains("account-facts")), "no facts request");
            });
        foreach (var status in new[] { 401, 403, 404, 429, 503 })
            await Case("optional HTTP " + status, async () =>
            {
                using var f = new Fixture(); f.Http.FactsStatus = (HttpStatusCode)status;
                var result = await f.Read();
                Check(result.Error is null && !result.Payload.TryGetProperty("accountFacts", out _), "no change to page error or body");
                Check(f.Http.Paths.Count(p => p.Contains("account-facts")) == 1, "no replay");
            });
        await Case("hanging optional facts leave the page its time", async () =>
        {
            // CX-OWNER-FACTS-073-R: the client's visitor request times out at 15 s.
            using var f = new Fixture(); f.Http.HangFacts = true;
            var started = System.Diagnostics.Stopwatch.StartNew();
            var result = await f.Read();
            Check(result.Error is null && !result.Payload.TryGetProperty("accountFacts", out _), "page returned without facts");
            Check(started.Elapsed < TimeSpan.FromSeconds(8), "facts read bounded: " + started.Elapsed);
        });
        foreach (var body in new[] { "{", "null", "{\"schemaVersion\":2,\"facts\":{}}", "{\"schemaVersion\":1,\"facts\":{\"language\":7}}" })
            await Case("malformed optional facts " + passed, async () =>
            {
                using var f = new Fixture(); f.Http.FactsBody = body;
                var result = await f.Read();
                Check(result.Error is null && !result.Payload.TryGetProperty("accountFacts", out _), "bad decoration ignored");
            });
        foreach (var flag in new[] { "", ",\"lastOnlineVisible\":false" })
            await Case("last online requires explicit yes " + passed, async () =>
            {
                using var f = new Fixture();
                f.Http.FactsBody = "{\"schemaVersion\":1,\"facts\":{\"language\":\"zh\",\"lastOnlineDay\":\"2026-11-08\"" + flag + "}}";
                var facts = (await f.Read()).Payload.GetProperty("accountFacts");
                Check(!facts.TryGetProperty("lastOnlineDay", out var value) || value.ValueKind == JsonValueKind.Null, "hidden day");
                Check(facts.GetProperty("language").GetString() == "zh", "other facts preserved");
            });
        await Case("historical member never supplements", async () =>
        {
            using var f = new Fixture(); f.Http.Historical = true;
            var result = await f.Read();
            Check(result.Error is null && f.Http.Paths.Contains(Base + "/visitor-legacy"), "historical page succeeds");
            Check(!f.Http.Paths.Any(p => p.Contains("account-facts")), "no historical facts request");
        });
        foreach (var limited in new[] { false, true })
            await Case("market scm-member route limited=" + limited, async () =>
            {
                using var f = new Fixture();
                if (limited) f.Http.FactsStatus = HttpStatusCode.TooManyRequests;
                var result = await f.ReadMarket();
                Check(result.Error is null, "market page succeeds");
                Check(f.Http.Paths.Contains(Base + "/scm-member/42/account-facts"), "exact market route");
                Check(result.Payload.TryGetProperty("accountFacts", out _) == !limited, "market optional facts");
            });
        foreach (var change in new[] { "generation", "account", "target", "target expiry", "failed facts generation" })
            await Case("final checks after facts: " + change, async () =>
            {
                using var f = new Fixture();
                f.Http.BeforeFacts = () =>
                {
                    if (change == "target expiry") f.Now = DateTimeOffset.UtcNow.AddHours(2);
                    else if (change == "target")
                    {
                        var entries = (System.Collections.IDictionary)typeof(ScmAccountBridgeHost)
                            .GetField("_marketTraderTargets", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(f.Host)!;
                        var entry = entries.Values.Cast<object>().Single();
                        entry.GetType().GetProperty("Id")!.SetValue(entry, 43L);
                    }
                    else if (change == "account")
                    {
                        var field = typeof(ScmAccountBridgeHost).GetField("_session", BindingFlags.Instance | BindingFlags.NonPublic)!;
                        var session = (ScmOAuthSession)field.GetValue(f.Host)!;
                        field.SetValue(f.Host, session with { Subject = "changed-synthetic-viewer", CredentialVersion = Guid.NewGuid() });
                    }
                    else typeof(ScmAccountBridgeHost).GetField("_generation", BindingFlags.Instance | BindingFlags.NonPublic)!
                        .SetValue(f.Host, f.Host.Generation + 1);
                };
                if (change == "failed facts generation") f.Http.FactsStatus = HttpStatusCode.ServiceUnavailable;
                var result = change.StartsWith("target", StringComparison.Ordinal) ? await f.ReadMarket() : await f.Read();
                Check(result.Error is not null && !result.Payload.TryGetProperty("accountFacts", out _), "stale page rejected");
                if (change == "target") Check(result.Error?.Code == "profile.visitor_unavailable", "original target mismatch error");
                if (change == "target expiry") Check(result.Error?.Code == "users.targetChanged", "original expired reference error");
            });
        // HK swap 5 (user 11-11): a full page's trade window and achievement count, both optional.
        await Case("full page forwards trade window and achievement count", async () =>
        {
            using var f = new Fixture();
            f.Http.PageTradeWindow = JsonDocument.Parse("""{"days":[1,1,1,1,1,0,0],"start":"19:30","end":"23:00","timezoneId":77}""").RootElement;
            f.Http.PageAchievements = 42;
            var page = (await f.Read()).Payload.GetProperty("profile");
            var window = page.GetProperty("tradeWindow");
            Check(window.GetProperty("start").GetString() == "19:30" && window.GetProperty("days").GetArrayLength() == 7, "window forwarded");
            Check(window.GetProperty("ownerOffsetMinutes").GetInt32() == 480, "owner offset resolved");
            Check(!window.TryGetProperty("timezoneId", out _), "SCM zone id stays in the Host");
            Check(page.GetProperty("achievementCount").GetInt32() == 42, "achievement count forwarded");
        });
        foreach (var bad in new[] { """{"days":[1,1,1],"start":"19:30","end":"23:00","timezoneId":77}""",
            """{"days":[1,1,1,1,1,0,0],"start":"25:00","end":"23:00","timezoneId":77}""", "\"text\"",
            """{"days":[1,1,1,1,1,0,0],"start":"19:30","end":"23:00","timezoneId":77,"memberId":9}""" })
            await Case("malformed trade window leaves only the window out " + passed, async () =>
            {
                using var f = new Fixture();
                f.Http.PageTradeWindow = JsonDocument.Parse(bad).RootElement;
                var result = await f.Read();
                Check(result.Error is null, "page survives");
                Check(!result.Payload.GetProperty("profile").TryGetProperty("tradeWindow", out _), "window dropped");
            });
        await Case("slow zone directory leaves only the window's offset out", async () =>
        {
            using var f = new Fixture(); f.Http.HangZones = true;
            f.Http.PageTradeWindow = JsonDocument.Parse("""{"days":[1,1,1,1,1,0,0],"start":"19:30","end":"23:00","timezoneId":77}""").RootElement;
            var started = System.Diagnostics.Stopwatch.StartNew();
            var result = await f.Read();
            Check(result.Error is null, "page survives");
            var window = result.Payload.GetProperty("profile").GetProperty("tradeWindow");
            Check(window.GetProperty("start").GetString() == "19:30", "window kept");
            Check(!window.TryGetProperty("ownerOffsetMinutes", out var offset) || offset.ValueKind == JsonValueKind.Null, "no offset");
            Check(started.Elapsed < TimeSpan.FromSeconds(10), "zone wait bounded: " + started.Elapsed);
        });
        await Case("older server sends neither", async () =>
        {
            using var f = new Fixture();
            var page = (await f.Read()).Payload.GetProperty("profile");
            Check(!page.TryGetProperty("tradeWindow", out _) && !page.TryGetProperty("achievementCount", out _), "nothing invented");
        });
        await Case("negative achievement count is dropped", async () =>
        {
            using var f = new Fixture(); f.Http.PageAchievements = -1;
            Check(!(await f.Read()).Payload.GetProperty("profile").TryGetProperty("achievementCount", out _), "invalid count dropped");
        });
        Console.WriteLine($"Visitor facts: {passed} passed, 0 failed");
    }

    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No vault IO");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
    private sealed class Fixture : IDisposable
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        internal readonly Transport Http = new();
        internal readonly ScmAccountBridgeHost Host;
        private readonly CommunityClient community;
        private readonly AccountBridgeDispatcher dispatcher;
        internal Fixture()
        {
            var uri = new Uri("https://fixture.invalid/");
            community = new CommunityClient(uri, Http);
            var oauth = new OAuthPkceClient(new ScmHttpClient(Http), new Vault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read trade.read", "/callback"));
            Host = new(oauth, new ScmProfileCacheStore(), "synthetic", () => null,
                initialSession: new("synthetic", "synthetic-viewer", "Synthetic", "synthetic-test",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "trade.read"]), communities: community) { MarketTraderClock = () => Now };
            dispatcher = new(Host);
        }
        internal async Task<BridgeEnvelope> Read(string route = "users.profile")
        {
            var context = Host.CurrentContext!;
            var directory = (CommunityPage)await Host.ReadCommunitiesAsync(context,
                BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
            var target = directory.Items.Single().TargetRef;
            var roster = BridgePayload.From(await Host.ReadCommunityWorkspaceAsync(context,
                BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
            var member = roster.GetProperty("members")[0].GetProperty("memberRef").GetString();
            object payload = route == "users.profile"
                ? new { schemaVersion = 1, source = "community", reference = member, contextRef = target }
                : new { schemaVersion = 1, targetRef = target, memberRef = member };
            return (await dispatcher.DispatchAsync(BridgeEnvelope.Request(route, Guid.NewGuid().ToString("N"),
                Host.Generation, payload, context), default)).Response;
        }
        internal async Task<BridgeEnvelope> ReadMarket()
        {
            var context = Host.CurrentContext!;
            var project = await Host.PrepareMarketTraderReferencesAsync(context, Host.Generation, default);
            var reference = project!(BridgePayload.From(new { creatorId = 42, orderOwnerId = 7, nickname = "Fixture", displayType = 2 }));
            Check(reference is not null, "market reference");
            return (await dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
                Host.Generation, new { schemaVersion = 1, source = "market", reference }, context), default)).Response;
        }
        public void Dispose() { dispatcher.Dispose(); Host.Dispose(); community.Dispose(); }
    }
    private sealed class Transport : HttpMessageHandler
    {
        private static async Task<HttpResponseMessage> Hang(CancellationToken token)
        {
            await Task.Delay(Timeout.Infinite, token);
            throw new OperationCanceledException(token);
        }

        internal readonly List<string> Paths = [];
        internal bool Restricted, Defaulted, Historical;
        internal string Visibility = "friendsOnly";
        internal HttpStatusCode PageStatus = HttpStatusCode.OK, FactsStatus = HttpStatusCode.OK;
        internal Action? BeforeFacts;
        internal bool HangFacts, HangZones;
        internal string? HeaderLastOnline;
        internal JsonElement? PageTradeWindow;
        internal int? PageAchievements;
        internal string FactsBody = """{"schemaVersion":1,"facts":{"reputation":128,"completedTrades":31,"sellOrders":5,"buyOrders":3,"language":"zh","lastOnlineDay":"2026-11-08","lastOnlineVisible":true,"timezoneId":77}}""";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = Uri.UnescapeDataString(request.RequestUri!.AbsolutePath); Paths.Add(path);
            HttpResponseMessage Json(object value, HttpStatusCode status = HttpStatusCode.OK) => new(status) { Content = JsonContent.Create(value) };
            if (path.Contains("account-facts"))
            {
                Check(request.Method == HttpMethod.Get && path is var p &&
                    (p == Base + "/account-facts/" + Target || p == Base + "/scm-member/42/account-facts"), "exact facts GET");
                BeforeFacts?.Invoke();
                if (HangFacts) return Hang(token);
                return Task.FromResult(new HttpResponseMessage(FactsStatus) { Content = new StringContent(FactsBody) });
            }
            if (path == "/app-api/member/timezone/list" && HangZones) return Hang(token);
            if (path == "/app-api/member/timezone/list") return Task.FromResult(Json(new { code = 0,
                data = new[] { new { id = 77, value = "Asia/Shanghai", label = "Synthetic", offset = "+08:00", offsetMinutes = -360 } } }));
            if (path == "/app-api/member/user/get") return Task.FromResult(Json(new { code = 0, data = new { id = 7 } }));
            if (path == "/api/fleets/directory") return Task.FromResult(Json(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Fixture", description = "", language = "", activeTime = "",
                    memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
            }));
            if (path == "/api/fleets/workspace")
            {
                var workspace = CommunityWorkspaceClientTests.Workspace();
                workspace["members"]![0]!["memberId"] = Historical ? "account:historical-member" : "account:" + Target;
                return Task.FromResult(Json(workspace));
            }
            var profile = new PersonalProfileDocumentContract(3, "synthetic-public-page", false, 7,
                DateTimeOffset.UtcNow, new("Visitor", ""), PersonalProfileContentContract.Empty, null, Visibility: Visibility,
                TradeWindow: PageTradeWindow, AchievementCount: PageAchievements);
            if (path == Base + "/visitor-legacy") return Task.FromResult(Json(new {
                schemaVersion = 1, legacyAccountId = "historical-member", profile }));
            Check(path == Base + "/visitor/" + Target || path == Base + "/visitor/scm-member", "exact visitor route");
            object body = Restricted ? new { schemaVersion = 2, restricted = true, visibility = Visibility,
                publicHeader = HeaderLastOnline is null
                    ? (object)new { callsign = "Visitor", defaulted = Defaulted, nameMasked = false }
                    : new { callsign = "Visitor", defaulted = Defaulted, nameMasked = false,
                        facts = new { language = "zh", lastOnlineDay = HeaderLastOnline } } } : profile;
            var response = Json(body, PageStatus);
            response.Headers.Add("X-StarBridge-Profile-Subject", Target);
            return Task.FromResult(response);
        }
    }
}
