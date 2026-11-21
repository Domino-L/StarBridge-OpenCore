using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ShowcaseRelayVisitor(string kind)
    {
        using var transport = new ShowcaseRelayTransport();
        using var client = new LegacyPasswordLoginClient(new Uri("http://127.0.0.1:9/"), new Store(), transport);
        using var directory = new VisitorDirectory();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), directory);
        using var host = CreateHost(client, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var owner = host.CurrentContext!;
        var mine = (CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var target = mine.Items.Single().TargetRef;
        var roster = JsonSerializer.SerializeToElement(await host.ReadCommunityWorkspaceAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
        var member = roster.GetProperty("members").EnumerateArray().Single(m => !m.GetProperty("isSelf").GetBoolean())
            .GetProperty("memberRef").GetString();
        var page = JsonSerializer.SerializeToNode(new PersonalProfileDocumentContract(3, "visitor-peer", false, 7,
            DateTimeOffset.UnixEpoch, new("Synthetic", ""), ProfileShowcaseTests.Content, null), ProfileShowcaseTests.Web)!.AsObject();
        if (kind != "absent") page["publicAchievements"] = JsonNode.Parse(kind switch
        {
            "valid" => "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
            "empty" => "[]",
            "invalid-id" => "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00Z\"},{\"id\":\"BAD\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
            "over-limit" => JsonSerializer.Serialize(Enumerable.Range(1, 10).Select(i => new { id = "a-" + i, earnedAt = "2026-11-01T12:00:00Z" })),
            "non-utc" => "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00+01:00\"}]",
            "bad-date" => "[{\"id\":\"journey-area18\",\"earnedAt\":\"not-a-date\"}]",
            _ => throw new ArgumentException("Unknown relay showcase fixture.", nameof(kind))
        });
        transport.Page = page.ToJsonString();
        var log = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
        var before = File.Exists(log) ? File.ReadAllLines(log).Length : 0;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", "relay-showcase-" + kind,
            host.Generation, new { schemaVersion = 1, source = "community", reference = member, contextRef = target }, owner))).Response;
        Check(response.Error is null && !response.Payload.GetProperty("editable").GetBoolean(),
            "relay visitor page failed: " + kind + " " + response.Error?.Code);
        var wire = response.Payload.GetProperty("profile");
        Check(wire.GetProperty("content").GetProperty("showcases")[0].GetProperty("id").GetString() == "achievements" &&
            (!wire.GetProperty("content").TryGetProperty("achievementShowcase", out var selections) || selections.ValueKind == JsonValueKind.Null),
            "relay visitor leaked owner achievement selections or lost showcase layout");
        Check(wire.TryGetProperty("publicAchievements", out var achievements) == (kind is "valid" or "empty"),
            "relay visitor forwarded invalid public achievements: " + kind);
        if (kind == "valid") Check(achievements.GetArrayLength() == 1 &&
            achievements[0].GetProperty("id").GetString() == "journey-area18" &&
            achievements[0].GetProperty("earnedAt").GetDateTimeOffset() == DateTimeOffset.Parse("2026-11-01T12:00:00Z"),
            "relay visitor changed a valid achievement");
        if (kind == "empty") Check(achievements.GetArrayLength() == 0, "relay visitor lost an explicit empty list");
        var diagnostics = File.Exists(log) ? File.ReadAllLines(log).Skip(before)
            .Where(line => line.Contains("step=visitor-public-achievements")).ToArray() : [];
        var invalid = kind is not ("valid" or "empty" or "absent");
        Check(diagnostics.Length == (invalid ? 1 : 0) && diagnostics.All(line =>
            line.EndsWith("step=visitor-public-achievements outcome=discarded")),
            "relay visitor diagnostic missing or contains user data");
        Check(transport.VisitorReads == 1, "relay visitor repeated the request");
    }

    private sealed class ShowcaseRelayTransport : HttpMessageHandler
    {
        internal string Page = "{}";
        internal int VisitorReads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.IsLoopback && request.RequestUri.Port == 9, "non-synthetic relay request");
            var body = request.RequestUri.AbsolutePath switch
            {
                "/api/auth/login" when request.Method == HttpMethod.Post => Transport.Valid,
                "/api/profiles/visitor-peer" when request.Method == HttpMethod.Get => ReadPage(),
                _ => throw new Exception("Unexpected relay showcase request")
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
        private string ReadPage() { VisitorReads++; return Page; }
    }
}
