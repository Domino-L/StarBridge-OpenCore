using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using StarBridge.Core.Profiles;

internal static partial class MarketplaceWriteTests
{
    private static async Task<int> VerifyExpiredExtraEntrypoints()
    {
        var passed = 0;
        foreach (var op in new[] { "send", "focus", "ticketRead", "ticketWrite", "profileAuthorization",
            "profileRead", "profileWrite", "profileTradeRead" })
        {
            var vault = new Vault();
            using var handler = new NoRequests();
            var uri = new Uri("https://fixture.invalid/");
            var client = new OAuthPkceClient(new ScmHttpClient(handler), vault,
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
            var missing = op switch
            {
                "ticketRead" or "profileTradeRead" => "trade.read",
                "profileRead" => "profile.read",
                "profileWrite" or "profileAuthorization" => "profile.write",
                _ => "trade.write",
            };
            var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
                DateTimeOffset.UtcNow.AddHours(-1),
                new[] { "trade.read", "trade.write", "profile.read", "profile.write" }.Where(s => s != missing).ToArray());
            var denied = false;
            try
            {
                if (op.StartsWith("ticket", StringComparison.Ordinal))
                    await client.IssueChatTicketAsync(session, default);
                else if (op == "profileAuthorization")
                    await client.AuthorizeProfileWriteAsync(session, default);
                else
                {
                    using var host = new ScmAccountBridgeHost(client,
                        new ScmProfileCacheStore(Path.Combine(Environment.CurrentDirectory, ".cxt11-patch", "test-cache")),
                        "scm", () => null, session, 1);
                    if (op.StartsWith("profile", StringComparison.Ordinal))
                        await host.TradeProfileAsync(WriterHost.Owner, true, BridgePayload.From(new { }), default);
                    else
                        await host.MarketplaceChatAsync(WriterHost.Owner, BridgePayload.From(new { operation = op }), default);
                }
            }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { denied = true; }
            catch (ScmApiAuthenticationException) when (op == "profileAuthorization") { denied = true; }
            Check(denied && handler.Calls == 0 && vault.Reads == 0 && vault.Writes == 0,
                "expired scope gate: " + op);
            passed++;
        }
        Console.WriteLine($"PASS expired extra scope entries: {passed}; HTTP=0, vault reads/writes=0");
        return passed + await VerifyTicketRefresh() + await VerifyTicketRejections() + await VerifyDirectWriteGates() + await VerifyRevokedAfterRefresh();
    }

    private static async Task<int> VerifyRevokedAfterRefresh()
    {
        var passed = 0;
        foreach (var area in new[] { "profile", "listings", "trade", "contracts", "records", "notices", "chat", "ticket", "authorization" })
        {
            var uri = new Uri("https://fixture.invalid/");
            var options = new ScmOAuthOptions("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback");
            using var handler = new RevokedGrant(options);
            var client = new OAuthPkceClient(new ScmHttpClient(handler), new RefreshVault(), options);
            var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(-1),
                ["profile.read", "profile.write", "trade.read", "trade.write", "blocklist.write"]);
            var input = BridgePayload.From(new { operation = area == "records" ? "unblock" : area == "notices" ? "readAll" : area == "chat" ? "send" : "create" });
            var denied = false;
            try
            {
                switch (area)
                {
                    case "profile": await client.TradeProfileAsync(session, true, input, () => true, default); break;
                    case "listings": await client.MarketplaceListingsAsync(session, input, () => true, default); break;
                    case "trade": await client.MarketplaceTradeAsync(session, input, () => true, default); break;
                    case "contracts": await client.MarketplaceContractsAsync(session, input, () => true, default); break;
                    case "records": await client.MarketplaceRecordsAsync(session, input, () => true, default); break;
                    case "notices": await client.MarketplaceNoticesAsync(session, input, () => true, default); break;
                    case "chat": await client.MarketplaceChatAsync(session, input, () => true, () => throw new Exception("Unexpected socket"), default); break;
                    case "ticket": await client.IssueChatTicketAsync(session, default); break;
                    default: await client.AuthorizeProfileWriteAsync(session, default); break;
                }
            }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { denied = true; }
            catch (ScmApiAuthenticationException) when (area == "authorization") { denied = true; }
            Check(denied && handler.Refreshes == 1 && handler.UserReads == 1, "revoked refreshed grant: " + area);
            passed++;
        }
        Console.WriteLine($"PASS revoked scopes checked after refresh: {passed}; resource writes=0");
        return passed;
    }

    private sealed class RefreshVault : ITokenVault
    {
        public string? LoadActiveAccountKey() => "fixture:opaque";
        public string? LoadRefreshToken(string key) => "synthetic-refresh";
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class RevokedGrant(ScmOAuthOptions options) : HttpMessageHandler
    {
        internal int Refreshes, UserReads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid", "synthetic refresh authority only");
            string body;
            if (request.RequestUri == options.TokenEndpoint)
            {
                Refreshes++;
                body = "{\"access_token\":\"synthetic-renewed\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}";
            }
            else
            {
                Check(request.Method == HttpMethod.Get && ++UserReads == 1, "only one refresh identity read; no resource writes");
                body = "{\"subject\":\"opaque\",\"displayName\":\"Fixture\",\"capabilities\":[]}";
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
    }

    private static async Task<int> VerifyDirectWriteGates()
    {
        var vault = new Vault();
        using var handler = new NoRequests();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), vault,
            new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
            DateTimeOffset.UtcNow.AddHours(-1), ["profile.read"]);
        // These existing one-shot grant writers do not refresh at all. Keep their own error contract.
        Func<Task>[] writes =
        [
            () => client.UpdatePersonalProfileVisibilityAsync(session, 0, "public", default),
            () => client.UpdatePersonalProfileBackgroundAsync(session, 0, "fixture", default),
            () => client.UpdatePersonalProfileAvatarAsync(session, 0, "fixture", default),
            () => client.UpdatePersonalProfileCallSignAsync(session, 0, "Fixture", default),
            () => client.SaveHandlePrivacyAsync(session, 0, "fixture", 0, default),
            () => client.UpdatePersonalProfileAsync(session, new(0, "public", "Fixture", 0, "", "", []), default),
            () => client.UpdatePagePresentationAsync(session, new(0, null, [], 0, "", null!), default),
            () => client.UpdateProfileAsync(session, new(default, default), default),
            () => client.ExecuteLegacyProfileMigrationAsync(session, "confirm", "fixture", false, default),
        ];
        foreach (var write in writes)
        {
            var denied = false;
            try { await write(); }
            catch (ScmApiForbiddenException) { denied = true; }
            Check(denied && handler.Calls == 0 && vault.Reads == 0 && vault.Writes == 0, "direct grant write gate");
        }
        client.StartTradeWindowSync(session, BridgePayload.From(new { }));
        Check(client.LastTradeWindowSync is null && handler.Calls == 0 && vault.Reads == 0 && vault.Writes == 0,
            "background window copy skips missing scope");
        Console.WriteLine($"PASS existing direct profile grant gates: {writes.Length + 1}; HTTP=0, vault reads/writes=0");
        return writes.Length + 1;
    }

    private static async Task<int> VerifyTicketRefresh()
    {
        var passed = 0;
        foreach (var mode in new[] { "success", "second401", "revokeRead", "revokeWrite" })
        {
            var uri = new Uri("https://fixture.invalid/");
            var options = new ScmOAuthOptions("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback");
            using var handler = new TicketRefresh(options, mode);
            var client = new OAuthPkceClient(new ScmHttpClient(handler), new RefreshVault(), options);
            var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
                DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
            string? error = null;
            try
            {
                var result = await client.IssueChatTicketAsync(session, default);
                Check(mode == "success" && result.Ticket == "fixture-ticket" &&
                    result.ActiveSession.AccessToken == "synthetic-renewed" &&
                    !ReferenceEquals(result.ActiveSession, session), "ticket returns refreshed session");
            }
            catch (ScmApiAuthenticationException) { error = "authentication"; }
            catch (ScmRefreshTemporarilyUnavailableException) { error = "temporary"; }
            catch (AccountBridgeHostException e) { error = e.Code; }
            Check(error == (mode == "success" ? null : mode == "second401" ? "temporary" :
                "marketplace.reauthorize_required"), "ticket refresh outcome: " + mode);
            Check(handler.Refreshes == 1 && handler.UserReads == 1 &&
                handler.Tickets == (mode.StartsWith("revoke", StringComparison.Ordinal) ? 1 : 2),
                "ticket refresh exactly once, scope checked before retry: " + mode);
            passed++;
        }
        Console.WriteLine($"PASS ticket 401 refresh/retry and revoked scopes: {passed}");
        return passed;
    }

    private sealed class TicketRefresh(ScmOAuthOptions options, string mode) : HttpMessageHandler
    {
        internal int Refreshes, UserReads, Tickets;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid", "synthetic ticket refresh authority only");
            var status = HttpStatusCode.OK;
            string body;
            if (request.RequestUri.AbsolutePath == "/app-api/member/chat/ws-ticket")
            {
                Check(request.Method == HttpMethod.Post && ++Tickets <= 2, "at most two ticket attempts");
                Check(request.Headers.Authorization?.Parameter == (Tickets == 1 ? "synthetic" : "synthetic-renewed"),
                    "ticket uses current session");
                status = Tickets == 1 || mode == "second401" ? HttpStatusCode.Unauthorized : HttpStatusCode.OK;
                body = """{"code":0,"data":"fixture-ticket"}""";
            }
            else if (request.RequestUri == options.TokenEndpoint)
            {
                Check(request.Method == HttpMethod.Post && ++Refreshes == 1, "one refresh only");
                body = """{"access_token":"synthetic-renewed","refresh_token":"synthetic-next","token_type":"Bearer","expires_in":3600}""";
            }
            else
            {
                Check(request.Method == HttpMethod.Get && ++UserReads == 1, "one refresh identity read only");
                var scopes = new[] { "trade.read", "trade.write" }.Where(scope =>
                    scope != (mode == "revokeRead" ? "trade.read" : mode == "revokeWrite" ? "trade.write" : ""));
                body = JsonSerializer.Serialize(new { subject = "opaque", displayName = "Fixture", capabilities = scopes });
            }
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }
    }
    private static async Task<int> VerifyTicketRejections()
    {
        var passed = 0;
        foreach (var mode in new[] { "business401", "http403", "business403", "scopeHeader",
            "scopeBody", "businessScope", "specific", "unknownSpecific", "businessKnown", "businessUnknown", "httpBusiness401", "description", "misleadingDescription" })
        {
            var vault = new Vault();
            using var handler = new TicketRejection(mode);
            var uri = new Uri("https://fixture.invalid/");
            var client = new OAuthPkceClient(new ScmHttpClient(handler), vault,
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
            var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
                DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
            var expected = mode switch
            {
                "http401" or "business401" or "httpBusiness401" => "marketplace.sign_in_required",
                "scopeHeader" or "scopeBody" or "businessScope" => "marketplace.reauthorize_required",
                "specific" or "businessKnown" => "marketplace.not_owner",
                "unknownSpecific" or "businessUnknown" => "marketplace.trade_rejected",
                "http403" or "description" or "misleadingDescription" => "marketplace.unavailable",
                _ => "marketplace.forbidden",
            };
            string? actual = null;
            try { await client.IssueChatTicketAsync(session, default); }
            catch (AccountBridgeHostException e) { actual = e.Code; }
            catch (ScmApiAuthenticationException) { actual = "marketplace.sign_in_required"; }
            Check(actual == expected, "ticket rejection " + mode);
            Check(handler.Calls == 1 && vault.Reads == 0 && vault.Writes == 0, "ticket is never replayed: " + mode);
            passed++;
        }
        Console.WriteLine($"PASS ticket refusal policy and no replay: {passed}");
        return passed;
    }

    private sealed class TicketRejection(string mode) : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.RequestUri!.Host == "fixture.invalid" && request.Method == HttpMethod.Post &&
                request.RequestUri.AbsolutePath == "/app-api/member/chat/ws-ticket", "only synthetic ticket request");
            var status = mode.StartsWith("business", StringComparison.Ordinal) ? HttpStatusCode.OK
                : mode == "http401" ? HttpStatusCode.Unauthorized : HttpStatusCode.Forbidden;
            var body = mode switch
            {
                "business401" or "httpBusiness401" => "{\"code\":401}",
                "business403" => "{\"code\":403}",
                "scopeBody" or "businessScope" => "{\"code\":403,\"error\":\"insufficient_scope\"}",
                "specific" => "{\"code\":1011009001,\"error\":\"insufficient_scope\"}",
                "unknownSpecific" or "businessUnknown" => "{\"code\":1002}",
                "businessKnown" => "{\"code\":1011009001}",
                "description" => "{\"error_description\":\"insufficient_scope\"}",
                _ => "{}",
            };
            var response = new HttpResponseMessage(status) { Content = new StringContent(body) };
            if (mode == "scopeHeader") response.Headers.WwwAuthenticate.ParseAdd("Bearer realm=\"fixture\", error=\"insufficient_scope\"");
            if (mode == "misleadingDescription") response.Headers.WwwAuthenticate.ParseAdd("Bearer error_description=\"denied, error=insufficient_scope\"");
            return Task.FromResult(response);
        }
    }

    private sealed class NoRequests : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            throw new Exception("Unexpected transport call at scope gate");
        }
    }
}
