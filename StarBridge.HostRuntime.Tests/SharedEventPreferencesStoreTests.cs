using StarBridge.Core.Events;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class SharedEventPreferencesStoreTests
{
    public static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-event-preferences-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://events.invalid", "owner");
            var store = new SharedEventPreferencesStore(root);
            Check(store.Read(owner).Settings is null && !Directory.Exists(root), "Read does not create consent");
            var joined = DateTimeOffset.UtcNow;
            var preferences = new SharedEventPreferences(new(true, SharedActivityEventTypes.Life),
                [new("A", joined, new(false, SharedActivityEventTypes.Ship))]);
            var operation = Guid.NewGuid().ToString("N");
            var first = store.Save(owner, 0, operation, preferences, () => true);
            var reopened = new SharedEventPreferencesStore(root).Read(owner);
            Check(reopened.Revision == 1 && reopened.Settings!.Room.EffectiveTypes == SharedActivityEventTypes.Life &&
                reopened.Settings.Communities.Single().Choice is { Enabled: false, SelectedTypes: SharedActivityEventTypes.Ship },
                "Independent choices survive reopening, including disabled selections");
            Check(new LocalPrivacyStore(root).Read(owner).Settings is null, "Event save does not grant realtime consent");
            Check(store.Read(owner with { Subject = "other" }).Settings is null, "Owner isolation");
            Check(store.Save(owner, 0, operation, preferences, () => true).SavedAt == first.SavedAt, "Same operation is idempotent");
            Expect("privacy_local.conflict", () => store.Save(owner, 0, Guid.NewGuid().ToString("N"), preferences, () => true));
            Expect("privacy_local.account_changed", () => store.Save(owner, 1, Guid.NewGuid().ToString("N"), preferences, () => false));
            Expect("privacy_local.invalid_request", () => store.Save(owner, 1, Guid.NewGuid().ToString("N"),
                preferences with { Room = new(true, (SharedActivityEventTypes)16) }, () => true));
            Check(store.Read(owner).Revision == 1, "Rejected writes preserve prior snapshot");
            var path = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Single();
            var bytes = File.ReadAllText(path);
            File.WriteAllText(path, bytes.Replace("\"selectedTypes\":32", "\"selectedTypes\":47"));
            Expect("privacy_local.read_failed", () => store.Read(owner));
            Expect("privacy_local.read_failed", () => store.Save(owner, 1, Guid.NewGuid().ToString("N"), preferences, () => true));
            Check(File.ReadAllText(path) != bytes, "Corrupt preferences are not overwritten with defaults");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); }
        catch (LocalPrivacyException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
}
