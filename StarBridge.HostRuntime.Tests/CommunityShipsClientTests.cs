using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityShipsClientTests
{
    internal static async Task Verify()
    {
        StarBridge.HostRuntime.Tests.CommunityShipCatalogTests.Verify();
        await CommunityLoanerSearchTests.Verify();
        var mode = "ok";
        var calls = 0;
        var current = true;
        var clock = new Clock();
        var revision = new string('a', 64);
        using var handler = new Handler(request =>
        {
            calls++;
            if (request.RequestUri!.AbsolutePath == "/api/fleets/ships/image/report-status")
            {
                Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "fixture-bearer", "recovery only reads current account receipt");
                var key = request.RequestUri.Query.Split('=')[1];
                if (mode == "report-check-network") throw new HttpRequestException("fixture lookup disconnect");
                return Json(new { schemaVersion = 1, clientRequestId = mode == "report-check-invalid" ? "wrong" : key,
                    status = mode == "report-check-missing" ? "unknown" : "accepted" });
            }
            if (request.Method == HttpMethod.Post)
            {
                Check(request.RequestUri!.AbsolutePath == "/api/fleets/ships/image/report" &&
                    request.Headers.Authorization?.Parameter == "fixture-bearer", "scoped authorized image report only");
                var command = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult()).RootElement;
                Check(command.GetProperty("code").GetString() == "A" && command.GetProperty("shipId").GetString() == new string('0', 64) &&
                    Guid.TryParseExact(command.GetProperty("clientRequestId").GetString(), "N", out _) &&
                    !command.TryGetProperty("mediaId", out _), "Host derives target and scoped request identity");
                if (mode == "report-network") throw new HttpRequestException("fixture disconnect after send");
                if (mode == "report-stale") current = false;
                if (mode.StartsWith("report-status-")) return new((HttpStatusCode)int.Parse(mode[14..]));
                if (mode == "report-invalid") return Json(new { schemaVersion = 1, reportId = "bad", status = "submitted" });
                if (mode == "report-large") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 5000)) };
                if (mode == "report-duplicate-json") return new(HttpStatusCode.OK)
                    { Content = new StringContent("{\"schemaVersion\":1,\"schemaVersion\":1}") };
                return Json(new { schemaVersion = 1, reportId = new string('f', 32), status = "submitted" });
            }
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "fixture-bearer", "authorized GET only");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Json(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { "A", "B" }.Select(code => new { code, name = "Organization " + code, description = "", language = "",
                    activeTime = "", memberCount = 2, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null })
            });
            if (request.RequestUri.AbsolutePath == "/api/fleets/ships/image")
            {
                if (mode.StartsWith("status-")) return new((HttpStatusCode)int.Parse(mode[7..]));
                if (mode == "stale") current = false;
                var image = JsonSerializer.SerializeToNode(new { schemaVersion = 1, code = "A", shipId = new string('0', 64),
                    version = new string('b', 64), contentHash = new string('c', 64), mimeType = "image/png",
                    offset = 0, next = (int?)null, totalBytes = 3, data = "AQID", cropFocusX = .3, cropFocusY = .7, cropZoom = 1.4 })!;
                switch (mode)
                {
                    case "image-code": image["code"] = "B"; break;
                    case "image-ship": image["shipId"] = new string('f', 64); break;
                    case "image-version": image["version"] = "bad"; break;
                    case "image-hash": image["contentHash"] = "bad"; break;
                    case "image-mime": image["mimeType"] = "text/html"; break;
                    case "image-size": image["totalBytes"] = 2097153; break;
                    case "image-count": image["data"] = "AQI="; break;
                    case "image-offset": image["offset"] = 196608; break;
                    case "image-next": image["next"] = 3; break;
                    case "image-crop": image["cropZoom"] = 0; break;
                }
                return Json(image);
            }
            Check(request.RequestUri.AbsolutePath == "/api/fleets/ships", "ship request stays on the bounded route");
            if (mode.StartsWith("status-")) return new((HttpStatusCode)int.Parse(mode[7..]));
            if (mode == "network") throw new HttpRequestException("fixture disconnect");
            if (mode == "duplicate-json") return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":1,\"schemaVersion\":1}") };
            if (mode == "stale") current = false;
            var offset = request.RequestUri.Query.Contains("offset=20") ? 20 : 0;
            if (offset > 0) Check(request.RequestUri.Query.Contains("revision=" + revision), "continuation bound to revision");
            var code = request.RequestUri.Query.Contains("code=B") ? "B" : "A";
            var library = request.RequestUri.Query.Contains("view=library");
            if (library) Check(request.RequestUri.Query.Contains("q=a%26b") && request.RequestUri.Query.Contains("sort=name") &&
                request.RequestUri.Query.Contains("descending=false") && request.RequestUri.Query.Contains("culture=en-US"), "library query is encoded and bounded");
            var root = JsonSerializer.SerializeToNode(new { schemaVersion = 1, code, revision, offset,
                next = offset == 0 ? (int?)20 : null, totalCount = 21,
                ships = Enumerable.Range(offset, offset == 0 ? 20 : 1).Select(i => new
                {
                    id = i.ToString("x64"), code = "test-ship", displayName = "Fixture ship", instanceId = "private-instance-" + i,
                    ownerMemberId = "account:private-account", ownerGameName = "", ownerCallsign = "Pilot",
                    ownerOnline = true, ownerLiveStatus = "InGame", ownerIsSelf = false, ownerHasAvatar = true,
                    sharedAt = (string?)null, hangarImportedAt = "2026-09-08T00:00:00Z", roleCategory = "Utility",
                    catalogSpec = "大型", catalogRole = "运输", catalogStatus = "Flyable", catalogPriceUsd = (string?)null,
                    customImageMediaId = "private-media", customImageCropFocusX = .3, customImageCropFocusY = .7,
                    customImageCropZoom = 1.4, secret = "never-export"
                }) })!;
            if (library)
            {
                root["queryVersion"] = 2;
                root["matchedCount"] = 21;
                root["query"] = JsonSerializer.SerializeToNode(new { text = "a&b", filter = "all", sort = "name", descending = false, culture = "en-US" });
            }
            switch (mode)
            {
                case "catalog-name":
                    root["ships"]![0]!["code"] = "catalog-idrisp";
                    root["ships"]![0]!["displayName"] = "Idris-P Frigate";
                    break;
                case "code": root["code"] = "another-organization"; break;
                case "schema": root["schemaVersion"] = 2; break;
                case "count": root["totalCount"] = 19; break;
                case "next": root["next"] = 19; break;
                case "revision": root["revision"] = "bad"; break;
                case "duplicate": root["ships"]![1]!["id"] = new string('0', 64); break;
                case "order": root["ships"]![0]!["id"] = new string('f', 64); break;
                case "member": root["ships"]![0]!["ownerMemberId"] = "account:"; break;
                case "time": root["ships"]![0]!["sharedAt"] = "not-a-date"; break;
                case "crop": root["ships"]![0]!["customImageCropZoom"] = -1; break;
                case "size": root["extra"] = new string('x', 410000); break;
                case "empty": root["ships"] = new JsonArray(); root["totalCount"] = 0; root["next"] = null; break;
                case "query-echo": root["query"]!["text"] = "another search"; break;
                case "query-version": root["queryVersion"] = 0; break;
                case "query-count": root["matchedCount"] = 22; break;
            }
            return Json(root);
        });
        using var client = new CommunityClient(new Uri("http://127.0.0.1:5058"), handler, clock, loanerSearchAvailable: false);
        var directory = await client.ReadAsync("fixture-bearer", new("mine", "", null, null), "scope", CancellationToken.None);
        var a = directory.Items[0].TargetRef;
        var b = directory.Items[1].TargetRef;
        void Current() { if (!current) throw new AccountBridgeHostException("fixture.stale"); }
        async Task<JsonElement> Read(string target, int offset = 0, string? rev = null, string scope = "scope") =>
            JsonSerializer.SerializeToElement(await client.ReadShipsAsync("fixture-bearer",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, offset, revision = rev }), scope, Current, CancellationToken.None));
        var first = await Read(a);
        Check(first.GetProperty("ships").GetArrayLength() == 20 && first.GetProperty("next").GetInt32() == 20, "bounded projection");
        var serialized = first.GetRawText();
        Check(!serialized.Contains("private-account") && !serialized.Contains("private-instance") && !serialized.Contains("private-media") &&
            !serialized.Contains("never-export") && !first.TryGetProperty("code", out _), "internal identities and extra fields stay in Host");
        var ship = first.GetProperty("ships")[0];
        mode = "catalog-name";
        var localized = (await Read(a)).GetProperty("ships")[0];
        Check(localized.GetProperty("displayName").GetString() == "伊德里斯-P",
            "Published catalog IDs must show the localized model name on organization readback");
        Check(!string.IsNullOrWhiteSpace(localized.GetProperty("englishName").GetString()) &&
            localized.GetProperty("manufacturer").GetString() == "Aegis Dynamics",
            "Organization readback exposes English model and manufacturer separately from internal code");
        mode = "ok";
        Check(ship.GetProperty("catalogIconKey").ValueKind == JsonValueKind.Null,
            "unknown local catalog identity has no guessed decorative icon");
        async Task<JsonElement> Report(string requestId, string? target = null, string reason = "spam", string scope = "scope", bool checkOnly = false) =>
            JsonSerializer.SerializeToElement(await client.ReportShipImageAsync("fixture-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target ?? a, shipRef = ship.GetProperty("shipRef").GetString(),
                version = new string('b', 64), requestId, reason, details = "", checkOnly }), scope, Current, CancellationToken.None));
        var reportId = Guid.NewGuid().ToString("N");
        var reportReceipt = await Report(reportId);
        Check(reportReceipt.GetProperty("status").GetString() == "accepted" && !reportReceipt.TryGetProperty("reportId", out _),
            "valid lightweight receipt is accepted without exporting moderation identities");
        var reportCalls = calls;
        Check((await Report(reportId)).GetProperty("status").GetString() == "accepted" && calls == reportCalls, "accepted bridge repeat does not POST again");
        Check((await Report(reportId, reason: "other")).GetProperty("error").GetString() == "intentConflict" && calls == reportCalls,
            "same intent different content rejected without HTTP");
        Check((await Report(Guid.NewGuid().ToString("N"), target: b)).GetProperty("status").GetString() == "rejected" && calls == reportCalls,
            "cross-organization image reference cannot report");
        Check((await Report(Guid.NewGuid().ToString("N"), scope: "other-account")).GetProperty("status").GetString() == "rejected" && calls == reportCalls,
            "cross-account image reference cannot report");
        await Error(() => Report("bad"), "communities.dataInvalid");
        foreach (var fault in new[] { "network", "invalid", "large", "duplicate-json", "stale", "status-500" })
        {
            mode = "report-" + fault;
            var id = Guid.NewGuid().ToString("N");
            var result = await Report(id);
            Check(result.GetProperty("status").GetString() == "unknown", "uncertain write is not reported as success: " + fault);
            current = true;
            var sentCalls = calls;
            Check((await Report(id)).GetProperty("status").GetString() == "unknown" && calls == sentCalls,
                "uncertain bridge repeat never replays POST: " + fault);
        }
        foreach (var (status, error) in new[] { (400, "dataInvalid"), (401, "identityUnavailable"), (403, "notAllowed"),
                     (404, "refreshRequired"), (409, "mediaChanged"), (429, "rateLimited") })
        {
            mode = "report-status-" + status;
            Check((await Report(Guid.NewGuid().ToString("N"))).GetProperty("error").GetString() == error, "stable rejection: " + status);
        }
        mode = "ok";
        var recoveryId = Guid.NewGuid().ToString("N");
        var beforeUnsentLookup = calls;
        Check((await Report(recoveryId, checkOnly: true)).GetProperty("status").GetString() == "unknown" && calls == beforeUnsentLookup,
            "unknown caller intent never starts a submission or fabricates a failure");
        mode = "report-network";
        await Report(recoveryId);
        foreach (var fault in new[] { "network", "invalid", "missing" })
        {
            mode = "report-check-" + fault;
            Check((await Report(recoveryId, checkOnly: true)).GetProperty("status").GetString() == "unknown",
                "lookup failure or absence keeps outcome unknown: " + fault);
        }
        mode = "ok";
        Check((await Report(recoveryId, checkOnly: true)).GetProperty("status").GetString() == "accepted", "read-only receipt resolves lost acknowledgement");
        var recoveredCalls = calls;
        Check((await Report(recoveryId)).GetProperty("status").GetString() == "accepted" && calls == recoveredCalls,
            "resolved intent cannot replay POST");
        async Task<JsonElement> Image(string target, string? source = null, string scope = "scope") =>
            JsonSerializer.SerializeToElement(await client.ReadShipImageAsync("fixture-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target, shipRef = source ?? ship.GetProperty("shipRef").GetString(), offset = 0, version = (string?)null
            }), scope, Current, CancellationToken.None));
        var original = await Image(a);
        Check(original.GetProperty("data").GetString() == "AQID" && original.GetProperty("cropZoom").GetDouble() == 1.4 &&
            original.GetProperty("shipRef").GetString() == ship.GetProperty("shipRef").GetString() &&
            !original.TryGetProperty("shipId", out _) && !original.TryGetProperty("code", out _), "image maps only scoped references and validated content");
        var imageCalls = calls;
        await Error(() => Image(b), "communities.refreshRequired");
        await Error(() => Image(a, new string('f', 32)), "communities.refreshRequired");
        await Error(() => Image(a, scope: "other"), "communities.refreshRequired");
        Check(calls == imageCalls, "cross-organization or fabricated image references never issue HTTP");
        foreach (var fault in new[] { "code", "ship", "version", "hash", "mime", "size", "count", "offset", "next", "crop" })
        {
            mode = "image-" + fault;
            await Error(() => Image(a), "communities.dataInvalid");
        }
        foreach (var (status, error) in new[] { (401, "identityUnavailable"), (403, "notAllowed"), (404, "notFound"), (409, "mediaChanged") })
        { mode = "status-" + status; await Error(() => Image(a), "communities." + error); }
        mode = "stale";
        await Error(() => Image(a), "fixture.stale");
        current = true; mode = "ok";
        Check(ship.GetProperty("ownerGameName").GetString() == "" && ship.GetProperty("sharedAt").ValueKind == JsonValueKind.Null &&
            ship.GetProperty("catalogPriceUsd").ValueKind == JsonValueKind.Null && ship.GetProperty("customImageCropFocusX").GetDouble() == .3,
            "redaction, unknown time/price and crop remain exact");
        Check(first.GetProperty("ships").EnumerateArray().Select(x => x.GetProperty("shipRef").GetString()).Distinct().Count() == 20,
            "same model has distinct instance references");
        var again = await Read(a);
        Check(again.GetProperty("ships")[0].GetProperty("shipRef").GetString() == ship.GetProperty("shipRef").GetString(), "stable within the same scope");
        var second = await Read(a, 20, revision);
        Check(second.GetProperty("ships").GetArrayLength() == 1 && second.GetProperty("next").ValueKind == JsonValueKind.Null, "last page");
        var other = await Read(b);
        Check(other.GetProperty("ships")[0].GetProperty("shipRef").GetString() != ship.GetProperty("shipRef").GetString() &&
            other.GetProperty("ships")[0].GetProperty("ownerMemberRef").GetString() != ship.GetProperty("ownerMemberRef").GetString(), "references are organization scoped");
        async Task<JsonElement> Library() => JsonSerializer.SerializeToElement(await client.ReadShipsAsync("fixture-bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, offset = 0, query = new
                { text = " a&b ", filter = "all", sort = "name", descending = false, culture = "en-US" } }), "scope", Current, CancellationToken.None));
        var libraryResult = await Library();
        Check(libraryResult.GetProperty("queryVersion").GetInt32() == 2 && libraryResult.GetProperty("matchedCount").GetInt32() == 21 &&
            libraryResult.GetProperty("query").GetProperty("text").GetString() == "a&b", "normalized library query returned intact");
        foreach (var broken in new[] { "query-echo", "query-version", "query-count" })
        {
            mode = broken;
            await Error(Library, broken == "query-version" ? "communities.upgradeRequired" : "communities.dataInvalid");
        }
        mode = "ok";
        var before = calls;
        await Error(() => Read(a, scope: "another-account"), "communities.refreshRequired");
        await Error(() => Read(a, 20), "communities.dataInvalid");
        await Error(() => Read(a, 1), "communities.dataInvalid");
        Check(calls == before, "invalid scope and cursor rejected before network");
        foreach (var broken in new[] { "code", "schema", "count", "next", "revision", "duplicate", "order", "member", "time", "crop", "size", "duplicate-json" })
        {
            mode = broken;
            await Error(() => Read(a), "communities.dataInvalid");
        }
        foreach (var pair in new[] { ("status-401", "identityUnavailable"), ("status-403", "notAllowed"),
            ("status-404", "notFound"), ("status-409", "shipsChanged"), ("status-503", "unavailable"), ("network", "unavailable") })
        {
            mode = pair.Item1;
            await Error(() => Read(a), "communities." + pair.Item2);
        }
        mode = "stale";
        await Error(() => Read(a), "fixture.stale");
        current = true; mode = "empty";
        Check((await Read(a)).GetProperty("ships").GetArrayLength() == 0, "empty shared directory is valid");
        mode = "ok";
        clock.Advance(4);
        await Read(a);
        clock.Advance(4);
        await Read(a);
        await Read(b);
        clock.Advance(4);
        mode = "status-403";
        await Error(() => Read(a), "communities.notAllowed");
        clock.Advance(2);
        mode = "ok";
        before = calls;
        await Read(a);
        Check(calls > before, "expired root addresses reauthorize against the server instead of demanding manual refresh");
        var freshDirectory = await client.ReadAsync("fixture-bearer", new("mine", "", null, null), "scope", CancellationToken.None);
        var fresh = freshDirectory.Items[0].TargetRef;
        await Read(fresh);
        client.Dispose();
        await Error(() => Read(fresh), "communities.refreshRequired");
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static async Task Error(Func<Task<JsonElement>> run, string expected)
    {
        try { await run(); throw new Exception("Expected " + expected); }
        catch (AccountBridgeHostException e) { Check(e.Code == expected, $"expected {expected}, got {e.Code}"); }
    }
    private static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> handle) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(handle(request));
    }
    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(int minutes) => _now = _now.AddMinutes(minutes);
    }
}
