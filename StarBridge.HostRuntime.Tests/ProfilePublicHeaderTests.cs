using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// DEPLOY-QUEUE §4 (user-approved 2026-10-21): a visitor outside a profile's visibility receives
// only the always-public header, and the owner's SCM trade window is copied to the profile service.
internal static class ProfilePublicHeaderTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL " + message);
    }

    private const string Avatar = "data:image/png;base64,iVBORw0KGgo=";

    private sealed class ScmBackgroundVault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("Read cannot save credentials");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }

    private static object Restricted(string? legacyId = null, object? header = null, string visibility = "friendsOnly") =>
        legacyId is null
            ? new { schemaVersion = 1, restricted = true, visibility, publicHeader = header ?? DefaultHeader() }
            : new { schemaVersion = 1, legacyAccountId = legacyId, restricted = true, visibility, publicHeader = header ?? DefaultHeader() };

    private static object DefaultHeader() => new
    {
        callsign = "Aster", avatarAssetId = Avatar, callSignOrigin = "scm", avatarOrigin = "rsi",
        tradeWindow = new { days = new[] { 1, 1, 1, 1, 1, 0, 0 }, start = "19:30", end = "23:00", timezoneId = 77 }
    };

    internal static async Task Run()
    {
        ParseIsAWhitelist();
        ScmWindowProjection();
        await VisitorRoutesDeclareAndCarryTheHeader();
        await ReadResponsesMatchTheSharedSample();
        await TradeWindowSync();
        Console.WriteLine("PASS profile public header: whitelist parse, bridge shape, visitor routes, trade window sync");
    }

    private static void ParseIsAWhitelist()
    {
        var header = PersonalProfilePublicHeader.Parse(BridgePayload.From(Restricted()), null);
        Check(header.Callsign == "Aster" && header.AvatarAssetId == Avatar && header.Visibility == "friendsOnly" &&
            header.TradeWindow is { Start: "19:30", End: "23:00", TimezoneId: 77 }, "valid header parsed");
        var bridge = BridgePayload.From(header.ToBridge());
        Check(bridge.GetProperty("restricted").GetBoolean() && !bridge.GetProperty("editable").GetBoolean() &&
            bridge.GetProperty("visibility").GetString() == "friendsOnly", "bridge says restricted, read-only");
        var bridgeHeader = bridge.GetProperty("publicHeader");
        Check(bridgeHeader.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(["avatarAssetId", "callSign", "tradeWindow"]),
            "bridge header carries only callsign, avatar and window (origins dropped)");
        Check(PersonalProfilePublicHeader.Parse(BridgePayload.From(new { schemaVersion = 1, restricted = true, visibility = "private",
            publicHeader = new { callsign = "Aster" } }), null).TradeWindow is null, "a never-synced window is null, not invented");
        Check(PersonalProfilePublicHeader.Parse(BridgePayload.From(Restricted("historical-member")), "historical-member").Callsign == "Aster",
            "legacy route echoes its id");

        foreach (var (bad, reason) in new (object Body, string Reason)[]
        {
            (new { schemaVersion = 1, restricted = true, visibility = "friendsOnly", publicHeader = DefaultHeader(), gameId = "x" }, "extra root field"),
            (new { schemaVersion = 1, restricted = false, visibility = "friendsOnly", publicHeader = DefaultHeader() }, "restricted false"),
            (new { schemaVersion = 2, restricted = true, visibility = "friendsOnly", publicHeader = DefaultHeader() }, "schema"),
            (Restricted(visibility: "public"), "public is never restricted"),
            (Restricted(header: new { callsign = "Aster", content = new { bio = "leak" } }), "extra header field"),
            (Restricted(header: new { callsign = "Aster", avatarAssetId = "https://cdn.example/a.png" }), "avatar must be a data URI"),
            (Restricted(header: new { callsign = "A\u0001" }), "control characters"),
            (Restricted(header: new { avatarAssetId = Avatar }), "callsign required"),
            (Restricted(header: new { callsign = "Aster", tradeWindow = new { days = new[] { 1, 1, 1 }, start = "19:30", end = "23:00", timezoneId = 77 } }), "seven days"),
            (Restricted(header: new { callsign = "Aster", tradeWindow = new { days = new int[7], start = "19:30", end = "23:00", timezoneId = 77 } }), "at least one day"),
            (Restricted(header: new { callsign = "Aster", tradeWindow = new { days = new[] { 1, 0, 0, 0, 0, 0, 0 }, start = "25:00", end = "23:00", timezoneId = 77 } }), "time"),
            (Restricted(header: new { callsign = "Aster", tradeWindow = new { days = new[] { 1, 0, 0, 0, 0, 0, 0 }, start = "19:30", end = "23:00", timezoneId = 77, userMobile = "QQ 1" } }), "no contact in window"),
            (Restricted(header: new { callsign = 7 }), "wrong kind"),
        })
        {
            try { PersonalProfilePublicHeader.Parse(BridgePayload.From(bad), null); throw new Exception("FAIL accepted: " + reason); }
            catch (JsonException) { }
        }
        try { PersonalProfilePublicHeader.Parse(BridgePayload.From(Restricted("other-member")), "historical-member"); throw new Exception("FAIL legacy id mismatch accepted"); }
        catch (JsonException) { }
        V2IsAWhitelistToo();
    }

    private static object Facts(long? timezoneId = 77) => new
    {
        reputation = 128, completedTrades = 31, sellOrders = 5, buyOrders = 3, lastOnlineDay = "2026-10-29",
        siteRegisteredDay = "2025-03-12", gameRegisteredDay = (string?)null, language = "zh", timezoneId,
        banned = true, banCount = 2
    };

    private static object V2(object? facts, bool defaulted = true, bool masked = true, string visibility = "private") => new
    {
        schemaVersion = 2, restricted = true, visibility,
        publicHeader = new { callsign = "A*****r", avatarAssetId = (string?)null, callSignOrigin = (string?)null, avatarOrigin = (string?)null,
            tradeWindow = (object?)null, defaulted, nameMasked = masked, facts }
    };

    private static string SharedSample(string name = "public-header-v2.json")
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var path = Path.Combine(directory.FullName, "contracts", "personal-profile", name);
            if (File.Exists(path)) return File.ReadAllText(path);
        }
        throw new Exception("FAIL shared sample not found: " + name);
    }

    private static void V2IsAWhitelistToo()
    {
        // The Java response test checks the same file, so neither side can drift alone.
        using (var sample = JsonDocument.Parse(SharedSample()))
        {
            var parsed = PersonalProfilePublicHeader.Parse(sample.RootElement, null);
            Check(parsed is { Defaulted: true, NameMasked: true, TradeWindow: { TimezoneId: 16 },
                Facts: { Reputation: 128, CompletedTrades: 31, SellOrders: 5, BuyOrders: 3, LastOnlineDay: "2026-10-29", Language: "zh", TimezoneId: 16, Banned: false, BanCount: 0 } },
                "the shared sample parses");
        }
        var header = PersonalProfilePublicHeader.Parse(BridgePayload.From(V2(Facts())), null);
        Check(header is { Defaulted: true, NameMasked: true, Facts: { Reputation: 128, CompletedTrades: 31, Banned: true, BanCount: 2, TimezoneId: 77, GameRegisteredDay: null } },
            "v2 header parsed");
        var wire = BridgePayload.From(header.ToBridge()).GetRawText();
        Check(!wire.Contains("timezoneId") && wire.Contains("\"lastOnlineDay\":\"2026-10-29\""),
            "the client receives the offset, never the SCM zone id");
        Check(PersonalProfilePublicHeader.Parse(BridgePayload.From(V2(null, defaulted: false, masked: false, visibility: "friendsOnly")), null).Facts is null,
            "an explicit choice has no facts");
        Check(BridgePayload.From(PersonalProfilePublicHeader.Parse(BridgePayload.From(V2(null, defaulted: false, masked: false, visibility: "friendsOnly")), null).ToBridge())
                .GetProperty("publicHeader").EnumerateObject().All(p => p.Name is "avatarAssetId" or "callSign" or "tradeWindow"),
            "an explicit choice reaches the client with exactly the original keys");
        var v2Bridge = BridgePayload.From(header.ToBridge()).GetProperty("publicHeader");
        Check(v2Bridge.EnumerateObject().All(p => p.Name is "avatarAssetId" or "callSign" or "tradeWindow" or "defaulted" or "nameMasked" or "facts") &&
            v2Bridge.GetProperty("defaulted").GetBoolean() && v2Bridge.GetProperty("nameMasked").GetBoolean(),
            "a never-saved page adds only its two flags and the facts");
        foreach (var (bad, reason) in new (object Body, string Reason)[]
        {
            (V2(Facts(), defaulted: false), "facts on an explicit choice"),
            (V2(null, defaulted: true, visibility: "friendsOnly"), "only a private default is defaulted"),
            (V2(new { reputation = 1, userMobile = "QQ 1" }), "no key outside the allow-list"),
            (V2(new { reputation = 1, completedTrades = 31, sellOrders = 5, buyOrders = 3, lastOnlineDay = "2026-10-29 21:30", siteRegisteredDay = (string?)null, gameRegisteredDay = (string?)null, language = "zh", timezoneId = 77, banned = true, banCount = 2 }), "a last-online time"),
            (V2(new { reputation = 1, completedTrades = -1, sellOrders = 5, buyOrders = 3, lastOnlineDay = (string?)null, siteRegisteredDay = (string?)null, gameRegisteredDay = (string?)null, language = "zh", timezoneId = 77, banned = true, banCount = 2 }), "negative count"),
            (V2(new { reputation = 1, completedTrades = 1, sellOrders = 5, buyOrders = 3, lastOnlineDay = (string?)null, siteRegisteredDay = (string?)null, gameRegisteredDay = (string?)null, language = "klingon", timezoneId = 77, banned = true, banCount = 2 }), "language"),
            (new { schemaVersion = 1, restricted = true, visibility = "private", publicHeader = new { callsign = "Aster", defaulted = true, nameMasked = true, facts = (object?)null } }, "v2 keys in a v1 answer"),
            (new { schemaVersion = 2, restricted = true, visibility = "private", publicHeader = new { callsign = "Aster", defaulted = "yes", nameMasked = true, facts = (object?)null } }, "flag kind"),
            (new { schemaVersion = 2, restricted = true, visibility = "private", publicHeader = new { callsign = "Aster", defaulted = true, nameMasked = true, facts = (object?)null, userMobile = "QQ 1" } }, "contact"),
        })
        {
            bool rejected;
            try { PersonalProfilePublicHeader.Parse(BridgePayload.From(bad), null); rejected = false; }
            catch (JsonException) { rejected = true; }
            Check(rejected, "accepted: " + reason);
        }
        foreach (var v2OnHistorical in new[] { true })
        {
            bool rejected;
            try { PersonalProfilePublicHeader.Parse(BridgePayload.From(new { schemaVersion = 2, legacyAccountId = "m", restricted = true, visibility = "private",
                publicHeader = new { callsign = "A", defaulted = false, nameMasked = false, facts = (object?)null } }), "m"); rejected = false; }
            catch (JsonException) { rejected = true; }
            Check(rejected == v2OnHistorical, "the historical route stays on v1");
        }
        Check(OAuthPkceClient.UsableTradedName(" Real_Handle ") == "Real_Handle" && OAuthPkceClient.UsableTradedName("pilot@example.invalid") is null &&
            OAuthPkceClient.UsableTradedName("Bob@Home") == "Bob@Home" && OAuthPkceClient.UsableTradedName("") is null && OAuthPkceClient.UsableTradedName("a\nb") is null,
            "an email nickname never opens through a trade");
    }

    private static void ScmWindowProjection()
    {
        var window = PersonalProfileTradeWindow.FromScm(BridgePayload.From(new
        { tradeTime = "[1,1,1,1,1,0,0]", tradeStartTime = "19:30:00", tradeEndTime = "23:00", timezoneId = "77", userMobile = "QQ 123456" }));
        Check(window is { Start: "19:30", End: "23:00", TimezoneId: 77 } && window.Days.SequenceEqual([1, 1, 1, 1, 1, 0, 0]),
            "SCM text window normalised to HH:mm");
        Check(PersonalProfileTradeWindow.FromScm(BridgePayload.From(new { tradeTime = "", tradeStartTime = "19:30", tradeEndTime = "23:00", timezoneId = 77 })) is null,
            "SCM blank tradeTime means not set");
        Check(PersonalProfileTradeWindow.FromScm(BridgePayload.From(new { tradeTime = new[] { 1, 0, 0, 0, 0, 0, 0 }, tradeStartTime = "19:30", tradeEndTime = "19:30", timezoneId = 77 })) is null,
            "an empty window is not published");
    }

    private sealed class Transport : HttpMessageHandler
    {
        internal readonly List<(HttpMethod Method, string Path, string? Accept, string? Body)> Requests = [];
        internal HttpStatusCode WindowStatus = HttpStatusCode.NoContent;
        internal bool SubjectHeader = true;
        internal object VisitorBody = Restricted();
        internal object LegacyBody = Restricted("historical-member");
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = Uri.UnescapeDataString(request.RequestUri!.AbsolutePath);
            var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            Requests.Add((request.Method, path, request.Headers.TryGetValues(PersonalProfilePublicHeader.AcceptHeader, out var v) ? v.Single() : null, body));
            if (path.EndsWith("/trade-window", StringComparison.Ordinal)) return new HttpResponseMessage(WindowStatus);
            if (path.EndsWith("/visitor-legacy", StringComparison.Ordinal))
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(LegacyBody) };
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(VisitorBody) };
            if (SubjectHeader) response.Headers.Add("X-StarBridge-Profile-Subject", path.Split('/').Last());
            return response;
        }
    }

    private static OAuthPkceClient Client(Transport transport)
    {
        var uri = new Uri("http://127.0.0.1:9/app-api/starbridge/v1/personal-profile");
        return new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read profile.write", "/callback"));
    }

    private static ScmOAuthSession Session(params string[] scopes) => new("synthetic", "viewer", "Pilot", "synthetic-token",
        DateTimeOffset.UtcNow.AddHours(1), scopes);

    // The Java route tests check the same file, so a response the released Host reads cannot drift alone.
    private static async Task ReadResponsesMatchTheSharedSample()
    {
        using var sample = JsonDocument.Parse(SharedSample("read-responses-v1.json"));
        var root = sample.RootElement;
        var transport = new Transport { VisitorBody = root.GetProperty("ownerDocument") };
        var oauth = Client(transport);
        var owner = await oauth.LoadPersonalProfileAsync(Session("profile.read"), default);
        Check(owner.Profile is { SchemaVersion: 3, PublicId: "synthetic-public-id", IsPublic: true, Visibility: "public", Revision: 7, AvatarStyle: 1,
                FleetAffiliationStatus: "unavailable", IsGameplayStatisticsPublic: true, Hangar: null, Identity: { Callsign: "Synthetic Pilot", GameId: "Synthetic-Pilot" },
                FleetAffiliation: { FleetCode: "SYNTH" }, GameplayStatistics: { PlayTimeSeconds: 3600, HistoricalSessionCount: 3, HistoryImportState: "imported" },
                Presentation: { SourceVersion.Length: 64 } } &&
            owner.Profile.Content is { ShowOnlineTime: true, Introduction: "Synthetic introduction", PresenceIntent: "looking-for-group", Modules.Length: 2 } &&
            owner.Profile.Content.Modules[1].FavoriteShipIds is ["0123456789abcdef0123456789abcdef"] &&
            owner.Profile.UpdatedAt == DateTimeOffset.Parse("2026-10-29T12:00:00Z", System.Globalization.CultureInfo.InvariantCulture),
            "the saved page sample is read in full");
        transport.VisitorBody = root.GetProperty("visitorDocument");
        var seen = await oauth.LoadVisitorPersonalProfileAsync(Session("profile.read"), "scm-v1:" + new string('a', 64), default);
        Check(seen.Restricted is null && seen.Profile is { PublicId: "synthetic-public-id", FleetAffiliationStatus: "shown", Presentation: null,
            Identity.GameId: "", Content.Modules.Length: 2 }, "the visitor sample is read in full");
        transport.VisitorBody = root.GetProperty("restrictedVisitor");
        var restricted = await oauth.LoadVisitorPersonalProfileAsync(Session("profile.read"), "scm-v1:" + new string('a', 64), default);
        Check(restricted.Restricted is { Visibility: "friendsOnly", Callsign: "Synthetic Pilot", Defaulted: false, NameMasked: false, Facts: null,
            AvatarAssetId: "data:image/png;base64,AAAA", TradeWindow: { Start: "19:30", End: "23:00", TimezoneId: 77 } }, "the v1 visitor sample parses");
        transport.LegacyBody = root.GetProperty("restrictedLegacy");
        var historical = await oauth.LoadLegacyMemberVisitorPersonalProfileAsync(Session("profile.read"), "historical-member", default);
        Check(historical.Restricted is { Callsign: "Synthetic Pilot", TradeWindow.TimezoneId: 77 }, "the v1 historical sample parses");
    }

    private static async Task VisitorRoutesDeclareAndCarryTheHeader()
    {
        var transport = new Transport();
        var oauth = Client(transport);
        var target = "scm-v1:" + new string('a', 64);
        var result = await oauth.LoadVisitorPersonalProfileAsync(Session("profile.read"), target, default);
        Check(result.Restricted is { Callsign: "Aster" } && result.Profile is null, "visitor route returns the header, no profile");
        Check(transport.Requests.Last().Accept == PersonalProfilePublicHeader.AcceptValues, "visitor read declares both public header versions");
        transport.SubjectHeader = false;
        try { await oauth.LoadVisitorPersonalProfileAsync(Session("profile.read"), target, default); throw new Exception("FAIL unconfirmed subject accepted"); }
        catch (ScmApiProtocolException) { }
        transport.SubjectHeader = true;
        transport.VisitorBody = Restricted(header: new { callsign = "Aster", gameId = "leak" });
        try { await oauth.LoadVisitorPersonalProfileAsync(Session("profile.read"), target, default); throw new Exception("FAIL leaking header accepted"); }
        catch (ScmApiProtocolException) { }

        var legacy = await oauth.LoadLegacyMemberVisitorPersonalProfileAsync(Session("profile.read"), "historical-member", default);
        Check(legacy.Restricted is { Callsign: "Aster" }, "legacy route returns the header");
        Check(transport.Requests.Last().Accept == PersonalProfilePublicHeader.AcceptValue, "legacy read declares public-header-v1 by header");
        using (var sent = JsonDocument.Parse(transport.Requests.Last().Body!))
            Check(sent.RootElement.EnumerateObject().Count() == 2, "legacy request body stays exactly two fields");
        transport.LegacyBody = Restricted("other-member");
        try { await oauth.LoadLegacyMemberVisitorPersonalProfileAsync(Session("profile.read"), "historical-member", default); throw new Exception("FAIL legacy mismatch accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "profile.visitor_identity_unavailable") { }
    }

    private static async Task TradeWindowSync()
    {
        var transport = new Transport();
        var oauth = Client(transport);
        var scm = BridgePayload.From(new { tradeTime = new[] { 1, 1, 1, 1, 1, 0, 0 }, tradeStartTime = "19:30", tradeEndTime = "23:00",
            timezoneId = 77, userMobile = "QQ 123456789", id = 4242 });
        int Puts() => transport.Requests.Count(r => r.Method == HttpMethod.Put);

        oauth.StartTradeWindowSync(Session("profile.read", "trade.read"), scm);
        Check(oauth.LastTradeWindowSync is null && Puts() == 0, "no profile.write, no sync");

        var owner = Session("profile.read", "trade.read", "profile.write");
        oauth.StartTradeWindowSync(owner, scm);
        await oauth.LastTradeWindowSync!;
        var put = transport.Requests.Single(r => r.Method == HttpMethod.Put);
        Check(put.Path.EndsWith("/personal-profile/trade-window", StringComparison.Ordinal), "sync uses the profile service route");
        using (var sent = JsonDocument.Parse(put.Body!))
        {
            var names = sent.RootElement.EnumerateObject().Select(p => p.Name).Order().ToArray();
            Check(names.SequenceEqual(["days", "end", "schemaVersion", "start", "timezoneId"]),
                "only the window travels: never the SCM member id or contact (" + string.Join(',', names) + ")");
        }
        var before = Puts();
        oauth.StartTradeWindowSync(owner, scm);
        if (oauth.LastTradeWindowSync is { } again) await again;
        Check(Puts() == before, "an unchanged window is not written again");

        oauth.StartTradeWindowSync(owner, BridgePayload.From(new { tradeTime = "", tradeStartTime = "", tradeEndTime = "", timezoneId = 77 }));
        await oauth.LastTradeWindowSync!;
        using (var cleared = JsonDocument.Parse(transport.Requests.Last(r => r.Method == HttpMethod.Put).Body!))
            Check(cleared.RootElement.GetProperty("cleared").GetBoolean(), "an unset SCM window clears the public one");

        transport.WindowStatus = HttpStatusCode.NotFound;
        var changed = BridgePayload.From(new { tradeTime = new[] { 0, 0, 0, 0, 0, 1, 1 }, tradeStartTime = "10:00", tradeEndTime = "12:00", timezoneId = 77 });
        oauth.StartTradeWindowSync(owner, changed);
        await oauth.LastTradeWindowSync!;
        before = Puts();
        oauth.StartTradeWindowSync(owner, BridgePayload.From(new { tradeTime = new[] { 1, 0, 0, 0, 0, 0, 0 }, tradeStartTime = "08:00", tradeEndTime = "09:00", timezoneId = 77 }));
        Check(Puts() == before, "a switched-off server (404) stops syncing for this owner");

        transport.WindowStatus = HttpStatusCode.TooManyRequests;
        var other = Client(transport);
        other.StartTradeWindowSync(owner, scm);
        await other.LastTradeWindowSync!;
        before = Puts();
        other.StartTradeWindowSync(owner, scm);
        await other.LastTradeWindowSync!;
        Check(Puts() == before + 1, "a refused write (429) is retried on the next read, not remembered");
    }
}
