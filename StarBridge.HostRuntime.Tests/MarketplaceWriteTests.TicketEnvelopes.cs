using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static partial class MarketplaceWriteTests
{
    private static async Task VerifyTicketEnvelope(string mode)
    {
        var uri = new Uri("https://fixture.invalid/");
        var options = new ScmOAuthOptions("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback");
        var c = new Case("ticket", "issue", "POST", "member/chat/ws-ticket", "{}", null,
            "marketplace.trade_rejected");
        var sample = mode.StartsWith("envelope-", StringComparison.Ordinal) ? EnvelopeCase(c, mode)
            : (Body: mode == "scopeHeader" ? "{}" : "<html><body>Access denied</body></html>",
                Expected: mode == "html" ? "marketplace.forbidden" : "marketplace.reauthorize_required");
        using var handler = new TicketEnvelopeHandler(options, mode, sample.Body);
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new RefreshVault(), options);
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic",
            DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
        string? error = null;
        string? ticket = null;
        try { ticket = (await client.IssueChatTicketAsync(session, default)).Ticket; }
        catch (AccountBridgeHostException e) { error = e.Code; }
        catch (ScmApiAuthenticationException) { error = "marketplace.sign_in_required"; }
        finally
        {
            Check(handler.Tickets == 1, "ticket POST count must be one: " + mode);
            Check(handler.Refreshes == 0, "only HTTP 401 may refresh: " + mode);
        }
        Check((error ?? "") == sample.Expected,
            $"ticket {mode}: expected {sample.Expected}, got {error ?? "success"}");
        Check(sample.Expected == "" ? ticket == "fixture-ticket" : ticket is null,
            "code zero returns the ticket; refusals return no ticket: " + mode);
    }

    private sealed class TicketEnvelopeHandler(ScmOAuthOptions options, string mode, string body) : HttpMessageHandler
    {
        internal int Tickets, Refreshes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid", "synthetic authority only");
            if (request.RequestUri == options.TokenEndpoint)
            {
                Refreshes++;
                throw new Exception("Unexpected refresh for non-401 ticket response");
            }
            Check(request.Method == HttpMethod.Post &&
                request.RequestUri.AbsolutePath == "/app-api/member/chat/ws-ticket", "ticket route and method");
            Tickets++;
            var response = new HttpResponseMessage(mode.StartsWith("envelope-200-", StringComparison.Ordinal)
                ? HttpStatusCode.OK : HttpStatusCode.Forbidden)
            {
                Content = new StringContent(body, System.Text.Encoding.UTF8,
                    mode.StartsWith("html", StringComparison.Ordinal) ? "text/html" : "application/json"),
            };
            if (mode is "htmlScope" or "scopeHeader")
                response.Headers.WwwAuthenticate.ParseAdd("Bearer error=\"insufficient_scope\"");
            return Task.FromResult(response);
        }
    }
}
