using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;

internal static class OfficialFleetRealtimeTextParsingTests
{
    internal static async Task Run()
    {
        var owner = "scm-v1:" + new string('a', 64);
        var checks = 0;
        var cases = 0;
        foreach (var field in new[] { "ship", "serverRegion" })
        {
            var limit = field == "ship" ? 512 : 32;
            var legal = "  " + string.Concat(Enumerable.Repeat("x\u00e9\u4e2d", limit));
            await Parse(field, legal, expected: null); // Existing oversize-only degradation.
            await Parse(field, legal[..limit], expected: legal[..limit]);
            await Parse(field, null, expected: null); // Server's cleared-field wire shape.
            await Parse(field, "x\0" + new string('x', limit), reject: true);
            await Parse(field, new string('x', limit) + "\0y", reject: true);
            await Parse(field, "x\0y", reject: true);
            foreach (var control in Enumerable.Range(0, 160).Select(i => (char)i).Where(char.IsControl))
                await Parse(field, new string('x', limit) + control + "y", reject: true);
        }
        Console.WriteLine($"PASS CX-CLOCK-SKEW Host display parsing {cases} cases, {checks} assertions, no network");

        async Task Parse(string field, string? value, string? expected = null, bool reject = false)
        {
            cases++;
            var member = new Dictionary<string, object?> {
                ["ownerBusinessSubjectId"] = owner, ["presence"] = "inGame",
                ["server"] = new { state = "value", value = "shard", confidence = "Exact" },
                ["ship"] = new { state = "value", value = "ship", confidence = "Exact" },
                ["location"] = new { state = "value", value = "location", confidence = "Exact" },
                ["arrivalPending"] = false, ["arrivalTargetCode"] = null,
                ["serverRegion"] = "US", ["hasServerSession"] = true, ["locationHiddenReason"] = null
            };
            member[field] = field == "serverRegion" ? value
                : new { state = value is null ? "unknown" : "value", value, confidence = value is null ? null : "Exact" };
            using var writer = new PrivacyRelayWriter(new("https://fixture.invalid/"), new JsonHandler(new {
                schemaVersion = 4, sourceRef = "officialFleet:7", coverage = "requestedOwners", requestedOwnerCount = 1,
                members = new[] { member }, supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                    presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false }
            }));
            try
            {
                var rows = await writer.ReadOfficialRuntimeAsync("", "officialFleet:7", [owner], default, () => { });
                Check(!reject, $"{field}: raw control characters must still be rejected");
                var row = rows[owner];
                Check(field == "ship" ? row.Ship.Value == expected && row.Ship.State == (expected is null ? "unknown" : "value")
                    : row.ServerRegion == expected, $"{field}: legal prefix or cleared value is accepted exactly");
                Check(row.Presence == "inGame" && row.Server.Value == "shard" && row.Location.Value == "location" &&
                    (field == "ship" ? row.ServerRegion == "US" : row.Ship.Value == "ship"),
                    $"{field}: parsing does not degrade other fields");
            }
            catch (AccountBridgeHostException error) when (reject)
            {
                Check(error.Code == "privacy_publication.response_invalid", $"{field}: invalid text remains fail-closed");
            }
        }
        void Check(bool value, string message) { checks++; if (!value) throw new Exception(message); }
    }

    private sealed class JsonHandler(object body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
    }
}