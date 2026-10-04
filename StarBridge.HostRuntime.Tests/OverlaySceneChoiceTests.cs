using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;
using StarBridge.Core.Overlay;

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
            (bool Known, string? Room) presetRoom = (false, null);
            (BridgeAccountContext? Owner, long Generation) scope = (Owner, 1);
            InformationOverlayModuleDemand? demand = null;
            OverlaySourceLease? roomLease = null;
            using var source = new OverlayCommunitySource(() => scope, reader, false, choiceStore: store, room: () => room,
                presetRoomTrigger: () => presetRoom, moduleDemand: () => demand, moduleRoomLease: () => roomLease);
            async Task<BridgeEnvelope> Send(string mode, long revision, string? code = null) =>
                (await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, Guid.NewGuid().ToString(), scope.Generation,
                    new { schemaVersion = 1, revision, mode, code }, scope.Owner), default)).Response;
            var read = await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.ReadRequest, "read", 1,
                new { schemaVersion = 1 }, Owner), default);
            Check(read.Response.Error is null && read.Response.Payload.GetProperty("organizations").GetArrayLength() == 2, "Read real authorized targets.");
            Check(read.Response.Payload.GetProperty("status").GetString() == "standby", "Closed overlay is not indefinitely loading.");
            Check(!read.Response.Payload.TryGetProperty("automaticPresetSourceId", out _),
                "Unknown room membership cannot manufacture an automatic preset trigger.");
            presetRoom = (true, null);
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
            Check((await Focus("A")).Payload.GetProperty("automaticPresetSourceId").GetString() == "org:A",
                "Preset trigger uses the shared C7 resolution result, independent of a preset binding.");
            presetRoom = (false, null);
            Check(!(await Focus("A")).Payload.TryGetProperty("automaticPresetSourceId", out _),
                "Unknown/expired room membership suppresses switching instead of restoring.");
            presetRoom = (true, "room-one");
            Check((await Focus("A")).Payload.GetProperty("automaticPresetSourceId").GetString() == "room:room-one",
                "Confirmed room identity drives entry and distinguishes different rooms.");
            presetRoom = (true, null);
            var choiceDirectory = Path.Combine(root, "overlay-source-v1");
            var roomPolicy = new OverlayPresetSources(new(OverlaySourceMode.Room));
            roomLease = new(OverlaySourceMode.Room, "room-one", OverlaySceneChoiceStore.Hash(Owner), 1, DateTimeOffset.UtcNow.AddMinutes(1));
            demand = new(roomPolicy, [OverlaySourceModule.Members]);
            var bound = (await Focus("A")).Payload;
            Check(bound.GetProperty("presetBindingId").GetString() == "room" && bound.GetProperty("actualId").GetString() == "room" &&
                bound.GetProperty("mode").GetString() == "auto", "Picker uses preset binding without replacing persisted account choice.");
            var preview = bound.GetProperty("resolvedSourceIds");
            Check(preview.GetProperty("auto").GetString() == "room" && preview.GetProperty("room").GetString() == "room" &&
                preview.GetProperty("org:A").GetString() == "org:A",
                "Preview uses the native automatic/explicit resolution rules without inferring them from selected mode.");
            demand = new(roomPolicy, [OverlaySourceModule.Members], new(OverlaySceneChoiceStore.Hash(Owner), 1,
                new(OverlaySourceMode.Community, "A", OverlaySceneChoiceStore.Hash(Owner))));
            var temporary = (await Focus("A")).Payload;
            Check(temporary.GetProperty("temporarySourceId").GetString() == "org:A" && temporary.GetProperty("actualId").GetString() == "org:A" &&
                store.Read(Owner).Revision == 0, "Both picker labels resolve the same temporary > preset > account precedence, without saving.");
            demand = new(roomPolicy, [], new(OverlaySceneChoiceStore.Hash(Owner), 2, OverlaySourceBinding.Automatic));
            Check(!(await Focus("A")).Payload.TryGetProperty("temporarySourceId", out _), "Picker drops old-generation temporary selection.");
            demand = null; roomLease = null;
            Directory.CreateDirectory(choiceDirectory);
            var lockPath = Path.Combine(choiceDirectory, OverlaySceneChoiceStore.Hash(Owner) + ".json.lock");
            using (var locked = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
                Check((await Send("room", 0)).Error?.Code == "overlayScenes.storage_unavailable", "Synthetic save lock failure is reported without changing the selected scope.");
            Check(source.CaptureResolutionContext(Owner, 1, null)?.FocusedCommunityCode == "A" && source.Mode == "auto",
                "A failed preference write cannot reset same-account focus or unlock a source budget.");
            room = new("room", "Room", "", 4, "", [], []);
            Check((await Focus("B")).Payload.GetProperty("actualId").GetString() == "room",
                "Existing current-room priority remains unchanged in automatic mode");
            room = null;
            Check((await Focus("unknown")).Error is not null, "Unknown focus rejected.");
            Check((await Send("community", 0, "B")).Error is null, "Select specific organization.");
            Check(source.CaptureResolutionContext(Owner, 1, null)?.FocusedCommunityCode == "B",
                "C7 most recent picker choice replaces the previous page focus.");
            await source.RefreshAsync();
            Check(source.Read()?.Code == "B" && source.Mode == "community", "Native source follows selection.");
            Check((await Focus("A")).Error is null, "Page context can update in manual mode.");
            Check(source.CaptureResolutionContext(Owner, 1, null)?.FocusedCommunityCode == "A",
                "C7 later page navigation becomes automatic focus without changing the manual account choice.");
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
        Check(!OverlaySceneChoiceStore.Valid("community", " A") && !OverlaySceneChoiceStore.Valid("community", "A ") &&
            OverlaySceneChoiceStore.Valid("community", "A"), "Saved codes obey the same exact-key contract as module sources.");
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

    internal static async Task LocalChoiceBypassesSlowCatalog()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-slow-catalog-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var reader = new SlowReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, choiceStore: new(root));
        Task<BridgeDispatchBatch>? read = null;
        Task<BridgeDispatchBatch>? select = null;
        try
        {
            read = source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.ReadRequest, "read", 1,
                new { schemaVersion = 1 }, Owner), default).AsTask();
            await reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            select = source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, "select", 1,
                new { schemaVersion = 1, revision = 0, mode = "room" }, Owner), default).AsTask();
            Check(await Task.WhenAny(select, Task.Delay(500)) == select,
                "A local room choice must not wait behind an unrelated network catalog read.");
            Check((await select).Response.Error is null && source.Mode == "room", "Room choice persists while catalog is pending.");
        }
        finally
        {
            reader.Release.TrySetResult([]);
            if (read is not null) await read;
            if (select is not null) await select;
            Directory.Delete(root, true);
        }
    }
    private sealed class SlowReader : IOverlayCommunityReader
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource<IReadOnlyList<OverlayCommunityTarget>> Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token)
        { Started.TrySetResult(); return Release.Task.WaitAsync(token); }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            throw new NotSupportedException();
    }
}
