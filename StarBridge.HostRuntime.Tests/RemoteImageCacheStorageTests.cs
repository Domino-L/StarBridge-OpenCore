using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class RemoteImageCacheStorageTests
{
    internal static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-image-cache-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("synthetic", "synthetic-authority", "synthetic-pilot");
            var store = new OfflineAccountStore(root);
            Check(store.CaptureRemoteImageRead(owner, null, "ship", () => true) is null, "cache does not select an absent account");
            store.Observe(owner, "Synthetic Pilot", () => true);
            var lease = store.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Check(lease is not null, "confirmed original owner admits resource lease");
            var now = DateTimeOffset.UtcNow;
            var key = Key("synthetic-resource");
            var body = Encoding.UTF8.GetBytes(string.Concat(Enumerable.Repeat("synthetic-private-image-body;", 140)));
            var value = new RemoteImageDiskValue(key, body, now, now.AddMinutes(3), 180, false, true, "\"synthetic-etag\"", Key("synthetic-target"));
            Check(store.PublishRemoteImage(lease!, value, () => true), "publish protected body and validator");
            var reopened = new OfflineAccountStore(root);
            var reopenedLease = reopened.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            var read = reopened.ReadRemoteImage(reopenedLease, key, () => true);
            Check(read is not null && read.Body.SequenceEqual(body) && read.ETag == value.ETag &&
                read.ValidatorTarget == value.ValidatorTarget && read.FreshUntilUtc == value.FreshUntilUtc && read.MustRevalidate,
                "new store rehydrates bytes, original freshness and validator");
            var paths = Directory.GetFiles(root, "*.bin", SearchOption.AllDirectories);
            Check(paths.All(path => !Path.GetFileName(path).Contains(owner.Subject, StringComparison.Ordinal)), "filenames contain no account subject");
            Check(paths.All(path => !Encoding.UTF8.GetString(File.ReadAllBytes(path)).Contains("synthetic-private-image-body", StringComparison.Ordinal)), "body is DPAPI protected at rest");
            Check(reopened.ReadRemoteImage(reopenedLease, key, () => false) is null &&
                !reopened.PublishRemoteImage(reopenedLease, value, () => false), "retired current callback denies read and publish");
            var avatar = reopened.CaptureRemoteImageRead(owner, null, "avatar", () => true)!;
            var other = reopened.CaptureRemoteImageRead(owner, null, "other", () => true)!;
            Check(reopened.PublishRemoteImage(avatar, value, () => true) && reopened.PublishRemoteImage(other, value, () => true), "excluded resource kinds persist independently");
            var sentinel = Path.Combine(root, "user-original.png");
            File.WriteAllBytes(sentinel, body);
            Check(StarBridge.HostRuntime.Support.ImageCacheMaintenance.Clear(root) == 1, "existing maintenance entry deletes only regenerable ship/organization entries");
            Check(!reopened.PublishRemoteImage(reopenedLease, value, () => true) &&
                reopened.ReadRemoteImage(reopenedLease, key, () => true) is null, "pre-cleanup network lease cannot refill or display");
            var afterClear = reopened.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Check(reopened.ReadRemoteImage(afterClear, key, () => true) is null &&
                reopened.ReadRemoteImage(avatar, key, () => true) is not null &&
                reopened.ReadRemoteImage(other, key, () => true) is not null && File.ReadAllBytes(sentinel).SequenceEqual(body),
                "new epoch misses cleared data and preserves excluded/original bytes");
            Check(reopened.PublishRemoteImage(afterClear, value, () => true) && reopened.RemoveRemoteImage(afterClear, key, () => true) &&
                reopened.ReadRemoteImage(afterClear, key, () => true) is null, "explicit resource rejection removes that body");
            var secondOwner = owner with { Subject = "synthetic-second-pilot" };
            reopened.Observe(secondOwner, "Synthetic Second Pilot", () => true);
            Check(reopened.ReadRemoteImage(avatar, key, () => true) is null &&
                !reopened.PublishRemoteImage(avatar, value, () => true), "account switch denies old leases");
            var second = reopened.CaptureRemoteImageRead(secondOwner, null, "avatar", () => true)!;
            Check(reopened.ReadRemoteImage(second, key, () => true) is null, "same resource key cannot cross account owners");
            var malformedRejected = false;
            try { reopened.ReadRemoteImage(second, "../escape", () => true); }
            catch (InvalidDataException) { malformedRejected = true; }
            Check(malformedRejected, "untrusted cache key cannot select a path");
            Check(reopened.CaptureRemoteImageRead(secondOwner, null, "unexpected", () => true) is null, "unknown resource kind is not admitted");
            var oversizedRejected = false;
            try { reopened.PublishRemoteImage(second, value with { Body = new byte[4 * 1024 * 1024 + 1] }, () => true); }
            catch (InvalidDataException) { oversizedRejected = true; }
            Check(oversizedRejected, "single body bound is enforced before publication");
            var largeBody = new byte[4 * 1024 * 1024];
            Random.Shared.NextBytes(largeBody);
            for (var i = 0; i < 14; i++)
                Check(reopened.PublishRemoteImage(second, value with { Key = Key("large-" + i), Body = largeBody }, () => true), "bounded image publish " + i);
            var largeFiles = Directory.GetFiles(Path.Combine(root, "offline-account-v1", "remote-images-v1"), "*.bin", SearchOption.AllDirectories)
                .Where(path => Path.GetFileNameWithoutExtension(path).Length == 162).ToArray();
            Check(largeFiles.Sum(path => new FileInfo(path).Length) <= 64L * 1024 * 1024 && largeFiles.Length <= 128,
                "actual protected bytes across owners and kinds stay within the global disk budget");
            var largeRestored = new OfflineAccountStore(root);
            var largeLease = largeRestored.CaptureRemoteImageRead(secondOwner, null, "avatar", () => true)!;
            Check(largeRestored.ReadRemoteImage(largeLease, Key("large-13"), () => true)?.Body.SequenceEqual(largeBody) == true &&
                largeRestored.ReadRemoteImage(largeLease, Key("large-0"), () => true) is null,
                "full 4 MiB body survives a fresh store while oldest quota victim is absent");
            var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
            // The dotnet host needs the assembly argument; an apphost already selects it.
            if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
            foreach (var argument in new[] { "--remote-image-cache-worker", root, Key("large-13"), Convert.ToHexString(SHA256.HashData(largeBody)) })
                start.ArgumentList.Add(argument);
            using (var child = Process.Start(start)!)
            {
                if (!child.WaitForExit(5000)) { child.Kill(entireProcessTree: true); child.WaitForExit(); throw new TimeoutException("Synthetic cache reader child did not exit."); }
                Check(child.ExitCode == 0, "independent process rehydrates exact protected 4 MiB body");
            }
            reopened.Pin(secondOwner, 123, () => true);
            Check(reopened.ReadRemoteImage(largeLease, Key("large-13"), () => true) is null, "completed mode pin retires online resource lease");
            var offline = reopened.CaptureRemoteImageRead(null, 123, "avatar", () => true)!;
            Check(reopened.ReadRemoteImage(offline, Key("large-13"), () => true)?.Body.SequenceEqual(largeBody) == true &&
                !reopened.PublishRemoteImage(offline, value, () => true), "exact original offline revision reads retained bytes and cannot publish network data");
            Check(reopened.CaptureRemoteImageRead(null, 124, "avatar", () => true) is null,
                "unselected offline revision cannot read resources");
            reopened.Observe(secondOwner, "Synthetic Second Pilot", () => true);
            Check(reopened.ReadSelectedDisplay(secondOwner, () => true)?.DisplayName == "Synthetic Second Pilot", "resource maintenance never changes account selection");
            var countRoot = Path.Combine(root, "count-fixture");
            var countStore = new OfflineAccountStore(countRoot);
            countStore.Observe(owner, "Synthetic Pilot", () => true);
            var countLease = countStore.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            for (var i = 0; i < 128; i++)
                if (!countStore.PublishRemoteImage(countLease, value with { Key = Key("count-" + i) }, () => true)) throw new InvalidOperationException("Count fixture publication failed.");
            var countDirectory = Path.Combine(countRoot, "offline-account-v1", "remote-images-v1", "ship");
            var firstPath = Directory.GetFiles(countDirectory, "*-" + Key("count-0") + "-*.bin").Single();
            var secondPath = Directory.GetFiles(countDirectory, "*-" + Key("count-1") + "-*.bin").Single();
            File.SetLastWriteTimeUtc(firstPath, DateTime.UtcNow.AddDays(-2));
            File.SetLastWriteTimeUtc(secondPath, DateTime.UtcNow.AddDays(-1));
            Check(countStore.ReadRemoteImage(countLease, Key("count-0"), () => true) is not null &&
                countStore.PublishRemoteImage(countLease, value with { Key = Key("count-128") }, () => true) &&
                Directory.GetFiles(countDirectory, "*.bin").Length == 128 &&
                countStore.ReadRemoteImage(countLease, Key("count-0"), () => true) is not null &&
                countStore.ReadRemoteImage(countLease, Key("count-1"), () => true) is null,
                "128-entry limit evicts the least recently used resource after a read promotes recency");
            using (var held = new FileStream(Path.Combine(countRoot, "offline-account-v1", "remote-images-v1", "writer.lock"),
                       FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                countStore.Observe(owner, "Synthetic Pilot Updated", () => true);
                Check(countStore.ReadSelectedDisplay(owner, () => true)?.DisplayName == "Synthetic Pilot Updated",
                    "held image writer never owns the original account publication lock");
            }
        }
        finally
        {
            if (!Path.GetFullPath(root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new IOException("Synthetic temporary root escaped the expected directory.");
            Directory.Delete(root, recursive: true);
        }
    }
    internal static int Worker(string root, string key, string expectedHash)
    {
        var store = new OfflineAccountStore(root);
        var owner = new BridgeAccountContext("synthetic", "synthetic-authority", "synthetic-second-pilot");
        var lease = store.CaptureRemoteImageRead(owner, null, "avatar", () => true);
        var value = lease is null ? null : store.ReadRemoteImage(lease, key, () => true);
        return value is not null && Convert.ToHexString(SHA256.HashData(value.Body)) == expectedHash ? 0 : 1;
    }
    private static string Key(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static void Check(bool passed, string name)
    { if (!passed) throw new InvalidOperationException("FAIL " + name); Console.WriteLine("PASS " + name); }
}
