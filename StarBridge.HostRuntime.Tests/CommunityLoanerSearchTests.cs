using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityLoanerSearchTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var offsets = new List<int>();
        var current = true;
        var matrixName = "Replacement";
        using var handler = new Handler(request => {
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "fixture", "authorized reads only");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Json(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Fixture", description = "", language = "", activeTime = "",
                    memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
            });
            var q = request.RequestUri.Query.TrimStart('?').Split('&').Select(part => part.Split('=', 2))
                .ToDictionary(pair => WebUtility.UrlDecode(pair[0]), pair => WebUtility.UrlDecode(pair[1]));
            Check(q["q"] == "" && q["filter"] == "concept" && q["sort"] == "name" && q["descending"] == "false", "server filters/order preserved; full search scope read");
            var offset = int.Parse(q["offset"]); offsets.Add(offset);
            if (offset > 0) Check(q["revision"] == new string('a', 64), "derived UI revision never sent to server");
            if (mode == "denied" && offset > 0) return new(HttpStatusCode.Forbidden);
            if (mode == "cancel" && offset > 0) current = false;
            var page = JsonSerializer.SerializeToNode(new {
                schemaVersion = 1, queryVersion = 2, code = "A", revision = new string(mode == "changed" && offset > 0 ? 'b' : 'a', 64),
                query = new { text = "", filter = "concept", sort = "name", descending = false, culture = "en-US" },
                offset, totalCount = 50, matchedCount = 45, next = offset < 40 ? (int?)(offset + 20) : null,
                ships = Enumerable.Range(offset, Math.Min(20, 45-offset)).Select(i => new {
                    id = i.ToString("x64"), code = "source-" + i, displayName = "Source " + i,
                    ownerMemberId = "account:fixture", ownerGameName = "", ownerCallsign = "Pilot", ownerOnline = true,
                    ownerLiveStatus = "InGame", ownerIsSelf = false, ownerHasAvatar = false,
                    sharedAt = (string?)null, hangarImportedAt = (string?)null, roleCategory = "Utility",
                    catalogSpec = "large", catalogRole = "Utility", catalogStatus = "Concept", catalogPriceUsd = (string?)null,
                    customImageMediaId = (string?)null, customImageCropFocusX = .5, customImageCropFocusY = .5, customImageCropZoom = 1.0,
                    privateAccount = "Replacement-secret"
                })
            })!;
            if (mode == "duplicate" && offset == 20) page["ships"]![0]!["id"] = new string('0', 64);
            if (mode == "wrong-query" && offset == 20) page["query"]!["filter"] = "all";
            if (mode == "large-count") { page["totalCount"] = 10001; page["matchedCount"] = 10001; }
            return Json(page);
        });
        using var client = new CommunityClient(new Uri("http://127.0.0.1:5058"), handler,
            shipLoaners: (code, _, _) => int.Parse(code[7..]) < 20 ? [] : [new {
                code = matrixName, displayName = matrixName, catalogSpec = "capital", catalogRole = "transport",
                catalogStatus = "flyable", catalogPriceUsd = "1200"
            }], loanerSearchAvailable: true);
        var directory = await client.ReadAsync("fixture", new("mine", "", null, null), "scope", CancellationToken.None);
        var target = directory.Items.Single().TargetRef;
        async Task<JsonElement> Search(string text = "Replacement", int offset = 0, string? revision = null, string scope = "scope") =>
            JsonSerializer.SerializeToElement(await client.ReadShipsAsync("fixture", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target, offset, revision,
                query = new { text, filter = "concept", sort = "name", descending = false, culture = "en-US" }
            }), scope, () => { if (!current) throw new AccountBridgeHostException("fixture.stale"); }, CancellationToken.None));
        var first = await Search();
        Check(offsets.SequenceEqual(new[] { 0, 20, 40 }), "search includes all authorized source pages");
        Check(first.GetProperty("totalCount").GetInt32() == 50 && first.GetProperty("matchedCount").GetInt32() == 25, "total and actual search count distinct");
        Check(first.GetProperty("ships")[0].GetProperty("code").GetString() == "source-20", "late-page Loaner hit preserves source sort order");
        var revision = first.GetProperty("revision").GetString();
        var detail = await Search(revision: revision);
        Check(first.GetProperty("ships")[0].GetProperty("shipRef").GetString() == detail.GetProperty("ships")[0].GetProperty("shipRef").GetString(), "detail reauthorization retains source reference");
        var next = await Search(offset: 20, revision: revision);
        Check(next.GetProperty("ships").GetArrayLength() == 5 && next.GetProperty("next").ValueKind == JsonValueKind.Null, "continuation has remaining five, no duplicate replacement assets");
        Check((await Search("Replacement-secret")).GetProperty("matchedCount").GetInt32() == 0, "private fields never enter search");
        Check((await Search("Source 0")).GetProperty("matchedCount").GetInt32() == 1, "ordinary source-name search is preserved");
        Check((await Search("Pilot")).GetProperty("matchedCount").GetInt32() == 45, "public owner search is preserved");
        Check((await Search("$1,200")).GetProperty("matchedCount").GetInt32() == 25, "WPF formatted price searchable");
        Check((await Search("旗舰级")).GetProperty("matchedCount").GetInt32() == 25, "localized specification searchable");
        await Error(() => Search("different", revision: revision), "communities.shipsChanged");
        matrixName = "Replacement changed";
        await Error(() => Search(revision: revision), "communities.shipsChanged");
        matrixName = "Replacement";
        foreach (var (fault, error) in new[] { ("changed", "communities.shipsChanged"), ("duplicate", "communities.dataInvalid"),
            ("wrong-query", "communities.dataInvalid"), ("large-count", "communities.unavailable"),
            ("denied", "communities.notAllowed"), ("cancel", "fixture.stale") })
        {
            mode = fault;
            await Error(() => Search(), error);
            current = true;
        }
        mode = "ok";
        var count = offsets.Count;
        await Error(() => Search(scope: "other-account"), "communities.refreshRequired");
        Check(count == offsets.Count, "wrong account fails before HTTP");
    }
    private static async Task Error(Func<Task<JsonElement>> action, string code)
    {
        try { await action(); } catch (AccountBridgeHostException e) when (e.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(value)) };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> handle) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(handle(request));
    }
}
