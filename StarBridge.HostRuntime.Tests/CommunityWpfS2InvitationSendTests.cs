using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2InvitationSendTests
{
    internal static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-wpf-invitation-").FullName;
        using var handler = new Handler();
        using var client = new CommunityClient(
            new Uri("https://legacy.invalid"),
            handler,
            invitationJournal: new InvitationOutboxJournal(root));
        const string scope = "legacy-scope";
        const string viewer = "self";
        var source = (await client.ReadWpfS2Async("legacy", new("mine", "", null, null), scope, viewer, default))
            .Items.Single().TargetRef;
        var direct = new InvitationDeliveryTarget("private", "recipient", scope, new Uri("https://legacy.invalid"), "Recipient");

        var preview = await client.PreviewWpfS2InvitationTargetAsync(
            "legacy", source, direct, scope, viewer, () => { }, default);
        Check(preview.CanSend && preview.EligibleRecipients == 1, "S2 private preview uses the original roster and card policy");
        var directId = Guid.NewGuid().ToString("N");
        var sent = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", directId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        Check(sent.Status == "sent" && handler.GenerationPosts == 1 && handler.DirectPosts == 1,
            "S2 private invitation generates and sends through original routes");
        Check(handler.GenerationHasNoClientReceiptFields && handler.DirectUsesOriginalShape,
            "S2 requests retain the original WPF wire shape");
        await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", directId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        Check(handler.GenerationPosts == 1 && handler.DirectPosts == 1, "confirmed S2 invitation is never replayed");

        handler.RecipientIsMember = true;
        var blocked = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", Guid.NewGuid().ToString("N"), source, direct, 1, "advance", scope, viewer, () => { }, default);
        Check(blocked.Status == "rejected" && blocked.Error == "notAllowed" && handler.GenerationPosts == 1,
            "existing organization member is rejected before invite generation");
        handler.RecipientIsMember = false;

        handler.GenerationMode = "lost";
        var generationId = Guid.NewGuid().ToString("N");
        var unknownGeneration = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", generationId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        var generations = handler.GenerationPosts;
        Check(unknownGeneration.Status == "unknown", "lost old-generation response remains unknown");
        var frozenGeneration = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", generationId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        Check(frozenGeneration.Status == "unknown" && handler.GenerationPosts == generations,
            "non-idempotent old generation is frozen instead of replayed");

        handler.GenerationMode = "ok";
        handler.DeliveryMode = "lost";
        var deliveryId = Guid.NewGuid().ToString("N");
        var unknownDelivery = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", deliveryId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        var deliveries = handler.DirectPosts;
        Check(unknownDelivery.Status == "unknown", "lost old-delivery response remains unknown");
        var frozenDelivery = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", deliveryId, source, direct, 1, "retryDelivery", scope, viewer, () => { }, default);
        Check(frozenDelivery.Status == "unknown" && handler.DirectPosts == deliveries,
            "old delivery without confirmation support is not replayed even after recovery request");

        handler.DeliveryMode = "ok";
        var room = new InvitationDeliveryTarget("room", "room-one", scope, new Uri("https://legacy.invalid"), "Room")
        {
            RecipientAccountIds = [viewer, "member", "outside-a", "outside-b", "outside-a"]
        };
        preview = await client.PreviewWpfS2InvitationTargetAsync(
            "legacy", source, room, scope, viewer, () => { }, default);
        Check(preview.CanSend && preview.EligibleRecipients == 2, "S2 room preview excludes self, organization members and duplicates");
        var roomSent = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", Guid.NewGuid().ToString("N"), source, room, 2, "advance", scope, viewer, () => { }, default);
        Check(roomSent.Status == "sent" && handler.RoomPosts == 1 && handler.RoomUsesOriginalShape,
            "S2 room invitation uses the original room chat attachment contract");

        handler.AfterGenerationWrite = client.InvalidateInvitePreviews;
        var switchedId = Guid.NewGuid().ToString("N");
        var switched = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", switchedId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        var switchedPosts = handler.GenerationPosts;
        Check(switched.Status == "unknown", "account invalidation after the old generation write cannot be reported as success");
        switched = await client.AdvanceWpfS2InvitationSendAsync(
            "legacy", "account", switchedId, source, direct, 1, "advance", scope, viewer, () => { }, default);
        Check(switched.Status == "unknown" && handler.GenerationPosts == switchedPosts,
            "account invalidation keeps the uncertain old generation frozen");
        handler.AfterGenerationWrite = null;

        handler.Policy = "commander";
        preview = await client.PreviewWpfS2InvitationTargetAsync(
            "legacy", source, direct, scope, viewer, () => { }, default);
        Check(!preview.CanSend, "restricted card policy does not infer commander permission from membership");
        handler.Owner = viewer;
        preview = await client.PreviewWpfS2InvitationTargetAsync(
            "legacy", source, direct, scope, viewer, () => { }, default);
        Check(preview.CanSend, "authenticated owner satisfies the original commander card policy");
    }

    private sealed class Handler : HttpMessageHandler
    {
        private readonly List<Invite> _invites = [];
        internal int GenerationPosts, DirectPosts, RoomPosts;
        internal bool RecipientIsMember;
        internal string GenerationMode = "ok", DeliveryMode = "ok", Policy = "all_members", Owner = "other-owner";
        internal bool GenerationHasNoClientReceiptFields = true, DirectUsesOriginalShape = true, RoomUsesOriginalShape = true;
        internal Action? AfterGenerationWrite;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "legacy", "legacy bearer remains scoped");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                return path switch
                {
                    "/api/fleets/membership" => Reply(new { fleetCode = "A" }),
                    "/api/fleets" => Reply(new[] { Fleet() }),
                    "/api/auth/session" => Reply(new { accountId = "self", userName = "owner-user" }),
                    _ => throw new InvalidOperationException("Unexpected GET " + path)
                };
            }
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            if (path == "/api/fleets/invites")
            {
                GenerationPosts++;
                GenerationHasNoClientReceiptFields &= request.RequestUri.Query.Length == 0 &&
                    !body.RootElement.TryGetProperty("clientRequestId", out _) &&
                    !body.RootElement.TryGetProperty("clientRequestedAt", out _) &&
                    body.RootElement.GetProperty("purpose").GetString() == "card";
                if (GenerationMode == "lost") throw new HttpRequestException("lost generation response");
                foreach (var invite in _invites) invite.Status = "Revoked";
                _invites.Add(new(Guid.NewGuid().ToString("N"), "INVITE-" + (_invites.Count + 1), DateTimeOffset.UtcNow,
                    DateTimeOffset.UtcNow.AddDays(7), body.RootElement.GetProperty("maxUses").GetInt32(), "Active"));
                AfterGenerationWrite?.Invoke();
                return Reply(Fleet());
            }
            if (path is not ("/api/friends/chat/messages" or "/api/party-rooms/chat"))
                throw new InvalidOperationException("Unexpected POST " + path);
            var direct = path == "/api/friends/chat/messages";
            if (direct)
            {
                DirectPosts++;
                DirectUsesOriginalShape &= request.RequestUri.Query.Length == 0 &&
                    !body.RootElement.TryGetProperty("clientRequestedAt", out _) &&
                    !body.RootElement.TryGetProperty("confirmOnly", out _);
            }
            else
            {
                RoomPosts++;
                RoomUsesOriginalShape &= request.RequestUri.Query.Length == 0 &&
                    !body.RootElement.TryGetProperty("clientMessageId", out _) &&
                    !body.RootElement.TryGetProperty("clientRequestedAt", out _) &&
                    !body.RootElement.TryGetProperty("confirmOnly", out _);
            }
            if (DeliveryMode == "lost") throw new HttpRequestException("lost delivery response");
            var id = direct ? body.RootElement.GetProperty("clientMessageId").GetString()! : Guid.NewGuid().ToString("N");
            var attachment = body.RootElement.GetProperty("attachment").Clone();
            return Reply(new
            {
                status = "sent",
                error = (string?)null,
                message = new
                {
                    sequence = 9,
                    messageId = id,
                    senderAccountId = "self",
                    recipientAccountId = direct ? "recipient" : null,
                    text = "",
                    createdAt = DateTimeOffset.UtcNow,
                    attachment
                }
            });
        }

        private object Fleet() => new
        {
            name = "Organization",
            code = "A",
            commander = "Owner",
            description = "",
            type = "PVP",
            activeTime = "19:00 - 22:00",
            joinPolicy = "Open",
            logoImageData = (string?)null,
            totalMembers = RecipientIsMember ? 3 : 2,
            ownerAccount = Owner,
            members = RecipientIsMember
                ? new[] { new { accountId = "self" }, new { accountId = "member" }, new { accountId = "recipient" } }
                : new[] { new { accountId = "self" }, new { accountId = "member" } },
            memberPermissions = Array.Empty<object>(),
            fleetInvitationCardPolicy = Policy,
            invites = _invites.Select(invite => new
            {
                id = invite.Id,
                code = invite.Code,
                createdBy = "Pilot",
                createdAt = invite.CreatedAt,
                expiresAt = invite.ExpiresAt,
                maxUses = invite.MaxUses,
                usedCount = 0,
                status = invite.Status,
                acceptMode = "Direct",
                createdByAccount = "owner-user"
            }).ToArray(),
            language = "zh-CN",
            activeSystemIds = new[] { "stanton" }
        };

        private sealed class Invite(string id, string code, DateTimeOffset createdAt, DateTimeOffset expiresAt, int maxUses, string status)
        {
            internal string Id { get; } = id;
            internal string Code { get; } = code;
            internal DateTimeOffset CreatedAt { get; } = createdAt;
            internal DateTimeOffset ExpiresAt { get; } = expiresAt;
            internal int MaxUses { get; } = maxUses;
            internal string Status { get; set; } = status;
        }
        private static HttpResponseMessage Reply(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
