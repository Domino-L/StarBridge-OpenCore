using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Hangar;
using static HangarLockedScanTests;

internal static class LocalHangarReconciliationBridgeTests
{
    public static void Verify()
    {
        var root = Directory.CreateTempSubdirectory("sb-hangar-reconciliation-");
        try
        {
            var store = new LocalHangarStore(root.FullName);
            using var test = new Harness(store);
            var initial = store.Save(test.Owner.Account, 0, "reconciliation-seed",
                Enumerable.Range(0, 201).Select(i => new StarBridge.Core.Hangar.CollectedHangarShip(
                    "synthetic-1", i, "Test Ship", "Test Builder", null)).ToArray(), false, false);
            test.Send("verify", test.Initial());
            JsonObject Page()
            {
                var body = test.Page(1, 1);
                var page = body["observation"]!["page"]!;
                page["totalPages"] = 1; page["nextPage"] = null;
                return body;
            }
            test.Send("observe", Page());
            Expect(test.Send("observe", Page()), "complete", "A singleton verified scan is complete");
            var first = test.Send("removals", new JsonObject { ["expectedRevision"] = 1 });
            if (first.Error is not null || first.Payload.GetProperty("total").GetInt32() != 201 ||
                first.Payload.GetProperty("rows").GetArrayLength() != 200 ||
                first.Payload.GetProperty("nextOffset").GetInt32() != 200 ||
                first.Payload.GetRawText().Contains("synthetic-1"))
                throw new Exception("Removal review must paginate local IDs without exposing pledge keys.");
            var second = test.Send("removals", new JsonObject { ["expectedRevision"] = 1, ["offset"] = 200 });
            if (second.Error is not null || second.Payload.GetProperty("rows").GetArrayLength() != 1 ||
                second.Payload.GetProperty("rows")[0].GetProperty("requiredCount").GetInt32() != 200)
                throw new Exception("Large duplicate groups lost candidates between review pages.");
            if (test.Send("removals", new JsonObject { ["expectedRevision"] = 0 }).Error?.Code != "hangar.revision_conflict" ||
                test.Send("removals", new JsonObject { ["expectedRevision"] = 1, ["ships"] = new JsonArray() }).Error?.Code != "hangar.invalid_observation" ||
                test.Send("save", new JsonObject { ["expectedRevision"] = 1 }).Error?.Code != "hangar.removal_selection_required")
                throw new Exception("Review/save failed to enforce verified scan and revision requirements.");
            var ids = initial.Ships.Skip(1).Select(s => s.Id).ToArray();
            var saved = test.Send("save", new JsonObject { ["expectedRevision"] = 1,
                ["removedShipIds"] = new JsonArray(ids.Select(s => (JsonNode?)JsonValue.Create(s)).ToArray()) });
            if (saved.Error is not null || saved.Payload.GetProperty("total").GetInt32() != 1 ||
                saved.Payload.GetProperty("formerTotal").GetInt32() != 200 ||
                saved.Payload.GetProperty("ships")[0].GetProperty("id").GetString() != initial.Ships[0].Id ||
                saved.Payload.GetProperty("inventorySavedAt").GetDateTimeOffset() != saved.Payload.GetProperty("savedAt").GetDateTimeOffset())
                throw new Exception("Resolved bridge save lost identity, history or inventory time.");
            test.Send("cancel", new JsonObject());
            if (test.Send("removals", new JsonObject { ["expectedRevision"] = 2 }).Error?.Code != "hangar.operation_expired")
                throw new Exception("Cancelled scan still offers removal choices.");
        }
        finally { root.Delete(true); }
    }
}
