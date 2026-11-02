using System.Security.Cryptography;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

// What an upgrading profile meets with first-use on: the real startup reader, then
// the real account startup decision, on a root holding only what it left behind.
internal static class FirstUseExistingUserUpgradeTests
{
    internal static async Task Run()
    {
        await Case("0.7.x update", "update", "returning", "previousUse", Official);
        await Case("0.7.x update with no device data", "update", "returning", "updateInstallation", _ => { });
        await Case("0.7.x data without an install stamp", null, "returning", "previousUse", Official);
        await Case("reinstall keeping account data", "fresh", "returning", "previousUse", AccountData);
        await Case("WPF configuration", "fresh", "returning", "previousUse", Wpf);
        await Case("setup already completed", "update", "returning", "completedSetup", Completed);
        await Case("damaged setup progress", "fresh", "unknown", "unreadableProgress", Damaged);
        await Case("no history and no install stamp", null, "unknown", "installationUnknown", _ => { });
        // The reader stops at its first hit, so each name has to stand alone.
        foreach (var file in new[] { "overlay.settings", "overlay.layout", "overlay.presets", "notification.settings.json",
            "sync-privacy.settings.json", "local-play-session.json" })
            await Case("reinstall keeping only " + file, "fresh", "returning", "previousUse", root =>
                File.WriteAllText(Path.Combine(root, file), "synthetic previous use; deliberately not parsed"));
        foreach (var directory in new[] { "personal-profile-cache", "chat-history" })
            await Case("reinstall keeping only " + directory, "fresh", "returning", "previousUse", root =>
                Directory.CreateDirectory(Path.Combine(root, directory)));
        Console.WriteLine("PASS existing user upgrade: no automatic setup, account startup untouched, seeded data byte-identical");
    }

    private static async Task Case(string name, string? source, string eligibility, string reason, Action<string> seed)
    {
        using var f = new LocalAccountStopTests.Fixture(initializeLocalState: false);
        seed(f.Root);
        var before = Snapshot(f.Root);
        var observed = new FirstUseStartupReader(f.Root, () => source is null ? null : new(source, "0.7.2")).Read();
        Require(observed == new FirstUseStartupObservation(eligibility, reason, false), name + ": " + observed);
        var calls = 0;
        using var runtime = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root,
            _ => { calls++; return Task.FromResult(f.Runtime); });
        Require(calls == 1 && ReferenceEquals(runtime, f.Runtime), name + ": ordinary account startup must run");
        Require(runtime.FirstUseMode!.Current.State == "online", name + ": mode " + runtime.FirstUseMode.Current.State);
        var current = await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Guid.NewGuid().ToString("N"),
            runtime.Generation, new { schemaVersion = 1 }));
        Require(current.Response.Error?.Code != "account.local_mode", name + ": account reads must not pause");
        Require(f.Host.CurrentContext is not null && !f.Vault.Deleted, name + ": the retained session and credentials stay");
        using (var lease = runtime.DeviceNetwork.Enter())
            Require(lease?.IsCurrent == true, name + ": online device work stays admitted");
        foreach (var (path, hash) in before)
            Require(File.Exists(path) && SHA256.HashData(File.ReadAllBytes(path)).SequenceEqual(hash), name + ": rewrote " + Path.GetFileName(path));
        if (eligibility == "returning" && reason != "completedSetup")
            Require(!Directory.Exists(Path.Combine(f.Root, "local-first-use-v1")) && !Directory.Exists(Path.Combine(f.Root, "first-use-completion-v1")),
                name + ": startup must not invent setup progress or completion");
        Console.WriteLine("PASS existing user upgrade: " + name);
    }

    private static void Official(string root)
    {
        foreach (var file in new[] { "application-preferences.v1.json", "application-behavior.json", "local-event-log.json" })
            File.WriteAllText(Path.Combine(root, file), "synthetic previous use; deliberately not parsed");
        AccountData(root);
    }

    private static void AccountData(string root)
    {
        foreach (var directory in new[] { "game-log-local-v1", "gameplay-time-local-v1" })
        {
            Directory.CreateDirectory(Path.Combine(root, directory));
            File.WriteAllText(Path.Combine(root, directory, "synthetic.bin"), "synthetic account data");
        }
    }

    private static void Wpf(string root) => File.WriteAllText(Path.Combine(root, "desktop.config"), "synthetic previous use; deliberately not parsed");

    private static void Completed(string root) => new FirstUseCompletionStore(root).Save(null, Guid.NewGuid().ToString("N"), "local",
        Guid.NewGuid().ToString("N"), "synthetic-source-0001", () => true);

    private static void Damaged(string root)
    {
        Directory.CreateDirectory(Path.Combine(root, "local-first-use-v1"));
        File.WriteAllBytes(Path.Combine(root, "local-first-use-v1", "state.bin"), [1, 2, 3]);
    }

    private static Dictionary<string, byte[]> Snapshot(string root) => Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
        .ToDictionary(path => path, path => SHA256.HashData(File.ReadAllBytes(path)));

    private static void Require(bool value, string label)
    { if (!value) throw new InvalidOperationException(label); }
}
