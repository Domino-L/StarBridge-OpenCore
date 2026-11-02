using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static class FriendsSnapshotStoreTests
{
    internal static Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-friends-snapshot-" + Guid.NewGuid().ToString("N"));
        var owner = new BridgeAccountContext("synthetic", "synthetic-authority", "synthetic-owner");
        var storage = owner with { Subject = "synthetic-storage" };
        var store = new OfflineAccountStore(root);
        try
        {
            store.Observe(owner, "Synthetic Owner", () => true, storage);
            FriendsView View(string name = "Stored Friend") => new(null, DateTimeOffset.UtcNow,
                [new(name, "SyntheticPilot", "friend", "must-not-persist-avatar", DateTimeOffset.UtcNow) {
                    AccountId = "private-peer-id", TargetRef = "private-action-lease", ChatTargetRef = "private-chat-lease",
                    ConversationKey = "private-conversation", Actions = ["remove", "block"] }], [], [], [], []);
            OfflineFriendsReadLease Begin() => store.BeginFriendsRead(owner, () => true) ?? throw new Exception("Missing friends lease");
            void Finish(OfflineFriendsReadLease lease, OfflineFriendsReadOutcome outcome, string name = "Stored Friend") =>
                store.CompleteFriendsRead(lease, outcome,
                    outcome is OfflineFriendsReadOutcome.Success or OfflineFriendsReadOutcome.ConfirmedWrite ? View(name) : null, () => true);
            void Seed(string name = "Stored Friend") => Finish(Begin(), OfflineFriendsReadOutcome.Success, name);
            string? Name() => new OfflineAccountStore(root).ReadSelectedFriends(owner, () => true)?.Directory.Friends.Single().Callsign;
            void Check(bool value, string reason) { if (!value) throw new Exception(reason); }

            Seed();
            var loaded = new OfflineAccountStore(root).ReadSelectedFriends(owner, () => true)!;
            var row = loaded.Directory.Friends.Single();
            Check(row.TargetRef is null && row.ChatTargetRef is null && row.ConversationKey is null && row.AccountId == "" &&
                row.Actions.Length == 0 && row.Shared is null && row.AvatarImageData is null, "Cache leaked live or sensitive row fields");
            var file = Path.Combine(root, "offline-account-v1", "friends-v1.bin");
            var encrypted = File.ReadAllBytes(file);
            Check(!Encoding.UTF8.GetString(encrypted).Contains("Stored Friend"), "Cache is plaintext");
            var clear = ProtectedData.Unprotect(encrypted, Encoding.UTF8.GetBytes("StarBridge.offline-account.friends.v1"), DataProtectionScope.CurrentUser);
            try { Check(!Encoding.UTF8.GetString(clear).Contains("private-") && !Encoding.UTF8.GetString(clear).Contains("must-not-persist"), "Excluded fields reached the encrypted document"); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            Check(Name() == "Stored Friend", "Restarted store lost the complete display");

            var a = Begin(); var b = Begin();
            Check(Name() is null, "Unresolved reads must withhold durable admission");
            Finish(a, OfflineFriendsReadOutcome.Transient);
            Check(Name() is null, "One transient result revived a still-pending read");
            Finish(b, OfflineFriendsReadOutcome.Transient);
            Check(Name() == "Stored Friend", "Concurrent known transient outcomes lost previous data");

            a = Begin(); b = Begin();
            Finish(b, OfflineFriendsReadOutcome.Success, "Newest Friend");
            Check(Name() is null, "New data published before all overlapping reads settled");
            Finish(a, OfflineFriendsReadOutcome.Success, "Older Friend");
            Check(Name() == "Newest Friend", "Older read overwrote latest directory");

            foreach (var commandLast in new[] { false, true })
            {
                a = Begin(); b = Begin();
                if (commandLast) Finish(b, OfflineFriendsReadOutcome.Success, "Pre-ack Read");
                Finish(a, OfflineFriendsReadOutcome.ConfirmedWrite, "Confirmed Command");
                if (!commandLast) Finish(b, OfflineFriendsReadOutcome.Success, "Pre-ack Read");
                Check(Name() == "Confirmed Command", "An overlapping read overwrote acknowledged mutation data");
            }
            a = Begin(); b = Begin();
            Finish(b, OfflineFriendsReadOutcome.Rejected);
            Finish(a, OfflineFriendsReadOutcome.ConfirmedWrite, "Refused Revival");
            Check(Name() is null, "Command acknowledgement crossed a refused read epoch");
            Seed();
            a = Begin(); Finish(a, OfflineFriendsReadOutcome.Unchanged);
            Check(Name() == "Stored Friend", "Definite no-write erased prior data");

            a = Begin(); b = Begin();
            Finish(a, OfflineFriendsReadOutcome.Rejected);
            Finish(b, OfflineFriendsReadOutcome.Success, "Forbidden Revival");
            Check(Name() is null, "Late success revived a refused directory");
            Seed();
            a = Begin(); b = Begin();
            Finish(b, OfflineFriendsReadOutcome.Success);
            Finish(a, OfflineFriendsReadOutcome.Rejected);
            Check(Name() is null, "Late refusal failed to withdraw newer candidate");

            Seed();
            a = Begin(); a.Dispose(); // Physical process/read exit without a classified result.
            b = Begin(); Finish(b, OfflineFriendsReadOutcome.Transient);
            Check(Name() is null, "A dead read was treated as a known transient result");
            Seed();

            var live = true;
            a = store.BeginFriendsRead(owner, () => live)!; live = false;
            Finish(a, OfflineFriendsReadOutcome.Success);
            Check(Name() is null, "Retired read published a response");
            Seed();

            a = Begin();
            var policy = Path.Combine(root, "offline-account-v1", "friends-policy-v1.bin");
            using (var held = new FileStream(policy, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                try { Finish(a, OfflineFriendsReadOutcome.Rejected); throw new Exception("Expected blocked policy replacement"); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            }
            Check(Name() is null, "A failed refusal write left old data readable");
            b = Begin(); Finish(b, OfflineFriendsReadOutcome.Transient);
            Check(Name() is null, "A later transient result revived an unrecorded refusal");
            Seed();

            a = Begin();
            store.Observe(owner, "Synthetic Owner", () => true, storage with { Subject = "other-storage" });
            Finish(a, OfflineFriendsReadOutcome.Success);
            Check(Name() is null, "Storage owner transition reused the old snapshot");
            store.Observe(owner, "Synthetic Owner", () => true, storage);
            Seed();
            Check(new OfflineAccountStore(root).ReadSelectedFriends(owner with { Subject = "other-owner" }, () => true) is null,
                "Another account read the snapshot");
            store.Pin(owner, 7, () => true);
            Check(Name() is null, "Online read ignored an offline mode selection");
            store.Observe(owner, "Synthetic Owner", () => true, storage);
            Seed();
            a = Begin();
            store.ClearFriends(owner, () => true);
            Finish(a, OfflineFriendsReadOutcome.Success, "After Logout");
            Check(Name() is null && !File.Exists(file), "Logout clear permitted a late publication or retained the data file");
            Seed();
            File.WriteAllBytes(file, [1, 2, 3]);
            try { _ = Name(); throw new Exception("Corrupt protection accepted"); }
            catch (CryptographicException) { }
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
}
