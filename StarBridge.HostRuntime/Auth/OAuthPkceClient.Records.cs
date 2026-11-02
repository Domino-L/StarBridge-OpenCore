using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // 0.7.2 G5/G6/G7: the member's received reviews, own reports and own blocklist. SCM already
    // grants these routes (blocklist.* and trade.* scopes on master). SCM member ids never reach
    // Flutter: a blocked user is an opaque per-process reference the Host maps back on unblock.
    private readonly object _recordsGate = new();
    private readonly byte[] _blockKey = RandomNumberGenerator.GetBytes(32);
    private readonly Dictionary<string, long> _blockRefs = new(StringComparer.Ordinal);
    private (string Owner, long Id)? _selfMemberId;

    private long GetSelfMemberId(string owner)
    {
        lock (_recordsGate)
            return _selfMemberId is { } known && known.Owner == owner ? known.Id : 0;
    }

    private long CacheSelfMemberId(string owner, JsonElement profile)
    {
        var self = profile.ValueKind == JsonValueKind.Object &&
            profile.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.Number &&
            id.TryGetInt64(out var value) ? value : 0;
        if (self <= 0) throw new AccountBridgeHostException("marketplace.unavailable");
        lock (_recordsGate) _selfMemberId = (owner, self);
        return self;
    }

    internal string BlockReference(string owner, long blockedUserId)
    {
        var mac = HMACSHA256.HashData(_blockKey, Encoding.UTF8.GetBytes(owner + "\n" + blockedUserId));
        var reference = Convert.ToHexString(mac, 0, 16).ToLowerInvariant();
        lock (_recordsGate) _blockRefs[owner + "\n" + reference] = blockedUserId;
        return reference;
    }

    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceRecordsAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token)
    {
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 2048 ||
            input.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "page" or "id" or "ref")))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        if (op is not ("reviews" or "reports" or "report" or "blocklist" or "unblock"))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var page = MarketplaceTradePolicy.Number(input, "page") ?? 1;
        if (page is < 1 or > 10000) throw new AccountBridgeHostException("marketplace.invalid_request");
        if (op == "unblock" && !session.Capabilities.Contains("blocklist.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        var owner = active.AuthorityId + "\n" + active.Subject;
        string[] needed = op switch
        {
            "blocklist" => ["blocklist.read"],
            "unblock" => ["blocklist.write"],
            "reviews" => ["trade.read", "profile.read"],
            _ => ["trade.read"],
        };
        if (needed.Any(scope => !active.Capabilities.Contains(scope, StringComparer.Ordinal)))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");

        async Task<JsonElement> Send(HttpMethod method, string path, object? body = null)
        {
            var diagnosticId = ScmAuthDiagnostics.NewCorrelationId();
            var watch = ScmAuthDiagnostics.Start(diagnosticId, "marketplace-records", $"operation={op} method={method.Method}");
            try
            {
                token.ThrowIfCancellationRequested();
                if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
                using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri, "app-api/" + path));
                request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, diagnosticId);
                if (body is not null) request.Content = System.Net.Http.Json.JsonContent.Create(body);
                // Writes are sent once; an uncertain answer is reconciled by reading the list again.
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
                var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, "marketplace-records", token)
                    : ReadMarketplaceWriteEnvelopeAsync(response, "marketplace-records", token));
                if (envelope.TryGetProperty("code", out var authCode) && authCode.ValueKind == JsonValueKind.Number)
                {
                    if (authCode.GetInt32() == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
                    if (authCode.GetInt32() == 403) throw new AccountBridgeHostException("marketplace.forbidden");
                }
                if (!envelope.TryGetProperty("code", out var code) || code.GetInt32() != 0)
                    throw new AccountBridgeHostException("marketplace.unavailable");
                var data = envelope.TryGetProperty("data", out var value) ? value.Clone() : default;
                ScmAuthDiagnostics.Completed(diagnosticId, "marketplace-records", watch, $"dataKind={data.ValueKind}");
                return data;
            }
            catch (Exception exception)
            {
                ScmAuthDiagnostics.Failed(diagnosticId, "marketplace-records", watch, exception);
                throw;
            }
        }

        object Page(JsonElement data, Func<JsonElement, object> project) => new
        {
            rows = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var list) && list.ValueKind == JsonValueKind.Array
                ? list.EnumerateArray().Take(50).Select(project).ToArray()
                : [],
            total = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("total", out var total) && total.ValueKind == JsonValueKind.Number
                ? total.GetInt64() : 0,
        };

        switch (op)
        {
            case "reviews":
            {
                // SCM lists the reviews *about* a member by its own id, which only the Host knows.
                var self = GetSelfMemberId(owner);
                if (self <= 0)
                {
                    var me = await Send(HttpMethod.Get, "member/user/get");
                    self = CacheSelfMemberId(owner, me);
                }
                var data = await Send(HttpMethod.Get, $"sc/order-reviews/page?reviewerId={self}&pageNo={page}&pageSize=20");
                return (Page(data, MarketplaceRecords.Review), active);
            }
            case "reports":
                return (Page(await Send(HttpMethod.Get, $"trade/order-report/my-list?pageNo={page}&pageSize=20"), MarketplaceRecords.Report), active);
            case "report":
            {
                var id = MarketplaceTradePolicy.Number(input, "id") ?? 0;
                if (id <= 0) throw new AccountBridgeHostException("marketplace.invalid_request");
                return (MarketplaceRecords.Report(await Send(HttpMethod.Get, $"trade/order-report/get?id={id}")), active);
            }
            case "blocklist":
            {
                var data = await Send(HttpMethod.Get, $"member/user-blacklist/my-list?pageNo={page}&pageSize=20");
                return (Page(data, row => MarketplaceRecords.Block(row, blocked => BlockReference(owner, blocked))), active);
            }
            default:
            {
                var reference = MarketplaceTradePolicy.Text(input, "ref") ?? "";
                long blocked;
                lock (_recordsGate)
                    if (!_blockRefs.TryGetValue(owner + "\n" + reference, out blocked))
                        throw new AccountBridgeHostException("marketplace.state_changed");
                await Send(HttpMethod.Delete, "member/user-blacklist/remove", new { blockedUserId = blocked });
                lock (_recordsGate) _blockRefs.Remove(owner + "\n" + reference);
                return (new { @ref = reference, confirmed = true }, active);
            }
        }
    }
}
