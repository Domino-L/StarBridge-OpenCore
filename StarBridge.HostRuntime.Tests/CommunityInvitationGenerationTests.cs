using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityInvitationGenerationTests
{
    internal static async Task Verify()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var target = (await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default)).Items.Single().TargetRef;
        var intent = new InvitationGenerationIntent(target, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, 1);
        Task<InvitationGenerationResult> Send(string scope = "account:1", Action? current = null) =>
            client.GenerateInvitationCardAsync("bearer", intent, scope, current ?? (() => { }), default);
        Check((await Send("other")).Status == "rejected" && handler.Bodies.Count == 0, "foreign account cannot resolve organization");
        handler.Version = 0;
        Check((await Send()).Error == "unavailable" && handler.Bodies.Count == 0, "older server never receives generation with ignored receipt fields");
        handler.Version = 1; handler.CanSend = false;
        Check((await Send()).Error == "notAllowed" && handler.Bodies.Count == 0, "ordinary code permission never grants card generation");
        handler.CanSend = true;
        handler.Mode = "lost";
        Check((await Send()).Status == "unknown" && handler.Bodies.Count == 1, "lost reply is unknown and never internally retried");
        handler.Mode = "ok";
        var recovered = await Send();
        Check(recovered.Status == "accepted" && recovered.Code == "INVITE-ABC" && handler.Bodies.Count == 2
            && handler.Bodies[0] == handler.Bodies[1], "reconciliation keeps original request id, timestamp and parameters");
        using (var data = JsonDocument.Parse(handler.Bodies[0]))
            Check(data.RootElement.GetProperty("purpose").GetString() == "card"
                && data.RootElement.GetProperty("expiresInDays").GetInt32() == 7
                && data.RootElement.GetProperty("fleetCode").GetString() == "A", "Host owns WPF card purpose/duration and resolves target code");
        foreach (var mode in new[] { "bulk", "wrong-id", "invalid-code", "invalid-invite", "expired", "wrong-status", "extra" })
        {
            handler.Mode = mode;
            Check((await Send()).Status == "unknown", "malformed/oversized success cannot authorize sending: " + mode);
        }
        handler.Mode = "unavailable";
        Check((await Send()).Error == "inviteInvalid", "revoked/pruned generation is terminal, not a new code");
        handler.Mode = "403";
        Check((await Send()).Error == "notAllowed", "server rechecks permission after preflight");
        handler.Mode = "503";
        Check((await Send()).Status == "unknown", "failure may follow a commit");
        handler.Mode = "ok";
        handler.OnAccess = client.InvalidateInvitePreviews;
        var before = handler.Bodies.Count;
        Check((await Send()).Status == "rejected" && handler.Bodies.Count == before, "account epoch invalidated before POST prevents generation");
        handler.OnAccess = null;
        var active = true;
        handler.OnPost = () => { active = false; client.InvalidateInvitePreviews(); };
        var late = await Send(current: () => { if (!active) throw new AccountBridgeHostException("communities.identityUnavailable"); });
        Check(late.Status == "unknown" && late.Code is null, "late response never exposes old-account code");
        handler.OnPost = null;
        foreach (var invalid in new[] { intent with { MaxUses = 0 }, intent with { MaxUses = 51 }, intent with { RequestId = "raw" } })
            Check((await client.GenerateInvitationCardAsync("bearer", invalid, "account:1", () => { }, default)).Error == "dataInvalid", "invalid internal intent rejected");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Version = 1;
        internal bool CanSend = true;
        internal string Mode = "ok";
        internal Action? OnAccess, OnPost;
        internal List<string> Bodies = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "bearer", "bearer preserved");
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Organization", description = "", language = "", activeTime = "", memberCount = 1,
                        relationship = "member", joinMode = "direct", actions = Array.Empty<string>() } } });
            if (request.Method == HttpMethod.Get)
            {
                Check(request.RequestUri!.PathAndQuery == "/api/fleets/admissions?code=A&section=access&offset=0", "card preflight never requests private invitation codes/applications");
                OnAccess?.Invoke();
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, code = "A", section = "access", inviteGenerationVersion = Version,
                    access = new { canSendInvitationCard = CanSend, canCreateInvite = !CanSend } });
            }
            Check(request.RequestUri!.PathAndQuery == "/api/fleets/invites?view=client", "only receipt-capable generation, no chat send yet");
            var body = await request.Content!.ReadAsStringAsync(token);
            Bodies.Add(body);
            OnPost?.Invoke();
            if (Mode == "lost") throw new HttpRequestException("Lost reply");
            if (int.TryParse(Mode, out var status)) return new((HttpStatusCode)status);
            if (Mode == "bulk") return Reply(new { privateSnapshot = new string('x', 5000) });
            using var parsed = JsonDocument.Parse(body);
            var fields = new Dictionary<string, object?> { ["schemaVersion"] = 1,
                ["status"] = Mode == "wrong-status" ? "ok" : Mode == "unavailable" ? "unavailable" : "accepted",
                ["requestId"] = Mode == "wrong-id" ? new string('b', 32) : parsed.RootElement.GetProperty("clientRequestId").GetString(),
                ["inviteId"] = Mode == "unavailable" ? null : Mode == "invalid-invite" ? "invalid" : new string('a', 32),
                ["code"] = Mode == "unavailable" ? null : Mode == "invalid-code" ? "BAD\nCODE" : "INVITE-ABC",
                ["expiresAt"] = Mode == "unavailable" ? null : DateTimeOffset.UtcNow.AddDays(Mode == "expired" ? -1 : 7) };
            if (Mode == "extra") fields["privateAccount"] = "never-forward";
            return Reply(fields);
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
