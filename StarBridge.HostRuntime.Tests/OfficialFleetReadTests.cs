using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetReadTests
{
    private sealed class Vault : ITokenVault {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private sealed class Handler : HttpMessageHandler {
        internal Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>?>? Failure;
        internal int PublicReads;
        internal bool NoFleet, BadProfile, Duplicate;
        internal TaskCompletionSource? PublicStarted, PublicRelease;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            if (Failure?.Invoke(request, token) is { } injected) return await injected;
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/app-api/starbridge/v1/bootstrap") {
                Require(request.RequestUri.Port == 18082 && request.Headers.Authorization?.Parameter == "synthetic-access", "Bootstrap remains on the authenticated resource server");
                var fleet = new ScmBootstrapFleet(7, "ASTER", "Aster", null, true, "Officer", 4, []);
                return Ok(new ScmBootstrapSnapshot(new("fixture-owner", "Pilot", null, false), new(false, null),
                    NoFleet ? [] : [fleet], NoFleet ? null : fleet, 0, 1, new() { ["fleets"] = 1 }, DateTimeOffset.UtcNow, ["profile.read", "organizations.read"]));
            }
            if (path == "/app-api/starbridge/v1/official-fleet/member-identities") {
                Require(request.RequestUri.Port == 18082 && request.Headers.Authorization?.Parameter == "synthetic-access" &&
                    request.Method == HttpMethod.Post, "Only Java authorizes member identity linkage");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                return Ok(new { schemaVersion = 1, sourceRef = body.RootElement.GetProperty("sourceRef").GetString(),
                    members = body.RootElement.GetProperty("memberIds").EnumerateArray()
                        .Select(id => new { memberId = id.GetInt64(), state = "unlinked" }).ToArray() });
            }
            PublicReads++;
            Require(request.RequestUri.Port == 18080 && request.Headers.Authorization is null, "Public core contract receives no resource token");
            Require(request.Method == HttpMethod.Get, "Fleet slice only reads");
            if (path == "/app-api/member/organization/get") {
                return Ok(new { code = 0, data = new { id = BadProfile ? 8 : 7, sid = "ASTER", membersCount = 1286,
                    description = "<p>Explore &amp; build</p><script>unsafe()</script>", customDescription = "Supplement",
                    primaryFocus = "Exploration", language = "English", hasAdminPermission = true, stars = 5,
                    tags = new[] { new { name = "Exploration" } } } });
            }
            Require(path == "/app-api/member/organization/member/page", "Only the existing public organization directory is used");
            Require(request.RequestUri.Query.Contains("organizationSid=ASTER") && request.RequestUri.Query.Contains("orderBy=join_time"), "SID comes from verified membership; server handles sorting");
            if (PublicStarted is { } started) {
                started.TrySetResult();
                await PublicRelease!.Task.WaitAsync(token);
            }
            return Ok(new { code = 0, data = new { total = 51, list = new[] {
                new { userId = 101, nickname = "Pilot", organizationRank = "Member", signInStatus = 2, lastTime = 999 },
                new { userId = Duplicate ? 101 : 102, nickname = "Wing", organizationRank = "Officer", signInStatus = 1, lastTime = 999 }
            } } });
        }
        private static HttpResponseMessage Ok(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value, options: Json) };
    }
    private static ScmAccountBridgeHost Host(Handler handler, ITokenVault? vault = null) {
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["organizations.read", "profile.read"]);
        return new(new OAuthPkceClient(new ScmHttpClient(handler), vault ?? new Vault(), options),
            new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null, initialSession: session, initialGeneration: 1);
    }
    private static JsonElement Query(string source = "officialFleet:7", string filter = "all", int page = 1) =>
        JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = source, search = "Pilot & Wing", filter, pageNumber = page, pageSize = 50 });
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Reject(Func<Task> action, string reason) {
        try { await action(); } catch (AccountBridgeHostException) { return; }
        throw new InvalidOperationException(reason);
    }

    internal static async Task Run() {
        RunPublicRosterDecoder();
        await RunPublicRosterHttpReaderAsync();
        await PublicMemberIdCompatibility();
        OfficialFleetAvatarTests.Run();
        await OfficialFleetIdentityTests.Run();
        using var handler = new Handler();
        using var host = Host(handler);
        var owner = host.CurrentContext!;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var identity = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getCurrent", "fleet-identity", 1,
            new { schemaVersion = 1 }, owner));
        Require(identity.Response.Status == "ok", "Identity is available through the actual dispatcher");
        var fleet = identity.Response.Payload.GetProperty("fleet");
        Require((!fleet.TryGetProperty("officialRankValue", out var stars) || stars.ValueKind == JsonValueKind.Null) &&
            fleet.GetProperty("officialRankName").GetString() == "Officer",
            "SCM raw rank and public stars/admin flags cannot invent normalized RSI stars or permissions");
        var profile = fleet.GetProperty("profile");
        Require(profile.GetProperty("memberCount").GetInt32() == 1286 &&
            profile.GetProperty("rsiDescription").GetString() == "Explore & build" &&
            !profile.TryGetProperty("hasAdminPermission", out _), "Profile remains bounded public content with HTML reduced to text");
        var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getMembers", "fleet-page", 1, Query(page: 2), owner));
        Require(response.Response.Status == "ok", "Members use the product dispatcher route");
        var page = response.Response.Payload;
        Require(page.GetProperty("coverage").GetString() == "scmRegisteredMembers" && page.GetProperty("totalPages").GetInt32() == 2,
            "SCM registered matches are paginated without claiming complete official coverage");
        var member = page.GetProperty("members")[0];
        Require(member.GetProperty("presence").GetString() == "unknown" && member.GetProperty("gameId").GetString() == "" &&
            (!member.TryGetProperty("starBridgeConnected", out var connected) || connected.ValueKind == JsonValueKind.Null) &&
            member.GetProperty("memberRef").GetString()!.Length == 64 && !member.TryGetProperty("userId", out _),
            "No SCM sign-in presence, invented Handle or raw user id reaches Flutter");
        var nextPage = JsonSerializer.SerializeToElement(await host.GetOfficialFleetMembersAsync(owner, Query(), default), Json);
        Require(nextPage.GetProperty("members")[0].GetProperty("memberRef").GetString() == member.GetProperty("memberRef").GetString(), "Opaque references survive same-context pagination");
        var reads = handler.PublicReads;
        await Reject(async () => { await host.GetOfficialFleetMembersAsync(owner, Query("officialFleet:99"), default); }, "Forged source must fail");
        await Reject(async () => { await host.GetOfficialFleetMembersAsync(owner, Query(filter: "online"), default); }, "Unsupported StarBridge presence filter must fail");
        Require(handler.PublicReads == reads, "Forged sources and filters do not query the public directory");
        handler.NoFleet = true;
        await Reject(async () => { await host.GetOfficialFleetMembersAsync(owner, Query(), default); }, "Removed membership must fail");
        handler.NoFleet = false;
        handler.Duplicate = true;
        await Reject(async () => { await host.GetOfficialFleetMembersAsync(owner, Query(), default); }, "Duplicate source identities must fail");
        handler.Duplicate = false;
        handler.BadProfile = true;
        Require((await host.GetOfficialFleetAsync(owner, default)).Fleet is { Profile: null }, "Optional profile failure preserves verified membership");
        handler.PublicStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.PublicRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var delayed = host.GetOfficialFleetMembersAsync(owner, Query(), default);
        await handler.PublicStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        host.Dispose();
        handler.PublicRelease.SetResult();
        await Reject(async () => { await delayed; }, "Retired owner cannot publish a late page");
    }
}
