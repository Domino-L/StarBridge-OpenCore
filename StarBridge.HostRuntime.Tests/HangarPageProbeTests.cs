using System.Text.Json;
using StarBridge.Core.Hangar;

internal static class HangarPageProbeTests
{
    // Test-only bridge. Production message validation/identity routing is not registered.
    public static void Verify(JsonElement results)
    {
        var expected = new Dictionary<string, string>(StringComparer.Ordinal) {
            ["first16"] = "ready", ["last16"] = "ready", ["scan-first"] = "ready", ["scan-last"] = "ready",
            ["untyped"] = "ready", ["empty-pledge"] = "ready", ["new-kind"] = "ready",
            ["empty-list"] = "unconfirmedEmpty", ["ui-filter"] = "filtered", ["url-filter"] = "filtered", ["search-filter"] = "filtered",
            ["pager-conflict"] = "unsupported", ["wrong-page-url"] = "unsupported", ["external-link"] = "unsupported",
            ["malformed-page"] = "unsupported", ["page-limit"] = "unsupported", ["missing-title"] = "unsupported",
            ["duplicate-key"] = "unsupported", ["nested-item"] = "unsupported", ["missing-filter"] = "unsupported",
            ["missing-root"] = "unsupported", ["long-title"] = "unsupported", ["missing-key"] = "unsupported",
            ["unknown-empty-layout"] = "unsupported", ["row-limit"] = "unsupported", ["single-page-unproven"] = "ready"
        };
        var pages = new Dictionary<string, HangarPageObservation>(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in results.EnumerateArray())
        {
            var id = entry.GetProperty("id").GetString()!;
            Require(seen.Add(id) && expected.TryGetValue(id, out _), "Unexpected/duplicate fixture case");
            var item = entry.GetProperty("observation");
            Require(item.EnumerateObject().Count() == 9 && item.GetProperty("schemaVersion").GetInt32() == 1 &&
                item.GetProperty("documentUrl").GetString() == "about:blank", $"{id}: invalid envelope");
            Require(item.GetProperty("status").GetString() == expected[id], $"{id}: wrong parse status");
            Require(!item.GetRawText().Contains("PRIVATE_NOT_COLLECTED", StringComparison.Ordinal), "Unrequested private fields collected");
            foreach (var pledge in item.GetProperty("pledges").EnumerateArray())
            {
                Require(pledge.EnumerateObject().Count() == 3, "Unexpected pledge fields");
                foreach (var child in pledge.GetProperty("items").EnumerateArray())
                    Require(child.EnumerateObject().Count() == 3, "Unexpected item fields");
            }
            if (expected[id] != "ready")
                Require(item.GetProperty("pledges").GetArrayLength() == 0, "Partial parse must not expose a ready inventory");
            else
                pages.Add(id, JsonSerializer.Deserialize<HangarPageObservation>(item.GetRawText(),
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!);
        }
        Require(seen.Count == expected.Count, "Missing native page cases");
        Require(pages["first16"] is { Page: 1, TotalPages: 16, NextPage: 2 }, "Visible numeric links are not total pages");
        Require(pages["last16"] is { Page: 16, TotalPages: null, NextPage: null }, "Observed last page has no next/last buttons");
        var lastOnly = new HangarScanSession();
        Require(lastOnly.Observe(1, pages["last16"]).State == HangarScanState.Invalid, "Last-page snapshot alone cannot complete a scan");

        var complete = Scan(pages["scan-first"], pages["scan-last"]);
        Require(complete.IsComplete && complete.Ships.Count == 2, "Two same-model ship children must remain two instances");
        Require(complete.Ships[0].PledgeKey == complete.Ships[1].PledgeKey && complete.Ships[0].ItemIndex != complete.Ships[1].ItemIndex,
            "Parent key is not a child instance ID");
        Require(complete.Ships.All(s => s.Title == "Test Ship" && s.Liner == "Test Builder" && s.AcquiredText == "Sep 01, 2026"), "Ship fields changed");
        Require(pages["scan-last"].Pledges[0].AcquiredText is null, "Absent date must remain absent");
        foreach (var id in new[] { "untyped", "empty-pledge", "new-kind" })
        {
            var result = Scan(pages[id], pages["scan-last"]);
            Require(result.IsComplete && result.Ships.Count == 0, $"{id}: non-ship contents must not block completion");
        }
        var single = new HangarScanSession();
        single.Observe(1, pages["single-page-unproven"]);
        Require(single.Observe(2, pages["single-page-unproven"]).Issue == HangarScanIssue.MissingPaginationProof,
            "Missing next alone is not evidence of a one-page hangar");
        Console.WriteLine($"PASS Native WebView2 page parsing: {seen.Count}/{expected.Count}; stable multi-page scan, package occurrences and incomplete-data gates");
    }

    private static HangarScanSnapshot Scan(HangarPageObservation first, HangarPageObservation last)
    {
        var scan = new HangarScanSession();
        Require(scan.Observe(1, first).Pages.Count == 0, "One sample must not advance");
        Require(scan.Observe(2, first).ExpectedPage == 2, "Stable first page must advance");
        scan.Observe(3, last);
        Require(scan.Observe(4, last).State == HangarScanState.VerifyingFirstPage, "Recheck first page before completion");
        scan.Observe(5, first);
        return scan.Observe(6, first);
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
