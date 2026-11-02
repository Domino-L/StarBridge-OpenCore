using System.Net;
using StarBridge.Core.Identity;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using System.Reflection;

internal static class MarketplaceTests
{
    private static void VerifyDefaultMarketAuthorization()
    {
        var endpoint = new Uri("https://fixture.invalid/");
        var settings = new ScmEnvironmentSettings("fixture", true, false, null,
            endpoint, endpoint, endpoint, endpoint, new HashSet<string>(),
            TimeSpan.FromSeconds(1), TimeSpan.FromMinutes(1));
        var options = ScmOAuthOptions.Create(settings);
        var oauth = new OAuthPkceClient(new ScmHttpClient(new Handler()), new EmptyVault(), options);
        var query = oauth.BuildAuthorizeUri(new Uri("http://127.0.0.1:12345/oauth/callback"),
            OAuthPkceParameters.Create(), options.Scope).Query.TrimStart('?').Split('&')
            .Select(pair => pair.Split('=', 2)).ToDictionary(pair => pair[0], pair => Uri.UnescapeDataString(pair[1]));
        var scopes = query["scope"].Split(' ').ToHashSet(StringComparer.Ordinal);
        Check(query["resource"] == "starbridge-api", "dedicated market authorization resource");
        Check(query["client_id"] == "starbridge-desktop", "registered desktop client");
        foreach (var scope in new[] { "trade.read", "trade.write", "checklist.read", "checklist.write", "blocklist.read", "blocklist.write" })
            Check(scopes.Contains(scope), "authorization URL requests " + scope);
        Check(scopes.Contains("profile.read") && scopes.Contains("profile.write") && !scopes.Contains("identity.link") &&
            !scopes.Any(scope => scope.StartsWith("trade_profile.", StringComparison.Ordinal)),
            "trade profile reuses existing profile and trade scopes; no obsolete scope or identity expansion");
        Console.WriteLine("PASS marketplace default authorization URL: six scopes and dedicated resource");
    }

    private sealed class BestPriceHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var q = request.RequestUri!.Query;
            Check(q.Contains("pageSize=1") && q.Contains("sortType=price") && q.Contains("displayType=1"), "one sorted row per item");
            Check(q.Contains("creatorType=1") ? q.Contains("sortOrder=asc") : q.Contains("sortOrder=desc"), "sell ascending, buy descending");
            var data = q.Contains("productId=7") ? "{\"total\":3,\"list\":[{\"unitPrice\":100}]}" : "{\"total\":0,\"list\":[]}";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    private sealed class TreeCountingHandler : HttpMessageHandler
    {
        internal int Trees;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            string data;
            if (uri.AbsolutePath.EndsWith("category-list")) { Interlocked.Increment(ref Trees); data = "[{\"id\":3,\"parentId\":0,\"name\":\"武器\"}]"; }
            else if (uri.AbsolutePath.EndsWith("search-list")) data = "{\"total\":422,\"list\":[]}";
            else data = "{\"total\":12,\"list\":[]}";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    private sealed class TrendingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("product/items/get"))
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                    { Content = new StringContent("{\"code\":0,\"data\":{\"qualityInfo\":null}}") });
            Check(request.RequestUri!.AbsolutePath.EndsWith("sc/orders/trending-items"), "trending route");
            const string data = "[{\"id\":43475,\"itemName\":\"科力晶\",\"price\":995573.76,\"changePercent\":-26.5,\"sellPrice\":1533333.5,\"buyPrice\":null,\"orderCount\":191,\"creatorId\":9}]";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    private sealed class CategoryCountHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            string data;
            if (uri.AbsolutePath.EndsWith("category-list")) data = "[{\"id\":3,\"parentId\":0},{\"id\":31,\"parentId\":3},{\"id\":4}]";
            else
            {
                Check(uri.AbsolutePath.EndsWith("sc/orders/page") && uri.Query.Contains("pageSize=1") && !uri.Query.Contains("categoryId=31"),
                    "one 1-row public order page per root category only");
                data = uri.Query.Contains("categoryId=3") ? "{\"total\":17,\"list\":[]}" : "{\"total\":0,\"list\":[]}";
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    private sealed class BrowseHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            string data;
            if (uri.AbsolutePath.EndsWith("category-list"))
                data = "[{\"id\":31,\"parentId\":3},{\"id\":3,\"parentId\":0,\"filterConfig\":\"{\\\"filters\\\":[{\\\"type\\\":\\\"enum\\\",\\\"jsonPath\\\":\\\"$.kind\\\",\\\"options\\\":[{\\\"value\\\":\\\"rifle\\\"}]}],\\\"sorts\\\":[{\\\"jsonPath\\\":\\\"$.speed\\\"}]}\"}]";
            else
            {
                Check(uri.AbsolutePath.EndsWith("search-list"), "no per-item or offers query in catalog");
                var query = Uri.UnescapeDataString(uri.Query);
                Check(query.Contains("enumFilters[$.kind]=rifle") && query.Contains("sortKey=$.speed"), "inherited category configuration encoded");
                Check(uri.Query.Contains("keyword=a%26b"), "keyword cannot inject query parameters");
                data = query.Contains("maxOrderCount=0") ? "{\"total\":420,\"list\":[]}" : "{\"total\":2,\"list\":[{\"id\":1,\"sellOrderCount\":1,\"buyOrderCount\":0}]}";
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    internal static async Task Run()
    {
        await MarketplaceImagelessCategoryTests.Run();
        await MarketplaceQualityTierTests.Run();
        await MarketplaceSupplementBudgetTests.Run();
        VerifyDefaultMarketAuthorization();
        await MarketplaceTradeTests.Run();
        await VerifyDispatch();
        await VerifyReadDiagnostics();
        using (var browse = new ScmMarketplaceReader(new("https://catalog.invalid/"), new BrowseHandler()))
        {
            var query = BridgePayload.From(new Dictionary<string,string> { ["minOrderCount"] = "1", ["enum:$.kind"] = "rifle", ["sortKey"] = "$.speed" });
            var result = BridgePayload.From(await browse.ReadAsync("marketItems", 0, "a&b", 31, 1, 1, default, "CN", query)).GetProperty("data");
            Check(result.GetProperty("total").GetInt32() == 2 && result.GetProperty("allTotal").GetInt32() == 422, "listed count and absent count use catalog aggregate, no price fanout");
            var bad = BridgePayload.From(new Dictionary<string,string> { ["enum:$.unconfigured"] = "rifle" });
            await Throws<ArgumentException>(() => browse.ReadAsync("marketItems", 0, "", 31, 1, 1, default, "CN", bad));
            foreach (var field in new[] { "creatorId", "ignoreStatus", "includeDeleted", "token" })
                await Throws<ArgumentException>(() => Task.FromResult(ScmMarketplaceReader.BrowseOptions(BridgePayload.From(new Dictionary<string,string> { [field] = "1" }))));
        }
        using (var counts = new ScmMarketplaceReader(new("https://catalog.invalid/"), new CategoryCountHandler()))
        {
            var rows = BridgePayload.From(await counts.ReadAsync("categoryListings", 0, "", 0, 1, 1, default)).GetProperty("data").GetProperty("rows");
            var byId = rows.EnumerateArray().ToDictionary(r => r.GetProperty("id").GetInt64(), r => r.GetProperty("count"));
            Check(byId.Count == 2 && byId[3].GetInt64() == 17 && byId[4].GetInt64() == 0, "on-sale count per root category, children excluded from the fan-out");
        }
        var treeHandler = new TreeCountingHandler();
        var now = DateTimeOffset.UtcNow;
        using (var shared = new ScmMarketplaceReader(new("https://catalog.invalid/"), treeHandler) { Clock = () => now })
        {
            var hall = BridgePayload.From(await shared.ReadAsync("categories", 0, "", 0, 1, 1, default)).GetProperty("data");
            Check(hall.GetProperty("total").GetInt64() == 422 && hall.GetProperty("rows").GetArrayLength() == 1, "tree and catalogue total both arrive");
            await Task.WhenAll(shared.ReadAsync("categoryListings", 0, "", 0, 1, 1, default), shared.ReadAsync("categoryListings", 0, "", 0, 1, 1, default));
            Check(treeHandler.Trees == 1, "one category tree read serves the hall, its counts and concurrent callers");
            now = now.AddMinutes(11);
            await shared.ReadAsync("categoryListings", 0, "", 0, 1, 1, default);
            Check(treeHandler.Trees == 2, "the shared tree is read again after ten minutes");
        }
        using (var trending = new ScmMarketplaceReader(new("https://catalog.invalid/"), new TrendingHandler()))
        {
            var row = BridgePayload.From(await trending.ReadAsync("trending", 0, "", 0, 1, 1, default)).GetProperty("data").GetProperty("rows")[0];
            Check(row.GetProperty("sellPrice").ToString() == "1533333.5" && row.GetProperty("orderCount").ToString() == "191" &&
                !row.TryGetProperty("creatorId", out _), "trending preserves daily weighted averages and historical record count without identity");
        }
        using (var bests = new ScmMarketplaceReader(new("https://catalog.invalid/"), new BestPriceHandler()))
        {
            var rows = BridgePayload.From(await bests.ReadAsync("bestPrices", 0, "7:1,8:0", 0, 1, 1, default)).GetProperty("data").GetProperty("rows");
            var list = rows.EnumerateArray().ToList();
            Check(list.Count == 2 && list.Any(r => r.GetProperty("id").GetInt64() == 7 && r.GetProperty("price").GetString() == "100") &&
                list.Any(r => r.GetProperty("id").GetInt64() == 8 && (!r.TryGetProperty("price", out var none) || none.ValueKind == JsonValueKind.Null)),
                "best ask / bid per item, empty side known as none");
            foreach (var bad in new[] { "", "7", "7:2", "a:1", "1:1,2:1,3:1,4:1,5:1,6:1,7:1,8:1,9:1,10:1,11:1" })
                await Throws<ArgumentException>(() => bests.ReadAsync("bestPrices", 0, bad, 0, 1, 1, default));
        }
        var options = new ScmOAuthOptions("synthetic", new("https://web.invalid/"), new("https://auth.invalid/"),
            new("https://resource.invalid/"), "desktop", "starbridge-api", "openid profile.read", "/callback");
        var session = new ScmOAuthSession("synthetic", "owner", "Fixture", "synthetic-token",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        foreach (var body in new[] { "{\"subject\":\"owner\",\"reputation\":412,\"point\":999}",
            "{\"subject\":\"owner\",\"reputation\":0}", "{\"subject\":\"owner\"}" })
        {
            var oauth = new OAuthPkceClient(new ScmHttpClient(new ReputationHandler(body)), new EmptyVault(), options);
            var result = await oauth.ReadMarketplaceReputationAsync(session, default);
            Check(result.Point == (body.Contains("412") ? 412L : body.Contains(":0") ? 0L : null), "reputation source and unknown preserved");
        }
        var wrongOwner = new OAuthPkceClient(new ScmHttpClient(new ReputationHandler("{\"subject\":\"other\",\"reputation\":412}")), new EmptyVault(), options);
        await Throws<ScmApiProtocolException>(() => wrongOwner.ReadMarketplaceReputationAsync(session, default));
        var transport = new Handler();
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), transport);
        var hot = BridgePayload.From(await reader.ReadAsync("hotWords", 0, "", 0, 1, 1, default)).GetProperty("data").GetProperty("rows");
        Check(hot.GetArrayLength() == 1 && hot[0].GetProperty("itemName").GetString() == "科力晶" && !hot[0].TryGetProperty("secret", out _), "hot words use bounded public projection");
        using (var related = new ScmMarketplaceReader(new("https://catalog.invalid/"), new RelatedHandler()))
        {
            var linked = BridgePayload.From(await related.ReadAsync("attachments", 17, "", 0, 1, 1, default)).GetProperty("data");
            Check(linked.GetProperty("rows")[0].GetProperty("id").GetInt32() == 23, "attachments use exact port query");
            Check(linked.GetProperty("filters")[0].GetProperty("requiredTags").GetString() == "ballistic_attach", "compatibility filter retained");
            var missing = BridgePayload.From(await related.ReadAsync("blueprints", 17, "", 0, 1, 1, default)).GetProperty("data");
            Check(missing.GetProperty("missing").GetString() == "materialIdentity", "missing UUID cannot guess blueprint mapping");
        }
        var item = BridgePayload.From(await reader.ReadAsync("item", 17, "", 0, 1, 1, default)).GetProperty("data");
        Check(item.GetProperty("itemName").GetString() == "测试物品", "SCM original retained");
        Check(item.GetProperty("itemNameHant").GetString() == "測試物品", "display-only traditional conversion: " + item.GetProperty("itemNameHant").GetString());
        Check(item.GetProperty("sellOrderCount").ValueKind == JsonValueKind.Null, "missing is not zero");
        Check(item.GetProperty("buyOrderCount").GetInt32() == 0, "real zero preserved");
        Check(!item.TryGetProperty("secret", out _), "unselected properties excluded");
        var quotes = BridgePayload.From(await reader.ReadAsync("offers", 17, "", 0, 1, 1, default))
            .GetProperty("data").GetProperty("rows")[0];
        Check(quotes.GetProperty("seller").GetString() == "F*****e", "seller stays masked");
        Check(quotes.GetProperty("tradeTime").GetString() == "[1,0,1,0,1,0,0]", "weekday array projection");
        Check(quotes.GetProperty("presence").GetString() == "offline", "stealth projected offline");
        Check(!quotes.TryGetProperty("creatorId", out _) && !quotes.TryGetProperty("userMobile", out _), "no account/contact leakage");
        Check(quotes.GetProperty("unitPrice").GetString() == "1234567", "full numeric price");
        Check(quotes.GetProperty("timezoneId").GetInt32() == 16, "trade window owner time zone kept");
        Check(quotes.GetProperty("remark").GetString() == "周末在线", "public note kept as plain trimmed text");
        Check(quotes.GetProperty("hasOngoingTransactions").GetBoolean(), "ongoing trade flag kept");
        Check(quotes.GetProperty("items")[0].GetProperty("unitPrice").GetString() == "1200", "per-item price kept");
        foreach (var (zone, fallback, expected) in new[] { ("Asia/Shanghai", 999, new long[] { 480 }), ("America/New_York", 999, new long[] { -240, -300 }), ("Mars/Base", 60, new long[] { 60 }) })
        {
            var tz = BridgePayload.From(BridgePayload.From(ScmMarketplaceReader.TimeZone(BridgePayload.From(new { id = 1, value = zone, label = zone, offset = "", offsetMinutes = fallback }))));
            Check(expected.Contains(tz.GetProperty("currentOffsetMinutes").GetInt64()), $"current offset for {zone}");
        }
        var offerFilter = BridgePayload.From(new Dictionary<string, string> { ["creatorStatus"] = "2", ["minQuality"] = "600", ["locationId"] = "8", ["sortOrder"] = "desc" });
        var offerQuery = ScmMarketplaceReader.OfferQuery(17, 1, 2, "CN", offerFilter);
        Check(offerQuery.Contains("productId=17") && offerQuery.Contains("creatorType=1") && offerQuery.Contains("pageNo=2") &&
            offerQuery.Contains("creatorStatus=2") && offerQuery.Contains("minQuality=600") && offerQuery.Contains("locationId=8") &&
            offerQuery.Contains("sortType=price") && offerQuery.Contains("sortOrder=desc"), "offer filters forwarded with fixed scope: " + offerQuery);
        Check(ScmMarketplaceReader.OfferQuery(17, 0, 1, "CN", default).Contains("sortOrder=desc") &&
            ScmMarketplaceReader.OfferQuery(17, 1, 1, "CN", default).Contains("sortOrder=asc"), "default price direction follows side");
        foreach (var field in new[] { "creatorType", "displayType", "minPrice", "sortType", "keyword" })
            await Throws<ArgumentException>(() => Task.FromResult(ScmMarketplaceReader.OfferQuery(17, 1, 1, "CN", BridgePayload.From(new Dictionary<string, string> { [field] = "1" }))));
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Throws<OperationCanceledException>(() => reader.ReadAsync("item", 17, "", 0, 1, 1, cancelled.Token));
        transport.Malformed = true;
        await Throws<HttpRequestException>(() => reader.ReadAsync("item", 17, "", 0, 1, 1, default));
        var root = Path.Combine(Path.GetTempPath(), "starbridge-market-tests-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new MarketplacePreferencesStore(root);
            Check(store.Read(null).Revision == 0, "new scope starts empty");
            var saved = store.Save(null, new(0, [17], [17], ["original"]), () => true);
            Check(saved.Revision == 1 && store.Read(null).Favorites.SequenceEqual([17L]), "atomic local persistence");
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, new(0, [], [], []), () => true)));
            await Throws<OperationCanceledException>(() => Task.FromResult(store.Save(null, saved with { Favorites = [18] }, () => false)));
            Check(store.Read(null).Favorites.SequenceEqual([17L]), "retired write cannot replace snapshot");
            var view = new MarketplaceView("ore", 3, "", 0, "rows", 0);
            store.Save(null, saved with { View = view }, () => true);
            Check(new MarketplacePreferencesStore(root).Read(null).View == view, "view survives new store instance");
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, saved with { View = view with { Layout = "unknown" } }, () => true)));
            Check(store.Read(null).PriceFormat == "auto", "files written before the price format read as auto");
            var formatted = store.Save(null, store.Read(null) with { PriceFormat = "chinese" }, () => true);
            Check(new MarketplacePreferencesStore(root).Read(null).PriceFormat == "chinese", "price format survives new store instance");
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, formatted with { PriceFormat = "scientific" }, () => true)));
            // Watch tab (G3): what an item looked like when followed, local only, only for followed items.
            var watching = store.Read(null);
            var watchedSaved = store.Save(null, watching with { Favorites = [17, 18], Watched = [new(17, "1200000", 4, 1760000000000), new(18, null, null, 1760000000001)] }, () => true);
            Check(new MarketplacePreferencesStore(root).Read(null).Watched!.Single(w => w.Id == 17).Price == "1200000", "watch snapshot survives new store instance");
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, watchedSaved with { Watched = [new(99, "1", 1, 1)] }, () => true)));
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, watchedSaved with { Watched = [new(17, "-1", 1, 1)] }, () => true)));
            await Throws<InvalidDataException>(() => Task.FromResult(store.Save(null, watchedSaved with { Watched = [new(17, "1", 1, 1), new(17, "2", 1, 1)] }, () => true)));
            using (var body = JsonDocument.Parse("{\"revision\":0,\"favorites\":[],\"recentItems\":[],\"recentSearches\":[],\"priceFormat\":\"intl\"}"))
                Check(MarketplacePreferencesStore.Parse(body.RootElement).PriceFormat == "intl", "bridge payload carries the price format");
            await VerifyPreferenceReadsNeverFail();
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        Console.WriteLine("PASS marketplace: anonymous bounded reads, projection, missing/zero, Hant, cancellation, atomic preferences and revision conflict");
    }
    /// <summary>Build 44: side 3 reached the preference store, whose failure ended the pipe session.</summary>
    private static async Task VerifyPreferenceReadsNeverFail()
    {
        var root = Directory.CreateTempSubdirectory("market-preference-read-").FullName;
        try
        {
            var store = new MarketplacePreferencesStore(root);
            store.Save(null, new(0, [17, 18], [17], ["ore"]), () => true);
            var file = Directory.GetFiles(Path.Combine(root, "marketplace-local-v1"), "*.json").Single();
            MarketplacePreferences Written(string json) { File.WriteAllText(file, json); return store.Read(null); }
            const string view = "\"view\":{\"Keyword\":\"ore\",\"Category\":3,\"Relation\":\"\",\"RelatedId\":0,\"Layout\":\"rows\",\"Side\":SIDE,\"ItemLayout\":\"cards\",\"OrderLayout\":\"cards\"}";
            const string core = "{\"Revision\":5,\"Favorites\":[17,18],\"RecentItems\":[17],\"RecentSearches\":[\"ore\"],";
            foreach (var side in new[] { "3", "99", "-1" })
            {
                var read = Written(core + view.Replace("SIDE", side) + "}");
                Check(read.View?.Side == 1 && read.View.Keyword == "ore" && read.View.Layout == "rows", "an unknown side alone falls back to the default side: " + side);
                Check(read.Revision == 5 && read.Favorites.SequenceEqual([17L, 18L]), "the other fields survive a bad side");
            }
            var badView = Written(core + "\"view\":{\"Layout\":\"unknown\",\"Keyword\":\"ore\"}}");
            Check(badView.View is null && badView.Favorites.Length == 2, "a bad view falls back without losing the rest");
            var badFields = Written("{\"Revision\":\"x\",\"Favorites\":[17,17,0,\"x\",18],\"RecentItems\":\"x\",\"RecentSearches\":[\"ore\",1],\"PriceFormat\":\"scientific\",\"Watched\":[{\"Id\":99}],\"Future\":1}");
            Check(badFields.Revision == 0 && badFields.Favorites.SequenceEqual([17L, 18L]) && badFields.RecentItems.Length == 0 &&
                badFields.RecentSearches.SequenceEqual(["ore"]) && badFields.PriceFormat == "auto" && badFields.Watched is null,
                "one bad value never costs the good ones; unknown fields are ignored");
            var someWatched = Written("{\"Revision\":5,\"Favorites\":[17,18],\"RecentItems\":[],\"RecentSearches\":[],\"Watched\":[{\"Id\":17,\"Price\":\"1200\",\"Count\":4,\"At\":1},{\"Id\":18,\"Price\":\"bad\",\"Count\":1,\"At\":1},{\"Id\":\"x\"}]}");
            Check(someWatched.Watched is [{ Id: 17, Price: "1200", Count: 4 }], "one bad watch snapshot does not cost the good ones");
            // Review P1: one bad id must not empty the favorites on the next save.
            var salvaged = Written("{\"Revision\":5,\"Favorites\":[17,18,0],\"RecentItems\":[],\"RecentSearches\":[]}");
            Check(salvaged.Revision == 5 && salvaged.Favorites.SequenceEqual([17L, 18L]), "favorites survive one bad id");
            store.Save(null, salvaged, () => true);
            Check(store.Read(null).Favorites.SequenceEqual([17L, 18L]) && store.Read(null).Revision == 6, "the save keeps the salvaged favorites");
            foreach (var corrupt in new[] { "not json", "[]", "null", "" })
                Check(Written(corrupt).Revision == 0 && store.Read(null).Favorites.Length == 0, "a corrupt file reads as empty: " + corrupt);
            Check(Written(new string(' ', 70000)).Revision == 0, "an oversized file reads as empty");
            // The recovered state can be saved over the damaged file.
            File.WriteAllText(file, core + view.Replace("SIDE", "3") + "}");
            var recovered = store.Read(null);
            Check(store.Save(null, recovered with { Favorites = [17] }, () => true).Revision == 6, "a recovered file saves normally");

            // A rejected write through the bridge is an error for that request, never an escaping exception.
            var previous = HostDataRoot.CurrentRoot;
            HostDataRoot.UsePreparedRoot(root);
            try
            {
                using var runtime = new AccountBridgeRuntime(DispatchProxy.Create<IAccountBridgeHost, MarketHost>());
                typeof(AccountBridgeRuntime).GetField("_marketplacePreferences", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .SetValue(runtime, new MarketplacePreferencesStore(root));
                var rejected = await runtime.DispatchAsync(BridgeEnvelope.Request("marketplace.preferences", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1, value = new { revision = 0, favorites = Array.Empty<long>(), recentItems = Array.Empty<long>(), recentSearches = Array.Empty<string>(),
                        view = new { keyword = "", relation = "", relatedId = 0, layout = "cards", side = 3, itemLayout = "cards", orderLayout = "cards" } } }));
                Check(rejected.Response.Status == "error" && rejected.Response.Error?.Code == "marketplace.unavailable", "an invalid preference write answers with an error");
            }
            finally { HostDataRoot.UsePreparedRoot(previous); }
            Console.WriteLine("PASS marketplace preferences: reads fall back field by field, rejected writes answer alone");
        }
        finally { Directory.Delete(root, true); }
    }
    private static async Task VerifyReadDiagnostics()
    {
        var previous = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("cx37-market-read-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            using var runtime = new AccountBridgeRuntime(DispatchProxy.Create<IAccountBridgeHost, MarketHost>());
            var handler = new DiagnosticHandler();
            typeof(AccountBridgeRuntime).GetField("_marketplace", BindingFlags.Instance | BindingFlags.NonPublic)!
                .SetValue(runtime, new ScmMarketplaceReader(new("https://catalog.invalid/"), handler));
            var log = Path.Combine(root, "scm-auth-diagnostics.log");
            async Task<BridgeDispatchBatch> Read(string operation) => await runtime.DispatchAsync(
                BridgeEnvelope.Request("marketplace.read", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1, operation, keyword = "private-keyword-marker", id = 987654321 }));
            var success = await Read("search");
            Check(success.Response.Status == "ok" && !File.Exists(log), "successful reads do not log diagnostics");
            handler.Fail = true;
            var failed = await Read("search");
            Check(failed.Response.Status != "ok", "transport failure returns an error");
            var lines = File.ReadAllLines(log);
            Check(lines.Length == 1 && lines[0].EndsWith(
                "correlationId=marketplace step=marketplace-read outcome=rejected operation=search code=marketplace.unavailable exceptionType=HttpRequestException",
                StringComparison.Ordinal), "one failure diagnostic contains only safe fields after timestamp");
            await Read("untrusted-operation-marker");
            lines = File.ReadAllLines(log);
            Check(lines.Length == 2 && lines[1].EndsWith(
                "correlationId=marketplace step=marketplace-read outcome=rejected code=marketplace.invalid_request",
                StringComparison.Ordinal), "invalid operations are omitted and validation has no exception type");
            // side 3 ("all types") is accepted for the hall's latest listings only.
            handler.Fail = false;
            async Task<BridgeDispatchBatch> Side(string operation, int side) => await runtime.DispatchAsync(
                BridgeEnvelope.Request("marketplace.read", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1, operation, side, id = operation == "offers" ? 5 : 0 }));
            Check((await Side("latest", 3)).Response.Status == "ok", "latest accepts side 3 (all types)");
            foreach (var (operation, side) in new[] { ("search", 3), ("offers", 3), ("latest", 4), ("latest", -1) })
            {
                var before = File.ReadAllLines(log).Length;
                var rejected = await Side(operation, side);
                var after = File.ReadAllLines(log);
                Check(rejected.Response.Status != "ok" && after.Length == before + 1 &&
                    after[^1].EndsWith("code=marketplace.invalid_request", StringComparison.Ordinal),
                    "side 3 stays latest-only; out-of-range sides are rejected");
            }
            var text = File.ReadAllText(log);
            foreach (var excluded in new[] { "private-keyword-marker", "untrusted-operation-marker", "987654321", "catalog.invalid", "private-exception-marker" })
                Check(!text.Contains(excluded, StringComparison.Ordinal), "diagnostics exclude request and exception contents");
            Console.WriteLine("PASS marketplace.read diagnostics: silent success, one safe failure line, whitelist and privacy");
        }
        finally
        {
            HostDataRoot.UsePreparedRoot(previous);
            Directory.Delete(root, true);
        }
    }
    private sealed class DiagnosticHandler : HttpMessageHandler
    {
        internal bool Fail;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (Fail) throw new HttpRequestException("private-exception-marker https://catalog.invalid/987654321");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                { Content = new StringContent("{\"code\":0,\"data\":{\"list\":[],\"total\":0}}") });
        }
    }
    private static async Task VerifyDispatch()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, MarketHost>();
        var probe = (MarketHost)(object)host;
        using var runtime = new AccountBridgeRuntime(host);
        var handler = new PendingHandler();
        typeof(AccountBridgeRuntime).GetField("_marketplace", BindingFlags.Instance | BindingFlags.NonPublic)!
            .SetValue(runtime, new ScmMarketplaceReader(new("https://catalog.invalid/"), handler));
        foreach (var json in new[] { "{}", "{\"schemaVersion\":1,\"operation\":\"purchase\"}", "{\"schemaVersion\":1,\"operation\":\"item\",\"id\":-1}",
            "{\"schemaVersion\":1,\"operation\":\"item\",\"id\":17,\"token\":\"invalid\"}", "{\"schemaVersion\":1,\"operation\":\"item\",\"id\":17,\"id\":18}" })
        {
            using var doc = JsonDocument.Parse(json);
            var rejected = await runtime.DispatchAsync(BridgeEnvelope.Request("marketplace.read", Guid.NewGuid().ToString("N"), 1, doc.RootElement));
            Check(rejected.Response.Status != "ok" && handler.Calls == 0, "malformed requests never reach transport");
        }
        var pending = runtime.DispatchAsync(BridgeEnvelope.Request("marketplace.read", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1, operation = "item", id = 17 })).AsTask();
        await handler.Started.Task;
        probe.Generation = 2;
        handler.Release.SetResult();
        Check((await pending).Response.Status != "ok", "in-flight old account generation cannot publish data");
    }
    public class MarketHost : DispatchProxy
    {
        internal long Generation = 1;
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch
        {
            "get_Generation" => Generation,
            "get_CurrentContext" => null,
            "get_SupportsConcurrentReads" => false,
            "add_AccountChanged" or "remove_AccountChanged" or "Dispose" => null,
            _ => throw new NotSupportedException(method.Name),
        };
    }
    private sealed class PendingHandler : HttpMessageHandler
    {
        internal int Calls;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Started.SetResult(); await Release.Task.WaitAsync(token);
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":{\"id\":17}}") };
        }
    }
    private sealed class RelatedHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            string data;
            if (uri.AbsolutePath.EndsWith("weapon-attachments"))
            {
                Check(uri.Query.Contains("subType=Barrel&minSize=1&maxSize=2&requiredTags=ballistic_attach"), "SCM port-derived filters");
                data = """[{"id":23,"itemName":"Attachment"}]""";
            }
            else data = """{"id":17,"extendedAttrs":{"ports":[{"name":"barrel","minSize":1,"maxSize":2,"requiredTags":["ballistic_attach"]}]}}""";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") });
        }
    }
    private static void Check(bool condition, string label) { if (!condition) throw new Exception(label); }
    private sealed class EmptyVault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }
    private sealed class ReputationHandler(string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Method == HttpMethod.Get && request.RequestUri!.Query == "?view=self" &&
                request.Headers.Authorization?.Scheme == "Bearer", "reputation uses authenticated self read");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
    }
    private static async Task Throws<T>(Func<Task> action) where T : Exception
    { try { await action(); } catch (T) { return; } throw new Exception("Expected " + typeof(T).Name); }
    private sealed class Handler : HttpMessageHandler
    {
        internal bool Malformed;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization is null && !request.Headers.Contains("Cookie"), "anonymous GET only");
            var data = request.RequestUri!.AbsolutePath.EndsWith("hot-words")
                ? """[{"itemId":17,"itemName":"科力晶","itemNameEn":"Carinite","secret":"excluded"}]"""
                : request.RequestUri!.AbsolutePath.Contains("orders")
                ? """{"list":[{"nickname":"Fixture","timezoneId":16,"creatorStatus":3,"tradeTime":[1,0,1,0,1,0,0],"unitPrice":1234567,"creatorId":91,"userMobile":"private","remark":"  <b>周末</b>在线  ","hasOngoingTransactions":true,"itemDetails":[{"itemId":"17","itemName":"测试","unitPrice":1200}]}],"total":1}"""
                : """{"id":17,"itemName":"测试物品","buyOrderCount":0,"secret":"excluded"}""";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Malformed ? "{}" : "{\"code\":0,\"data\":" + data + "}") });
        }
    }
}
