using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlaySceneChoiceTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-scene-owner");
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static async Task BridgeAndPersistence()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-scene-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new OverlaySceneChoiceStore(root);
            var reader = new Reader();
            InformationOverlayRoomContent? room = null;
            (BridgeAccountContext? Owner, long Generation) scope = (Owner, 1);
            using var source = new OverlayCommunitySource(() => scope, reader, false, choiceStore: store, room: () => room);
            async Task<BridgeEnvelope> Send(string mode, long revision, string? code = null) =>
                (await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, Guid.NewGuid().ToString(), scope.Generation,
                    new { schemaVersion = 1, revision, mode, code }, scope.Owner), default)).Response;
            var read = await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.ReadRequest, "read", 1,
                new { schemaVersion = 1 }, Owner), default);
            Check(read.Response.Error is null && read.Response.Payload.GetProperty("organizations").GetArrayLength() == 2, "Read real authorized targets.");
            Check(read.Response.Payload.GetProperty("status").GetString() == "standby", "Closed overlay is not indefinitely loading.");
            async Task<BridgeEnvelope> Focus(string code) =>
                (await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.FocusRequest, Guid.NewGuid().ToString(), scope.Generation,
                    new { schemaVersion = 1, code }, scope.Owner), default)).Response;
            Check((await Focus("B")).Error is null, "Authorized page focus accepted.");
            await source.RefreshAsync();
            Check(source.Mode == "auto" && source.Read()?.Code == "B" && store.Read(Owner).Revision == 0,
                "Automatic source follows page without persisting a manual choice.");
            Check((await Focus("A")).Error is null, "Second organization focus accepted.");
            await source.RefreshAsync();
            Check(source.Read()?.Code == "A", "Automatic source follows organization switches.");
            room = new("room", "Room", "", 4, "", [], []);
            Check((await Focus("B")).Payload.GetProperty("actualId").GetString() == "room",
                "Existing current-room priority remains unchanged in automatic mode");
            room = null;
            Check((await Focus("unknown")).Error is not null, "Unknown focus rejected.");
            Check((await Send("community", 0, "B")).Error is null, "Select specific organization.");
            await source.RefreshAsync();
            Check(source.Read()?.Code == "B" && source.Mode == "community", "Native source follows selection.");
            Check((await Focus("A")).Error is null, "Page context can update in manual mode.");
            await source.RefreshAsync();
            Check(source.Read()?.Code == "B" && store.Read(Owner).Code == "B", "Manual source does not follow page.");
            using var restarted = new OverlayCommunitySource(() => scope, reader, false, choiceStore: new(root));
            Check(restarted.Mode == "community", "Restart restores choice without reprompt.");
            await restarted.RefreshAsync();
            Check(restarted.Read()?.Code == "B", "Restart preserves exact organization.");
            Check((await Send("auto", 0)).Error?.Code == "overlayScenes.conflict", "Reject stale revision.");
            Check((await Send("fleet", 1)).Error is not null, "Fleet remains disabled.");
            Check((await Send("community", 1, "unknown")).Error is not null, "Reject unknown target.");
            reader.Fail = true;
            Check((await Send("room", 1)).Error is null, "Room choice works while directory offline.");
            Check(store.Read(Owner).Mode == "room", "Choice persisted atomically.");
            Check((await Send("auto", 2)).Error is null, "Auto choice is also independent of directory.");
            reader.Fail = false;
            await source.RefreshAsync();
            Check(source.Read()?.Code == "A", "Returning to automatic uses the page visited during manual mode");
            var old = scope;
            scope = (Owner with { Subject = "synthetic-other" }, 2);
            Check(source.Mode == "auto" && source.Read() is null, "Account switch clears old content/choice.");
            var stale = await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, "stale", old.Generation,
                new { schemaVersion = 1, revision = 3, mode = "room", code = (string?)null }, old.Owner), default);
            Check(stale.Response.Error is not null && store.Read(scope.Owner!).Revision == 0, "Late owner cannot write new account.");
            Check(store.Read(Owner).Revision == 3, "Other owner did not mutate original choice.");
            reader.Fail = false;
            reader.Targets = [new("A", "Organization", "a")];
            scope = (Owner, 3);
            Check((await Send("community", 3, "B")).Error is not null, "Leaving an organization revokes selection authority.");
        }
        finally { Directory.Delete(root, true); }
    }
    internal static Task StoreGuards()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-scene-store-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new OverlaySceneChoiceStore(root);
            Check(store.Read(Owner).Mode == "auto", "Fresh account defaults automatic.");
            try { store.Save(Owner, 0, "room", null, () => false); throw new Exception("Late write accepted."); }
            catch (OperationCanceledException) { }
            Check(store.Read(Owner).Revision == 0, "Late writes leave no choice.");
            store.Save(Owner, 0, "community", "B", () => true);
            var path = Directory.GetFiles(Path.Combine(root, "overlay-source-v1"), "*.json").Single();
            File.WriteAllText(path, "{}");
            try { store.Read(Owner); throw new Exception("Corrupt choice silently reset."); }
            catch (InvalidDataException) { }
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private sealed class Reader : IOverlayCommunityReader
    {
        internal bool Fail;
        internal IReadOnlyList<OverlayCommunityTarget> Targets = [new("A", "Organization", "a"), new("B", "Organization", "b")];
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Fail ? throw new AccountBridgeHostException("communities.unavailable", true) : Task.FromResult(Targets);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            Task.FromResult(new InformationOverlayCommunityContent(target.Code, target.Name, []));
    }
}
