using StarBridge.Core.Identity;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

// A returning user whose setup predates the completion store, or whose receipt no
// longer names the current profile or log source. The gate guards exactly two
// exits: the gameplay recording owner and the Game.log event journal batch.
internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunColdCompletion()
    {
        await Case("cold returning user without a completion receipt binds and records it once", () => ColdCompletion("backfill"));
        await Case("cold new user without a completion receipt is not backfilled", () => ColdCompletion("newUser"));
        await Case("cold receipt for another log source asks for identity review, then records it", () => ColdCompletion("source"));
        await Case("cold receipt for another profile asks for identity review, then records it", () => ColdCompletion("profile"));
        await Case("cold local-mode receipt asks for identity review, then records it", () => ColdCompletion("localReceipt"));
        await Case("cold game identity mismatch stays blocked and writes no receipt", () => ColdCompletion("mismatch"));
        await Case("cold sign-in before the backfill needs explicit confirmation, then records it", () => ColdCompletion("relogin"));
        await Case("cold confirmation whose receipt cannot be saved stays blocked, then retries", () => ColdCompletion("saveFails"));
        await Case("cold backfill puts the receipt back when the local identity changes during commit", () => ColdCompletion("localChangeDuringCommit"));
        await Case("cold backfill puts the receipt back when a sign-in lands during commit", () => ColdCompletion("reloginDuringCommit"));
        await Case("cold backfill commit and Host close never interleave", () => ColdCompletion("closeDuringCommit"));
        await Case("cold gate reads never bind a receipt whose commit has not finished", () => ColdCompletion("readDuringCommittedRelogin"));
        await Case("cold backfill whose rollback cannot delete the receipt stays blocked until confirmed", () => ColdCompletion("backfillRollbackFails"));
        await Case("cold confirmation whose rollback cannot restore the old receipt stays blocked until confirmed again", () => ColdCompletion("confirmRollbackFails"));
        await Case("cold receipt left by a failed rollback stays blocked after a restart and a new sign-in", () => ColdCompletion("rollbackFailsThenRestart"));
        await Case("cold gate read that pauses while the rollback succeeds still never binds", () => ColdCompletion("readerPausedDuringRollback"));
        await Case("cold unreadable receipt is never backfilled, and explicit confirmation recovers it", () => ColdCompletion("unreadableConfirm"));
        await Case("cold unreadable receipt recovery puts the same bytes back when a sign-in lands during commit", () => ColdCompletion("unreadableRollback"));
        await Case("cold valid receipt held open by another process is never recovered as damaged", () => ColdCompletion("lockedReceipt"));
        await Case("cold completion receipt keeps its confirmed state in its own file", ColdCompletionStore);
    }

    private sealed class Disposal(Action dispose) : IDisposable
    {
        public void Dispose() => dispose();
    }

    // The two receipt forms of checked saves (those with an after-commit check).
    private static Task ColdCompletionStore()
    {
        var root = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "fu-completion-" + Id())).FullName;
        try
        {
            var folder = Path.Combine(root, "first-use-completion-v1");
            var statePath = Path.Combine(folder, "state.bin");
            var store = new FirstUseCompletionStore(root);
            var old = new StarBridge.HostRuntime.Onboarding.Rollback0721.FirstUseCompletionStore(root);
            bool OldReads()
            {
                try { return old.Read() is not null; }
                catch (StarBridge.HostRuntime.Onboarding.Rollback0721.LocalFirstUseException error) when (error.Code == "firstUse.completion_read_failed") { return false; }
            }
            // Nothing but the receipt itself (and the store's lock) holds its state.
            bool OnlyReceipt() => Directory.GetFileSystemEntries(folder).Select(Path.GetFileName)
                .All(name => name is "state.bin" or "state.bin.lock");
            // The receipt file cannot be moved into place: nothing was committed.
            store.CommitProbe = () => Directory.CreateDirectory(statePath);
            string? failed = null;
            try { store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true); }
            catch (LocalFirstUseException error) { failed = error.Code; }
            store.CommitProbe = null;
            Directory.Delete(statePath);
            Check(failed is not null && store.Read() is null && OnlyReceipt(), "A receipt that was never written leaves nothing behind: " + failed);
            // The after-commit check fails and the new file is removed again.
            failed = null;
            try { store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => false); }
            catch (LocalFirstUseException error) { failed = error.Code; }
            Check(failed == "firstUse.context_changed" && store.Read() is null, "A receipt put back leaves nothing behind: " + failed);
            // A confirmed save is the 0.7.2.1 receipt, readable by 0.7.2.1 itself.
            var saved = store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true);
            Check(store.Read() == saved && !saved.Unconfirmed && OldReads() && old.Read()!.OperationId == saved.OperationId && OnlyReceipt(),
                "A confirmed receipt is the ordinary 0.7.2.1 receipt");
            // While the after-commit check runs, the file itself says unconfirmed;
            // a reader keeps that answer even after the file has changed.
            FirstUseCompletion? during = null; var oldDuring = true;
            var next = store.Save(saved, Id(), "online", Id(), "synthetic-source-key", () => true,
                afterCommit: () => { during = store.Read(); oldDuring = OldReads(); return true; });
            Check(during is { Unconfirmed: true } && during.OperationId == next.OperationId && !oldDuring,
                "A receipt is unconfirmed in the file until its after-commit check passed, also to 0.7.2.1");
            Check(store.Read() == next && !next.Unconfirmed && during != next, "Once confirmed the file holds the confirmed form");
            // A rollback that never ran (the check threw): the file stays unconfirmed,
            // for this store, a new one (a restart) and 0.7.2.1, with no other file to lose.
            failed = null;
            try { store.Save(next, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => throw new IOException()); }
            catch (LocalFirstUseException error) { failed = error.Code; }
            var left = new FirstUseCompletionStore(root).Read();
            Check(failed == "firstUse.completion_write_failed" && store.Read() is { Unconfirmed: true } &&
                left is { Unconfirmed: true } && !OldReads() && OnlyReceipt(),
                "A receipt left behind stays unconfirmed in its own file: " + failed);
            // A put-back over it restores it as it was: still unconfirmed.
            failed = null;
            try { store.Save(left, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => false); }
            catch (LocalFirstUseException error) { failed = error.Code; }
            Check(failed == "firstUse.context_changed" && store.Read() == left && !OldReads(), "A put-back keeps an unconfirmed receipt unconfirmed: " + failed);
            // Confirming it again leaves the confirmed form.
            var again = store.Save(left, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true);
            Check(new FirstUseCompletionStore(root).Read() == again && !again.Unconfirmed && OldReads(), "A new confirmed save replaces it");
            // Recovery of an unreadable receipt is only for that case.
            string? Code(Action save) { try { save(); return null; } catch (LocalFirstUseException error) { return error.Code; } }
            Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) == "firstUse.revision_conflict" &&
                store.Read() == again, "A readable receipt is never replaced as unreadable");
            Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, replaceUnreadable: true)) == "firstUse.invalid_request" &&
                Code(() => store.Save(again, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) == "firstUse.invalid_request",
                "Recovery needs a checked save and no expected receipt");
            // An unreadable file larger than the store would keep to put back is left alone.
            var oversized = RandomNumberGenerator.GetBytes(64 * 1024 + 1);
            File.WriteAllBytes(statePath, oversized);
            Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) == "firstUse.completion_write_failed" &&
                File.ReadAllBytes(statePath).AsSpan().SequenceEqual(oversized), "An oversized unreadable file is not replaced");
            // An unreadable receipt within that size is replaced by a confirmed one.
            File.WriteAllBytes(statePath, RandomNumberGenerator.GetBytes(96));
            var recovered = store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true);
            Check(store.Read() == recovered && !recovered.Unconfirmed && OldReads() && OnlyReceipt(), "An unreadable receipt is recovered in the confirmed form");
            var valid = File.ReadAllBytes(statePath);
            // A valid receipt that another process holds open exclusively cannot be
            // read, but is not damaged: recovery fails and never touches it, even if
            // the lock is released later inside the commit window.
            var probeRan = false;
            using (var locked = new FileStream(statePath, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                store.CommitProbe = () => { probeRan = true; locked.Dispose(); };
                Check(Code(() => store.Read()) == "firstUse.completion_read_failed", "The locked receipt cannot be read");
                Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) == "firstUse.completion_write_failed" && !probeRan,
                    "A locked valid receipt is never taken as damaged");
                store.CommitProbe = null;
            }
            Check(File.ReadAllBytes(statePath).AsSpan().SequenceEqual(valid) && store.Read() == recovered, "The locked receipt is untouched");
            // A valid receipt that appears after the damaged one was checked is kept.
            File.WriteAllBytes(statePath, RandomNumberGenerator.GetBytes(96));
            store.CommitProbe = () => File.WriteAllBytes(statePath, valid);
            Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) == "firstUse.revision_conflict" &&
                File.ReadAllBytes(statePath).AsSpan().SequenceEqual(valid), "A receipt written after the check is never overwritten");
            store.CommitProbe = null;
            // The same for a damaged deferred receipt when an ordinary one appears.
            var deferredFolder = Directory.CreateDirectory(Path.Combine(root, "first-use-completion-deferred-v1")).FullName;
            File.Delete(statePath);
            File.WriteAllBytes(Path.Combine(deferredFolder, "state.bin"), RandomNumberGenerator.GetBytes(96));
            store.CommitProbe = () => File.WriteAllBytes(statePath, valid);
            Check(Code(() => store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true)) is "firstUse.revision_conflict" &&
                File.ReadAllBytes(statePath).AsSpan().SequenceEqual(valid), "An ordinary receipt written after the deferred check is never overwritten");
            store.CommitProbe = null;
            // Without that, a damaged deferred receipt is recovered as an ordinary one.
            File.Delete(statePath);
            var fromDeferred = store.Save(null, Id(), "online", Id(), "synthetic-source-key", () => true, afterCommit: () => true, replaceUnreadable: true);
            Check(store.Read() == fromDeferred && !fromDeferred.Unconfirmed, "A damaged deferred receipt is recovered as an ordinary receipt");
        }
        finally { Directory.Delete(root, recursive: true); }
        return Task.CompletedTask;
    }

    private static async Task ColdCompletion(string scenario)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        await f.Original.PrepareOrdinary();
        var root = f.Original.Local.Root;
        var local = new LocalFirstUseStore(root);
        var saved = local.Read();
        local.SelectSource(saved.Revision, Id(), Path.Combine(root, "other", "LIVE", "Game.log"), "LIVE", () => true);
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var mode = f.Original.Mode;
        Check((await Finish(mode.ApplyRootOfflineAsync(0, Id(), native.Generation, native))).State == "offline", "Original online owner must actually exit.");
        mode.RequestResume(mode.Current.Revision, Id());
        var revision = mode.Current.Revision;
        Check(await Finish(mode.ResumeOnlineCandidateAsync(revision)) == "observed", "Retained session must be freshly authenticated.");
        var review = await mode.ReadOnlineIdentityAsync(revision);
        Check((await mode.ConfirmOnlineIdentityAsync(revision, review.ConfirmationKey!)).State == "accountConfirmedForHandoff", "Account handoff");
        using (var composition = new CompositionFixture(f, native))
            Check((await Finish(native.InstallConfirmedOnlineAsync(revision, composition.Composition.Configure))).State == "online", "Online installed");
        await native.DisposeAsync();
        f.Original.Candidate!.Dispose();

        using var transport = new FirstUseOnlineReturnTests.Transport();
        var uri = new Uri("https://synthetic.example.invalid/");
        Task? callback = null;
        // Exercises the real PKCE listener without a visible browser or endpoint.
        void OpenBrowser(Uri authorization)
        {
            var query = authorization.Query.TrimStart('?').Split('&').Select(value => value.Split('=', 2))
                .ToDictionary(value => Uri.UnescapeDataString(value[0]), value => Uri.UnescapeDataString(value[1]));
            var target = new Uri(query["redirect_uri"] + "?code=synthetic-code&state=" + Uri.EscapeDataString(query["state"]));
            Check(target.IsLoopback, "Synthetic browser may call only the actual loopback listener.");
            callback = Task.Run(async () =>
            {
                using var client = new HttpClient(new SocketsHttpHandler { UseProxy = false });
                using var response = await client.GetAsync(target);
                response.EnsureSuccessStatusCode();
            });
        }
        ScmAccountBridgeHost host = null!;
        AccountBridgeRuntime runtime = null!;
        using var stack = new Disposal(() => { runtime?.Dispose(); host?.Dispose(); });
        // Starts the cold Host on this data root, as an app launch does.
        async Task StartCold()
        {
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), f.Original.Vault,
                new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource", "openid profile.read offline_access", "/callback"),
                authorizationBrowser: OpenBrowser);
            host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(Path.Combine(root, "cold-profile")), "synthetic", () => "Pilot-Example");
            var started = runtime = AccountBridgeRuntime.CreateAccountBusinessRuntime(host, root, null, false, null);
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(root, _ => Task.FromResult(started));
            await started.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), started.Generation, new { schemaVersion = 1 }));
        }
        await StartCold();
        async Task SignIn()
        {
            // An ordinary sign-in with the same Handle: a new session, not the restored one.
            var before = runtime.Generation;
            var result = await runtime.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), runtime.Generation, new { schemaVersion = 1 }));
            if (callback is not null) await callback.WaitAsync(TimeSpan.FromSeconds(5));
            Check(result.Response.Status == "ok" && runtime.Generation > before, "Synthetic sign-in: " + result.Response.Error?.Code);
        }
        var cold = runtime.FirstUseMode!;
        Check(cold.HasInstalledOnlineAccount, "Cold online account restored");
        // The user's data: an online switch committed seconds after its origin
        // receipt, which stays on disk. That is a finished switch, not pending.
        // Overlay appearances, community content and roster preferences are only
        // emptied while the first-use local source returns a frame.
        var modeStore = new FirstUseModeStore(root);
        var coldLocal = cold.LocalMode();
        Check(modeStore.Read().Phase == "online" && modeStore.ReadOnlineOrigin() is { CandidateStarted: true } &&
            cold.Current.State == "online" && !coldLocal.Active && coldLocal.Generation >= 0 &&
            runtime.FirstUseOverlaySource is { } overlaySource && overlaySource.Capture() is null,
            "A finished online switch with its origin receipt left on disk does not hold back overlay data");
        var snapshot = local.Read();
        local.ConfirmIdentity(snapshot.Revision, Id(), new(snapshot.SelectedSourceKey!, Id(), scenario == "mismatch" ? "Other-Pilot" : "Pilot-Example",
            DateTimeOffset.UtcNow, "history", true, false), () => true);
        var confirmed = local.Read();
        var store = new FirstUseCompletionStore(root);
        switch (scenario)
        {
            case "source" or "saveFails" or "confirmRollbackFails" or "lockedReceipt": store.Save(null, Id(), "online", confirmed.ActiveProfileId!, "synthetic-older-source-key", () => true); break;
            case "profile": store.Save(null, Id(), "online", Id(), confirmed.SelectedSourceKey!, () => true); break;
            case "localReceipt": store.Save(null, Id(), "local", confirmed.ActiveProfileId!, confirmed.SelectedSourceKey!, () => true); break;
        }
        // A receipt this user's DPAPI cannot decrypt.
        var unreadableBytes = RandomNumberGenerator.GetBytes(96);
        if (scenario.StartsWith("unreadable", StringComparison.Ordinal))
        {
            Directory.CreateDirectory(Path.Combine(root, "first-use-completion-v1"));
            File.WriteAllBytes(Path.Combine(root, "first-use-completion-v1", "state.bin"), unreadableBytes);
        }
        var before = scenario.StartsWith("unreadable", StringComparison.Ordinal) ? null : store.Read();
        cold.ReturningAtStartup = scenario != "newUser";

        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        bool Ready() => (bool)typeof(AccountBridgeRuntime).GetProperty("FirstUseGameIdentityReady", flags)!.GetValue(runtime)!;
        bool GameplayOwner()
        {
            var owner = typeof(AccountBridgeRuntime).GetMethod("GameplayRecordingOwner", flags)!.Invoke(runtime, null)!;
            return owner.GetType().GetField("Item1")!.GetValue(owner) is BridgeAccountContext;
        }
        Func<bool> RecordingAllowed()
        {
            var gameLog = typeof(AccountBridgeRuntime).GetField("_gameLog", flags)!.GetValue(runtime)!;
            return (Func<bool>)gameLog.GetType().GetField("_recordingAllowed", flags)!.GetValue(gameLog)!;
        }
        bool JournalAccepts()
        {
            var folder = Directory.CreateDirectory(Path.Combine(root, "journal-" + Id())).FullName;
            using var journal = new LocalGameEventJournal(Path.Combine(folder, "local-event-log.json"));
            journal.Load();
            var batch = new GameLogJournalBatch(journal);
            batch.BeginRead(); batch.Complete(() => true);
            batch.BeginRead();
            batch.Add(new(LocalGameEventCategories.Location, "PlayerLocationChanged", "Arrived at a city", "synthetic arrival"));
            batch.Complete(RecordingAllowed());
            return journal.Entries.Any(e => e.Category == LocalGameEventCategories.Location);
        }
        // The guide's own gate (receipt + local identity). Since 11-08 it no longer
        // decides recording; GameplayOwner and the journal follow the account identity.
        bool Open() => cold.HasInstalledOnlineForCompletion && Ready();
        bool Closed() => !cold.HasInstalledOnlineForCompletion && !Ready();
        var probe = typeof(AccountBridgeRuntime).GetProperty("GameLogIdentityCheckForTests", flags)!;
        void LogCheck(LocalIdentityCheckState? state) =>
            probe.SetValue(runtime, state is { } value ? () => (LocalIdentityCheckState?)value : null);
        // Whatever the guide's state (receipt, local identity, new user, local
        // mismatch), an installed online session keeps its playtime owner, and
        // recording follows the account page: verified Handle equals the log's.
        LogCheck(LocalIdentityCheckState.NotObserved);
        Check(GameplayOwner() && !JournalAccepts(), "No log identity: owner kept, nothing recorded (" + scenario + ")");
        LogCheck(LocalIdentityCheckState.Mismatch);
        Check(GameplayOwner() && !JournalAccepts(), "Log Handle differs from the verified Handle: nothing recorded (" + scenario + ")");
        LogCheck(LocalIdentityCheckState.Match);
        Check(GameplayOwner() && JournalAccepts(), "Verified Handle matches the log: recorded without the guide receipt (" + scenario + ")");
        LogCheck(null);

        switch (scenario)
        {
            case "backfill":
            {
                Check(before is null && Open(), "Checks that pass bind gameplay and the event journal: " + FirstUseIdentityDiagnostics.Last);
                var written = store.Read();
                Check(written is { Mode: "online", Revision: 1, LogDeferred: false } && written.ProfileId == confirmed.ActiveProfileId &&
                    written.SourceKey == confirmed.SelectedSourceKey, "The missing receipt is recorded for the bound profile and source");
                Check(Open() && store.Read() == written && FirstUseIdentityDiagnostics.Last == "bound", "Later reads do not write again");
                f.Original.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
                Check(Closed(), "A recorded receipt never authorizes a replacement credential");
                break;
            }
            case "newUser":
                Check(Closed() && store.Read() is null && FirstUseIdentityDiagnostics.Last == "no-history",
                    "A user still in first-use setup gets no receipt from the gate");
                break;
            case "mismatch":
                Check(Closed() && store.Read() is null && FirstUseIdentityDiagnostics.Last == "assess-mismatch",
                    "A game identity mismatch stays blocked and records nothing: " + FirstUseIdentityDiagnostics.Last);
                break;
            case "relogin":
            {
                await SignIn();
                Check(Closed() && store.Read() is null && FirstUseIdentityDiagnostics.Last == "not-restored-session",
                    "A signed-in session is not the restored one, so nothing is backfilled: " + FirstUseIdentityDiagnostics.Last);
                var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null,
                    "After a sign-in the existing identity review asks: " + identity.State);
                Check(Closed(), "Reading the review does not open recording");
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State == "boundOnlineIdentity" && Open(),
                    "Explicit confirmation opens both exits");
                Check(store.Read() is { Mode: "online", Revision: 1, LogDeferred: false } written && written.ProfileId == confirmed.ActiveProfileId &&
                    written.SourceKey == confirmed.SelectedSourceKey, "The explicit confirmation records the receipt");
                break;
            }
            case "saveFails":
            {
                Check(Closed() && store.Read() == before && FirstUseIdentityDiagnostics.Last == "history-source-mismatch",
                    "A changed receipt blocks both exits: " + FirstUseIdentityDiagnostics.Last);
                var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null, "Identity review: " + identity.State);
                var folder = new DirectoryInfo(Path.Combine(root, "first-use-completion-v1"));
                var denied = new DirectorySecurity();
                denied.SetSecurityDescriptorBinaryForm(folder.GetAccessControl().GetSecurityDescriptorBinaryForm(), AccessControlSections.Access);
                using var user = WindowsIdentity.GetCurrent();
                var rule = new FileSystemAccessRule(user.User!, FileSystemRights.CreateFiles, AccessControlType.Deny);
                denied.AddAccessRule(rule);
                folder.SetAccessControl(denied);
                try
                {
                    string? state = null;
                    try { state = (await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State; }
                    catch (LocalFirstUseException) { }
                    Check(state != "boundOnlineIdentity" && FirstUseIdentityDiagnostics.Last == "history-update-failed" && store.Read() == before,
                        "A receipt that cannot be saved is not reported as bound: " + state + " " + FirstUseIdentityDiagnostics.Last);
                    Check(Closed(), "A receipt that was not saved keeps both exits closed");
                }
                finally
                {
                    denied.RemoveAccessRuleSpecific(rule);
                    folder.SetAccessControl(denied);
                }
                var retry = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(retry.State == "installedReviewRequired" && retry.ConfirmationKey is not null, "The review can be confirmed again: " + retry.State);
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, retry.ConfirmationKey!)).State == "boundOnlineIdentity" && Open(),
                    "Once writable, the same confirmation opens both exits");
                Check(store.Read() is { Mode: "online", LogDeferred: false } replaced && replaced.Revision == before!.Revision + 1 &&
                    replaced.SourceKey == confirmed.SelectedSourceKey, "The receipt is replaced on the retry");
                break;
            }
            case "localChangeDuringCommit":
            {
                var probed = new FirstUseCompletionStore(root);
                probed.CommitProbe = () =>
                {
                    probed.CommitProbe = null;
                    var now = local.Read();
                    local.SelectSource(now.Revision, Id(), Path.Combine(root, "third", "LIVE", "Game.log"), "LIVE", () => true);
                };
                cold.ColdCompletionHistory = probed;
                Check(Closed() && store.Read() is null, "A receipt committed while the local identity changed is put back");
                break;
            }
            case "reloginDuringCommit":
            {
                var probed = new FirstUseCompletionStore(root);
                var signedIn = false;
                probed.CommitProbe = () =>
                {
                    probed.CommitProbe = null;
                    signedIn = Task.Run(SignIn).Wait(TimeSpan.FromSeconds(15));
                };
                cold.ColdCompletionHistory = probed;
                Check(Closed() && signedIn && store.Read() is null && FirstUseIdentityDiagnostics.Last == "not-restored-session",
                    "A receipt committed while a sign-in landed is put back: " + signedIn + " " + FirstUseIdentityDiagnostics.Last);
                break;
            }
            case "closeDuringCommit":
            {
                var probed = new FirstUseCompletionStore(root);
                Task? closing = null;
                var waited = false;
                probed.CommitProbe = () =>
                {
                    probed.CommitProbe = null;
                    closing = Task.Run(cold.Close);
                    waited = !closing.Wait(TimeSpan.FromMilliseconds(300));
                };
                cold.ColdCompletionHistory = probed;
                _ = Ready();
                Check(closing is not null && closing.Wait(TimeSpan.FromSeconds(5)) && waited && store.Read() is { Mode: "online" },
                    "Close waits for the receipt commit window and runs after it");
                Check(!Ready() && !cold.HasInstalledOnlineForCompletion, "After Close nothing binds");
                break;
            }
            case "readDuringCommittedRelogin":
            {
                // The receipt is on disk and a same-Handle sign-in has landed, but
                // the writer has not run its after-commit check yet. A concurrent
                // gate read sees the file and must neither bind it nor wait.
                var probed = new FirstUseCompletionStore(root);
                var signedIn = false; var readerDone = false; var readerBound = true;
                var onDisk = false;
                probed.CommittedProbe = () =>
                {
                    probed.CommittedProbe = null;
                    signedIn = Task.Run(SignIn).Wait(TimeSpan.FromSeconds(15));
                    onDisk = store.Read() is { Mode: "online" };
                    var reader = Task.Run(() => cold.HasInstalledOnlineForCompletion);
                    readerDone = reader.Wait(TimeSpan.FromSeconds(5));
                    readerBound = !readerDone || reader.Result;
                };
                cold.ColdCompletionHistory = probed;
                var first = Ready();
                Check(signedIn && onDisk && readerDone && !readerBound && !first,
                    "A concurrent read neither waits for nor binds an unfinished commit: " + signedIn + " " + onDisk + " " + readerDone + " " + readerBound);
                Check(store.Read() is null && Closed(), "The receipt is put back and nothing stays bound: " + FirstUseIdentityDiagnostics.Last);
                break;
            }
            case "readerPausedDuringRollback":
            {
                // A concurrent gate read takes the new receipt and pauses there.
                // Meanwhile the writer's after-commit check fails (a same-Handle
                // sign-in landed) and the rollback succeeds. The reader then goes
                // on with the receipt it already holds and must not bind it.
                var probed = new FirstUseCompletionStore(root);
                var signedIn = false; var readerHeld = false;
                var holding = new ManualResetEventSlim(); var resume = new ManualResetEventSlim();
                FirstUseCompletion? held = null;
                Task<bool>? reader = null;
                probed.CommittedProbe = () =>
                {
                    probed.CommittedProbe = null;
                    signedIn = Task.Run(SignIn).Wait(TimeSpan.FromSeconds(15));
                    probed.ReadProbe = value =>
                    {
                        if (value is null || held is not null) return;
                        probed.ReadProbe = null;
                        held = value; holding.Set();
                        resume.Wait(TimeSpan.FromSeconds(15));
                    };
                    reader = Task.Run(() => cold.HasInstalledOnlineForCompletion);
                    readerHeld = holding.Wait(TimeSpan.FromSeconds(5));
                };
                cold.ColdCompletionHistory = probed;
                bool first;
                try { first = Ready(); }
                finally { resume.Set(); }
                var readerDone = reader is not null && reader.Wait(TimeSpan.FromSeconds(5));
                Check(signedIn && readerHeld && held is { Unconfirmed: true } && store.Read() is null && !first,
                    "The reader holds the new receipt while the rollback removes it: " + signedIn + " " + readerHeld + " " + held);
                Check(readerDone && !reader!.Result, "The paused reader does not bind the receipt it read before the rollback");
                Check(Closed() && store.Read() is null, "Nothing stays bound: " + FirstUseIdentityDiagnostics.Last);
                break;
            }
            case "lockedReceipt":
            {
                // A valid receipt (for an older log source) that another process,
                // such as a virus scanner, holds open without sharing.
                var statePath = Path.Combine(root, "first-use-completion-v1", "state.bin");
                var held = File.ReadAllBytes(statePath);
                using (var locked = new FileStream(statePath, FileMode.Open, FileAccess.Read, FileShare.None))
                {
                    Check(Closed() && FirstUseIdentityDiagnostics.Last == "exception", "A locked receipt blocks automatic binding: " + FirstUseIdentityDiagnostics.Last);
                    var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                    Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null, "Identity review: " + identity.State);
                    string? state = null;
                    try { state = (await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State; }
                    catch (LocalFirstUseException) { }
                    Check(state != "boundOnlineIdentity" && FirstUseIdentityDiagnostics.Last == "history-update-failed",
                        "A confirmation while the receipt is locked stays blocked: " + state + " " + FirstUseIdentityDiagnostics.Last);
                }
                Check(File.ReadAllBytes(statePath).AsSpan().SequenceEqual(held) && store.Read() == before,
                    "The locked valid receipt is never replaced as damaged");
                Check(Closed() && FirstUseIdentityDiagnostics.Last == "history-source-mismatch", "Once released it is the same receipt: " + FirstUseIdentityDiagnostics.Last);
                var retry = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(retry.State == "installedReviewRequired" && retry.ConfirmationKey is not null, "The review can be confirmed again: " + retry.State);
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, retry.ConfirmationKey!)).State == "boundOnlineIdentity" && Open() &&
                    FirstUseIdentityDiagnostics.Last == "bound", "Once released, the ordinary update path opens both exits: " + FirstUseIdentityDiagnostics.Last);
                Check(store.Read() is { Unconfirmed: false } updated && updated.Revision == before!.Revision + 1 && updated.SourceKey == confirmed.SelectedSourceKey,
                    "The receipt is updated, not recovered");
                break;
            }
            case "unreadableConfirm" or "unreadableRollback":
            {
                var statePath = Path.Combine(root, "first-use-completion-v1", "state.bin");
                bool Untouched() => File.ReadAllBytes(statePath).AsSpan().SequenceEqual(unreadableBytes);
                // Never taken as "no receipt": no automatic backfill, the file stays as it is.
                Check(Closed() && FirstUseIdentityDiagnostics.Last == "exception" && Untouched(),
                    "An unreadable receipt blocks automatic binding and is not replaced: " + FirstUseIdentityDiagnostics.Last);
                if (scenario == "unreadableRollback")
                {
                    var probed = new FirstUseCompletionStore(root);
                    var signedIn = false; var during = false;
                    probed.CommittedProbe = () =>
                    {
                        probed.CommittedProbe = null;
                        during = probed.Read() is { Unconfirmed: true };
                        signedIn = Task.Run(SignIn).Wait(TimeSpan.FromSeconds(15));
                    };
                    cold.ColdCompletionHistory = probed;
                    var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                    Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null, "Identity review: " + identity.State);
                    string? state = null;
                    try { state = (await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State; }
                    catch (LocalFirstUseException) { }
                    Check(state != "boundOnlineIdentity" && signedIn && during && FirstUseIdentityDiagnostics.Last == "history-update-failed",
                        "A recovery whose session changed is not reported as bound: " + state + " " + signedIn + " " + during + " " + FirstUseIdentityDiagnostics.Last);
                    Check(Untouched() && Closed(), "The unreadable bytes are put back exactly and nothing binds: " + FirstUseIdentityDiagnostics.Last);
                }
                var recovery = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(recovery.State == "installedReviewRequired" && recovery.ConfirmationKey is not null, "The identity review asks: " + recovery.State);
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, recovery.ConfirmationKey!)).State == "boundOnlineIdentity" && Open(),
                    "Explicit confirmation recovers the recording, as it did before the receipt was required: " + FirstUseIdentityDiagnostics.Last);
                Check(store.Read() is { Mode: "online", LogDeferred: false, Unconfirmed: false } recovered &&
                    recovered.ProfileId == confirmed.ActiveProfileId && recovered.SourceKey == confirmed.SelectedSourceKey,
                    "A confirmed receipt replaces the unreadable one");
                runtime.Dispose(); host.Dispose();
                await StartCold();
                cold = runtime.FirstUseMode!;
                Check(Open() && FirstUseIdentityDiagnostics.Last == "bound", "The next launch binds without asking again: " + FirstUseIdentityDiagnostics.Last);
                break;
            }
            case "backfillRollbackFails" or "confirmRollbackFails" or "rollbackFailsThenRestart":
            {
                var statePath = Path.Combine(root, "first-use-completion-v1", "state.bin");
                var probed = new FirstUseCompletionStore(root);
                var signedIn = false;
                FileStream? held = null;
                // After the file is in place: a same-Handle sign-in lands, then a
                // reader holds the receipt open without delete sharing, so the
                // rollback can neither delete nor replace it.
                probed.CommittedProbe = () =>
                {
                    probed.CommittedProbe = null;
                    signedIn = Task.Run(SignIn).Wait(TimeSpan.FromSeconds(15));
                    held = new FileStream(statePath, FileMode.Open, FileAccess.Read, FileShare.Read);
                };
                try
                {
                    cold.ColdCompletionHistory = probed;
                    if (scenario != "confirmRollbackFails")
                    {
                        Check(!Ready() && signedIn && held is not null, "A backfill whose rollback failed is not reported as bound: " + signedIn);
                    }
                    else
                    {
                        Check(Closed() && FirstUseIdentityDiagnostics.Last == "history-source-mismatch", "A changed receipt blocks both exits");
                        var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                        Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null, "Identity review: " + identity.State);
                        string? state = null;
                        try { state = (await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State; }
                        catch (LocalFirstUseException) { }
                        Check(state != "boundOnlineIdentity" && signedIn && held is not null && FirstUseIdentityDiagnostics.Last == "history-update-failed",
                            "A confirmation whose rollback failed is not reported as bound: " + state + " " + FirstUseIdentityDiagnostics.Last);
                    }
                    Check(store.Read() is { Mode: "online", LogDeferred: false } left && left.SourceKey == confirmed.SelectedSourceKey,
                        "The rollback really failed: the new receipt is still readable");
                    Check(Closed() && FirstUseIdentityDiagnostics.Last == "history-uncertain",
                        "A receipt left by a failed rollback never binds automatically: " + FirstUseIdentityDiagnostics.Last);
                }
                finally { held?.Dispose(); }
                Check(Closed() && FirstUseIdentityDiagnostics.Last == "history-uncertain", "Releasing the file does not lift the block");
                if (scenario == "rollbackFailsThenRestart")
                {
                    // The receipt file alone says it is unconfirmed: no other file
                    // whose loss could lift the block.
                    Check(Directory.GetFileSystemEntries(Path.GetDirectoryName(statePath)!).Select(Path.GetFileName)
                        .All(name => name is "state.bin" or "state.bin.lock") && store.Read() is { Unconfirmed: true },
                        "Only the receipt file holds its unconfirmed state");
                    // A new process knows nothing of the old one's memory.
                    runtime.Dispose(); host.Dispose();
                    await StartCold();
                    cold = runtime.FirstUseMode!;
                    cold.ReturningAtStartup = true;
                    Check(cold.HasInstalledOnlineAccount && Closed() && FirstUseIdentityDiagnostics.Last == "history-uncertain",
                        "After a restart the uncertain receipt still does not bind: " + FirstUseIdentityDiagnostics.Last);
                    // A sign-in before the first binding: a backfill would refuse this
                    // session, so the left-over receipt must not stand in for one.
                    await SignIn();
                    Check(Closed() && FirstUseIdentityDiagnostics.Last == "history-uncertain",
                        "After a restart and a new sign-in the uncertain receipt still does not bind: " + FirstUseIdentityDiagnostics.Last);
                }
                var retry = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(retry.State == "installedReviewRequired" && retry.ConfirmationKey is not null, "The identity review asks: " + retry.State);
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, retry.ConfirmationKey!)).State == "boundOnlineIdentity" && Open(),
                    "An explicit confirmation clears the block and opens both exits");
                Check(store.Read() is { } after && !after.Unconfirmed && after.SourceKey == confirmed.SelectedSourceKey,
                    "The confirmation leaves a confirmed receipt on disk");
                if (scenario == "rollbackFailsThenRestart")
                {
                    runtime.Dispose(); host.Dispose();
                    await StartCold();
                    cold = runtime.FirstUseMode!;
                    Check(Open() && FirstUseIdentityDiagnostics.Last == "bound", "The next launch binds without asking again: " + FirstUseIdentityDiagnostics.Last);
                }
                break;
            }
            default:
            {
                var expected = scenario switch
                {
                    "source" => "history-source-mismatch", "profile" => "history-profile-mismatch", _ => "history-mode-mismatch"
                };
                Check(Closed() && store.Read() == before && FirstUseIdentityDiagnostics.Last == expected,
                    "A changed receipt blocks both exits and is kept: " + FirstUseIdentityDiagnostics.Last);
                var identity = await cold.ReadOnlineIdentityAsync(cold.Current.Revision);
                Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null,
                    "A changed receipt leads to the existing identity review: " + identity.State);
                Check(Closed(), "Reading the review does not open recording");
                Check((await cold.ConfirmOnlineIdentityAsync(cold.Current.Revision, identity.ConfirmationKey!)).State == "boundOnlineIdentity" && Open(),
                    "Explicit confirmation opens both exits");
                var replaced = store.Read();
                Check(replaced is { Mode: "online", LogDeferred: false } && replaced.Revision == before!.Revision + 1 &&
                    replaced.ProfileId == confirmed.ActiveProfileId && replaced.SourceKey == confirmed.SelectedSourceKey,
                    "Confirmation replaces the receipt so the next cold start binds without asking");
                break;
            }
        }
    }
}
