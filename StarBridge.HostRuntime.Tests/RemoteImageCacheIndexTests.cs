using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class RemoteImageCacheIndexTests
{
    internal static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-image-index-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("synthetic", "synthetic-authority", "synthetic-index-pilot");
            var store = new OfflineAccountStore(root);
            store.Observe(owner, "Synthetic Index Pilot", () => true);
            var before = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(store.RemoveRemoteImage(before, Key("rejected"), () => true), "missing rejected resource gets a durable tombstone");
            Require(store.PublishRemoteImage(before, Value("unrelated"), () => true), "per-key rejection preserves an unrelated preexisting publication lease");
            Require(!store.PublishRemoteImage(before, Value("rejected"), () => true), "missing writer cannot cross the rejection tombstone");
            var fresh = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(store.PublishRemoteImage(fresh, Value("rejected"), () => true), "new post-rejection network observation can publish");
            var heldDelete = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            var rejectedPath = Directory.GetFiles(Path.Combine(root, "offline-account-v1", "remote-images-v1", "ship"), "*-" + Key("rejected") + "-*.bin").Single();
            using (var held = new FileStream(rejectedPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var deleteFailed = false;
                try { store.RemoveRemoteImage(heldDelete, Key("rejected"), () => true); }
                catch (IOException) { deleteFailed = true; }
                Require(deleteFailed, "actual held file prevents physical deletion");
                var reader = new OfflineAccountStore(root);
                var after = reader.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
                Require(reader.ReadRemoteImage(after, Key("rejected"), () => true) is null &&
                    !store.PublishRemoteImage(heldDelete, Value("rejected"), () => true),
                    "durable tombstone hides undeleted bytes and retires the old publisher");
            }
            // More distinct rejections than the bounded index capacity force
            // compaction; an old MISS must not become valid when forgotten.
            for (var i = 0; i < 515; i++)
            {
                var lease = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
                if (!store.RemoveRemoteImage(lease, Key("retired-" + i), () => true)) throw new InvalidOperationException("Synthetic tombstone failed.");
            }
            Require(!store.PublishRemoteImage(before, Value("forgotten-miss"), () => true), "index compaction fences every older missing-resource lease");
            var current = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(store.ReadRemoteImage(current, Key("unrelated"), () => true) is not null,
                "compaction preserves an existing live body");
            Require(store.PublishRemoteImage(current, Value("new-after-compaction"), () => true), "fresh publication works after bounded history compaction");
        }
        finally
        {
            if (!Path.GetFullPath(root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new IOException("Synthetic temporary root escaped the expected directory.");
            Directory.Delete(root, recursive: true);
        }
    }
    private static RemoteImageDiskValue Value(string resource)
    {
        var now = DateTimeOffset.UtcNow;
        return new(Key(resource), [1, 2, 3], now, now.AddMinutes(2), 120, false, false, "\"fixture\"", Key("target"));
    }
    private static string Key(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static void Require(bool passed, string message)
    { if (!passed) throw new InvalidOperationException("FAIL " + message); Console.WriteLine("PASS " + message); }
}
