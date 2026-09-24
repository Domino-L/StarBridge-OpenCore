using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class CommunityMemberSharingTests
{
    internal static async Task Verify()
    {
        var joined = new DateTimeOffset(2026, 9, 1, 0, 0, 0, TimeSpan.Zero);
        var scope = new CommunityRealtimeScope("A", joined, CommunityRealtimeScope.SupportedFields, false, false, [],
            [new("fixture-member", joined, PlayerSharedStateFields.Ship)]);
        var owner = new BridgeAccountContext("test", "privacy.invalid", "fixture-owner");
        var input = new PrivacyPublicationInput(owner, 1, "Fixture_Handle", true, "LIVE",
            new(new("connected", "US", "fixture-server"), new("confirmed", "Orison"), new("confirmed", "fixture", "Fixture Ship")));
        var settings = LocalPrivacySettings.EditorDefaults with { Communities = [scope], Room = new(0, false) };
        var payload = PrivacyPublicationPayload.Build(input, settings, false);
        Check(payload.GetProperty("ship").GetString() == "Fixture Ship" &&
            payload.GetProperty("location").GetString() == "Unknown", "only individually allowed fields uploaded");
        var mode = "ok";
        using var writer = new PrivacyRelayWriter(new Uri("https://privacy.invalid"), new Handler(async (request, token) => {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new CommunitySharingTargets(2, "A", [new("A", "A", joined)]), options: LocalPrivacyStore.Json) };
            if (request.RequestUri!.AbsolutePath.EndsWith("/community-members/read"))
            {
                if (mode == "unsupported") return new(HttpStatusCode.NotFound);
                if (mode == "changed") return new(HttpStatusCode.Conflict);
                var row = new CommunityMemberSharingTarget("fixture-member", joined, "Member", "Member_Handle", false, false, 0);
                var page = new CommunityMemberDirectoryPage(3, "A", joined, new string('A', 64), 0, 1, [row]);
                if (mode == "short") page = page with { Total = 2 };
                if (mode == "duplicate") page = page with { Total = 2, Members = [row, row] };
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(page, options: LocalPrivacyStore.Json) };
            }
            var body = JsonNode.Parse(await request.Content!.ReadAsStringAsync(token))!.AsObject();
            Check(body["schemaVersion"]!.GetValue<int>() == 3, "individual grant requires version 3");
            if (mode == "drop") body["communities"]![0]!.AsObject().Remove("memberOverrides");
            if (mode == "broaden") body["communities"]![0]!["memberOverrides"]![0]!["fields"] = 15;
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
            response.Headers.Add("X-StarBridge-Realtime-Version", mode == "downgrade" ? "2" : "3");
            return response;
        }));
        await writer.SendAsync("fixture", payload, default);
        foreach (var failure in new[] { "drop", "broaden", "downgrade" })
        {
            mode = failure;
            await Reject(() => writer.SendAsync("fixture", payload, default), "privacy_publication.response_invalid");
        }
        mode = "ok";
        var request = new CommunityMemberDirectoryRequest(3, scope);
        Check((await writer.ReadCommunityMembersAsync("fixture", request, default)).Members.Length == 1, "directory read");
        foreach (var failure in new[] { "short", "duplicate" })
        {
            mode = failure;
            await Reject(() => writer.ReadCommunityMembersAsync("fixture", request, default), "privacy_publication.response_invalid");
        }
        mode = "unsupported";
        await Reject(() => writer.ReadCommunityMembersAsync("fixture", request, default), "privacy_publication.member_scopes_unavailable");
        mode = "changed";
        await Reject(() => writer.ReadCommunityMembersAsync("fixture", request, default), "privacy_publication.members_changed");
        var current = (Context: (BridgeAccountContext?)owner, Generation: 1L);
        var reads = 0;
        var bridge = new CommunitySharingDispatcher(() => current,
            (_, _, _) => Task.FromResult(new CommunitySharingTargets(2, "A", [])),
            (_, _, _, _) => {
                reads++;
                current = (owner with { Subject = "other" }, 2);
                return Task.FromResult(new CommunityMemberDirectoryPage(3, "A", joined, new string('A', 64), 0, 0, []));
            });
        var envelope = BridgeEnvelope.Request("privacy.communityMembers", Guid.NewGuid().ToString("N"), 1, request, owner);
        Check((await bridge.DispatchAsync(envelope, default)).Response.Error?.Code == "privacy_publication.account_changed", "read result discarded after account switch");
        await bridge.DispatchAsync(envelope, default);
        Check(reads == 1, "stale request does not invoke directory");
    }
    private static async Task Reject(Func<Task> action, string code)
    { try { await action(); } catch (AccountBridgeHostException error) when (error.Code == code) { return; } throw new Exception("Expected " + code); }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }
}
