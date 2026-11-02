using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Communities;

internal static class CommunityShipMetadataRecoveryTests
{
    internal static async Task Verify()
    {
        var catalog = new ShipPresentationCatalog(null,
            "规格\t英文飞船名\t中文飞船名\t定位\t官网状态\t价格USD\t隐藏标签\n" +
            "小型\tRecovery Test\t回填测试\tCombat\t可飞\t50\t\n" +
            "大型\tConcept Test\t概念测试\tTransport\t概念\t300\t\n");
        foreach (var adapter in new[] { "wpf", "community", "official" })
        {
            var ownerId = adapter == "official" ? new string('c', 64) : "account:fixture-owner";
            JsonObject Row(int i)
            {
                var row = JsonSerializer.SerializeToNode(new {
                    id = i.ToString("x64"), code = i == 2 ? "catalog-concepttest" : i == 4 ? "Recovery Test EX" : "catalog-recoverytest",
                    displayName = i == 2 ? "Concept Test" : i == 4 ? "Recovery Test EX" : "Recovery Test",
                    instanceId = adapter == "official" ? null : "fixture-instance-" + i,
                    ownerAccountId = "fixture-owner", ownerMemberId = ownerId, ownerGameName = "", ownerCallsign = "Pilot",
                    ownerOnline = adapter != "official", ownerLiveStatus = adapter == "official" ? "Unknown" : "Online", ownerIsSelf = true, ownerHasAvatar = false,
                    sharedAt = (string?)null, hangarImportedAt = (string?)null, roleCategory = i == 3 ? "Transport" : "unknown",
                    catalogSpec = i == 3 ? "大型" : "待分类", catalogRole = i == 3 ? "运输" : "unknown",
                    catalogStatus = i == 1 ? "可飞" : i == 3 ? "概念" : "未知", catalogPriceUsd = i == 3 ? "0" : null,
                    customImageMediaId = (string?)null, customImageCropFocusX = .5, customImageCropFocusY = .5, customImageCropZoom = 1.0,
                    privateSecret = "never-export"
                })!.AsObject();
                return row;
            }
            using var handler = new Handler(request =>
            {
                Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "fixture", "Only existing authorized GET routes");
                var path = request.RequestUri!.AbsolutePath;
                if (path == "/api/fleets/membership") return Json(new { fleetCode = "A" });
                if (path == "/api/fleets") return Json(new[] { new {
                    code = "A", name = "Fixture", totalMembers = 1,
                    members = new[] { new { accountId = "fixture-owner", gameName = "", callsign = "Pilot", online = true, liveStatus = "Online" } },
                    ships = Enumerable.Range(0, 5).Select(Row).ToArray()
                } });
                if (path == "/api/fleets/directory") return Json(new {
                    schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Fixture", description = "", language = "", activeTime = "", memberCount = 1,
                        relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
                });
                if (path == "/api/official-fleets/context") return Json(new {
                    schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = "OFFICIALFLEET:7", name = "Fixture",
                    announcementsAvailable = false, chatAvailable = false, canSend = false, readReceiptsAvailable = false,
                    canManageAnnouncements = false, activityAvailable = false
                });
                Check(path == (adapter == "official" ? "/api/official-fleets/ships" : "/api/fleets/ships"), "No cross-adapter fallback");
                var q = request.RequestUri.Query.TrimStart('?').Split('&').Select(v => v.Split('=', 2))
                    .ToDictionary(p => WebUtility.UrlDecode(p[0]), p => WebUtility.UrlDecode(p[1]));
                Check(q["offset"] == "0" && q["filter"] == "all", "Server query authority stays unchanged");
                var page = JsonSerializer.SerializeToNode(new {
                    schemaVersion = 1, code = "A", revision = new string('a', 64), queryVersion = 2,
                    query = new { text = q["q"], filter = "all", sort = "name", descending = false, culture = "en-US" },
                    offset = 0, next = (int?)null, totalCount = 5, matchedCount = 5, ships = Enumerable.Range(0, 5).Select(Row).ToArray()
                })!.AsObject();
                if (adapter == "official")
                {
                    page["sourceRef"] = "officialFleet:7";
                    page["coverage"] = "completeAuthorizedProjection";
                    page["identityValidUntilUtc"] = JsonValue.Create(DateTimeOffset.UtcNow.AddMinutes(1));
                }
                return Json(page);
            });
            using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler,
                shipLoaners: (_, status, _) => status == "概念" ? [new { code = "replacement", displayName = "Replacement", catalogStatus = "可飞" }] : [],
                loanerSearchAvailable: true, shipCatalog: catalog.Find);
            const string scope = "fixture-scope";
            string target;
            if (adapter == "official") target = J(await client.OpenOfficialFleetAsync("fixture", "officialFleet:7", scope, () => {}, default)).GetProperty("targetRef").GetString()!;
            else target = (adapter == "wpf"
                ? await client.ReadWpfS2Async("fixture", new("mine", "", null, null), scope, "fixture-owner", default)
                : await client.ReadAsync("fixture", new("mine", "", null, null), scope, default)).Items.Single().TargetRef;
            async Task<JsonElement> Read(string text = "", string filter = "all", string sort = "name")
            {
                var body = J(new { schemaVersion = 1, targetRef = target, offset = 0, revision = (string?)null,
                    query = new { text, filter, sort, descending = false, culture = "en-US" } });
                if (adapter != "official") return J(await client.ReadShipsAsync("fixture", body, scope, () => {}, default));
                return J(await client.ReadOfficialShipsAsync("fixture", body, "officialFleet:7", scope, () => {},
                    (_, _) => Task.FromResult<IReadOnlyDictionary<string, CommunityClient.OfficialShipOwner>>(
                        new Dictionary<string, CommunityClient.OfficialShipOwner> { [ownerId] = new("visible", "Pilot", null, null, null) }), TimeProvider.System, default));
            }
            var page = await Read();
            var ships = page.GetProperty("ships").EnumerateArray().ToArray();
            Check(ships.Length == 5 && ships.Select(s => s.GetProperty("shipRef").GetString()).Distinct().Count() == 5, adapter + ": duplicate model instances remain separate");
            var recovered = ships.Where(s => s.GetProperty("code").GetString() == "catalog-recoverytest" && s.GetProperty("catalogPriceUsd").GetString() != "0").ToArray();
            Check(recovered.Length == 2 && recovered.All(s => s.GetProperty("catalogStatus").GetString() == "可飞" && s.GetProperty("catalogPriceUsd").GetString() == "50" && s.GetProperty("catalogSpec").GetString() == "小型"), adapter + ": unknown status and missing price are recovered independently");
            var known = ships.Single(s => s.GetProperty("catalogPriceUsd").GetString() == "0");
            Check(known.GetProperty("catalogStatus").GetString() == "概念" && known.GetProperty("catalogRole").GetString() == "运输", adapter + ": valid remote metadata wins");
            var unknown = ships.Single(s => s.GetProperty("code").GetString() == "Recovery Test EX");
            Check(unknown.GetProperty("catalogStatus").GetString() == "未知" && unknown.GetProperty("catalogPriceUsd").ValueKind == JsonValueKind.Null, adapter + ": unknown variant stays unknown");
            var concept = ships.Single(s => s.GetProperty("code").GetString() == "catalog-concepttest");
            Check(concept.GetProperty("catalogStatus").GetString() == "概念" && concept.GetProperty("loaners").GetArrayLength() == 1, adapter + ": loaners use recovered status");
            Check(!page.GetRawText().Contains("never-export") && !page.GetRawText().Contains("fixture-instance"), adapter + ": instance and private fields remain redacted");
            Check((await Read("Replacement")).GetProperty("matchedCount").GetInt32() == 2, adapter + ": loaner search uses recovered status");
            Check((await Read("50")).GetProperty("matchedCount").GetInt32() == 2, adapter + ": search uses recovered price");
            if (adapter == "wpf")
            {
                Check((await Read(filter: "flyable")).GetProperty("matchedCount").GetInt32() == 2, "Recovery precedes WPF filtering");
                Check((await Read(filter: "unknown")).GetProperty("matchedCount").GetInt32() == 1, "Recovered rows leave WPF unknown filter");
                Check((await Read(sort: "price")).GetProperty("ships")[0].GetProperty("catalogPriceUsd").GetString() == "0", "Recovery precedes WPF price sorting");
            }
        }
    }

    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> read) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(read(request)); }
}
