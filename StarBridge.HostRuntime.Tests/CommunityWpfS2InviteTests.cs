using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2InviteTests
{
    internal static async Task Verify()
    {
        using (var f = new Fixture())
        {
            var preview = await f.Preview();
            Check(!preview.AlreadyMember && !preview.MembershipConflict && f.Writes == 0, "S2 unjoined preview reads original routes");
            Check(!JsonSerializer.Serialize(preview).Contains("INVITE-SECRET"), "Do not echo the invitation credential");
            var calls = f.Calls;
            var request = Command(preview.PreviewRef);
            Check((await f.Client.AcceptInviteAsync("fixture", request, "other", () => { }, default)).Status == "rejected" && f.Calls == calls, "Cross-account reference rejected before transport");
            Check((await f.Accept(request)).Status == "accepted" && f.Writes == 1 && f.Member == "B", "Readback confirms original invite acceptance");
            await f.Accept(request);
            var fresh = await f.Preview();
            Check(fresh.AlreadyMember && (await f.Accept(Command(fresh.PreviewRef))).Status == "accepted" && f.Writes == 1, "Already joined or repeated intent never consumes twice");
        }
        using (var f = new Fixture { Member = "A" })
        {
            var preview = await f.Preview();
            Check(preview.MembershipConflict && !preview.AlreadyMember, "Preserve preview while exposing S2 single-membership restriction");
            Check((await f.Accept(Command(preview.PreviewRef))).Error == "membershipConflict" && f.Writes == 0, "Never leave another organization or consume its replacement invite");
        }
        using (var f = new Fixture())
        {
            var preview = await f.Preview();
            f.Member = "A";
            Check((await f.Accept(Command(preview.PreviewRef))).Error == "membershipConflict" && f.Writes == 0, "Membership checked again after preview");
            f.Client.InvalidateInvitePreviews();
            var before = f.Calls;
            Check((await f.Accept(Command(preview.PreviewRef))).Status == "rejected" && f.Calls == before, "Invalidated preview cannot recreate old authority");
        }
        foreach (var mode in new[] { "lost", "lost-joined", "unconfirmed", "readback-fails", "403" })
        {
            using var f = new Fixture();
            var preview = await f.Preview();
            f.Mode = mode;
            var request = Command(preview.PreviewRef);
            var result = await f.Accept(request);
            Check(result.Status == (mode == "403" ? "rejected" : "unknown"), "Truthful outcome " + mode);
            await f.Accept(request);
            Check(f.Writes == 1, "No repeat consumption " + mode);
            if (mode == "403") continue;
            f.Mode = "ok";
            var refreshed = await f.Preview();
            var reconciled = await f.Accept(Command(refreshed.PreviewRef));
            Check(f.Writes == 1, "New preview must not replay uncertain write " + mode);
            if (mode == "lost-joined") Check(reconciled.Status == "accepted", "Membership reconciliation confirms lost receipt without repost");
        }
        using (var f = new Fixture { Mode = "multi" })
        {
            try { await f.Preview(); throw new InvalidOperationException("Expected missing membership snapshot rejection"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
            Check(f.Writes == 0, "Incomplete multi-membership snapshots never authorize a write");
        }
    }
    private static JsonElement Command(string preview) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), previewRef = preview });
    private static void Check(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
    private sealed class Fixture : IDisposable
    {
        internal string? Member;
        internal string Mode = "ok";
        internal int Calls, Writes;
        internal readonly CommunityClient Client;
        internal Fixture() => Client = new(new Uri("https://fixture.invalid"), new Handler(this));
        internal async Task<CommunityInviteView> Preview() => (CommunityInviteView)await Client.PreviewInviteAsync("fixture",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, inviteCode = "INVITE-SECRET" }), "scope", () => { }, default, wpfS2: true);
        internal Task<CommunityCommand> Accept(JsonElement body) => Client.AcceptInviteAsync("fixture", body, "scope", () => { }, default);
        public void Dispose() => Client.Dispose();
        internal HttpResponseMessage Send(HttpRequestMessage request)
        {
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "fixture", "Original authenticated source");
            switch (request.RequestUri!.AbsolutePath)
            {
                case "/api/fleets/invites/preview":
                    Check(request.Method == HttpMethod.Post, "Existing read-only preview verb");
                    return Json(new { fleetCode = "B", fleetName = "Organization B", commander = "Owner", joinPolicy = "Invite", totalMembers = 3,
                        expiresAt = DateTimeOffset.UtcNow.AddHours(1), remainingUses = 5, acceptMode = "Direct" });
                case "/api/fleets/membership":
                    Check(request.Method == HttpMethod.Get, "Read-only membership");
                    if (Mode == "readback-fails" && Writes > 0) throw new HttpRequestException("fixture");
                    return Mode == "multi" ? Json(new { fleetCode = "A", fleetCodes = new[] { "A" } }) : Json(new { fleetCode = Member });
                case "/api/fleets":
                    Check(request.Method == HttpMethod.Get, "Read-only authorized snapshot");
                    return Json(new[] { new { code = Member, publicListingEnabled = false } });
                case "/api/fleets/invites/accept":
                    Check(request.Method == HttpMethod.Post, "Existing acceptance verb");
                    Writes++;
                    if (Mode == "403") return new(HttpStatusCode.Forbidden);
                    if (Mode is "ok" or "lost-joined") Member = "B";
                    if (Mode is "lost" or "lost-joined") throw new HttpRequestException("fixture");
                    return Json(new { privateBulkSnapshot = "must-not-be-used-as-receipt" });
                default: throw new InvalidOperationException("Unexpected route; no directory, player publication, leave or new API is permitted in this fixture");
            }
        }
        private static HttpResponseMessage Json(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private sealed class Handler(Fixture fixture) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(fixture.Send(request));
    }
}
