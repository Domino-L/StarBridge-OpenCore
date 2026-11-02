using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;

internal static class OfficialFleetIdentityObservationTests
{
    internal static async Task Run(string? fixtureDirectory = null)
    {
        await OfficialFleetIdentityTests.Run();
        var initial = DateTimeOffset.Parse("2026-10-17T12:00:00Z");
        var clock = new Clock { Now = initial };
        using var handler = new Handler(clock);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api",
            "profile.read organizations.read", "/oauth/callback");
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options)
            { OfficialFleetIdentityObservationClock = clock };
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "organizations.read"]);
        var first = await oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", Enumerable.Range(1, 100).Select(i => (long)i).ToArray(), default);
        Check(first.Result.Count == 100 && first.Result.Values.All(r => r.IdentityValidUntilUtc == initial.AddSeconds(5)) && handler.ValidRequest,
            "actual V2 transport negotiates the exact same trusted route and preserves every source deadline");
        clock.Now = initial.AddSeconds(3);
        OfficialFleetMemberIdentityObservation.EnsureCurrent(first.Result.Values, clock.Now);
        Check(first.Result[1].Identity.Callsign == "Bridge Pilot1", "last observation within its original TTL is not an atomic revocation guarantee");
        clock.Now = initial.AddSeconds(6);
        var last = await oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", [101], default);
        Check(last.Result[101].IdentityValidUntilUtc == initial.AddSeconds(11), "later batch has its independently observed deadline");
        Refuses(() => OfficialFleetMemberIdentityObservation.EnsureCurrent(first.Result.Values.Concat(last.Result.Values), clock.Now),
            "101 owners cannot reuse an expired original deadline after a later batch; no receipt-time TTL renewal");
        Check(first.Result[1].IdentityValidUntilUtc == initial.AddSeconds(5), "final checks never overwrite original source timestamps");
        clock.Now = initial;
        using var validDocument = JsonDocument.Parse(handler.Body([42]));
        var valid = validDocument.RootElement.GetRawText().Replace("\\u002B", "+");
        foreach (var invalid in new[] {
            valid.Replace("\"schemaVersion\":2", "\"schemaVersion\":1"),
            valid.Replace("officialFleet:7", "officialFleet:8"),
            valid.Replace("2026-10-17T12:00:00.0000000+00:00", "2026-10-17T12:00:00"),
            valid.Replace("+00:00", "+01:00"),
            valid.Replace("+00:00", "Z\\n"),
            valid.Replace("12:00:05", "12:00:06"),
            valid.Replace("12:00:00", "12:00:02"),
            valid.Replace("12:00:05", "12:00:00"),
            valid.Replace("\"identityObservedAtUtc\":", "\"identityObservedAtUtc\":\"2026-10-17T12:00:00Z\",\"identityObservedAtUtc\":"),
            valid.Replace("\"visible\"", "\"restricted\""),
        }) {
            Check(invalid != valid, "Each negative fixture must actually mutate the valid transport");
            Refuses(() => Parse(invalid, [42], clock.Now), "invalid negotiation, UTC, deadline, duplicate or privacy state is rejected");
        }
        Refuses(() => Parse(valid, [42], initial.AddSeconds(5)), "deadline equality is expired before exposure");
        _ = Parse(valid.Replace("+00:00", "Z"), [42], clock.Now);
        if (fixtureDirectory is not null)
        {
            foreach (var (file, ids, state) in new[] {
                ("identities-single-visible.json", new long[]{42}, "visible"),
                ("identities-single-restricted.json", new long[]{42}, "restricted"),
                ("identities-single-unlinked.json", new long[]{43}, "unlinked"),
            })
            {
                handler.Override = File.ReadAllText(Path.Combine(fixtureDirectory, file));
                var real = await oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", ids, default);
                Check(real.Result[ids[0]].Identity.State == state && real.Result[ids[0]].IdentityValidUntilUtc == initial.AddSeconds(5),
                    "unchanged actual Java V2 bytes pass the real OAuth reader with the original observation deadline");
                if (state != "visible") Check(real.Result[ids[0]].Identity is { Callsign: null, BusinessSubjectId: null, AvatarImageData: null },
                    "negative V2 observations never carry a name, profile target or avatar");
            }
            handler.Override = File.ReadAllText(Path.Combine(fixtureDirectory, "identities-v1-unchanged.json"));
            var refused = false;
            try { await oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", [42], default); }
            catch (AccountBridgeHostException error) when (error.Code == OfficialFleetMemberIdentity.Unavailable) { refused = true; }
            Check(refused, "old Java schema1 cannot silently satisfy the explicit V2 caller");
            handler.Override = null;
        }
        var calls = handler.Calls;
        Refuses(() => oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", Enumerable.Range(1, 101).Select(i => (long)i).ToArray(), default),
            "V2 preserves the upstream100 member limit before HTTP");
        Check(handler.Calls == calls, "invalid cardinality never sends a credential");
        Console.WriteLine("PASS G1 V2 exact negotiation/UTC/privacy and actual101-owner original deadline expiry; V1 regression preserved");
    }

    private static IReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation> Parse(string text, long[] ids, DateTimeOffset now)
    { using var document = JsonDocument.Parse(text); return OfficialFleetMemberIdentityObservation.Parse(document.RootElement, "officialFleet:7", ids, now); }
    private static void Refuses(Action action, string message)
    { try { action(); } catch (AccountBridgeHostException error) when (error.Code == OfficialFleetMemberIdentity.Unavailable) { return; } throw new Exception(message); }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Clock : TimeProvider { internal DateTimeOffset Now; public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Vault : ITokenVault {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null; public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class Handler(Clock clock) : HttpMessageHandler
    {
        internal int Calls; internal bool ValidRequest; internal string? Override;
        internal string Body(long[] ids) => JsonSerializer.Serialize(new { schemaVersion = 2, sourceRef = "officialFleet:7", members = ids.Select(id => new {
            memberId = id, state = "visible", businessSubjectId = "scm-v1:" + id.ToString("x64"), callsign = "Bridge Pilot" + id,
            identityObservedAtUtc = clock.Now.ToString("O"), identityValidUntilUtc = clock.Now.AddSeconds(5).ToString("O") }) });
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; token.ThrowIfCancellationRequested();
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var ids = body.RootElement.GetProperty("memberIds").EnumerateArray().Select(id => id.GetInt64()).ToArray();
            ValidRequest = request.RequestUri!.AbsoluteUri == "http://127.0.0.1:18082/app-api/starbridge/v1/official-fleet/member-identities" &&
                request.Method == HttpMethod.Post && request.Headers.Authorization?.Parameter == "synthetic-access" &&
                request.Headers.GetValues("X-StarBridge-Member-Identity-Version").Single() == "2" &&
                body.RootElement.GetProperty("schemaVersion").GetInt32() == 2 && ids.Length is > 0 and <= 100;
            Check(ValidRequest, "actual negotiated request uses fixed route, bearer and bounded exact schema");
            return new(HttpStatusCode.OK) { Content = new StringContent(Override ?? Body(ids), System.Text.Encoding.UTF8, "application/json") };
        }
    }
}
