using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityInviteClientTests
{
    internal static async Task Verify()
    {
        await Lifecycle();
        await UncertainAndRejected();
        await LatePreview();
        await ConcurrentAndLateAcceptance();
    }

    private static async Task Lifecycle()
    {
        using var fixture = new Fixture();
        var preview = await fixture.Preview();
        Check(preview.Name == "Organization B" && preview.RemainingUses == 3 && !preview.AlreadyMember, "verified WPF preview fields");
        Check(!JsonSerializer.Serialize(preview).Contains("INVITE-B") && fixture.Writes == 0, "preview is read-only and does not echo invitation credential");
        var command = Command(preview.PreviewRef);
        var calls = fixture.Calls;
        Check((await fixture.Client.AcceptInviteAsync("bearer", command, "other:1", () => { }, default)).Status == "rejected" && fixture.Calls == calls,
            "preview reference cannot cross account scope");
        var result = await fixture.Accept(command);
        Check(result.Status == "accepted" && fixture.Writes == 1 && fixture.Joined, "join confirmed by scoped membership readback");
        Check((await fixture.Accept(command)).Status == "accepted" && fixture.Writes == 1, "same intent never consumes twice");
        var next = await fixture.Preview();
        Check(next.AlreadyMember && (await fixture.Accept(Command(next.PreviewRef))).Status == "accepted" && fixture.Writes == 1,
            "already in target never posts even with a fresh preview");
        var reused = JsonSerializer.SerializeToElement(new { schemaVersion = 1, requestId = command.GetProperty("requestId").GetString(), previewRef = next.PreviewRef });
        Check((await fixture.Accept(reused)).Error == "requestChanged", "cannot change target under same request ID");
        foreach (var invalid in new object[] { new { schemaVersion = 1, inviteCode = "" }, new { schemaVersion = 1, inviteCode = "A", fleetCode = "B" } })
            await Error(() => fixture.Client.PreviewInviteAsync("bearer", JsonSerializer.SerializeToElement(invalid), "viewer:1", () => { }, default), "communities.dataInvalid");
        Check(fixture.Writes == 1, "invalid requests never mutate");
    }

    private static async Task UncertainAndRejected()
    {
        foreach (var mode in new[] { "lost", "500", "404", "403", "401", "400", "readback-fails", "unconfirmed" })
        {
            using var fixture = new Fixture();
            var preview = await fixture.Preview();
            fixture.Mode = mode;
            var command = Command(preview.PreviewRef);
            var result = await fixture.Accept(command);
            var definitive = mode is "404" or "403" or "401" or "400";
            Check(result.Status == (definitive ? "rejected" : "unknown"), "truthful result: " + mode);
            await fixture.Accept(command);
            Check(fixture.Writes == 1, "same intent is never replayed: " + mode);
            if (definitive)
            {
                fixture.Mode = "ok";
                var recovered = await fixture.Preview();
                Check((await fixture.Accept(Command(recovered.PreviewRef))).Status == "accepted" && fixture.Writes == 2,
                    "new explicit intent can retry definitive refusal after recovery: " + mode);
                continue;
            }
            await fixture.Accept(Command(preview.PreviewRef));
            Check(fixture.Writes == 1, "no second POST under same or fresh intent: " + mode);
            fixture.Mode = "ok";
            var fresh = await fixture.Preview();
            await fixture.Accept(Command(fresh.PreviewRef));
            Check(fixture.Writes == 1, "re-preview of same invite cannot repeat uncertain consumption: " + mode);
        }
        foreach (var mode in new[] { "expired", "exhausted", "preview404", "huge", "bad-json", "wrong-mode" })
        {
            using var fixture = new Fixture { Mode = mode };
            await Error(() => fixture.Client.PreviewInviteAsync("bearer", PreviewBody(), "viewer:1", () => { }, default),
                mode is "huge" or "bad-json" ? "communities.dataInvalid" : "communities.inviteInvalid");
            Check(fixture.Writes == 0, "invalid preview never joins");
        }
    }

    private static async Task LatePreview()
    {
        using var fixture = new Fixture();
        fixture.HoldPreview = true;
        var pending = fixture.Preview();
        await fixture.Ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        fixture.Client.InvalidateInvitePreviews();
        fixture.Release.SetResult();
        await Error(async () => await pending, "communities.identityUnavailable");
        Check(fixture.Writes == 0, "late preview cannot recreate old account target");
    }

    private static async Task ConcurrentAndLateAcceptance()
    {
        using var fixture = new Fixture();
        var preview = await fixture.Preview();
        fixture.HoldAccept = true;
        var current = true;
        void Current() { if (!current) throw new AccountBridgeHostException("account.stale_generation"); }
        var pending = fixture.Client.AcceptInviteAsync("bearer", Command(preview.PreviewRef), "viewer:1", Current, default);
        await fixture.Ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            Check((await fixture.Accept(Command(preview.PreviewRef))).Error == "busy" && fixture.Writes == 1, "concurrent accept is rejected before transport");
            current = false;
            fixture.Client.InvalidateInvitePreviews();
        }
        finally { fixture.Release.SetResult(); }
        Check((await pending).Status == "unknown", "late accept cannot claim current account success");
        Check((await fixture.Accept(Command(preview.PreviewRef))).Status == "rejected", "old preview remains invalid after completion");
    }

    private static JsonElement PreviewBody() => JsonSerializer.SerializeToElement(new { schemaVersion = 1, inviteCode = " invite-b " });
    private static JsonElement Command(string previewRef) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), previewRef });
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static void Check(bool value, string why) { if (!value) throw new InvalidOperationException(why); }
    private static async Task Error(Func<Task<object>> call, string code)
    {
        try { await call(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException error) when (error.Code == code) { }
    }
    private sealed class Fixture : HttpMessageHandler
    {
        internal readonly CommunityClient Client;
        internal int Writes, Calls;
        internal bool Joined, HoldPreview, HoldAccept;
        internal string Mode = "ok";
        internal TaskCompletionSource Ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal Fixture() { Client = new(new Uri("https://community.invalid"), this); }
        internal async Task<CommunityInviteView> Preview() => (CommunityInviteView)await Client.PreviewInviteAsync("bearer", PreviewBody(), "viewer:1", () => { }, default);
        internal Task<CommunityCommand> Accept(JsonElement command) => Client.AcceptInviteAsync("bearer", command, "viewer:1", () => { }, default);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "bearer", "SCM bearer only");
            switch (request.RequestUri!.AbsolutePath)
            {
                case "/api/fleets/invites/preview":
                    var body = await request.Content!.ReadFromJsonAsync<JsonElement>(cancellationToken: token);
                    Check(body.EnumerateObject().Count() == 1 && body.GetProperty("inviteCode").GetString() == "INVITE-B", "WPF code normalization without extra fields");
                    if (HoldPreview) { Ready.SetResult(); await Release.Task; }
                    if (Mode == "preview404") return new(HttpStatusCode.NotFound);
                    if (Mode is "huge" or "bad-json") return new(HttpStatusCode.OK) { Content = new StringContent(Mode == "huge" ? new string('x', 17000) : "{") };
                    return Reply(new { fleetCode = "B", fleetName = "Organization B", commander = "Example owner", totalMembers = 3, joinPolicy = "Invite",
                        expiresAt = Mode == "expired" ? DateTimeOffset.UtcNow.AddMinutes(-1) : DateTimeOffset.UtcNow.AddHours(2),
                        remainingUses = Mode == "exhausted" ? 0 : 3, acceptMode = Mode == "wrong-mode" ? "Unknown" : "Direct", privateData = "never-forward" });
                case "/api/fleets/invites/accept":
                    Writes++;
                    var accept = await request.Content!.ReadFromJsonAsync<JsonElement>(cancellationToken: token);
                    Check(accept.EnumerateObject().Count() == 1 && accept.GetProperty("inviteCode").GetString() == "INVITE-B", "only Host-resolved invite is submitted");
                    if (HoldAccept) { Ready.SetResult(); await Release.Task; }
                    if (Mode == "lost") throw new HttpRequestException("lost reply");
                    if (int.TryParse(Mode, out var status)) return new((HttpStatusCode)status);
                    Joined = Mode != "unconfirmed";
                    return Reply(new { privateBulk = "do-not-forward" });
                case "/api/fleets/directory":
                    Check(request.Method == HttpMethod.Get && request.RequestUri.Query.Contains("view=mine") && request.RequestUri.Query.Contains("code=B"), "membership check is target-scoped, not old bulk query");
                    if (Mode == "readback-fails" && Writes > 0) return new(HttpStatusCode.ServiceUnavailable);
                    return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                        items = Joined ? new object[] { new { code = "B", name = "Organization B", description = "", language = "", activeTime = "", memberCount = 4,
                            relationship = "member", joinMode = "inviteOnly", actions = new[] { "leave" } } } : Array.Empty<object>() });
                default: throw new InvalidOperationException("Unexpected route");
            }
        }
    }
}
