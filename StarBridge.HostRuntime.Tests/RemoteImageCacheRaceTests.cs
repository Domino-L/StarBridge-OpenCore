using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class RemoteImageCacheRaceTests
{
    internal static void Run()
    {
        var failures = new List<string>();
        RunCase("explicit rejection fences a previously captured cache-miss writer", (root, owner) =>
        {
            var first = new OfflineAccountStore(root);
            var late = first.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            var second = new OfflineAccountStore(root);
            var accepted = second.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(second.PublishRemoteImage(accepted, Value("same-resource", 2), () => true), "control publishes initial body");
            Require(second.RemoveRemoteImage(accepted, Key("same-resource"), () => true), "control rejects that resource");
            var unrelated = second.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(second.PublishRemoteImage(unrelated, Value("another-resource", 3), () => true), "another resource remains usable");
            Require(!first.PublishRemoteImage(late, Value("same-resource", 1), () => true), "late pre-rejection writer must not repopulate disk");
            var current = second.CaptureRemoteImageRead(owner, null, "ship", () => true)!;
            Require(second.ReadRemoteImage(current, Key("same-resource"), () => true) is null &&
                second.ReadRemoteImage(current, Key("another-resource"), () => true)?.Body[0] == 3,
                "rejected body remains absent while unrelated cache survives");
        });
        RunCase("a late older response cannot overwrite a newer accepted response", (root, owner) =>
        {
            var store = new OfflineAccountStore(root);
            var late = store.CaptureRemoteImageRead(owner, null, "organization", () => true)!;
            var otherWindow = new OfflineAccountStore(root);
            var newer = otherWindow.CaptureRemoteImageRead(owner, null, "organization", () => true)!;
            Require(otherWindow.PublishRemoteImage(newer, Value("same-resource", 2), () => true), "newer response control publishes");
            Require(!store.PublishRemoteImage(late, Value("same-resource", 1), () => true), "previous cache-miss writer loses publication race");
            var current = otherWindow.CaptureRemoteImageRead(owner, null, "organization", () => true)!;
            Require(otherWindow.ReadRemoteImage(current, Key("same-resource"), () => true)?.Body[0] == 2,
                "newer accepted body remains current");
        });
        if (failures.Count > 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));

        void RunCase(string name, Action<string, BridgeAccountContext> run)
        {
            var root = Path.Combine(Path.GetTempPath(), "StarBridge-image-race-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            var owner = new BridgeAccountContext("synthetic", "synthetic-authority", "synthetic-race-pilot");
            try
            {
                new OfflineAccountStore(root).Observe(owner, "Synthetic Race Pilot", () => true);
                run(root, owner);
                Console.WriteLine("PASS " + name);
            }
            catch (Exception error) { failures.Add("FAIL " + name + ": " + error.Message); Console.WriteLine(failures[^1]); }
            finally
            {
                if (!Path.GetFullPath(root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Synthetic temporary root escaped the expected directory.");
                Directory.Delete(root, recursive: true);
            }
        }
    }
    private static RemoteImageDiskValue Value(string resource, byte marker)
    {
        var now = DateTimeOffset.UtcNow;
        return new(Key(resource), [marker, 2, 3], now, now.AddMinutes(2), 120, false, false, "\"fixture\"", Key("target"));
    }
    private static string Key(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static void Require(bool passed, string message)
    { if (!passed) throw new InvalidOperationException(message); }
}
