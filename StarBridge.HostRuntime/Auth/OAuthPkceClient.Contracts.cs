using System.Globalization;
using System.Net.Http;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    /// <summary>One SCM app-api call for the trading hall: 401 requires sign-in; only explicit scope denial requires reauthorization.
    /// Specific business refusals retain their stable codes. Writes go once; callers reconcile by reading again.</summary>
    private async Task<JsonElement> HallSendAsync(ScmOAuthSession active, string area, string op, HttpMethod method, string path,
        object? body, Func<bool> current, CancellationToken token)
    {
        var diagnosticId = ScmAuthDiagnostics.NewCorrelationId();
        var watch = ScmAuthDiagnostics.Start(diagnosticId, area, $"operation={op} method={method.Method}");
        try
        {
            token.ThrowIfCancellationRequested();
            if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
            using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri, "app-api/" + path));
            request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, diagnosticId);
            if (body is not null) request.Content = System.Net.Http.Json.JsonContent.Create(body);
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
            var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, area, token)
                : ReadMarketplaceWriteEnvelopeAsync(response, area, token));
            var code = envelope.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetInt32() : -1;
            if (code == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
            if (code == 403) throw new AccountBridgeHostException("marketplace.forbidden");
            // SCM refused (e.g. reputation too low, slots full): a fixed code, then the caller reads again.
            if (code != 0) throw new AccountBridgeHostException(code > 0 ? "marketplace.trade_rejected" : "marketplace.unavailable");
            var data = envelope.TryGetProperty("data", out var value) ? value.Clone() : default;
            ScmAuthDiagnostics.Completed(diagnosticId, area, watch, $"dataKind={data.ValueKind}");
            return data;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Failed(diagnosticId, area, watch, exception);
            throw;
        }
    }

    // 0.7.2 G1: SCM contracts (bounty / service / cooperation). Public list, mine, detail with
    // milestones and participants; publish, apply, quit, start, complete, cancel, review, dispute.
    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceContractsAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token)
    {
        string[] allowed = ["schemaVersion", "operation", "id", "page", "type", "status", "keyword", "scope", "message",
            "reason", "evidence", "participantId", "rating", "comment", "contract"];
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 8192 ||
            input.EnumerateObject().Any(p => !allowed.Contains(p.Name)))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        var write = op is "create" or "apply" or "quit" or "start" or "complete" or "cancel" or "review" or "dispute";
        if (!write && op is not ("list" or "mine" or "detail")) throw new AccountBridgeHostException("marketplace.invalid_request");
        var page = MarketplaceTradePolicy.Number(input, "page") ?? 1;
        if (page is < 1 or > 10000) throw new AccountBridgeHostException("marketplace.invalid_request");
        if (write && !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        if (!active.Capabilities.Contains(write ? "trade.write" : "trade.read", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var owner = active.AuthorityId + "\n" + active.Subject;
        string? Chat(long member) => ChatPeerReference(owner, member);
        Task<JsonElement> Send(HttpMethod method, string path, object? body = null) =>
            HallSendAsync(active, "marketplace-contracts", op, method, path, body, current, token);
        static string Q(string? text) => Uri.EscapeDataString(text ?? "");

        long Id()
        {
            var id = input.TryGetProperty("id", out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) ? n : 0;
            return id > 0 ? id : throw new AccountBridgeHostException("marketplace.invalid_request");
        }
        string? Text(string key, int max, bool required = false)
        {
            var text = MarketplaceTradePolicy.Text(input, key)?.Trim();
            if (string.IsNullOrEmpty(text)) return required ? throw new AccountBridgeHostException("marketplace.invalid_request") : null;
            return text.Length <= max ? text : throw new AccountBridgeHostException("marketplace.invalid_request");
        }
        object Page(JsonElement data, Func<JsonElement, object> project) => new
        {
            rows = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var list) && list.ValueKind == JsonValueKind.Array
                ? list.EnumerateArray().Take(50).Select(project).ToArray() : [],
            total = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("total", out var total) && total.TryGetInt64(out var t) ? t : 0,
        };
        string Filters()
        {
            var query = $"pageNo={page}&pageSize=20";
            if (Text("type", 20) is { } type)
                query += Array.IndexOf(MarketplaceContracts.Types, type) >= 0 ? "&contractType=" + type : throw new AccountBridgeHostException("marketplace.invalid_request");
            if (MarketplaceTradePolicy.Number(input, "status") is { } status)
                query += status is >= 1 and <= 5 ? "&status=" + status : throw new AccountBridgeHostException("marketplace.invalid_request");
            if (Text("keyword", 50) is { } keyword) query += "&keyword=" + Q(keyword);
            return query;
        }

        switch (op)
        {
            case "list":
                return (Page(await Send(HttpMethod.Get, "trade/contract/page?" + Filters()), row => MarketplaceContracts.Contract(row, Chat)), active);
            case "mine":
            {
                var scope = Text("scope", 20) switch
                {
                    null or "created" => "",
                    "participated" => "&mineScope=PARTICIPATED",
                    _ => throw new AccountBridgeHostException("marketplace.invalid_request"),
                };
                return (Page(await Send(HttpMethod.Get, "trade/contract/my-page?" + Filters() + scope), row => MarketplaceContracts.Contract(row, Chat)), active);
            }
            case "detail":
            {
                var id = Id();
                var contract = Send(HttpMethod.Get, $"trade/contract/get?id={id}");
                var milestones = Send(HttpMethod.Get, $"trade/contract/milestones?contractId={id}");
                var participants = Send(HttpMethod.Get, $"trade/contract/participants/page?contractId={id}&pageNo=1&pageSize=50");
                await Task.WhenAll(contract, milestones, participants);
                var people = participants.Result;
                var viewer = people.ValueKind == JsonValueKind.Object && people.TryGetProperty("extra", out var extra) &&
                             extra.ValueKind == JsonValueKind.Object && extra.TryGetProperty("viewerParticipant", out var me) &&
                             me.ValueKind == JsonValueKind.Object ? MarketplaceContracts.Participant(me, Chat) : null;
                return (new
                {
                    contract = MarketplaceContracts.Contract(contract.Result, Chat),
                    milestones = milestones.Result.ValueKind == JsonValueKind.Array
                        ? milestones.Result.EnumerateArray().Take(50).Select(MarketplaceContracts.Milestone).ToArray() : [],
                    participants = Page(people, row => MarketplaceContracts.Participant(row, Chat)),
                    me = viewer,
                }, active);
            }
            case "create":
            {
                if (!input.TryGetProperty("contract", out var c) || c.ValueKind != JsonValueKind.Object)
                    throw new AccountBridgeHostException("marketplace.invalid_request");
                return (new { id = Created(await Send(HttpMethod.Post, "trade/contract/create", ContractBody(c))) }, active);
            }
            case "apply":
            {
                var data = await Send(HttpMethod.Post, "trade/contract/apply",
                    new { contractId = Id(), applyMessage = Text("message", 1000), applyShips = Array.Empty<long>() });
                return (new { confirmed = true, participantId = Created(data) }, active);
            }
            case "quit" or "start" or "complete":
                await Send(HttpMethod.Post, $"trade/contract/{op}?contractId={Id()}");
                return (new { confirmed = true }, active);
            case "cancel":
                await Send(HttpMethod.Post, $"trade/contract/cancel?contractId={Id()}&reason={Q(Text("reason", 500, true))}");
                return (new { confirmed = true }, active);
            case "dispute":
            {
                var evidence = Text("evidence", 1000) is { } e ? "&evidence=" + Q(e) : "";
                var data = await Send(HttpMethod.Post, $"trade/contract/dispute/create?contractId={Id()}&reason={Q(Text("reason", 1000, true))}{evidence}");
                return (new { confirmed = true, disputeId = Created(data) }, active);
            }
            default:
            {
                var participant = input.TryGetProperty("participantId", out var p) && p.TryGetInt64(out var pid) && pid > 0 ? pid
                    : throw new AccountBridgeHostException("marketplace.invalid_request");
                var rating = MarketplaceTradePolicy.Number(input, "rating") is { } r and >= 1 and <= 5 ? r
                    : throw new AccountBridgeHostException("marketplace.invalid_request");
                var data = await Send(HttpMethod.Post, "trade/contract/review",
                    new { participantId = participant, rating, comment = Text("comment", 1000) });
                return (new { confirmed = true, reviewId = Created(data) }, active);
            }
        }
    }

    private static long Created(JsonElement data) =>
        data.ValueKind == JsonValueKind.Number && data.TryGetInt64(out var id) && id > 0 ? id : 0;

    /// <summary>The publish form, validated with SCM's own limits before it is sent.</summary>
    private static object ContractBody(JsonElement c)
    {
        var bad = new AccountBridgeHostException("marketplace.invalid_request");
        if (c.EnumerateObject().Any(p => p.Name is not ("type" or "title" or "description" or "location" or "rewardType" or "rewardUec"
                or "rewardNote" or "slots" or "minReputation" or "requirements" or "expireTime")))
            throw bad;
        string? Text(string key, int max, bool required = false)
        {
            var text = MarketplaceTradePolicy.Text(c, key)?.Trim();
            if (string.IsNullOrEmpty(text)) return required ? throw bad : null;
            return text.Length <= max ? text : throw bad;
        }
        var type = Text("type", 20, true)!;
        if (Array.IndexOf(MarketplaceContracts.Types, type) < 0) throw bad;
        var rewardType = Text("rewardType", 10, true)!;
        if (rewardType is not ("UEC" or "ITEMS")) throw bad;
        long? uec = c.TryGetProperty("rewardUec", out var u) && u.ValueKind == JsonValueKind.Number && u.TryGetInt64(out var amount) ? amount : null;
        if (rewardType == "UEC" && uec is not (> 0 and <= 1_000_000_000_000)) throw bad;
        var note = Text("rewardNote", 500);
        if (rewardType == "ITEMS" && note is null) throw bad;
        var slots = MarketplaceTradePolicy.Number(c, "slots") is { } s and >= 1 and <= 100 ? s : throw bad;
        var reputation = MarketplaceTradePolicy.Number(c, "minReputation") ?? 0;
        if (reputation < 0) throw bad;
        var expire = c.TryGetProperty("expireTime", out var x) && x.ValueKind == JsonValueKind.Number && x.TryGetInt64(out var at) ? at : 0;
        if (expire <= DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()) throw bad;
        return new
        {
            contractType = type,
            creatorType = 0,
            title = Text("title", 100, true),
            description = Text("description", 2000),
            locationDescription = Text("location", 500),
            rewardType,
            rewardUec = rewardType == "UEC" ? uec : null,
            rewardDescription = note,
            maxParticipants = slots,
            minReputation = reputation,
            otherRequirements = Text("requirements", 1000),
            expireTime = expire,
        };
    }
}
