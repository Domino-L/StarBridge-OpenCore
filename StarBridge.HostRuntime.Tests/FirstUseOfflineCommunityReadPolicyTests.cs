using System.Net;
using StarBridge.HostRuntime.Account;

internal static partial class FirstUseModeTests
{
    internal static Task OfflineCommunityPolicyFaults()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var owner = f.Host.CurrentContext!;
        var store = new OfflineAccountStore(f.Root);
        var reader = new OfflineAccountStore(f.Root);
        store.Observe(owner, "Synthetic Pilot", () => true);
        store.ObserveOrganizations(owner, 1, null, null, [new("one", "One", OfflineAvatar, false)], () => true);
        var before = reader.ReadSelectedOrganizations(owner, () => true)!;
        var read = store.BeginOrganizationRead(owner, () => true)!;
        Require(reader.ReadSelectedOrganizations(owner, () => true) is null, "Cold readers cannot accept an unresolved refresh guard");
        store.CompleteOrganizationRead(read, false, () => true);
        var restored = reader.ReadSelectedOrganizations(owner, () => true)!;
        Require(restored.Version == before.Version && restored.CachedAtUtc == before.CachedAtUtc,
            "A transient or cancelled read restores only the old version and original successful time");
        var denied = store.BeginOrganizationRead(owner, () => true)!;
        var policyPath = Path.Combine(f.Root, "offline-account-v1", "organizations-policy.bin");
        using (File.Open(policyPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { store.CompleteOrganizationRead(denied, true, () => true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            Require(reader.ReadSelectedOrganizations(owner, () => true) is null,
                "The durable pending guard survives failure to publish the refusal itself");
        }
        Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true) is null,
            "Cold reopen after failed refusal publication still cannot revive old names or bytes");
        var fresh = store.BeginOrganizationRead(owner, () => true)!;
        store.ObserveOrganizations(owner, 2, null, null, [new("new", "Fresh", null, true)], () => true, fresh);
        store.CompleteOrganizationRead(fresh, false, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true)?.Items.Single().Name == "Fresh", "Only fresh confirmed data heals the blocked display");
        return Task.CompletedTask;
    }

    internal static Task OfflineCommunityPolicyReadRaces()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var owner = f.Host.CurrentContext!;
        var store = new OfflineAccountStore(f.Root);
        var reader = new OfflineAccountStore(f.Root);
        store.Observe(owner, "Synthetic Pilot", () => true);
        store.ObserveOrganizations(owner, 1, null, null, [new("old", "Old", OfflineAvatar, false)], () => true);
        var older = store.BeginOrganizationRead(owner, () => true)!;
        var newer = store.BeginOrganizationRead(owner, () => true)!;
        store.ObserveOrganizations(owner, 1, null, null, [new("new", "New", null, true)], () => true, newer);
        store.CompleteOrganizationRead(newer, false, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true) is null, "New success does not remove an older unresolved guard");
        store.CompleteOrganizationRead(older, true, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true) is null, "An older request's later explicit refusal withdraws previously published data");
        var denied = store.BeginOrganizationRead(owner, () => true)!;
        var late = store.BeginOrganizationRead(owner, () => true)!;
        store.CompleteOrganizationRead(denied, true, () => true);
        store.ObserveOrganizations(owner, 1, null, null, [new("late", "Stale success", OfflineAvatar, false)], () => true, late);
        store.CompleteOrganizationRead(late, false, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true) is null, "A success started before refusal cannot revive data");
        var fresh = store.BeginOrganizationRead(owner, () => true)!;
        store.ObserveOrganizations(owner, 1, null, null, [new("fresh", "Revalidated", null, true)], () => true, fresh);
        store.CompleteOrganizationRead(fresh, false, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true)?.Items.Single().Name == "Revalidated", "A new authenticated read after refusal can recover display");
        var first = store.BeginOrganizationRead(owner, () => true)!;
        var second = store.BeginOrganizationRead(owner, () => true)!;
        store.ObserveOrganizations(owner, 1, null, null, [new("second", "Newest", null, true)], () => true, second);
        store.CompleteOrganizationRead(second, false, () => true);
        store.ObserveOrganizations(owner, 1, null, null, [new("first", "Older success", null, true)], () => true, first);
        store.CompleteOrganizationRead(first, false, () => true);
        Require(reader.ReadSelectedOrganizations(owner, () => true)?.Items.Single().Name == "Newest", "An older late success cannot replace a newer confirmed directory");
        return Task.CompletedTask;
    }

    internal static Task OfflineCommunityCrossStoreFailedWithdrawal()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var owner = f.Host.CurrentContext!;
        var first = new OfflineAccountStore(f.Root);
        var second = new OfflineAccountStore(f.Root);
        first.Observe(owner, "Synthetic Pilot", () => true);
        first.ObserveOrganizations(owner, 1, null, null, [new("old", "Old", null, true)], () => true);
        var denied = first.BeginOrganizationRead(owner, () => true)!;
        var late = second.BeginOrganizationRead(owner, () => true)!;
        var path = Path.Combine(f.Root, "offline-account-v1", "organizations-policy.bin");
        using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { first.CompleteOrganizationRead(denied, true, () => true); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        second.ObserveOrganizations(owner, 1, null, null, [new("late", "Late other-store response", null, true)], () => true, late);
        second.CompleteOrganizationRead(late, false, () => true);
        Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true) is null,
            "Another store's older request cannot undo a refusal whose final policy write failed");
        var fresh = second.BeginOrganizationRead(owner, () => true)!;
        second.ObserveOrganizations(owner, 1, null, null, [new("fresh", "Fresh after failed withdrawal", null, true)], () => true, fresh);
        second.CompleteOrganizationRead(fresh, false, () => true);
        Require(first.ReadSelectedOrganizations(owner, () => true)?.Items.Single().Name == "Fresh after failed withdrawal",
            "A genuinely new authenticated read after unknown exits heals the blocked display");
        return Task.CompletedTask;
    }

    internal static Task OfflineCommunityPolicyBounds()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var owner = f.Host.CurrentContext!;
        var store = new OfflineAccountStore(f.Root);
        store.Observe(owner, "Synthetic Pilot", () => true);
        store.ObserveOrganizations(owner, 1, null, null, [new("old", "Old", null, true)], () => true);
        var before = store.ReadSelectedOrganizations(owner, () => true)!;
        var reads = Enumerable.Range(0, 64).Select(_ => store.BeginOrganizationRead(owner, () => true)!).ToArray();
        try { store.BeginOrganizationRead(owner, () => true); throw new Exception("Unbounded read admission"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        foreach (var read in reads) store.CompleteOrganizationRead(read, false, () => true);
        Require(store.ReadSelectedOrganizations(owner, () => true)?.Version == before.Version, "Bounded consumers can all finish without losing eligible old data");
        Require(store.BeginOrganizationRead(owner with { Subject = "other" }, () => true) is null &&
            store.BeginOrganizationRead(owner, () => false) is null, "Foreign owners and retired reads cannot arm the display");
        return Task.CompletedTask;
    }
}
