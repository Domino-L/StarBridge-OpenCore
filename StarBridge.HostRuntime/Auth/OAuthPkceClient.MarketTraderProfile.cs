using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private static bool ValidVisitorSubject(string subject) =>
        subject.Length == 71 && subject.StartsWith("scm-v1:", StringComparison.Ordinal) &&
        subject.AsSpan(7).IndexOfAnyExcept("0123456789abcdef") < 0;

    internal Task<ScmPersonalProfileResult> LoadMarketTraderPersonalProfileAsync(
        ScmOAuthSession session, long scmUserId, CancellationToken token)
    {
        if (scmUserId <= 0) throw new ArgumentException("Invalid visitor target.");
        VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.MarketTrader);
        var endpoint = new Uri(options.PersonalProfileEndpoint.AbsoluteUri.TrimEnd('/') + "/visitor/scm-member");
        return LoadVisitorPersonalProfileAtAsync(session,
            endpoint, null, token, () => new HttpRequestMessage(HttpMethod.Post, endpoint)
            { Content = JsonContent.Create(new { schemaVersion = 1, scmUserId }) });
    }

    /// <summary>The name SCM shows this viewer on their own trades for everybody on the newest pages, newest row
    /// first; a null name is a person whose name must stay masked. SCM's page has no counterparty filter, so one read
    /// serves every person the viewer opens, and the answer stays in memory.</summary>
    internal Task<(Dictionary<long, string?> Result, ScmOAuthSession ActiveSession)> LoadTradedMemberNamesAsync(
        ScmOAuthSession session, int pages, TimeSpan budget, CancellationToken token)
    {
        // Outside the retry: a token refreshed halfway continues from the page it stopped on.
        var names = new Dictionary<long, string?>();
        var page = 1;
        var watch = System.Diagnostics.Stopwatch.StartNew();
        return SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            if (!active.Capabilities.Contains("trade.read", StringComparer.Ordinal)) return names;
            for (; page <= pages; page++)
            {
                // A page is opening on this: what was read by now is the answer.
                if (page > 1 && watch.Elapsed > budget) break;
                using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(options.ResourceServerBaseUri,
                    "app-api/sc/order-transactions/page?pageSize=" + TradedNamePageSize + "&pageNo=" + page));
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
                var envelope = await ReadMarketplaceEnvelopeAsync(response, "market-trader-name", ct);
                var code = ScmMarketplaceReader.At(envelope, "code").TryGetInt64Safe();
                if (code == 401) throw new ScmApiAuthenticationException("SCM account authorization is required.");
                if (code != 0) throw new ScmApiProtocolException("Traded name unavailable.");
                var rows = ScmMarketplaceReader.At(ScmMarketplaceReader.At(envelope, "data"), "list");
                if (rows.ValueKind != JsonValueKind.Array) throw new ScmApiProtocolException("Traded name unavailable.");
                foreach (var row in rows.EnumerateArray())
                {
                    if (ScmMarketplaceReader.At(row, "orderOwnerId").TryGetInt64Safe() is > 0 and var owner)
                        names.TryAdd(owner, UsableTradedName(MarketplaceTradePolicy.Text(row, "orderOwnerName")));
                    if (ScmMarketplaceReader.At(row, "tradingerId").TryGetInt64Safe() is > 0 and var trader)
                        names.TryAdd(trader, UsableTradedName(MarketplaceTradePolicy.Text(row, "tradingerName")));
                }
                if (rows.GetArrayLength() < TradedNamePageSize) break;
            }
            return names;
        }, token);
    }

    // Older trades than these stay masked. The whole scan runs once per sign-in; see WithTradedHandleAsync.
    internal const int TradedNamePages = 20;
    private const int TradedNamePageSize = 100;

    /// <summary>An email sign-up's nickname stays masked even after a trade.</summary>
    internal static string? UsableTradedName(string? name)
    {
        var text = name?.Trim();
        return string.IsNullOrEmpty(text) || text.Length > 128 || text.Any(char.IsControl) ||
            System.Text.RegularExpressions.Regex.IsMatch(text, @"^[^@\s]+@[^@\s]+\.[^@\s]+$") ? null : text;
    }

    internal Task<(long Result, ScmOAuthSession ActiveSession)> LoadMarketTraderViewerAsync(
        ScmOAuthSession session, CancellationToken token) =>
        SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            if (!active.Capabilities.Contains("profile.read", StringComparer.Ordinal) ||
                !active.Capabilities.Contains("trade.read", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Market viewer unavailable.");
            using var request = new HttpRequestMessage(HttpMethod.Get,
                new Uri(options.ResourceServerBaseUri, "app-api/member/user/get"));
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var envelope = await ReadMarketplaceEnvelopeAsync(response, "market-viewer", ct);
            var id = ScmMarketplaceReader.At(ScmMarketplaceReader.At(envelope, "data"), "id").TryGetInt64Safe();
            if (ScmMarketplaceReader.At(envelope, "code").TryGetInt64Safe() != 0 ||
                id is not > 0)
                throw new ScmApiProtocolException("Market viewer unavailable.");
            return id.Value;
        }, token);
}
