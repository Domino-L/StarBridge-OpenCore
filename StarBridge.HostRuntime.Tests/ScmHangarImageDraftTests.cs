using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;
using StarBridge.Core.Hangar;

[System.Runtime.Versioning.SupportedOSPlatform("windows")]
internal static class ScmHangarImageDraftTests
{
    internal static async Task RunAsync()
    {
        PublicationImages();
        await PreparePublicationImagesAsync();
        var owner = new BridgeAccountContext("fixture", "scm", "owner");
        long generation = 2;
        var ship = new LocalHangarShip("instance", "pledge", "Fixture ship", null, null, DateTimeOffset.UtcNow);
        var snapshot = new LocalHangarSnapshot(1, null, null, [ship]);
        using var picker = new Picker();
        using var bridge = new HangarImageDraftBridge(picker, () => (owner, generation), _ => snapshot);
        BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, body, owner);
        Task<BridgeDispatchBatch> Pick(string id = "instance") => bridge.DispatchAsync(Request("hangarImage.pick", new { schemaVersion = 1, shipId = id, expectedRevision = snapshot.Revision })).AsTask();
        var unknown = await Pick("missing");
        Check(unknown.Response.Error?.Code == "hangar.image_ship_unavailable" && picker.Picks == 0, "unknown ship cannot open a file picker");
        var forged = await bridge.DispatchAsync(Request("hangarImage.pick", new { schemaVersion = 1, shipId = "instance", expectedRevision = 1, path = "never-read.png" }));
        Check(forged.Response.Error is not null && picker.Picks == 0, "arbitrary path is rejected");
        var selected = await Pick();
        var reference = selected.Response.Payload.GetProperty("draftRef").GetString()!;
        Check(selected.Response.Payload.GetProperty("status").GetString() == "selected" && !selected.Response.Payload.GetRawText().Contains("sourceRef"), "only draft reference and bounded preview leave Host");
        Expect("hangar.image_not_prepared", () => bridge.TakePrepared(owner, generation, reference));
        var cropped = await bridge.DispatchAsync(Request("hangarImage.crop", new { schemaVersion = 1, draftRef = reference, x = 0.0, y = 0.0, size = 1.0 }));
        Check(cropped.Response.Payload.GetProperty("status").GetString() == "prepared", "crop prepares image without persistence");
        snapshot = snapshot with { Revision = 2 };
        Expect("hangar.revision_conflict", () => bridge.TakePrepared(owner, generation, reference));
        selected = await Pick(); reference = selected.Response.Payload.GetProperty("draftRef").GetString()!;
        await bridge.DispatchAsync(Request("hangarImage.crop", new { schemaVersion = 1, draftRef = reference, x = 0.0, y = 0.0, size = 1.0 }));
        var prepared = bridge.TakePrepared(owner, generation, reference);
        Check(prepared.Ship == ship && prepared.Revision == 2 && prepared.ImageData == Picker.Image, "confirmation consumes exact current ship and native image");
        Expect("hangar.image_draft_expired", () => bridge.TakePrepared(owner, generation, reference));
        picker.Cancel = true;
        Check((await Pick()).Response.Payload.GetProperty("status").GetString() == "cancelled", "cancel has no draft");
        picker.Cancel = false;
        picker.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var late = Pick();
        Check((await Pick()).Response.Error?.Code == "hangar.image_busy", "duplicate pick is rejected");
        generation++; bridge.Invalidate();
        picker.Pending.SetResult(new(new string('a', 32), Picker.Image, 512, 512));
        Check((await late).Response.Status != "ok", "late old-account image never reaches new account");
        Check(snapshot.Ships.Count == 1 && snapshot.Ships[0] == ship, "draft operations leave inventory unchanged");
        await SaveRoundTripAsync();
        Console.WriteLine("PASS SCM hangar image drafts: native selection, exact ship/revision, cancel, stale account and one-time confirmation");
    }
    private static async Task PreparePublicationImagesAsync()
    {
        var first = new LocalHangarShip("one", "pledge", "Fixture ship", null, null, DateTimeOffset.UtcNow);
        var snapshot = new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, "fixture", [first, first with { Id = "two" }]);
        var reads = 0; var uploads = 0; var stale = false;
        Task<StarBridge.Core.ShipMedia.ShipMediaSummaryContract> Upload(StarBridge.Core.ShipMedia.ShipMediaUploadRequestContract request, CancellationToken token)
        {
            uploads++;
            Check(reads == 2 && !request.ImageBase64.StartsWith("data:") && Guid.TryParseExact(request.ClientRequestId, "N", out _),
                "all local images are read before upload and transport contains prepared bytes only");
            return Task.FromResult(new StarBridge.Core.ShipMedia.ShipMediaSummaryContract(Guid.NewGuid().ToString("N"),
                request.ShipInstanceId, request.ShipCode, request.ShipDisplayName, "owner", "Fixture", "image/png", 1, 1, 100, DateTimeOffset.UtcNow));
        }
        var result = await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return id == "one" ? Picker.Image : null; }, Upload, () => { }, default);
        Check(uploads == 1 && result[0].ImageMediaId is not null && result[1].ImageMediaId is null,
            "only ships with local images upload and receive references");
        reads = 0; uploads = 0;
        try
        {
            await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return id == "one" ? Picker.Image : "invalid"; }, Upload, () => { }, default);
            throw new InvalidOperationException("Invalid image accepted");
        }
        catch (LocalHangarStoreException e) when (e.Code == "hangar.image_read_failed") { }
        Check(uploads == 0, "bad later local image prevents every upload");
        reads = 0;
        try
        {
            await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return Picker.Image; },
                async (request, token) => { var receipt = await Upload(request, token); stale = true; return receipt; },
                () => { if (stale) throw new LocalHangarStoreException("hangar.revision_conflict", "Changed"); }, default);
            throw new InvalidOperationException("Stale publication accepted");
        }
        catch (LocalHangarStoreException e) when (e.Code == "hangar.revision_conflict") { }
        Check(uploads == 1, "version change after first upload prevents second upload and publication");
    }

    private static void PublicationImages()
    {
        var ship = new LocalHangarShip("exact-instance", "pledge", "Fixture ship", null, null, DateTimeOffset.UtcNow);
        var snapshot = new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, "fixture", [ship]);
        var plain = CommunityHangarPublication.Build(snapshot).Single();
        var media = new StarBridge.Core.ShipMedia.ShipMediaSummaryContract(Guid.NewGuid().ToString("N"),
            ship.Id, plain.Code, ship.Title, "owner", "Fixture", "image/png", 1, 1, 100, DateTimeOffset.UtcNow);
        Check(plain.ImageMediaId is null, "ordinary publication does not infer image consent");
        Check(CommunityHangarPublication.WithImages(snapshot, "owner", [media]).Single().ImageMediaId == media.MediaId,
            "approved exact-owner upload receipt is attached");
        Check(CommunityHangarPublication.WithImages(snapshot, "owner", []).Single().ImageMediaId is null,
            "no approved receipt means no stale image reference");
        foreach (var invalid in new[] { media with { OwnerAccountId = "other" }, media with { ShipInstanceId = "EXACT-INSTANCE" },
            media with { ShipCode = "other" }, media with { MediaId = "local/path.png" } })
            Expect("hangar.image_not_allowed", () => CommunityHangarPublication.WithImages(snapshot, "owner", [invalid]));
        Expect("hangar.image_not_allowed", () => CommunityHangarPublication.WithImages(snapshot, "owner", [media, media]));
        var json = System.Text.Json.JsonSerializer.Serialize(CommunityHangarPublication.WithImages(snapshot, "owner", [media]));
        Check(!json.Contains("OwnerAccountId") && !json.Contains("ImageBase64") && !json.Contains("CustomImagePath"),
            "publication contains media reference, not local storage or owner metadata");
    }

    private static async Task SaveRoundTripAsync()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-hangar-image-test-");
        try
        {
            var owner = new BridgeAccountContext("fixture", "scm", "image-owner");
            var store = new LocalHangarStore(root.FullName);
            var snapshot = store.Save(owner, 0, "scan", [new CollectedHangarShip("pledge", 0, "Fixture", null, null)], false, false);
            var id = snapshot.Ships.Single().Id;
            using var picker = new Picker();
            using var bridge = new HangarImageDraftBridge(picker, () => (owner, 1L), store.Read, store);
            BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, body, owner);
            var selected = await bridge.DispatchAsync(Request("hangarImage.pick", new { schemaVersion = 1, shipId = id, expectedRevision = 1 }));
            var reference = selected.Response.Payload.GetProperty("draftRef").GetString()!;
            await bridge.DispatchAsync(Request("hangarImage.crop", new { schemaVersion = 1, draftRef = reference, x = 0.0, y = 0.0, size = 1.0 }));
            Check(store.Read(owner).Revision == 1 && store.ReadCustomImage(owner, 1, id) is null, "preparing does not persist image");
            var saved = await bridge.DispatchAsync(Request("hangarImage.save", new { schemaVersion = 1, draftRef = reference }));
            Check(saved.Response.Payload.GetProperty("revision").GetInt64() == 2, "explicit confirmation persists a revision");
            var reopened = new LocalHangarStore(root.FullName);
            Check(reopened.ReadCustomImage(owner, 2, id) == Picker.Image, "image survives store reopen");
            var read = await bridge.DispatchAsync(Request("hangarImage.read", new { schemaVersion = 1, shipId = id, expectedRevision = 2 }));
            Check(read.Response.Payload.GetProperty("imageData").GetString() == Picker.Image, "bridge reads native-owned image without path");
            Check(store.SaveCustomImage(owner, 1, reference, id, Picker.Image).Revision == 2, "identical save receipt replays without revision change");
            Expect("hangar.revision_conflict", () => store.SaveCustomImage(owner, 1, "stale", id, Picker.Image));
            Expect("hangar.account_changed", () => store.SaveCustomImage(owner, 2, "cancel", id, Picker.Image, () => false));
            var file = Directory.GetFiles(Path.Combine(root.FullName, "hangar-local-v1"), "*.json").Single();
            using (var locked = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
                Expect("hangar.storage_write_failed", () => store.SaveCustomImage(owner, 2, "retry", id, Picker.Image));
            Check(store.Read(owner).Revision == 2 && store.ReadCustomImage(owner, 2, id) == Picker.Image, "failed commit leaves old inventory and image intact");
            Check(store.SaveCustomImage(owner, 2, "retry", id, Picker.Image).Revision == 3, "failed save can be retried explicitly");
            Expect("hangar.image_ship_unavailable", () => store.ReadCustomImage(owner with { Subject = "other" }, 0, id));
            var image = Directory.GetFiles(Path.Combine(root.FullName, "hangar-local-v1"), "*.png").Single();
            // This is a freshly created synthetic fixture, never a user file.
            File.WriteAllBytes(image, [1, 2, 3]);
            Expect("hangar.image_read_failed", () => store.ReadCustomImage(owner, 3, id));
            Check(store.Read(owner).Revision == 3, "corrupt image does not corrupt inventory");
            var restoreRequest = Request("hangarImage.restore", new { schemaVersion = 1, shipId = id, expectedRevision = 3 });
            var restored = await bridge.DispatchAsync(restoreRequest);
            Check(restored.Response.Payload.GetProperty("revision").GetInt64() == 4, "restore default commits a local revision");
            Check(store.ReadCustomImage(owner, 4, id) is null && File.Exists(image), "restore removes reference, never original or retained image bytes");
            Check((await bridge.DispatchAsync(restoreRequest)).Response.Payload.GetProperty("revision").GetInt64() == 4, "restore replay preserves revision");
            var staleRestore = await bridge.DispatchAsync(Request("hangarImage.restore", new { schemaVersion = 1, shipId = id, expectedRevision = 3 }));
            Check(staleRestore.Response.Error?.Code == "hangar.revision_conflict", "new stale restore cannot erase newer state");
            Check(new LocalHangarStore(root.FullName).Read(owner).Ships.Single().Id == id, "restore preserves ship across reopen");
        }
        finally { root.Delete(recursive: true); }
    }
    private static void Expect(string code, Action action)
    {
        try { action(); }
        catch (LocalHangarStoreException error) { Check(error.Code == code, "expected draft rejection: " + code); return; }
        throw new InvalidOperationException("Expected draft rejection: " + code);
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Picker : ICommunityLogoPicker
    {
        internal const string Image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        internal int Picks;
        internal bool Cancel;
        internal TaskCompletionSource<CommunityLogoSource?>? Pending;
        public Task<CommunityLogoSource?> PickAsync(CancellationToken token)
        { Picks++; return Pending?.Task ?? Task.FromResult(Cancel ? null : new CommunityLogoSource(new string('a', 32), Image, 512, 512)); }
        public string Crop(string sourceRef, double x, double y, double size) => Image;
        public void Clear() { }
        public void Dispose() { }
    }
}
