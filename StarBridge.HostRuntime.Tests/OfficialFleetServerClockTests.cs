using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.HostRuntime.Privacy;

internal static class OfficialFleetServerClockTests
{
    private static readonly DateTimeOffset Epoch = DateTimeOffset.Parse("2026-11-03T12:00:00Z");
    private static readonly Uri Endpoint = new("https://fixture.invalid/identity");
    private static int _checks;
    internal static async Task Run()
    {
        _checks = 0;
        foreach (var skew in new[] { -1.07, -9, 0, 9 })
        foreach (var source in new[] { "body", "date" })
        {
            var local = new Clock { Now = Epoch.AddSeconds(skew) };
            var handler = new Handler(local, skew, source);
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new ScmOAuthOptions(
                "fixture", new("https://fixture.invalid/"), new("https://fixture.invalid/"), new("https://fixture.invalid/"),
                "fixture", "fixture", "profile.read organizations.read", "/callback")) { OfficialFleetIdentityObservationClock = local };
            var session = new ScmOAuthSession("fixture", "fixture", "Fixture", "synthetic-access", Epoch.AddYears(1), ["profile.read", "organizations.read"]);
            var result = await oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, "officialFleet:7", [1], default);
            Check(result.Result[1].IdentityValidUntilUtc == Epoch.AddSeconds(5), "transport preserves the original deadline");
            Check(oauth.OfficialFleetIdentityObservationClock.GetUtcNow() == local.Now, "default transport never estimates an offset");
            Check(handler.Calls == 1, "default transport never adds a calibration request");
        }
        foreach (var mode in new[] { "missing", "hours", "bad", "slow", "untrusted", "business-error", "redirect", "cached" })
        {
            var local = new Clock { Now = Epoch.AddSeconds(-2) };
            var clock = new OfficialFleetServerClock(local, enableOffsetEstimation: true);
            Sample(clock, local, Epoch, mode);
            Sample(clock, local, Epoch, mode);
            Check(clock.GetUtcNow() == local.Now, "unusable sample falls back to the unmodified local clock: " + mode);
            Check(clock.DiagnosticCode is not "identity-time-calibrated", "unusable sample has a fixed diagnostic");
        }
        {
            var local = new Clock { Now = Epoch.AddSeconds(-2) };
            var clock = new OfficialFleetServerClock(local, enableOffsetEstimation: true);
            Sample(clock, local, Epoch); Check(clock.GetUtcNow() == local.Now, "one sample never calibrates");
            Sample(clock, local, Epoch); Check(clock.GetUtcNow() == Epoch, "two consistent samples calibrate");
            Sample(clock, local, Epoch.AddSeconds(20));
            Check(clock.GetUtcNow() == local.Now, "single discontinuity cannot move corrected time to the anomalous sample");
            Sample(clock, local, Epoch); Sample(clock, local, Epoch);
            Check(clock.GetUtcNow() == Epoch, "normal samples recover after outlier");
            local.Now = local.Now.AddSeconds(2); // User synchronizes Windows, without monotonic time advancing.
            Check(clock.GetUtcNow() == local.Now && clock.DiagnosticCode == "identity-clock-changed", "wall-clock sync invalidates old offset immediately");
            Check(clock.TimeFailure().Code == "official_fleet.identity_time_invalid", "syncing to correct time is not misreported as skew");
            Sample(clock, local, Epoch); Sample(clock, local, Epoch);
            Check(clock.GetUtcNow() == Epoch && clock.TimeFailure().Code == "official_fleet.identity_time_invalid", "same session converges after sync, without retaining skew error");
            local.Now += TimeSpan.FromSeconds(11);
            _ = clock.GetUtcNow();
            Check(clock.TimeFailure().Code == "official_fleet.identity_clock_skew", "only a confirmed difference from extrapolated server UTC reports skew");
            local.Now -= TimeSpan.FromSeconds(11);
            Check(clock.TimeFailure().Code == "official_fleet.identity_time_invalid", "a second synchronization cannot leave a stale skew hint");
            local.Now += TimeSpan.FromSeconds(11);
            Sample(clock, local, Epoch); Sample(clock, local, Epoch);
            local.Advance(TimeSpan.FromSeconds(16));
            using var proof = JsonDocument.Parse(Proof());
            Refuses(() => OfficialFleetMemberIdentityObservation.Parse(proof.RootElement, "officialFleet:7", [1], clock.GetUtcNow()), "original deadline plus more than ten seconds is expired");
        }
        {
            var local = new Clock { Now = Epoch.AddSeconds(6) };
            var clock = new OfficialFleetServerClock(local, enableOffsetEstimation: true);
            Sample(clock, local, Epoch); Sample(clock, local, Epoch);
            Sample(clock, local, Epoch, "missing");
            Check(clock.GetUtcNow() == local.Now, "missing time discards an earlier estimate");
            Sample(clock, local, Epoch); Sample(clock, local, Epoch);
            local.Advance(TimeSpan.FromMinutes(3));
            Check(clock.GetUtcNow() == local.Now && clock.DiagnosticCode == "identity-time-stale", "stale calibration cannot survive indefinitely");
        }
        {
            var local = new Clock { Now = Epoch.AddSeconds(-2) };
            var clock = new OfficialFleetServerClock(local, enableOffsetEstimation: true);
            Sample(clock, local, Epoch, "nested"); Sample(clock, local, Epoch, "nested");
            Check(clock.GetUtcNow() == Epoch, "existing page.serverTime takes priority over Date");
        }
        {
            var local = new Clock { Now = Epoch.AddSeconds(-2) };
            var clock = new OfficialFleetServerClock(local, enableOffsetEstimation: true);
            // Server timestamp is generated halfway through a 400ms request.
            Sample(clock, local, Epoch.AddMilliseconds(200), elapsed: TimeSpan.FromMilliseconds(400));
            Sample(clock, local, Epoch.AddMilliseconds(600), elapsed: TimeSpan.FromMilliseconds(400));
            Check((clock.GetUtcNow() - Epoch.AddMilliseconds(800)).Duration() <= TimeSpan.FromMilliseconds(200), "estimate respects the measured RTT interval");
            Sample(clock, local, Epoch.AddMilliseconds(1080), elapsed: TimeSpan.FromMilliseconds(400));
            Check(clock.GetUtcNow() > Epoch.AddMilliseconds(1200) && clock.GetUtcNow() < Epoch.AddMilliseconds(1280),
                "a bounded noisy sample is smoothed, not copied");
        }
        using (var observation = new OfficialMemberReadObservation())
        {
            observation.Fail(new AccountBridgeHostException("official_fleet.identity_time_invalid"));
            Check(observation.Code == "identity-time-invalid", "real expiry is no longer data-invalid");
        }
        using (var observation = new OfficialMemberReadObservation())
        {
            observation.Fail(new AccountBridgeHostException("official_fleet.identity_clock_skew"));
            Check(observation.Code == "identity-clock-skew", "skew diagnostic is distinct");
        }
        await OversizeFields();
        DefaultGraceMatrix();
        using (var proof = JsonDocument.Parse(Proof()))
        {
            _ = OfficialFleetMemberIdentityObservation.Parse(proof.RootElement, "officialFleet:7", [1], Epoch.AddSeconds(-10));
            Refuses(() => OfficialFleetMemberIdentityObservation.Parse(proof.RootElement, "officialFleet:7", [1], Epoch.AddSeconds(-10).AddTicks(-1)), "future tolerance is exactly ten seconds");
        }
        Console.WriteLine($"PASS CX-CLOCK-SKEW {_checks} assertions, deterministic clocks, no network");
    }

    private static void DefaultGraceMatrix()
    {
        var local = new Clock { Now = Epoch };
        var clock = new OfficialFleetServerClock(local);
        Sample(clock, local, Epoch.AddSeconds(30)); Sample(clock, local, Epoch.AddSeconds(30));
        Check(clock.GetUtcNow() == Epoch && !clock.NeedsConfirmation, "default clock ignores even repeated valid server samples");
        foreach (var seconds in new[] { 1.07, 9, 10, 11 })
        {
            using var proof = JsonDocument.Parse(Proof());
            foreach (var now in new[] { Epoch.AddSeconds(-seconds), Epoch.AddSeconds(5 + seconds) })
            {
                if (seconds < 10 || now == Epoch.AddSeconds(-10))
                {
                    _ = OfficialFleetMemberIdentityObservation.Parse(proof.RootElement, "officialFleet:7", [1], now);
                    Check(true, "future grace includes ten seconds; expiry grace ends at ten seconds");
                }
                else Refuses(() => OfficialFleetMemberIdentityObservation.Parse(proof.RootElement, "officialFleet:7", [1], now), "reject at expiry cutoff or beyond future grace");
            }
        }
        using var valid = JsonDocument.Parse(Proof());
        _ = OfficialFleetMemberIdentityObservation.Parse(valid.RootElement, "officialFleet:7", [1], Epoch.AddSeconds(15).AddTicks(-1));
        Refuses(() => OfficialFleetMemberIdentityObservation.Parse(valid.RootElement, "officialFleet:7", [1], Epoch.AddSeconds(15)), "original until plus ten seconds is already expired");
        Refuses(() => OfficialFleetMemberIdentityObservation.Parse(valid.RootElement, "officialFleet:7", [1], Epoch.AddSeconds(15).AddTicks(1)), "expiry grace has an exact boundary");
        using var longProof = JsonDocument.Parse(Proof().Replace("12:00:05", "12:00:06"));
        try { _ = OfficialFleetMemberIdentityObservation.Parse(longProof.RootElement, "officialFleet:7", [1], Epoch); }
        catch (AccountBridgeHostException e) when (e.Code == OfficialFleetMemberIdentity.Unavailable)
        { Check(true, "six-second proof span stays structurally invalid"); return; }
        throw new Exception("six-second proof span was accepted");
    }

    private static void Sample(OfficialFleetServerClock clock, Clock local, DateTimeOffset server, string mode = "body", TimeSpan? elapsed = null)
    {
        var start = clock.Start();
        local.Advance(mode == "slow" ? TimeSpan.FromSeconds(6) : elapsed ?? TimeSpan.Zero);
        var body = mode switch {
            "missing" => "{}", "bad" => "{\"serverTime\":\"invalid\"}",
            "hours" => JsonSerializer.Serialize(new { serverTime = server.AddHours(3) }),
            "business-error" => JsonSerializer.Serialize(new { serverTime = server, code = 401 }),
            "nested" => JsonSerializer.Serialize(new { page = new { serverTime = server } }),
            _ => JsonSerializer.Serialize(new { serverTime = server })
        };
        using var root = JsonDocument.Parse(body);
        using var response = new HttpResponseMessage(mode == "untrusted" ? HttpStatusCode.Unauthorized : HttpStatusCode.OK);
        response.Headers.Date = mode == "nested" ? server.AddHours(3) : server; // Explicit body time takes priority.
        if (mode == "redirect") response.RequestMessage = new(HttpMethod.Get, "https://other.invalid/identity");
        if (mode == "cached") response.Headers.Age = TimeSpan.FromSeconds(1);
        if (mode == "missing") response.Headers.Date = null;
        clock.Observe(start, response, root.RootElement, Endpoint);
    }

    private static async Task OversizeFields()
    {
        var owner = "scm-v1:" + new string('a', 64);
        foreach (var field in new[] { "serverRegion", "ship", "server", "location", "arrivalTargetCode" })
        {
            var member = new Dictionary<string, object?> {
                ["ownerBusinessSubjectId"] = owner, ["presence"] = "inGame",
                ["server"] = new { state = "value", value = "shard", confidence = "Exact" },
                ["ship"] = new { state = "value", value = "ship", confidence = "Exact" },
                ["location"] = new { state = "value", value = "location", confidence = "Exact" },
                ["arrivalPending"] = false, ["arrivalTargetCode"] = null,
                ["serverRegion"] = "US", ["hasServerSession"] = true, ["locationHiddenReason"] = null
            };
            member[field] = field is "serverRegion" or "arrivalTargetCode" ? new string('x', field == "serverRegion" ? 33 : 513)
                : new { state = "value", value = new string('x', 513), confidence = "Exact" };
            using var writer = new PrivacyRelayWriter(new("https://fixture.invalid/"), new JsonHandler(new {
                schemaVersion = 4, sourceRef = "officialFleet:7", coverage = "requestedOwners", requestedOwnerCount = 1,
                members = new[] { member }, supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                    presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false }
            }));
            var rows = await writer.ReadOfficialRuntimeAsync("synthetic", "officialFleet:7", [owner], default, () => { });
            var row = rows[owner];
            Check(row.Presence == "inGame", "oversize text never drops the row");
            Check(field switch { "serverRegion" => row.ServerRegion is null, "arrivalTargetCode" => row.ArrivalTargetCode is null,
                "ship" => row.Ship.State == "unknown" && row.Location.Value == "location",
                "server" => row.Server.State == "unknown" && row.Ship.Value == "ship",
                _ => row.Location.State == "unknown" && row.Ship.Value == "ship" }, "only the oversize field becomes unavailable");
        }
    }
    private static string Proof() => JsonSerializer.Serialize(new { schemaVersion = 2, sourceRef = "officialFleet:7", members = new[] {
        new { memberId = 1, state = "unlinked", identityObservedAtUtc = Epoch, identityValidUntilUtc = Epoch.AddSeconds(5) } } });
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }
    private static void Refuses(Action action, string message)
    { try { action(); } catch (AccountBridgeHostException error) when (error.Code is "official_fleet.identity_time_invalid" or "official_fleet.identity_clock_skew") { _checks++; return; } throw new Exception(message); }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now; private long _tick;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => _tick;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        internal void Advance(TimeSpan amount) { Now += amount; _tick += amount.Ticks; }
    }
    private sealed class JsonHandler(object body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
    }
    private sealed class Handler(Clock local, double skew, string source) : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            var server = local.Now.AddSeconds(-skew);
            using var doc = JsonDocument.Parse(Proof());
            var root = doc.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
            if (source == "body") root["serverTime"] = JsonSerializer.SerializeToElement(server);
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(root) };
            response.Headers.Date = server;
            return Task.FromResult(response);
        }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("No credential writes");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("No credential writes");
    }
}
