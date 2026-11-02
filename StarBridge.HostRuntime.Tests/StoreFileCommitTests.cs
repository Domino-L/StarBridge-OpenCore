using System.Security.AccessControl;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

// 2026-10-31: File.Replace showed lease-free readers a missing file. A settings save
// that merged from such a read wrote the loss back, and first use could be misjudged.
internal static class StoreFileCommitTests
{
    private static readonly BridgeAccountContext Owner = new("test", "https://commit.invalid", "synthetic");
    private static readonly OfficialFleetRealtimeTarget Target = new("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
    private static readonly TimeSpan StressTime = TimeSpan.FromSeconds(1.5);
    private const int MinimumCommits = 20;

    private static LocalPrivacySettings Settings(OfficialFleetRealtimeChoice? choice) => new(true,
        new(PlayerSharedStateFields.Presence | PlayerSharedStateFields.Server, true, false, ["group-1"]),
        new(PlayerSharedStateFields.Location, true), OfficialFleet: choice);
    private static OfficialFleetRealtimeChoice Choice(int? maximum) =>
        new(Target, CommunityRealtimeScope.SupportedFields, "initial", Op(), maximum);
    private static string Op() => Guid.NewGuid().ToString("N");

    internal static async Task Verify()
    {
        await InTemporaryRoot(PrivacyReaderNeverSeesAGap);
        await InTemporaryRoot(EditorSaveKeepsOfficialChoiceAtAnyGap);
        await InTemporaryRoot(OfficialSaveKeepsOtherSettingsAtAnyGap);
        await InTemporaryRoot(OfficialSaveRefusesAnAudienceItDidNotCheck);
        await InTemporaryRoot(PrivacyCommitKeepsATightenedDacl);
        await InTemporaryRoot(StuckReaderFailsPrivacyCommitWithoutChange);
        await InTemporaryRoot(LostOwnerStopsAWaitingPrivacyCommit);
        await InTemporaryRoot(OutsideChangeDuringAWaitStopsThePrivacyCommit);
        await InTemporaryRoot(StartupKeepsCompletedSetupDuringCommit);
        await InTemporaryRoot(StartupKeepsProgressDuringCommit);
    }

    private static async Task InTemporaryRoot(Func<string, Task> test)
    {
        var root = Directory.CreateTempSubdirectory("starbridge-store-commit-").FullName;
        try { await test(root); }
        finally { try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    private static void Check(bool condition, string failure)
    {
        if (!condition) throw new InvalidOperationException(failure);
    }

    private static string PrivacyFile(string root) =>
        Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();

    // A dedicated writer thread: a starved thread pool must not hide the gap.
    private static void WhileWriting(Action write, Action read)
    {
        var done = false;
        var commits = 0;
        Exception? failure = null;
        var writer = new Thread(() =>
        {
            try { while (!Volatile.Read(ref done)) { write(); Interlocked.Increment(ref commits); } }
            catch (Exception error) { failure = error; }
        }) { IsBackground = true };
        writer.Start();
        var until = DateTime.UtcNow + StressTime;
        var limit = DateTime.UtcNow + TimeSpan.FromSeconds(30);
        try { while ((DateTime.UtcNow < until || Volatile.Read(ref commits) < MinimumCommits) && DateTime.UtcNow < limit && failure is null) read(); }
        finally { Volatile.Write(ref done, true); writer.Join(); }
        if (failure is not null) throw new InvalidOperationException("The writer failed.", failure);
        Check(commits >= MinimumCommits, "The readers overlapped too few commits: " + commits);
    }

    private static Task PrivacyReaderNeverSeesAGap(string root)
    {
        var store = new LocalPrivacyStore(root);
        store.Save(Owner, 0, Op(), Settings(Choice(2)), () => true);
        var paused = false;
        var reads = 0L;
        WhileWriting(() => store.SetPublicationPaused(Owner, 1, paused = !paused, () => true), () =>
        {
            reads++;
            Check(store.Read(Owner).Revision == 1, "A reader saw no saved privacy settings during a commit.");
            Check(!store.NeedsFirstChoice(Owner), "A commit reopened the first privacy choice.");
        });
        Check(reads > 0, "The reader never ran.");
        Console.WriteLine("PASS Privacy readers see no gap during a commit");
        return Task.CompletedTask;
    }

    // Stands in for another writer mid commit, which only a read outside the write
    // lock can overlap: the Nth owner check outside the lock hides the file until the next.
    private sealed class SimulatedGap(string path, int skip)
    {
        private readonly string _hidden = path + ".hidden";
        private int _remaining = skip;
        private bool _isHidden;
        internal bool Used { get; private set; }

        internal BridgeAccountContext Resolve(BridgeAccountContext owner)
        {
            if (_isHidden) Restore();
            else if (!Used && !LockHeld() && _remaining-- == 0)
            {
                File.Move(path, _hidden);
                _isHidden = true;
                Used = true;
            }
            return owner;
        }

        internal void Restore()
        {
            if (!_isHidden) return;
            File.Move(_hidden, path);
            _isHidden = false;
        }

        private bool LockHeld()
        {
            try { using var free = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); return false; }
            catch (IOException) { return true; }
        }
    }

    // Walks the gap across every lease-free owner check of one save.
    private static async Task AtEveryGap(string root, LocalPrivacySettings initial, Func<LocalPrivacyStore, string, Task<BridgeEnvelope>> save,
        Action<LocalPrivacySnapshot> verifyKept, Action<LocalPrivacySnapshot> verifySaved)
    {
        for (var skip = 0; ; skip++)
        {
            var folder = Path.Combine(root, "gap-" + skip);
            var store = new LocalPrivacyStore(folder);
            store.Save(Owner, 0, Op(), initial, () => true);
            var gap = new SimulatedGap(PrivacyFile(folder), skip);
            store.ResolveOwner = gap.Resolve;
            var operation = Op();
            BridgeEnvelope response;
            try { response = await save(store, operation); }
            finally { store.ResolveOwner = null; gap.Restore(); }
            var saved = store.Read(Owner);
            verifyKept(saved);
            if (response.Error is null)
            {
                Check(saved.Revision == 2 && saved.OperationId == operation, "A reported save did not commit.");
                verifySaved(saved);
            }
            else
            {
                // The gap read as "no saved revision", which the revision check refuses.
                Check(response.Error.Code == "privacy_local.conflict", "Unexpected refusal: " + response.Error.Code);
                Check(saved.Revision == 1, "A refused save changed the revision.");
            }
            if (!gap.Used)
            {
                Check(skip > 0, "The simulated gap never opened.");
                Check(response.Error is null, "A save without any gap failed: " + response.Error?.Code);
                return;
            }
        }
    }

    private static async Task EditorSaveKeepsOfficialChoiceAtAnyGap(string root)
    {
        var choice = Choice(2);
        var edited = Settings(null) with { Room = new(PlayerSharedStateFields.Presence, false) };
        await AtEveryGap(root, Settings(choice), (store, operation) =>
        {
            var dispatcher = new LocalPrivacyDispatcher(store, () => (Owner, 4L));
            return Task.FromResult(dispatcher.Dispatch(BridgeEnvelope.Request("privacy.localSave", Op(), 4,
                new { schemaVersion = 1, expectedRevision = 1, operationId = operation, settings = edited }, Owner)).Response);
        }, saved => Check(saved.Settings?.OfficialFleet == choice, "An editor save lost the official fleet choice."),
        saved => Check(saved.Settings!.Room == edited.Room, "A reported editor save did not apply."));
        Console.WriteLine("PASS Editor save keeps the official fleet choice wherever a gap falls");
    }

    private static OfficialFleetRealtimePrivacyBridge Bridge(LocalPrivacyStore store) =>
        new(store, () => (Owner, 1L), (_, _, _) => Task.FromResult(
            new OfficialRealtimeContextWire(4, "officialFleet:7", Target, null, "initial", true, true)), () => true);

    private static async Task<string?> ContextRef(OfficialFleetRealtimePrivacyBridge bridge)
    {
        var scope = (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead", Op(), 1,
            new { schemaVersion = 1 }, Owner), default)).Response;
        Check(scope.Error is null, "The official fleet read failed: " + scope.Error?.Code);
        return scope.Payload.GetProperty("contextRef").GetString();
    }

    private static async Task OfficialSaveKeepsOtherSettingsAtAnyGap(string root)
    {
        var initial = Settings(Choice(null));
        await AtEveryGap(root, initial, async (store, operation) =>
        {
            var bridge = Bridge(store);
            var resolve = store.ResolveOwner;
            store.ResolveOwner = null;
            var context = await ContextRef(bridge);
            store.ResolveOwner = resolve;
            return (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave", Op(), 1,
                new { schemaVersion = 1, contextRef = context, expectedRevision = 1, operationId = operation, fields = 1 }, Owner), default)).Response;
        }, saved =>
        {
            Check(saved.Settings!.Fleet.Fields == initial.Fleet.Fields && saved.Settings.Fleet.VisibilityGroupIds.SequenceEqual(["group-1"]) &&
                saved.Settings.Room.Fields == initial.Room.Fields, "An official fleet save replaced the other privacy choices.");
        }, saved => Check(saved.Settings!.OfficialFleet?.Fields == (PlayerSharedStateFields)1, "A reported official fleet save did not apply."));
        Console.WriteLine("PASS Official fleet save keeps the other privacy choices wherever a gap falls");
    }

    // The first read saw no retained audience, so nothing checked the one on disk.
    private static async Task OfficialSaveRefusesAnAudienceItDidNotCheck(string root)
    {
        var store = new LocalPrivacyStore(root);
        var choice = Choice(2);
        store.Save(Owner, 0, Op(), Settings(choice), () => true);
        var bridge = Bridge(store);
        var context = await ContextRef(bridge);
        var gap = new SimulatedGap(PrivacyFile(root), 0);
        store.ResolveOwner = gap.Resolve;
        BridgeEnvelope response;
        try
        {
            response = (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave", Op(), 1,
                new { schemaVersion = 1, contextRef = context, expectedRevision = 1, operationId = Op(), fields = 15 }, Owner), default)).Response;
        }
        finally { store.ResolveOwner = null; gap.Restore(); }
        Check(response.Error?.Code == "privacy_local.changed", "An unchecked audience got: " + (response.Error?.Code ?? "saved"));
        Check(store.Read(Owner).Settings?.OfficialFleet == choice, "The refused save changed the choice.");
        Console.WriteLine("PASS Official fleet save refuses an audience its remote check did not cover");
    }

    private static Task PrivacyCommitKeepsATightenedDacl(string root)
    {
        var store = new LocalPrivacyStore(root);
        store.Save(Owner, 0, Op(), Settings(null), () => true);
        var file = new FileInfo(PrivacyFile(root));
        var tightened = file.GetAccessControl(AccessControlSections.Access);
        tightened.SetAccessRuleProtection(true, true);
        file.SetAccessControl(tightened);
        var expected = file.GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorSddlForm(AccessControlSections.Access);
        store.Save(Owner, 1, Op(), Settings(null), () => true);
        var actual = new FileInfo(file.FullName).GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorSddlForm(AccessControlSections.Access);
        Check(actual == expected, "A commit dropped the file's DACL.");
        Console.WriteLine("PASS Privacy commit keeps a tightened DACL");
        return Task.CompletedTask;
    }

    private static Task StuckReaderFailsPrivacyCommitWithoutChange(string root)
    {
        var store = new LocalPrivacyStore(root);
        store.Save(Owner, 0, Op(), Settings(null), () => true);
        var path = PrivacyFile(root);
        var before = File.ReadAllBytes(path);
        string? code = null;
        using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            try { store.Save(Owner, 1, Op(), Settings(null), () => true); }
            catch (LocalPrivacyException error) { code = error.Code; }
        Check(code == "privacy_local.write_failed", "A stuck reader gave: " + (code ?? "saved"));
        Check(before.SequenceEqual(File.ReadAllBytes(path)), "A failed commit changed the file.");
        Check(!Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "A failed commit left its temporary file.");
        Console.WriteLine("PASS A stuck reader fails the privacy commit and changes nothing");
        return Task.CompletedTask;
    }

    private static Task LostOwnerStopsAWaitingPrivacyCommit(string root)
    {
        var store = new LocalPrivacyStore(root);
        store.Save(Owner, 0, Op(), Settings(null), () => true);
        var path = PrivacyFile(root);
        var before = File.ReadAllBytes(path);
        var reading = false;
        var waits = 0;
        string? code = null;
        using (var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            reading = true;
            // The checks before the commit pass; the first one during the wait does not.
            try { store.Save(Owner, 1, Op(), Settings(null), () => !reading || ++waits < 5); }
            catch (LocalPrivacyException error) { code = error.Code; }
        }
        Check(code == "privacy_local.account_changed", "A lost owner gave: " + (code ?? "saved"));
        Check(before.SequenceEqual(File.ReadAllBytes(path)), "A withdrawn commit changed the file.");
        Console.WriteLine("PASS A lost owner stops a waiting privacy commit");
        return Task.CompletedTask;
    }

    private static Task OutsideChangeDuringAWaitStopsThePrivacyCommit(string root)
    {
        var store = new LocalPrivacyStore(root);
        store.Save(Owner, 0, Op(), Settings(null), () => true);
        var path = PrivacyFile(root);
        var directory = Path.GetDirectoryName(path)!;
        var outside = File.ReadAllBytes(path);
        outside[0] = (byte)' ';
        var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var temporarySeen = 0;
        string? code = null;
        try
        {
            // The second check that finds the temporary file runs during the wait.
            store.Save(Owner, 1, Op(), Settings(null), () =>
            {
                if (Directory.EnumerateFiles(directory, "*.tmp").Any() && ++temporarySeen == 2)
                {
                    reader.Dispose();
                    File.WriteAllBytes(path, outside);
                }
                return true;
            });
        }
        catch (LocalPrivacyException error) { code = error.Code; }
        finally { reader.Dispose(); }
        Check(code == "privacy_local.conflict", "An outside change gave: " + (code ?? "saved"));
        Check(outside.SequenceEqual(File.ReadAllBytes(path)), "A waiting commit overwrote an outside change.");
        Console.WriteLine("PASS An outside change stops a waiting privacy commit");
        return Task.CompletedTask;
    }

    private static Task StartupKeepsCompletedSetupDuringCommit(string root)
    {
        var store = new FirstUseCompletionStore(root);
        var profile = Op();
        var saved = store.Save(null, Op(), "local", profile, "synthetic-source-0001", () => true);
        var startup = new FirstUseStartupReader(root, () => new("fresh", "0.7.2"));
        WhileWriting(() => saved = store.Save(saved, Op(), "local", profile, "synthetic-source-0001", () => true), () =>
        {
            var seen = startup.Read();
            Check(seen.Reason == "completedSetup", "Startup read a completed setup as: " + seen.Reason);
        });
        Console.WriteLine("PASS Startup keeps a completed setup during a commit");
        return Task.CompletedTask;
    }

    private static Task StartupKeepsProgressDuringCommit(string root)
    {
        var store = new LocalFirstUseStore(root);
        var saved = store.SaveProgress(0, Op(), new("mode", "local", null, null, null), () => true);
        var startup = new FirstUseStartupReader(root, () => new("fresh", "0.7.2"));
        WhileWriting(() => saved = store.SaveProgress(saved.Revision, Op(), new("mode", "local", null, null, null), () => true), () =>
        {
            var seen = startup.Read();
            Check(seen.Reason == "resume", "Startup read saved progress as: " + seen.Reason);
        });
        Console.WriteLine("PASS Startup keeps saved first-use progress during a commit");
        return Task.CompletedTask;
    }
}
