using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class CommunityLogoBridgeTests
{
    internal static async Task Verify()
    {
        var owner = new BridgeAccountContext("test", "test", "owner");
        var generation = 2L;
        using var picker = new Picker();
        using var bridge = new CommunityLogoBridge(picker, () => (owner, generation));
        BridgeEnvelope Request(string name, object? payload = null) => BridgeEnvelope.Request(name,
            Guid.NewGuid().ToString("N"), generation, payload ?? new { schemaVersion = 1 }, owner);
        var selected = await bridge.DispatchAsync(Request("communities.pickLogo"));
        Require(selected.Response.Payload.GetProperty("status").GetString() == "selected", "native selection response");
        Require(!selected.Response.Payload.GetRawText().Contains("path", StringComparison.OrdinalIgnoreCase), "no file path crosses bridge");
        var cropped = await bridge.DispatchAsync(Request("communities.cropLogo", new { schemaVersion = 1, sourceRef = new string('a', 32), x = 0.0, y = 0.0, size = 1.0 }));
        Require(cropped.Response.Payload.GetProperty("status").GetString() == "cropped" && picker.Crops == 1, "crop reaches native owner once");
        var invalid = await bridge.DispatchAsync(Request("communities.pickLogo", new { schemaVersion = 1, path = "never-read.png" }));
        Require(invalid.Response.Error?.Code == "communities.invalidImage" && picker.Picks == 1, "arbitrary path rejected before picker");
        foreach (var badSize in new[] { -.1, .19, 1.01 })
        {
            var bad = await bridge.DispatchAsync(Request("communities.cropLogo", new { schemaVersion = 1, sourceRef = new string('a', 32), x = 0.0, y = 0.0, size = badSize }));
            Require(bad.Response.Error is not null && picker.Crops == 1, "invalid crop rejected");
        }
        var stale = Request("communities.pickLogo") with { SessionGeneration = 1 };
        Require((await bridge.DispatchAsync(stale)).Response.Error?.Code == "communities.identityUnavailable" && picker.Picks == 1, "stale account cannot select files");

        picker.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = bridge.DispatchAsync(Request("communities.pickLogo")).AsTask();
        Require((await bridge.DispatchAsync(Request("communities.pickLogo"))).Response.Error?.Code == "communities.busy", "one dialog at a time");
        generation++;
        bridge.Invalidate();
        picker.Pending.SetResult(new(new string('b', 32), "data:image/png;base64,AQ==", 1, 1));
        var late = await pending;
        Require(late.Response.Status != "ok" && picker.Clears > 0, "late old-account image is cleared and never returned");
        picker.Pending = null;
        picker.Cancel = true;
        var cancelled = await bridge.DispatchAsync(Request("communities.pickLogo"));
        Require(cancelled.Response.Payload.GetProperty("status").GetString() == "cancelled", "picker cancellation is not image failure");
        picker.Cancel = false;
        var avatar = await bridge.DispatchAsync(Request("account.pickAvatar"));
        Require(avatar.Response.Payload.GetProperty("status").GetString() == "selected", "Account avatar uses the same safe file picker");
        var avatarCrop = await bridge.DispatchAsync(Request("account.cropAvatar", new {
            schemaVersion = 1, sourceRef = new string('a', 32), x = 0.0, y = 0.0, size = 1.0 }));
        Require(avatarCrop.Response.Payload.GetProperty("status").GetString() == "cropped", "Avatar alias supports validated crop");
        var avatarInvalid = await bridge.DispatchAsync(Request("account.pickAvatar", new { schemaVersion = 1, path = "never-read.png" }));
        Require(avatarInvalid.Response.Error is not null, "Avatar cannot supply an arbitrary native path");
        Require((await bridge.DispatchAsync(Request("account.clearAvatarDraft"))).Response.Status == "ok", "Avatar draft can be cleared");
    }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Picker : ICommunityLogoPicker
    {
        internal int Picks, Crops, Clears;
        internal bool Cancel;
        internal TaskCompletionSource<CommunityLogoSource?>? Pending;
        public Task<CommunityLogoSource?> PickAsync(CancellationToken token)
        { Picks++; return Pending?.Task ?? Task.FromResult(Cancel ? null : new CommunityLogoSource(new string('a', 32), "data:image/png;base64,AQ==", 512, 512)); }
        public string Crop(string sourceRef, double x, double y, double size) { Crops++; return "data:image/png;base64,AQ=="; }
        public void Clear() => Clears++;
        public void Dispose() { }
    }
}
