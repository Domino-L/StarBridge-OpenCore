using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Hangar;
using static HangarLockedScanTests;

internal static class LocalHangarBridgeTests
{
    public static Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-local-hangar-bridge-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var test = new Harness(new LocalHangarStore(root));
            if (test.Send("inventory", new JsonObject()).Payload.GetProperty("revision").GetInt64() != 0)
                throw new Exception("New authenticated hangar should be unsaved");
            test.Send("verify", test.Initial());
            foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) })
                test.Send("observe", test.Page(page, doc));
            var done = test.Send("observe", test.Page(1, 3));
            if (!done.Payload.GetProperty("canSave").GetBoolean()) throw new Exception("Complete local scan cannot save");
            var saved = test.Send("save", new JsonObject { ["expectedRevision"] = 0, ["confirmEmpty"] = false });
            if (saved.Error != null || saved.Payload.GetProperty("total").GetInt32() != 2 ||
                saved.Payload.GetProperty("revision").GetInt64() != 1)
                throw new Exception("Confirmed scan was not durably saved");
            var repeated = test.Send("save", new JsonObject { ["expectedRevision"] = 0, ["confirmEmpty"] = false });
            if (repeated.Error != null || repeated.Payload.GetProperty("revision").GetInt64() != 1)
                throw new Exception("Retry duplicated the save");
            test.Send("cancel", new JsonObject());
            if (test.Send("save", new JsonObject { ["expectedRevision"] = 1 }).Error?.Code != "hangar.operation_expired")
                throw new Exception("Cancelled candidate remained saveable");
            using var reopened = new Harness(new LocalHangarStore(root));
            var read = reopened.Send("inventory", new JsonObject());
            if (read.Payload.GetProperty("total").GetInt32() != 2 ||
                read.Payload.GetRawText().Contains("synthetic-1"))
                throw new Exception("Reopen lost ships or exposed raw pledge keys");
            // Like WPF, a verified scan replaces the inventory even if package
            // accessories have no recognized type. Removed ships enter history.
            reopened.Send("verify", reopened.Initial());
            JsonObject CompletePage() {
                var body = reopened.Page(1, 1);
                var page = body["observation"]!["page"]!;
                page["totalPages"] = 1; page["nextPage"] = null;
                page["pledges"]![0]!["sourceKey"] = "synthetic-new";
                page["pledges"]![0]!["items"]!.AsArray().Add(
                    new JsonObject { ["title"] = "Unclassified object", ["kind"] = "unknown" });
                return body;
            }
            reopened.Send("observe", CompletePage());
            var complete = reopened.Send("observe", CompletePage());
            Expect(complete, "complete", "Non-ship items do not block completion");
            var merged = reopened.Send("save", new JsonObject { ["expectedRevision"] = 1 });
            if (merged.Error != null || merged.Payload.GetProperty("total").GetInt32() != 1 ||
                merged.Payload.GetProperty("partial").GetBoolean())
                throw new Exception("Complete scan did not replace the old inventory");
            reopened.Owner = reopened.Owner with { Generation = 8 };
            Expect(reopened.Send("save", new JsonObject { ["expectedRevision"] = 2 }),
                "accountChanged", "A restored generation cannot commit an old scan");
            if (reopened.Send("inventory", new JsonObject()).Payload.GetProperty("revision").GetInt64() != 2)
                throw new Exception("Account transition changed durable hangar");
            using var injected = new Harness(new LocalHangarStore(root));
            injected.Send("verify", injected.Initial());
            foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) })
                injected.Send("observe", injected.Page(page, doc));
            var rejected = injected.Send("save", new JsonObject {
                ["expectedRevision"] = 2, ["ships"] = new JsonArray() });
            if (rejected.Error?.Code != "hangar.invalid_observation")
                throw new Exception("Client supplied a replacement inventory");
            var historyStore = new LocalHangarStore(root);
            historyStore.Save(injected.Owner.Account, 2, "history-clear", [], false, true);
            var history = injected.Send("inventory", new JsonObject { ["former"] = true, ["revision"] = 3 });
            if (history.Error is not null || history.Payload.GetProperty("total").GetInt32() != 3 ||
                !history.Payload.GetProperty("former").GetBoolean() ||
                history.Payload.GetRawText().Contains("synthetic-1") ||
                history.Payload.GetProperty("ships")[0].GetProperty("removedAt").GetDateTimeOffset() == default)
                throw new Exception("History lost removal facts or exposed pledge identities.");
            if (injected.Send("inventory", new JsonObject()).Payload.GetProperty("total").GetInt32() != 0 ||
                injected.Send("inventory", new JsonObject { ["former"] = true, ["revision"] = 2 }).Error?.Code != "hangar.revision_conflict")
                throw new Exception("History affected current inventory or mixed revisions.");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        VerifyEmptyConfirmation();
        return Task.CompletedTask;
    }

    private static void VerifyEmptyConfirmation()
    {
        var root = Directory.CreateTempSubdirectory("sb-hangar-empty-");
        try
        {
            using var test = new Harness(new LocalHangarStore(root.FullName));
            test.Send("verify", test.Initial());
            JsonObject Page()
            {
                var body = test.Page(1, 1);
                var page = body["observation"]!["page"]!;
                page["totalPages"] = 1; page["nextPage"] = null;
                page["pledges"]![0]!["items"]![0]!["kind"] = null;
                return body;
            }
            test.Send("observe", Page());
            Expect(test.Send("observe", Page()), "complete", "Non-ship-only scan completes");
            var unconfirmed = test.Send("save", new JsonObject { ["expectedRevision"] = 0, ["confirmEmpty"] = false });
            if (unconfirmed.Error?.Code != "hangar.empty_confirmation_required")
                throw new Exception("Ignoring accessories bypassed empty inventory confirmation");
            var confirmed = test.Send("save", new JsonObject { ["expectedRevision"] = 0, ["confirmEmpty"] = true });
            if (confirmed.Error is not null || confirmed.Payload.GetProperty("partial").GetBoolean() ||
                confirmed.Payload.GetProperty("total").GetInt32() != 0)
                throw new Exception("Confirmed empty inventory was not saved complete");
        }
        finally { root.Delete(true); }
    }
}
