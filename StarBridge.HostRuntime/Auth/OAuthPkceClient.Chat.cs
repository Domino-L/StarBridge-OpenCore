using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // 0.7.2 G9: SCM trade messages, two-way with the SCM site. REST reads the lists; sending needs
    // the chat WebSocket. Peers are opaque per-process references, never SCM member ids.
    private readonly object _chatGate = new();
    private readonly byte[] _chatKey = RandomNumberGenerator.GetBytes(32);
    private readonly Dictionary<string, (long Peer, long Conversation)> _chatPeers = new(StringComparer.Ordinal);
    private (string Owner, ScmChatConnection Connection)? _chat;
    internal Func<IScmChatTransport> ChatTransport { get; set; } = () => new ClientWebSocketChatTransport();

    internal Action<Uri> OpenScmBrowser { get; set; } = Support.HelpSupportBridgeDispatcher.OpenBrowser;

    internal Uri ChatEndpoint => new UriBuilder(options.WebSocketEndpoint)
    {
        Path = "/infra/ws/chat",
    }.Uri;

    /// <summary>An opaque reference for another member, usable for chat by this owner only.</summary>
    internal string ChatPeerReference(string owner, long peer, long conversation = 0)
    {
        var mac = HMACSHA256.HashData(_chatKey, Encoding.UTF8.GetBytes(owner + "\n" + peer));
        var reference = Convert.ToHexString(mac, 0, 16).ToLowerInvariant();
        lock (_chatGate)
        {
            if (_chatPeers.Count > 5000) _chatPeers.Clear();
            var key = owner + "\n" + reference;
            if (conversation == 0 && _chatPeers.TryGetValue(key, out var known)) conversation = known.Conversation;
            _chatPeers[key] = (peer, conversation);
        }
        return reference;
    }

    internal static string ChatOwner(ScmOAuthSession session) => session.AuthorityId + "\n" + session.Subject;

    /// <summary>Starts (or keeps) the owner's chat socket for the whole signed-in session. Pushes reach
    /// <paramref name="pushed"/> already projected: no SCM member ids, peers as opaque references.</summary>
    internal ScmChatConnection StartChat(string owner, Func<CancellationToken, Task<string>> issueTicket, Action<object> pushed)
    {
        void Project(ScmChatPush push)
        {
            if (ProjectChatPush(owner, push) is { } payload) pushed(payload);
        }
        lock (_chatGate)
        {
            if (_chat is { } live && live.Owner == owner && !live.Connection.Faulted)
            {
                live.Connection.OnPush(Project);
                return live.Connection;
            }
            var retired = _chat?.Connection;
            if (retired is not null) _ = retired.DisposeAsync().AsTask();
            var connection = new ScmChatConnection(ChatEndpoint, issueTicket, ChatTransport, Project);
            _chat = (owner, connection);
            return connection;
        }
    }

    /// <summary>A one-time chat ticket: refresh and retry once on HTTP 401.</summary>
    internal async Task<(string Ticket, ScmOAuthSession ActiveSession)> IssueChatTicketAsync(ScmOAuthSession session, CancellationToken token)
    {
        // The ticket both receives and sends messages, so SCM grants it only with
        // trade.read and trade.write together (partner fix e8bd0168, PR #9).
        if (!session.Capabilities.Contains("trade.read", StringComparer.Ordinal) ||
            !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        session = await EnsureActiveSessionAsync(session, token);
        if (!session.Capabilities.Contains("trade.read", StringComparer.Ordinal) ||
            !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        // Resolve the sender before the socket can deliver a cross-session echo.
        var owner = ChatOwner(session);
        if (GetSelfMemberId(owner) == 0 && session.Capabilities.Contains("profile.read", StringComparer.Ordinal))
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(options.ResourceServerBaseUri, "app-api/member/user/get"));
                using var response = await scmHttpClient.SendAsync(request, session.AccessToken, token);
                var envelope = await ReadMarketplaceEnvelopeAsync(response, "marketplace-chat-self", token);
                if (envelope.TryGetProperty("code", out var code) && code.ValueKind == JsonValueKind.Number &&
                    code.TryGetInt32(out var value) && value == 0 && envelope.TryGetProperty("data", out var profile))
                    CacheSelfMemberId(owner, profile);
            }
            catch (Exception) when (!token.IsCancellationRequested)
            {
                // Profile availability must not prevent ticket issuance or chat connection.
            }
        }
        // Until SCM grants the chat routes (PR #9) the ticket is refused with 403: stop quietly, never
        // retry in a loop and never treat it as a lost sign-in.
        try
        {
            return await IssueChatTicketCoreAsync(session, token);
        }
        catch (ScmApiForbiddenException)
        {
            throw new AccountBridgeHostException("marketplace.forbidden");
        }
    }

    private async Task<(string Ticket, ScmOAuthSession ActiveSession)> IssueChatTicketCoreAsync(ScmOAuthSession session, CancellationToken token)
    {
        return await SendResourceRequestWithRefreshAndSessionAsync(session, async (current, cancellation) =>
        {
            // Recheck both grants after any refresh, including a 401-triggered refresh.
            if (!current.Capabilities.Contains("trade.read", StringComparer.Ordinal) ||
                !current.Capabilities.Contains("trade.write", StringComparer.Ordinal))
                throw new AccountBridgeHostException("marketplace.reauthorize_required");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.ResourceServerBaseUri, "app-api/member/chat/ws-ticket"));
            using var response = await scmHttpClient.SendAsync(request, current.AccessToken, cancellation);
            var envelope = await ReadMarketplaceWriteEnvelopeAsync(response, "marketplace-chat-ticket", cancellation);
            var code = envelope.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetInt32() : -1;
            if (code == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
            if (code == 403) throw new AccountBridgeHostException("marketplace.forbidden");
            return code == 0 && envelope.TryGetProperty("data", out var ticket) && ticket.ValueKind == JsonValueKind.String &&
                   ticket.GetString() is { Length: > 0 and <= 512 } text
                ? text
                : throw new AccountBridgeHostException("marketplace.unavailable");
        }, token);
    }

    private object? ProjectChatPush(string owner, ScmChatPush push)
    {
        switch (push.Kind)
        {
            case "message":
            {
                var from = MarketplaceChat.Id(push.Content, "fromUserId");
                if (from == 0) return null;
                if (from == GetSelfMemberId(owner))
                {
                    var to = MarketplaceChat.Id(push.Content, "toUserId");
                    return to == 0 ? null : new { kind = "message", @ref = ChatPeerReference(owner, to), message = MarketplaceChat.Message(push.Content, to) };
                }
                return new
                {
                    kind = "message",
                    @ref = ChatPeerReference(owner, from),
                    name = push.Content.TryGetProperty("fromUserNickname", out var n) && n.ValueKind == JsonValueKind.String
                        ? n.GetString() is { Length: > 100 } longName ? longName[..100] : n.GetString() : null,
                    message = MarketplaceChat.Message(push.Content, from),
                };
            }
            case "echo" or "sent":
            {
                var to = MarketplaceChat.Id(push.Content, "toUserId");
                return to == 0 ? null : new { kind = "message", @ref = ChatPeerReference(owner, to), message = MarketplaceChat.Message(push.Content, to) };
            }
            case "unread":
                return push.Content.TryGetInt64(out var count) ? new { kind = "unread", count = Math.Max(0, count) } : null;
            default:
                return new { kind = "resync" };
        }
    }

    internal async Task StopChatAsync()
    {
        ScmChatConnection? connection;
        lock (_chatGate)
        {
            connection = _chat?.Connection;
            _chat = null;
        }
        if (connection is not null) await connection.DisposeAsync();
    }

    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceChatAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, Func<ScmChatConnection> connection, CancellationToken token)
    {
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 2048 ||
            input.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "ref" or "before" or "content" or "orderId" or "orderNumber" or "clientMessageId")))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        if (op is not ("conversations" or "history" or "openScm" or "open" or "openOrder" or "read" or "unread" or "send" or "focus" or "close"))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var write = op is "open" or "openOrder" or "read" or "send" or "focus";
        // The caller's session and the active session must both carry the scope (L07g made
        // the installed session the active one; a narrower caller view still fails closed).
        if (!session.Capabilities.Contains(write ? "trade.write" : "trade.read", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        var owner = active.AuthorityId + "\n" + active.Subject;
        if (!active.Capabilities.Contains(write ? "trade.write" : "trade.read", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");

        async Task<JsonElement> Send(HttpMethod method, string path, object? body = null)
        {
            var diagnosticId = ScmAuthDiagnostics.NewCorrelationId();
            var watch = ScmAuthDiagnostics.Start(diagnosticId, "marketplace-chat", $"operation={op} method={method.Method}");
            try
            {
                token.ThrowIfCancellationRequested();
                if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
                using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri, "app-api/" + path));
                request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, diagnosticId);
                if (body is not null) request.Content = System.Net.Http.Json.JsonContent.Create(body);
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
                var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, "marketplace-chat", token)
                    : ReadMarketplaceWriteEnvelopeAsync(response, "marketplace-chat", token));
                var code = envelope.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetInt32() : -1;
                if (code == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
                if (code == 403) throw new AccountBridgeHostException("marketplace.forbidden");
                if (code != 0) throw new AccountBridgeHostException("marketplace.unavailable");
                var data = envelope.TryGetProperty("data", out var value) ? value.Clone() : default;
                ScmAuthDiagnostics.Completed(diagnosticId, "marketplace-chat", watch, $"dataKind={data.ValueKind}");
                return data;
            }
            catch (Exception exception)
            {
                ScmAuthDiagnostics.Failed(diagnosticId, "marketplace-chat", watch, exception);
                throw;
            }
        }

        (long Peer, long Conversation) Peer()
        {
            var reference = MarketplaceTradePolicy.Text(input, "ref") ?? "";
            lock (_chatGate)
                return _chatPeers.TryGetValue(owner + "\n" + reference, out var peer)
                    ? peer
                    : throw new AccountBridgeHostException("marketplace.state_changed");
        }

        object Conversation(JsonElement row)
        {
            var peer = MarketplaceChat.Id(row, "otherUserId");
            if (peer == 0) throw new JsonException("Conversation without member.");
            return MarketplaceChat.Conversation(row, ChatPeerReference(owner, peer, MarketplaceChat.Id(row, "id")), () => BlockReference(owner, peer));
        }

        switch (op)
        {
            case "openScm":
            {
                var (peer, _) = Peer();
                token.ThrowIfCancellationRequested();
                if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
                OpenScmBrowser(new Uri(Support.HelpSupportBridgeDispatcher.ScmWebsiteRoot,
                    "message?userId=" + peer.ToString(System.Globalization.CultureInfo.InvariantCulture)));
                return (new { confirmed = true }, active);
            }
            case "conversations":
            {
                var data = await Send(HttpMethod.Get, "member/chat/conversations/list?limit=50");
                var rows = data.ValueKind == JsonValueKind.Array ? data.EnumerateArray().Take(100).Select(Conversation).ToArray() : [];
                // The socket normally runs from sign-in; a failed one is started again here.
                if (active.Capabilities.Contains("trade.write", StringComparer.Ordinal)) connection();
                return (new { rows }, active);
            }
            case "unread":
            {
                var data = await Send(HttpMethod.Get, "member/chat/unread/count");
                return (new { count = data.ValueKind == JsonValueKind.Number && data.TryGetInt64(out var n) ? Math.Max(0, n) : 0 }, active);
            }
            case "history":
            {
                var (peer, _) = Peer();
                var before = input.TryGetProperty("before", out var b) && b.ValueKind == JsonValueKind.Number && b.TryGetInt64(out var cursor) && cursor > 0
                    ? $"&lastMessageId={cursor}" : "";
                var data = await Send(HttpMethod.Get, $"member/chat/messages/history?otherUserId={peer}&pageSize=20{before}");
                var rows = data.ValueKind == JsonValueKind.Array
                    ? data.EnumerateArray().Take(50).Select(row => MarketplaceChat.Message(row, peer)).ToArray()
                    : [];
                return (new { rows }, active);
            }
            case "open":
            {
                var (peer, _) = Peer();
                return (Conversation(await Send(HttpMethod.Post, "member/chat/conversations/create", new { otherUserId = peer })), active);
            }
            case "openOrder":
            {
                // 订单详情「联系卖家」: the seller is found by the Host from the public order.
                var number = MarketplaceTradePolicy.Text(input, "orderNumber")?.Trim() ?? "";
                if (number.Length is 0 or > 64 || number.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('-' or '_')))
                    throw new AccountBridgeHostException("marketplace.invalid_request");
                var order = await Send(HttpMethod.Get, "sc/orders/get?orderNumber=" + Uri.EscapeDataString(number));
                var seller = MarketplaceChat.Id(order, "orderOwnerId") is var orderOwner and > 0 ? orderOwner : MarketplaceChat.Id(order, "creatorId");
                if (seller <= 0) throw new AccountBridgeHostException("marketplace.state_changed");
                return (Conversation(await Send(HttpMethod.Post, "member/chat/conversations/create", new { otherUserId = seller })), active);
            }
            case "read":
            {
                var (_, conversation) = Peer();
                if (conversation <= 0) throw new AccountBridgeHostException("marketplace.state_changed");
                var data = await Send(HttpMethod.Put, $"member/chat/conversations/{conversation}/mark-read");
                return (new { confirmed = data.ValueKind == JsonValueKind.True }, active);
            }
            case "focus":
            {
                long? peer = input.TryGetProperty("ref", out _) ? Peer().Peer : null;
                await connection().FocusAsync(peer, token);
                return (new { focused = peer is not null }, active);
            }
            case "close":
                await StopChatAsync();
                return (new { closed = true }, active);
            default:
            {
                var (peer, _) = Peer();
                var content = (MarketplaceTradePolicy.Text(input, "content") ?? "").Trim();
                if (content.Length is 0 or > MarketplaceChat.MaxContent) throw new AccountBridgeHostException("marketplace.invalid_request");
                string? clientMessageId = null;
                if (input.TryGetProperty("clientMessageId", out var suppliedId))
                {
                    if (suppliedId.ValueKind != JsonValueKind.String)
                        throw new AccountBridgeHostException("marketplace.invalid_request");
                    clientMessageId = suppliedId.GetString();
                }
                ScmChatConnection.ValidateClientMessageId(clientMessageId);
                string? quoteId = null;
                if (input.TryGetProperty("orderId", out var order))
                {
                    if (order.ValueKind != JsonValueKind.Number || !order.TryGetInt64(out var orderId) || orderId <= 0)
                        throw new AccountBridgeHostException("marketplace.invalid_request");
                    quoteId = orderId.ToString(System.Globalization.CultureInfo.InvariantCulture);
                }
                if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
                var result = await connection().SendAsync(peer, content, quoteId is null ? null : "order", quoteId, token, clientMessageId);
                return (new
                {
                    status = result.Status,
                    reason = result.Reason,
                    message = result.Message.ValueKind == JsonValueKind.Object ? MarketplaceChat.Message(result.Message, peer) : null,
                }, active);
            }
        }
    }
}
