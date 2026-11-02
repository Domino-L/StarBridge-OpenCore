using StarBridge.HostRuntime.Hangar;
internal static class HangarImagePublicationTests
{
    internal static async Task Verify() { PublicationImages(); await PreparePublicationImagesAsync(); }
    private static void Check(bool valid, string message) { if (!valid) throw new InvalidOperationException(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); }
        catch (LocalHangarStoreException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
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
        var result = await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return id == "one" ? "data:image/png;base64,AA==" : null; }, Upload, () => { }, default);
        Check(uploads == 1 && result[0].ImageMediaId is not null && result[1].ImageMediaId is null,
            "only ships with local images upload and receive references");
        reads = 0; uploads = 0;
        try
        {
            await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return id == "one" ? "data:image/png;base64,AA==" : "invalid"; }, Upload, () => { }, default);
            throw new InvalidOperationException("Invalid image accepted");
        }
        catch (LocalHangarStoreException e) when (e.Code == "hangar.image_read_failed") { }
        Check(uploads == 0, "bad later local image prevents every upload");
        reads = 0;
        try
        {
            await HangarImagePublication.PrepareAsync(snapshot, "owner", id => { reads++; return "data:image/png;base64,AA=="; },
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

}
