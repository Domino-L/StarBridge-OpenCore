using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class CommunityWideImageBridgeTests
{
    internal static async Task Verify()
    {
        BridgeAccountContext? owner = new("test", "fixture", "synthetic-owner");
        long generation = 1;
        using var picker = new Picker();
        using var bridge = new CommunityLogoBridge(picker, () => (owner, generation));
        BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request("communities." + name,
            Guid.NewGuid().ToString("N"), generation, body, owner);
        BridgeEnvelope Pick(string kind = "banner") => Request("pickWideImage", new { schemaVersion = 1, kind });
        BridgeEnvelope Crop(string kind = "banner", double width = 1) => Request("cropWideImage",
            new { schemaVersion = 1, sourceRef = new string('a', 32), kind, x = 0, y = 0, width });
        void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        foreach (var kind in new[] { "banner", "background" })
        {
            var selected = (await bridge.DispatchAsync(Pick(kind))).Response;
            Check(selected.Payload.GetProperty("status").GetString() == "selected", "selected");
            Check(!selected.Payload.GetRawText().Contains("path", StringComparison.OrdinalIgnoreCase), "opaque source only");
            var crop = (await bridge.DispatchAsync(Crop(kind))).Response;
            Check(crop.Payload.GetProperty("status").GetString() == "cropped", "cropped");
            var clear = (await bridge.DispatchAsync(Request("clearWideImage", new { schemaVersion = 1 }))).Response;
            Check(clear.Payload.GetProperty("status").GetString() == "cleared", "cleared");
            Check((await bridge.DispatchAsync(Crop(kind))).Response.Error?.Code == "communities.invalidImage", "cleared ref rejected");
        }
        await bridge.DispatchAsync(Pick());
        foreach (var invalid in new[] { Crop("background"), Crop(width: .199), Crop(width: 1.01), Pick("square"),
            Request("cropWideImage", new { schemaVersion = 1, sourceRef = new string('a', 32), kind = "banner", x = .9, y = 0, width = .2 }),
            Request("cropWideImage", new { schemaVersion = 1, sourceRef = new string('a', 32), kind = "banner", x = 0, y = .9, width = 1 }),
            Request("pickWideImage", new { schemaVersion = 1, kind = "banner", path = "never-open.png" }),
            Crop() with { AccountContext = new("test", "fixture", "other") },
            Crop() with { SessionGeneration = 0 } })
            Check((await bridge.DispatchAsync(invalid)).Response.Status == "error", "invalid/foreign requests rejected");
        picker.Image = "data:image/jpeg;base64," + Convert.ToBase64String(new byte[2 * 1024 * 1024]);
        Check((await bridge.DispatchAsync(Crop())).Response.Status == "ok", "2 MiB accepted");
        picker.Image = "data:image/jpeg;base64," + Convert.ToBase64String(new byte[2 * 1024 * 1024 + 1]);
        Check((await bridge.DispatchAsync(Crop())).Response.Error?.Code == "communities.invalidImage", "2 MiB plus one rejected");
        picker.Preview = new string('x', 700001);
        Check((await bridge.DispatchAsync(Pick())).Response.Error?.Code == "communities.invalidImage", "preview bound");
        picker.Preview = "data:image/png;base64,AQ==";
        picker.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = bridge.DispatchAsync(Pick()).AsTask();
        Check((await bridge.DispatchAsync(Pick())).Response.Error?.Code == "communities.busy", "wide busy");
        Check((await bridge.DispatchAsync(Request("pickLogo", new { schemaVersion = 1 }))).Response.Error?.Code == "communities.busy", "shared dialog mutex");
        generation++;
        bridge.Invalidate();
        picker.Pending.SetResult(new(new string('a', 32), picker.Preview, 1920, 1080));
        Check((await pending).Response.Status != "ok", "late old generation discarded");
        Check((await bridge.DispatchAsync(Crop())).Response.Status == "error", "old ref invalidated");
        picker.Pending = null;
        picker.Cancel = true;
        Check((await bridge.DispatchAsync(Pick())).Response.Payload.GetProperty("status").GetString() == "cancelled", "cancelled selection");
        picker.SupportsWideImage = false;
        Check((await bridge.DispatchAsync(Pick())).Response.Error?.Code == "communities.unavailable", "capability required");
        bridge.Dispose();
        Check(picker.Disposed && picker.Clears > 0, "dispose releases retained original");
        Check((await bridge.DispatchAsync(Pick())).Response.Status == "error", "disposed request rejected");
        Console.WriteLine("PASS wide bridge: round trips, identity/generation, mutex, limits, invalidation, disposal");
    }

    private sealed class Picker : ICommunityLogoPicker
    {
        public bool SupportsWideImage { get; set; } = true;
        internal string Preview = "data:image/png;base64,AQ==";
        internal string Image = "data:image/jpeg;base64,AQ==";
        internal int Clears;
        internal bool Cancel, Disposed;
        internal TaskCompletionSource<CommunityLogoSource?>? Pending;
        public Task<CommunityLogoSource?> PickAsync(CancellationToken token) => Pending?.Task ??
            Task.FromResult(Cancel ? null : new CommunityLogoSource(new string('a', 32), Preview, 1920, 1080));
        public string Crop(string sourceRef, double x, double y, double size) => throw new NotSupportedException();
        public string CropWide(string sourceRef, string kind, double x, double y, double width) => Image;
        public void Clear() => Clears++;
        public void Dispose() { Disposed = true; Clear(); }
    }
}
