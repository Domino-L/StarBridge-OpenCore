using System.Net;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task VisitorOrganizationLogos()
    {
        var passed = 0;
        foreach (var scenario in new[] { "success", "mismatch", "hidden", "community", "unknown",
            "inline", "failure", "timeout", "zero-id", "restricted", "denied", "self", "slow" })
        {
            using var profile = new ScmVisitorTransport { AllowFriendIdentity = true };
            using var directory = new ScmVisitorFriendsTransport();
            using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://example.invalid/"), directory);
            var uri = new Uri("https://example.invalid/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(profile), new ScmBackgroundVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            var calls = 0;
            var logos = new PublicOrganizationLogoReader(async (sid, token) => {
                calls++;
                if (sid != "FIXTURE") throw new Exception("FleetCode must be trimmed before lookup");
                if (scenario == "failure") throw new HttpRequestException();
                if (scenario == "timeout") throw new OperationCanceledException();
                // A slow lookup must not hold the profile page past the short wait.
                if (scenario == "slow") await Task.Delay(TimeSpan.FromSeconds(6), token);
                return JsonDocument.Parse(JsonSerializer.Serialize(new {
                    id = scenario == "zero-id" ? 0 : 17,
                    sid = scenario == "mismatch" ? "OTHER" : " fixture ",
                    image = "https://example.invalid/logo.png"
                }));
            });
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), friends: friends, publicOrganizationLogos: logos);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var owner = host.CurrentContext!;
            var peers = await host.ReadFriendsAsync(owner, BridgePayload.From(new { schemaVersion = 1 }), default);
            var document = new PersonalProfileDocumentContract(3, "opaque-public-profile", false, 7, DateTimeOffset.UtcNow,
                new("Visitor", ""), PersonalProfileContentContract.Empty,
                scenario == "hidden" ? null : new("Fleet", " FIXTURE ", null, "Member", "blue",
                    LogoImageData: scenario == "inline" ? "inline-server-image" : null,
                    Kind: scenario == "community" ? "community" : scenario == "unknown" ? null : "officialFleet"),
                Visibility: "friendsAndMainFleet");
            profile.WireBody = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (scenario == "restricted") profile.WireBody = JsonSerializer.Serialize(new {
                schemaVersion = 1, restricted = true, visibility = "private", publicHeader = new { callsign = "Visitor" }
            });
            if (scenario == "denied") profile.Status = HttpStatusCode.Forbidden;
            profile.AllowOwnProfile = scenario == "self";
            var started = System.Diagnostics.Stopwatch.StartNew();
            var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                scenario == "self" ? AccountBridgeRequestNames.GetPersonalProfile : "users.profile",
                Guid.NewGuid().ToString("N"), host.Generation,
                new { schemaVersion = 1, source = "friend", reference = peers.Friends.Single().TargetRef }, owner), default)).Response;
            if (started.Elapsed > TimeSpan.FromSeconds(4)) throw new Exception(scenario + ": profile waited too long for the logo");
            // SCM leaves Kind empty for the main fleet: an unmarked affiliation is the main fleet.
            var shouldQuery = scenario is "success" or "unknown" or "mismatch" or "failure" or "timeout" or "zero-id" or "slow";
            if (calls != (shouldQuery ? 1 : 0)) throw new Exception(scenario + ": unexpected logo query count");
            if (scenario == "denied")
            {
                if (response.Error is null) throw new Exception("Denied visitor must fail");
            }
            else
            {
                if (response.Error is not null) throw new Exception(scenario + ": profile failed: " + response.Error.Code);
                if (scenario == "restricted")
                {
                    if (!response.Payload.GetProperty("restricted").GetBoolean()) throw new Exception("Expected restricted header");
                }
                else
                {
                    response.Payload.GetProperty("profile").TryGetProperty("fleetAffiliation", out var affiliation);
                    var url = affiliation.ValueKind == JsonValueKind.Object && affiliation.TryGetProperty("logoUrl", out var value)
                        ? value.GetString() : null;
                    if (url != (scenario is "success" or "unknown" ? "https://example.invalid/logo.png" : null))
                        throw new Exception(scenario + ": incorrect bridge logoUrl");
                }
            }
            passed++;
            Console.WriteLine("PASS visitor organization logo " + scenario);
        }
        Console.WriteLine($"Visitor organization logo: {passed} passed, 0 failed");
    }
}
