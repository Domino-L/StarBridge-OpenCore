using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetIdentityTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private const string Subject = "scm-v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static readonly object Query = new { schemaVersion = 1, sourceRef = "officialFleet:7", search = "", filter = "all", pageNumber = 1, pageSize = 50 };

    internal static async Task Run()
    {
        using var handler = new Handler();
        using var host = Host(handler);
        using var runtime = new AccountBridgeRuntime(host);
        var owner = host.CurrentContext!;
        async Task<BridgeEnvelope> Members() => (await runtime.DispatchAsync(
            BridgeEnvelope.Request("officialFleet.getMembers", Guid.NewGuid().ToString("N"), 1, Query, owner))).Response;
        var page = await Members();
        Check(page.Status == "ok", "Registered identity enrichment passes the actual product admission gate: " + page.Error?.Code);
        var rows = page.Payload.GetProperty("members");
        var linked = rows[0]; var unlinked = rows[1]; var restricted = rows[2];
        var reference = linked.GetProperty("profileTargetRef").GetString()!;
        Check(linked.GetProperty("callsign").GetString() == "Bridge Pilot" && Absent(linked, "avatarUrl") &&
            linked.GetProperty("identityState").GetString() == "starBridge" && linked.GetProperty("starBridgeConnected").GetBoolean() &&
            linked.GetProperty("presence").GetString() == "unknown", "StarBridge display identity never fabricates online state or retains the SCM avatar");
        Check(reference.Length == 64 && reference == linked.GetProperty("memberRef").GetString() &&
            !page.Payload.GetRawText().Contains(Subject) && !linked.TryGetProperty("userId", out _), "Only scoped opaque references cross Bridge");
        Check(unlinked.GetProperty("callsign").GetString() == "SCM-only Pilot" && unlinked.GetProperty("avatarUrl").GetString() == "https://robertsspaceindustries.com/scm.png" &&
            Absent(unlinked, "profileTargetRef"), "Confirmed unlinked members keep SCM presentation without a fake profile action");
        Check(restricted.GetProperty("callsign").GetString() == "—" && restricted.GetProperty("identityState").GetString() == "restricted" &&
            Absent(restricted, "avatarUrl") && Absent(restricted, "profileTargetRef") &&
            Absent(restricted, "starBridgeConnected"), "Privacy denial cannot fall back to SCM identity or expose a connected marker");
        object Target(string r, string source = "officialFleet:7") => new { schemaVersion = 1, source = "officialFleet", reference = r, contextRef = source };
        async Task<BridgeEnvelope> Profile(object target) => (await runtime.DispatchAsync(
            BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"), 1, target, owner))).Response;
        var profile = await Profile(Target(reference));
        Check(profile.Status == "ok" && handler.ProfileReads == 1 && handler.IdentityReads == 3,
            "Existing visitor card reads between two fresh fleet-link/privacy checks");
        var before = handler.ProfileReads;
        Check((await Profile(Target(new string('0', 64)))).Status == "error" &&
            (await Profile(Target(reference, "officialFleet:8"))).Status == "error" && handler.ProfileReads == before,
            "Guessed and cross-fleet references cannot resolve accounts");
        var social = await runtime.DispatchAsync(BridgeEnvelope.Request("users.social", "fleet-no-social", 1, Target(reference), owner));
        Check(social.Response.Status == "error" && handler.ProfileReads == before, "A fleet profile grants no social action authority");
        handler.State = "restricted";
        Check((await Profile(Target(reference))).Status == "error" && handler.ProfileReads == before, "A newly blocked/private member cannot use an older visible reference");
        handler.State = "visible";
        page = await Members(); reference = page.Payload.GetProperty("members")[0].GetProperty("profileTargetRef").GetString()!;
        handler.RevokeDuringProfile = true;
        Check((await Profile(Target(reference))).Status == "error", "Privacy changed during a slow visitor read cannot publish the profile");
        handler.RevokeDuringProfile = false;
        handler.State = "visible";
        foreach (var malformed in new[] { "missing", "duplicate", "wrongScope", "hiddenFields", "badAvatar", "unavailable" })
        {
            handler.Malformed = malformed;
            var rejected = await Members();
            Check(rejected.Status == "error" && rejected.Error is { Code: OfficialFleetMemberIdentity.Unavailable, Retryable: false },
                "Unknown, partial, corrupt and unavailable identity verdicts fail closed: " + malformed);
        }
        handler.Malformed = null;
        handler.Delay = true;
        var pending = Members();
        await handler.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        host.Dispose(); handler.Release.TrySetResult();
        Check((await pending).Status != "ok", "A retired owner cannot return a late identity page");
        Console.WriteLine("PASS official fleet registered identity projection, profile authority, privacy and late retirement");
        await SelfRow();
    }

    // Only the Java-verified visible row whose business subject is the viewer's own is marked;
    // a failed viewer identity read keeps the page and marks nobody.
    private static async Task SelfRow()
    {
        foreach (var (viewer, expectSelf) in new[] { (Subject, true), ("scm-v1:" + new string('b', 64), false), ((string?)null, false) })
        {
            using var handler = new Handler { Viewer = viewer };
            using var host = Host(handler);
            using var runtime = new AccountBridgeRuntime(host);
            async Task<BridgeEnvelope> Members() => (await runtime.DispatchAsync(
                BridgeEnvelope.Request("officialFleet.getMembers", Guid.NewGuid().ToString("N"), 1, Query, host.CurrentContext!))).Response;
            var page = await Members();
            Check(page.Status == "ok", "Viewer identity lookup never fails the member page: " + page.Error?.Code);
            var rows = page.Payload.GetProperty("members");
            Check((rows[0].TryGetProperty("isSelf", out var self) && self.GetBoolean()) == expectSelf &&
                Absent(rows[1], "isSelf") && Absent(rows[2], "isSelf") && !page.Payload.GetRawText().Contains(Subject),
                "Only the viewer's own visible row is marked, without exposing the subject: " + (viewer ?? "unavailable"));
            Check(handler.BusinessReads == 1, "Viewer business identity is read once per page attempt");
            page = await Members();
            Check(page.Status == "ok" && handler.BusinessReads == (viewer is null ? 2 : 1),
                "A verified viewer identity is reused for the same generation; failures are not cached");
            handler.State = "restricted";
            page = await Members();
            Check(page.Status == "ok" && page.Payload.GetProperty("members").EnumerateArray().All(row => Absent(row, "isSelf")) &&
                handler.BusinessReads == (viewer is null ? 2 : 1), "Without a visible linked row no viewer identity is read or marked");
        }
        Console.WriteLine("PASS official fleet self row is marked only from the viewer's verified business identity");
    }

    private static ScmAccountBridgeHost Host(HttpMessageHandler handler, PublicOrganizationLogoReader? logos = null)
    {
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "fixture", "fixture", "profile.read organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "organizations.read"]);
        return new(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options), new ScmProfileCacheStore(Path.GetTempPath()),
            "fixture", () => null, initialSession: session, initialGeneration: 1, publicOrganizationLogos: logos);
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static bool Absent(JsonElement row, string name) => !row.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null;
    private sealed class Vault : ITokenVault
    {
        public string? LoadRefreshToken(string a) => throw new Exception("No credential reads");
        public string? LoadActiveAccountKey() => throw new Exception("No credential reads");
        public void SaveRefreshToken(string a, string b) => throw new Exception("No credential writes");
        public void DeleteRefreshToken(string a) => throw new Exception("No credential deletion");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal string State = "visible";
        internal string? Malformed, Viewer;
        internal bool RevokeDuringProfile, Delay;
        internal int IdentityReads, ProfileReads, BusinessReads;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.IsLoopback, "Synthetic HTTP only");
            var path = Uri.UnescapeDataString(request.RequestUri.AbsolutePath);
            var authenticated = path.StartsWith("/app-api/starbridge/", StringComparison.Ordinal);
            Check(authenticated ? request.RequestUri.Port == 18082 && request.Headers.Authorization?.Parameter == "synthetic-access" :
                request.RequestUri.Port == 18080 && request.Headers.Authorization is null, "Public and resource credentials remain separate");
            if (path == "/app-api/starbridge/v1/bootstrap")
            {
                var fleet = new ScmBootstrapFleet(7, "ASTER", "Synthetic Aster", null, true, "Officer", 4, []);
                return Ok(new ScmBootstrapSnapshot(new("fixture-owner", "Synthetic", null, false), new(false, null), [fleet], fleet,
                    0, 1, new() { ["fleets"] = 1 }, DateTimeOffset.UtcNow, ["profile.read", "organizations.read"]));
            }
            if (path == "/app-api/starbridge/v1/business-identity")
            {
                BusinessReads++;
                Check(request.Method == HttpMethod.Get, "Viewer identity is a read");
                if (Viewer is null) return new(HttpStatusCode.ServiceUnavailable);
                return Ok(new { schemaVersion = 1, issuer = "fixture-issuer", subject = "fixture-owner", businessSubjectId = Viewer,
                    scopes = new[] { "profile.read", "organizations.read" } });
            }
            if (path == "/app-api/member/organization/member/page") return Ok(new { code = 0, data = new { total = 3, list = new[] {
                new { userId = 101, nickname = "Old SCM Pilot", avatar = "https://example.invalid/scm-old.png", organizationRank = "Officer" },
                new { userId = 102, nickname = "SCM-only Pilot", avatar = "https://robertsspaceindustries.com/scm.png", organizationRank = "Member" },
                new { userId = 103, nickname = "Private SCM Pilot", avatar = "https://example.invalid/secret.png", organizationRank = "Member" }
            } } });
            if (path == "/app-api/starbridge/v1/official-fleet/member-identities")
            {
                IdentityReads++;
                Check(request.Method == HttpMethod.Post, "Identity projection never registers accounts");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.GetProperty("sourceRef").GetString() == "officialFleet:7", "Identity request is scoped to verified fleet");
                if (Delay) { Started.TrySetResult(); await Release.Task.WaitAsync(token); }
                if (Malformed == "unavailable") return new(HttpStatusCode.ServiceUnavailable);
                var ids = body.RootElement.GetProperty("memberIds").EnumerateArray().Select(x => x.GetInt64()).ToArray();
                var members = ids.Select(id => id == 101 && State == "visible"
                    ? new OfficialFleetMemberIdentity(id, "visible", Subject, "Bridge Pilot", Malformed == "badAvatar" ? "data:image/png;base64,invalid" : null)
                    : new OfficialFleetMemberIdentity(id, id == 102 ? "unlinked" : State == "unlinked" && id == 101 ? "unlinked" : "restricted")).ToArray();
                if (Malformed == "missing") members = [];
                if (Malformed == "duplicate") members = [members[0], members[0], members[0]];
                if (Malformed == "hiddenFields") members[2] = new(103, "restricted", Subject, "Must stay hidden");
                return Ok(new { schemaVersion = 1, sourceRef = Malformed == "wrongScope" ? "officialFleet:8" : "officialFleet:7", members });
            }
            if (path == "/app-api/starbridge/v1/personal-profile/visitor/" + Subject)
            {
                ProfileReads++;
                if (RevokeDuringProfile) State = "restricted";
                var response = Ok(new PersonalProfileDocumentContract(3, "synthetic-public-profile", true, 1, DateTimeOffset.UtcNow,
                    new("Bridge Pilot", ""), PersonalProfileContentContract.Empty, null, Visibility: "public"));
                response.Headers.Add("X-StarBridge-Profile-Subject", Subject);
                return response;
            }
            throw new InvalidOperationException("Unexpected synthetic HTTP route");
        }
        private static HttpResponseMessage Ok(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value, options: Json) };
    }
}
