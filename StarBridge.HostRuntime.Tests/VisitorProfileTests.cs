using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task VisitorProfile()
    {
        using var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var directory = new VisitorDirectory();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), directory);
        using var host = CreateHost(client, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var context = host.CurrentContext!;
        var scope = JsonSerializer.Serialize(context) + ":" + host.Generation;
        var mine = (CommunityPage)await host.ReadCommunitiesAsync(context,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var target = mine.Items.Single().TargetRef;
        var roster = JsonSerializer.SerializeToElement(await host.ReadCommunityWorkspaceAsync(context,
            BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
        var peer = roster.GetProperty("members").EnumerateArray().Single(m => !m.GetProperty("isSelf").GetBoolean());
        var member = peer.GetProperty("memberRef").GetString()!;
        var payload = BridgePayload.From(new { schemaVersion = 1, targetRef = target, memberRef = member });
        Check(communities.ResolveVisitorProfileTarget(payload, scope, context.Subject) == "visitor-peer", "Host resolves the roster reference, not a display name");
        var document = new PersonalProfileDocumentContract(3, "visitor-peer", false, 2, DateTimeOffset.UtcNow,
            new("Peer", "Peer_Handle"), PersonalProfileContentContract.Empty with { Introduction = "Shared content" },
            null, new([]), null, Visibility: "friendsFleetAndOrganizations");
        transport.Body = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        using var dispatcher = new AccountBridgeDispatcher(host);
        using var product = new CompositeBridgeDispatcher(
            new HostBridgeDispatcher("visitor-product-route"), new AccountBridgeRuntime(host),
            new HostBridgeDispatcher("unused-preferences"));
        using var cancellation = new CancellationTokenSource();
        Task<AccountBridgeDispatchResult> Read(object body) => dispatcher.DispatchAsync(BridgeEnvelope.Request(
            "communities.memberPersonalProfile", Guid.NewGuid().ToString("N"), host.Generation, body, context), cancellation.Token);
        var result = await Read(payload);
        Check(result.Response.Error is null && !result.Response.Payload.GetProperty("editable").GetBoolean(), "visitor response is read-only");
        Check(result.Response.Payload.GetProperty("profile").GetProperty("content").GetProperty("introduction").GetString() == "Shared content",
            "server-authorized related audience is not hidden just because IsPublic is false");
        Check(transport.Path == "/api/profiles/visitor-peer" && transport.Authorized &&
            !result.Response.Payload.GetRawText().Contains("visitor-peer"), "authenticated visitor endpoint; internal target stays in Host");
        var before = transport.Calls;
        var avatarPayload = new { schemaVersion = 1, source = "community", reference = member, contextRef = target, query = "Peer_Handle" };
        var avatarResult = await product.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
            host.Generation, avatarPayload, context), default);
        Check(avatarResult.Response.Error is null && !avatarResult.Response.Payload.GetProperty("editable").GetBoolean(),
            "product avatar route must render authorized profile; error=" + avatarResult.Response.Error?.Code);
        // The public directory accepts organization logos up to 512 KiB. The
        // visitor route must not silently substitute the 96 KiB room-avatar cap.
        var png = Convert.FromBase64String(transport.DirectoryLogo);
        foreach (var size in new[] { 120 * 1024, 512 * 1024, 512 * 1024 + 1 })
        {
            var bytes = new byte[size];
            png.CopyTo(bytes, 0);
            transport.DirectoryLogo = Convert.ToBase64String(bytes);
            transport.Body = JsonSerializer.Serialize(document with {
                FleetAffiliation = new("Fixture", "TEST", null, "Member", "blue")
            }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            var projected = await product.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
                host.Generation, avatarPayload, context));
            Check(projected.Response.Error is null, "optional logo must not break the authorized profile");
            var affiliation = projected.Response.Payload.GetProperty("profile").GetProperty("fleetAffiliation");
            var logo = affiliation.TryGetProperty("logoImageData", out var value) ? value.GetString() : null;
            var expected = StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(transport.DirectoryLogo, 512 * 1024);
            Check(logo == expected, "visitor affiliation must retain exactly the directory logo budget, size=" + size);
        }
        transport.Body = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var self = roster.GetProperty("members").EnumerateArray().Single(m => m.GetProperty("isSelf").GetBoolean());
        var socialResult = await product.DispatchAsync(BridgeEnvelope.Request("users.social", Guid.NewGuid().ToString("N"),
            host.Generation, new { schemaVersion = 1, source = "community", reference = self.GetProperty("memberRef").GetString(), contextRef = target }, context));
        Check(socialResult.Response.Error is null && socialResult.Response.Payload.GetProperty("results")[0]
            .GetProperty("relationship").GetString() == "self", "product social route reaches the verified account owner");
        var unknown = await product.DispatchAsync(BridgeEnvelope.Request("users.unknown", Guid.NewGuid().ToString("N"),
            host.Generation, new { schemaVersion = 1 }, context));
        Check(unknown.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "unregistered user operations stay closed");
        before = transport.Calls;
        avatarResult = await product.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
            host.Generation, new { schemaVersion = 1, source = "community", reference = "visitor-peer", contextRef = target }, context), default);
        Check(avatarResult.Response.Error is not null && transport.Calls == before, "shared avatar route rejects raw IDs before HTTP");
        result = await Read(new { schemaVersion = 1, targetRef = target, memberRef = "visitor-peer" });
        Check(result.Response.Error is not null && transport.Calls == before, "raw ID is not an opaque reference");
        result = await Read(new { schemaVersion = 1, targetRef = target, memberRef = member, publicId = "other-user" });
        Check(result.Response.Error is not null && transport.Calls == before, "target injection rejected before HTTP");
        foreach (var status in new[] { HttpStatusCode.NotFound, HttpStatusCode.Forbidden })
        {
            transport.Status = status;
            result = await Read(payload);
            Check(result.Response.Error?.Code == "profile.visitor_not_visible", "missing and forbidden share a safe unavailable result");
            avatarResult = await product.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
                host.Generation, avatarPayload, context));
            Check(avatarResult.Response.Error?.Code == "profile.visitor_not_visible", "product route retains server visibility checks");
        }
        transport.Status = HttpStatusCode.OK;
        transport.Body = JsonSerializer.Serialize(document with { PublicId = context.Subject }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        result = await Read(payload);
        Check(result.Response.Error is not null, "wrong user's response must never appear as the visitor");
        transport.Body = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        transport.Pending = true;
        var pending = Read(payload);
        await transport.Started.Task;
        await host.LogoutAsync(context, default);
        // Dispatcher cancellation interrupts the request; a late success cannot cross generations.
        cancellation.Cancel();
        result = await pending;
        Check(result.Response.Error is not null, "account change drops pending visitor content");
    }

    private sealed class VisitorDirectory : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Method == HttpMethod.Get, "visitor fixture must remain read-only");
            object body = request.RequestUri!.AbsolutePath switch
            {
                "/api/fleets/membership" => new { fleetCode = "A" },
                "/api/fleets" => new[] { new {
                    code = "A", name = "Fixture", description = "", type = "", language = "", activeTime = "", totalMembers = 2,
                    lastUpdated = "2026-09-21T00:00:00Z",
                    members = new[] { "legacy-synthetic", "visitor-peer" }.Select(id => new {
                        accountId = id, gameName = "", callsign = "Fixture", roleTitle = "Member", online = false,
                        liveStatus = "Offline", ship = (string?)null, location = (string?)null,
                        lastUpdated = "2026-09-21T00:00:00Z", avatarImageData = (string?)null }).ToArray()
                } },
                _ => Array.Empty<object>(),
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }
}
