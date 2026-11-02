using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static Task ManualOfflineCredentialSelection()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-manual-proof-selection-" + Guid.NewGuid().ToString("N"));
        var owner = new BridgeAccountContext("fixture", "fixture-authority", "fixture-owner");
        var vault = new WindowsTokenVault(System.IO.Path.Combine(root, "scm-token-vault.json"));
        var key = owner.Authority + ":" + owner.Subject;
        var stamp = vault.SaveRefreshTokenWithRetirement(key, "synthetic-refresh");
        var store = new OfflineAccountStore(root);
        store.Observe(owner, "Synthetic Pilot", () => true);
        store.Pin(owner, 7, () => true);
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(7, () => true), "mode and display alone cannot select authorization");
        store.Pin(owner, 7, () => true, stamp);
        AssertEqual(owner, store.ReadRetainedOwner(7, () => true), "exact original credential may select original account");
        AssertEqual(owner, new OfflineAccountStore(root).ReadRetainedOwner(7, () => true), "cold manual selection preserves exact credential");
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(8, () => true), "wrong mode revision");
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(7, () => false), "retired mode");
        vault.SaveRefreshToken(key, "synthetic-new-session");
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(7, () => true), "same owner newer credentials cannot adopt old pin");
        var other = owner with { Subject = "other" };
        var otherStamp = vault.SaveRefreshTokenWithRetirement(other.Authority + ":" + other.Subject, "synthetic-other");
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(7, () => true), "other active account");
        store.Pin(owner, 7, () => true, otherStamp);
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(7, () => true), "credential owner hash must match pinned account");
        stamp = vault.SaveRefreshTokenWithRetirement(key, "synthetic-restored");
        store.Pin(owner, 9, () => true, stamp);
        store.ReturnToOffline(9, 11, () => true);
        AssertEqual(owner, store.ReadRetainedOwner(11, () => true), "cancelled resume preserves original credential across revision");
        vault.DeleteRefreshToken(key);
        AssertEqual<BridgeAccountContext?>(null, store.ReadRetainedOwner(11, () => true), "credential deletion disables retained selection");
        Console.WriteLine("PASS 10 manual offline credential selection checks; synthetic fixture: " + root);
        return Task.CompletedTask;
    }
}
