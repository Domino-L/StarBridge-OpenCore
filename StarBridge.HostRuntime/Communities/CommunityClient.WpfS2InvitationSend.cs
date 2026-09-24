using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.Fleets;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<string> RebindWpfS2InvitationSourceAsync(
        string bearer,
        InvitationOutboxItem item,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        if (item.Origin != _origin.GetLeftPart(UriPartial.Authority)) throw Invalid();
        current();
        var page = await ReadWpfS2Async(bearer, new("mine", "", null, null), scope, viewerId, token);
        current();
        var matches = page.Items.Where(row =>
        {
            var target = Resolve(row.TargetRef, scope, allowWpfS2: true);
            return target.WpfS2ViewerId == viewerId && target.Code.Equals(item.SourceCode, StringComparison.OrdinalIgnoreCase);
        }).ToArray();
        if (matches.Length != 1 || matches[0].Relationship is not ("member" or "owner")) throw Invalid();
        return matches[0].TargetRef;
    }

    internal async Task<InvitationTargetPreview> PreviewWpfS2InvitationTargetAsync(
        string bearer,
        string organizationRef,
        InvitationDeliveryTarget destination,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        var state = await ReadWpfS2InvitationStateAsync(
            bearer, organizationRef, destination, scope, viewerId, current, token);
        var eligible = state.CanSend ? state.EligibleRecipients : 0;
        return new(eligible > 0, eligible);
    }

    internal async Task<InvitationSendProgress> AdvanceWpfS2InvitationSendAsync(
        string bearer,
        string accountKey,
        string operationId,
        string organizationRef,
        InvitationDeliveryTarget destination,
        int maxUses,
        string action,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        if (!InvitationOutboxJournal.IsId(operationId) || maxUses is < 1 or > 50 ||
            destination.Scope != scope || action is not ("advance" or "check" or "retryDelivery"))
            return new(operationId, "rejected", "dataInvalid");
        current();
        var source = Resolve(organizationRef, scope, allowWpfS2: true);
        if (source.WpfS2ViewerId != viewerId) return new(operationId, "rejected", "dataInvalid");
        var origin = _origin.GetLeftPart(UriPartial.Authority);
        if (destination.Origin.GetLeftPart(UriPartial.Authority) != origin)
            return new(operationId, "rejected", "dataInvalid");
        var pending = (await _invitationWorkflow.Value.ReadAsync(accountKey)).SingleOrDefault(item => item.Id == operationId);
        current();
        if (pending is not null && (pending.SourceCode != source.Code || pending.Channel != destination.Channel ||
            pending.DestinationId != destination.Id || pending.Origin != origin || pending.MaxUses != maxUses))
            return new(operationId, "rejected", "intentChanged");
        if (pending is null && action != "advance") return new(operationId, "unknown", "notFound");
        if (pending is null)
        {
            var preview = await PreviewWpfS2InvitationTargetAsync(
                bearer, organizationRef, destination, scope, viewerId, current, token);
            if (!preview.CanSend) return new(operationId, "rejected", "notAllowed");
            if (destination.Channel == "private" ? maxUses != 1 : maxUses != preview.EligibleRecipients)
                return new(operationId, "rejected", "refreshRequired");
        }

        var original = pending ?? new InvitationOutboxItem(
            operationId,
            source.Code,
            destination.Channel,
            destination.Id,
            origin,
            DateTimeOffset.UtcNow,
            maxUses,
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes("invitation-delivery:" + operationId)))[..32].ToLowerInvariant(),
            "prepared",
            SourceName: source.Name,
            DestinationName: destination.DisplayName);
        return await _invitationWorkflow.Value.ExecuteAsync(
            accountKey,
            original,
            action,
            state => GenerateWpfS2InvitationCardAsync(
                bearer, new(organizationRef, state.Id, state.RequestedAt, state.MaxUses), scope, viewerId, current, token),
            (_, intent, confirm) => DeliverWpfS2InvitationCardAsync(
                bearer, organizationRef, destination, intent, confirm, scope, viewerId, current, token),
            () => { token.ThrowIfCancellationRequested(); current(); },
            generationRetrySafe: false,
            deliveryConfirmationSupported: false);
    }

    private sealed record WpfS2InvitationState(JsonElement Fleet, bool CanSend, int EligibleRecipients);

    private async Task<WpfS2InvitationState> ReadWpfS2InvitationStateAsync(
        string bearer,
        string organizationRef,
        InvitationDeliveryTarget destination,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        current();
        var target = Resolve(organizationRef, scope, allowWpfS2: true);
        if (target.WpfS2ViewerId != viewerId || destination.Scope != scope ||
            destination.Channel is not ("private" or "room") ||
            destination.Origin.GetLeftPart(UriPartial.Authority) != _origin.GetLeftPart(UriPartial.Authority))
            throw Invalid();
        var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
            Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase));
        current();
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token);
        current();
        var management = ownership == WpfS2Ownership.Self ||
            WpfS2HasPermission(fleet, viewerId, "canManageFleetInfo") ||
            WpfS2HasPermission(fleet, viewerId, "canRemoveMembers") ||
            WpfS2HasPermission(fleet, viewerId, "canPublishTasks") ||
            WpfS2HasPermission(fleet, viewerId, "canPublishPlans");
        var canSend = FleetInvitationAccessPolicy.Allows(
            Optional(fleet, "fleetInvitationCardPolicy", 32),
            isFleetMember: true,
            isCommander: ownership == WpfS2Ownership.Self,
            hasManagementAccess: management);

        var members = Rows(fleet, "members", 10000);
        var memberIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in members)
        {
            var id = Optional(row, "accountId", 512)?.Trim();
            if (!string.IsNullOrEmpty(id) && !memberIds.Add(id)) throw Invalid();
        }
        int eligible;
        if (destination.Channel == "private")
        {
            eligible = memberIds.Contains(destination.Id) ? 0 : 1;
        }
        else
        {
            var candidates = destination.RecipientAccountIds
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .Select(id => id.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            eligible = candidates.Count(id =>
                !id.Equals(viewerId, StringComparison.OrdinalIgnoreCase) && !memberIds.Contains(id));
        }
        return new(fleet, canSend, Math.Min(50, eligible));
    }

    private async Task<InvitationGenerationResult> GenerateWpfS2InvitationCardAsync(
        string bearer,
        InvitationGenerationIntent intent,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        if (!InvitationOutboxJournal.IsId(intent.TargetRef) || !InvitationOutboxJournal.IsId(intent.RequestId) ||
            intent.MaxUses is < 1 or > 50 || intent.RequestedAt > DateTimeOffset.UtcNow.AddMinutes(5))
            return new("rejected", "dataInvalid");
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var sent = false;
        try
        {
            var target = Resolve(intent.TargetRef, scope, allowWpfS2: true);
            var placeholder = new InvitationDeliveryTarget("private", "placeholder", scope, _origin);
            var state = await ReadWpfS2InvitationStateAsync(
                bearer, intent.TargetRef, placeholder, scope, viewerId, current, token);
            if (!state.CanSend) return new("rejected", "notAllowed");
            var priorIds = WpfS2InvitationRows(state.Fleet).Select(row => Text(row, "id", 128))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var session = await WorkspaceJson(bearer, "/api/auth/session", token, 2 * 1024 * 1024);
            if (!Text(session, "accountId", 512).Equals(viewerId, StringComparison.OrdinalIgnoreCase))
                return new("rejected", "identityUnavailable");
            var userName = Optional(session, "userName", 512)?.Trim();
            current();
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/invites"))
            {
                Content = JsonContent.Create(new
                {
                    FleetCode = target.Code,
                    ExpiresInDays = 7,
                    intent.MaxUses,
                    AcceptMode = "Direct",
                    Purpose = "card"
                })
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            lock (_inviteGate)
            {
                current();
                deadline.Token.ThrowIfCancellationRequested();
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                sent = true;
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (!response.IsSuccessStatusCode)
                return response.StatusCode switch
                {
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                    HttpStatusCode.NotFound or HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                    _ => new("unknown", "outcomeUnknown")
                };
            using var document = await ReadBoundedJsonAsync(response, 8 * 1024 * 1024, deadline.Token);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !Text(root, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            var now = DateTimeOffset.UtcNow;
            var candidates = WpfS2InvitationRows(root).Where(row =>
            {
                var id = Text(row, "id", 128);
                var code = Text(row, "code", 40);
                var created = row.GetProperty("createdAt").GetDateTimeOffset();
                var expires = row.GetProperty("expiresAt").GetDateTimeOffset();
                var creator = Optional(row, "createdByAccount", 512)?.Trim();
                return !priorIds.Contains(id) && InvitationOutboxJournal.IsId(id) &&
                       !string.IsNullOrWhiteSpace(code) && code.Length >= 6 && !code.Any(char.IsControl) &&
                       Text(row, "status", 32).Equals("Active", StringComparison.OrdinalIgnoreCase) &&
                       Text(row, "acceptMode", 32).Equals("Direct", StringComparison.OrdinalIgnoreCase) &&
                       Number(row, "maxUses", 0, 50) == intent.MaxUses && Number(row, "usedCount", 0, 50) == 0 &&
                       created >= intent.RequestedAt.AddMinutes(-5) && created <= now.AddMinutes(5) && expires > now &&
                       (string.IsNullOrEmpty(creator) || creator.Equals(viewerId, StringComparison.OrdinalIgnoreCase) ||
                        creator.Equals(userName, StringComparison.OrdinalIgnoreCase));
            }).ToArray();
            if (candidates.Length != 1) throw Invalid();
            var invite = candidates[0];
            deadline.Token.ThrowIfCancellationRequested();
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            return new("accepted", InviteId: Text(invite, "id", 128), Code: Text(invite, "code", 40),
                ExpiresAt: invite.GetProperty("expiresAt").GetDateTimeOffset());
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            JsonException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        {
            return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired");
        }
        finally
        {
            _write.Release();
        }
    }

    private async Task<InvitationDeliveryResult> DeliverWpfS2InvitationCardAsync(
        string bearer,
        string organizationRef,
        InvitationDeliveryTarget destination,
        InvitationDeliveryIntent intent,
        bool confirmOnly,
        string scope,
        string viewerId,
        Action current,
        CancellationToken token)
    {
        InvitationDeliveryResult BeforeSend(string reason) => new(confirmOnly ? "unknown" : "rejected", reason);
        if (!InvitationOutboxJournal.IsId(intent.RequestId) || !InvitationOutboxJournal.IsId(organizationRef) ||
            destination.Channel is not ("private" or "room") || string.IsNullOrWhiteSpace(destination.Id) ||
            destination.Id.Length > 256 || destination.Id.Any(char.IsControl) || destination.Scope != scope ||
            destination.Origin.GetLeftPart(UriPartial.Authority) != _origin.GetLeftPart(UriPartial.Authority) ||
            !ChatAttachmentPolicy.TryNormalize(intent.Card, out var card, out _) ||
            card?.Kind != ChatAttachmentKinds.FleetInvitation || card != intent.Card ||
            intent.RequestedAt > DateTimeOffset.UtcNow.AddMinutes(5)) return BeforeSend("dataInvalid");
        if (confirmOnly) return new("unknown", "outcomeUnknown");
        if (!await _write.WaitAsync(0, token)) return BeforeSend("busy");
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var posted = false;
        try
        {
            var state = await ReadWpfS2InvitationStateAsync(
                bearer, organizationRef, destination, scope, viewerId, current, token);
            if (!state.CanSend || state.EligibleRecipients <= 0) return new("rejected", "notAllowed");
            var inviteCode = intent.Card.FleetInviteCode?.Trim();
            if (string.IsNullOrEmpty(inviteCode) || !WpfS2InvitationRows(state.Fleet).Any(row =>
                    Text(row, "code", 40).Equals(inviteCode, StringComparison.OrdinalIgnoreCase) &&
                    Text(row, "status", 32).Equals("Active", StringComparison.OrdinalIgnoreCase) &&
                    row.GetProperty("expiresAt").GetDateTimeOffset() > DateTimeOffset.UtcNow))
                return new("rejected", "inviteInvalid");
            var path = destination.Channel == "private" ? "/api/friends/chat/messages" : "/api/party-rooms/chat";
            object body = destination.Channel == "private"
                ? new
                {
                    targetAccountId = destination.Id,
                    text = "",
                    attachment = intent.Card,
                    clientMessageId = intent.RequestId,
                    origin = "friend_center"
                }
                : new
                {
                    roomId = destination.Id,
                    text = "",
                    attachment = intent.Card
                };
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path))
            {
                Content = JsonContent.Create(body, body.GetType())
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            var sentAt = DateTimeOffset.UtcNow;
            lock (_inviteGate)
            {
                current();
                deadline.Token.ThrowIfCancellationRequested();
                if (epoch != _inviteEpoch) return BeforeSend("identityUnavailable");
                posted = true;
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (!response.IsSuccessStatusCode)
            {
                var reason = response.StatusCode switch
                {
                    HttpStatusCode.Unauthorized => "identityUnavailable",
                    HttpStatusCode.Forbidden => "notAllowed",
                    HttpStatusCode.NotFound => "refreshRequired",
                    HttpStatusCode.BadRequest or HttpStatusCode.Conflict => "dataInvalid",
                    HttpStatusCode.TooManyRequests => "rateLimited",
                    _ => "outcomeUnknown"
                };
                return new(reason == "outcomeUnknown" ? "unknown" : "rejected", reason);
            }
            using var document = await ReadBoundedJsonAsync(response, 2 * 1024 * 1024, deadline.Token);
            var root = document.RootElement;
            var message = root.GetProperty("message");
            if (message.ValueKind != JsonValueKind.Object) throw Invalid();
            var messageId = Text(message, "messageId", 128);
            var sequence = message.GetProperty("sequence").GetInt64();
            var created = message.GetProperty("createdAt").GetDateTimeOffset();
            var text = Text(message, "text", 4096, multiline: true);
            var sender = Optional(message, "senderAccountId", 512)?.Trim();
            var recipient = Optional(message, "recipientAccountId", 512)?.Trim();
            var attachment = message.GetProperty("attachment").Deserialize<ChatAttachmentContract>(
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (!ChatAttachmentPolicy.TryNormalize(attachment, out var normalized, out _) || normalized is null ||
                normalized.Kind != ChatAttachmentKinds.FleetInvitation || normalized.FleetInviteCode != intent.Card.FleetInviteCode ||
                normalized.Title != intent.Card.Title || normalized.Summary != intent.Card.Summary || normalized.ExpiresAt != intent.Card.ExpiresAt ||
                string.IsNullOrWhiteSpace(messageId) || sequence <= 0 || text.Length != 0 ||
                created < sentAt.AddMinutes(-5) || created > DateTimeOffset.UtcNow.AddMinutes(5) ||
                !string.IsNullOrEmpty(sender) && !sender.Equals(viewerId, StringComparison.OrdinalIgnoreCase) ||
                destination.Channel == "private" && (messageId != intent.RequestId || recipient != destination.Id)) throw Invalid();
            deadline.Token.ThrowIfCancellationRequested();
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            return new("sent", MessageId: messageId, Sequence: sequence, CreatedAt: created);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            JsonException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        {
            return new(posted ? "unknown" : "rejected", posted ? "outcomeUnknown" : "refreshRequired");
        }
        finally
        {
            _write.Release();
        }
    }

    private static JsonElement[] WpfS2InvitationRows(JsonElement fleet)
    {
        if (!fleet.TryGetProperty("invites", out var invites) || invites.ValueKind == JsonValueKind.Null) return [];
        if (invites.ValueKind != JsonValueKind.Array || invites.GetArrayLength() > 1000) throw Invalid();
        var rows = invites.EnumerateArray().ToArray();
        if (rows.Select(row => Text(row, "id", 128)).Distinct(StringComparer.OrdinalIgnoreCase).Count() != rows.Length)
            throw Invalid();
        return rows;
    }
}
