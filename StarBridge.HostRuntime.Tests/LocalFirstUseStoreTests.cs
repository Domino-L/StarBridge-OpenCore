using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;
using StarBridge.HostRuntime.Onboarding;

internal static class LocalFirstUseStoreTests
{
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Op() => Guid.NewGuid().ToString("N");
    private static LocalIdentityProof Proof(string handle = "Pilot-Example") =>
        new("fixture-source-live-1", "fixture-evidence-0001", handle, Now.AddMinutes(-1), "current", true, false);

    internal static void Run()
    {
        MissingReadDoesNotCreateFiles();
        IndependentProfilesAndReopen();
        ProgressIsNotIdentityOrCompletion();
        EvidenceAndContextGuards();
        RevisionAndBusyWriter();
        CorruptionNeverOverwrites();
        StrictProtectedDocument();
        ForgetOnlySelectedIdentity();
        LinkedStorageRejected();
        Console.WriteLine("PASS first-use local store: independent profiles, DPAPI reopen, progress, CAS, failure preservation and explicit forgetting");
    }

    private static void MissingReadDoesNotCreateFiles()
    {
        using var fixture = new Fixture();
        var snapshot = fixture.Store.Read();
        Require(snapshot.Revision == 0 && snapshot.Profiles.Count == 0, "Missing state is empty, not completed.");
        Require(!Directory.Exists(fixture.Root), "A read has no filesystem writes.");
    }

    private static void IndependentProfilesAndReopen()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Root);
        var legacy = Path.Combine(fixture.Root, "existing-account.json");
        File.WriteAllText(legacy, "synthetic untouched account fixture");
        var first = fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => true);
        var id1 = first.ActiveProfileId;
        var second = fixture.Store.ConfirmIdentity(1, Op(), Proof("Other-Pilot"), () => true);
        Require(second.Profiles.Count == 2 && second.ActiveProfileId != id1, "A different Handle creates a separate profile.");
        var again = fixture.Store.ConfirmIdentity(2, Op(), Proof("pilot-example"), () => true);
        Require(again.Profiles.Count == 2 && again.ActiveProfileId == id1, "Explicit confirmation reselects the existing Handle.");
        Require(again.Profiles[0].Handle == "Pilot-Example", "Case changes do not rename or duplicate a profile.");
        var reopened = fixture.NewStore().Read();
        Require(reopened.Revision == 3 && reopened.ActiveProfileId == id1 && reopened.Profiles.Count == 2,
            "Independent identities survive reopening.");
        var raw = File.ReadAllBytes(fixture.Path);
        Require(!Encoding.UTF8.GetString(raw).Contains("Pilot-Example"), "Handle is not cleartext on disk.");
        Require(!fixture.Path.Contains("Pilot") && File.ReadAllText(legacy) == "synthetic untouched account fixture",
            "No Handle filenames, no legacy/account reads or changes.");
    }

    private static void ProgressIsNotIdentityOrCompletion()
    {
        using var fixture = new Fixture();
        var waiting = new LocalFirstUseProgress("identity", "local", "fixture-source-live-1", null, null);
        var saved = fixture.Store.SaveProgress(0, Op(), waiting, () => true);
        Require(saved.Profiles.Count == 0 && saved.ActiveProfileId is null, "Saving a page creates no identity.");
        Require(fixture.NewStore().Read().Progress == waiting, "Unfinished wait can resume.");
        Expect("firstUse.invalid_state", () => fixture.Store.SaveProgress(1, Op(),
            new("summary", "local", null, null, null), () => true));
        Expect("firstUse.invalid_state", () => fixture.Store.SaveProgress(1, Op(),
            new("online", "local", null, null, null), () => true));
        Expect("firstUse.invalid_state", () => fixture.Store.SaveProgress(1, Op(),
            new("log", null, null, null, null), () => true));
        var confirmed = fixture.Store.ConfirmIdentity(1, Op(), Proof(), () => true);
        var summary = new LocalFirstUseProgress("summary", "local", "fixture-source-live-1",
            "fixture-evidence-0001", confirmed.ActiveProfileId);
        fixture.Store.SaveProgress(2, Op(), summary, () => true);
        Require(fixture.NewStore().Read().Progress == summary, "A summary is still only presentation progress.");
        // There is deliberately no completion/permission write in this store.
        Expect("firstUse.invalid_state", () => fixture.Store.SaveProgress(3, Op(),
            summary with { ProfileId = Op() }, () => true));
    }

    private static void EvidenceAndContextGuards()
    {
        using var fixture = new Fixture();
        foreach (var invalid in new[] {
            Proof() with { Handle = " " }, Proof() with { Handle = " Pilot-Example" },
            Proof() with { Handle = "../../other" }, Proof() with { SourceKey = "C:/Game.log" },
            Proof() with { EvidenceKey = "short" }, Proof() with { ObservedAt = Now.AddSeconds(1) },
            Proof() with { Origin = "history", ScopeChecked = false },
            Proof() with { Origin = "history", RequiresFreshEvidence = true },
            Proof() with { Origin = "process" }, Proof() with { Origin = "launcher" },
            Proof() with { Origin = "freshSession", RequiresFreshEvidence = true }
        }) Expect("firstUse.evidence_required", () => fixture.Store.ConfirmIdentity(0, Op(), invalid, () => true));
        Require(!Directory.Exists(fixture.Root), "Rejected proof does not create state.");
        Expect("firstUse.context_changed", () => fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => false));
        var first = fixture.Store.ConfirmIdentity(0, Op(), Proof() with { Origin = "history" }, () => true);
        var old = File.ReadAllBytes(fixture.Path);
        var checks = 0;
        Expect("firstUse.context_changed", () => fixture.Store.ConfirmIdentity(first.Revision, Op(),
            Proof("Other-Pilot"), () => ++checks < 2));
        Require(File.ReadAllBytes(fixture.Path).SequenceEqual(old), "Lost evidence at commit keeps the previous file.");
        Require(!Directory.EnumerateFiles(fixture.Folder, "*.tmp").Any(), "Own temporary file is cleaned after a failed write.");
    }

    private static void RevisionAndBusyWriter()
    {
        using var fixture = new Fixture();
        var operation = Op();
        fixture.Store.ConfirmIdentity(0, operation, Proof(), () => true);
        var old = File.ReadAllBytes(fixture.Path);
        Expect("firstUse.revision_conflict", () => fixture.Store.ConfirmIdentity(0, operation, Proof("Other-Pilot"), () => true));
        Expect("firstUse.revision_conflict", () => fixture.Store.ConfirmIdentity(1, operation, Proof(), () => true));
        Expect("firstUse.revision_conflict", () => fixture.NewStore().ConfirmIdentity(0, Op(), Proof(), () => true));
        using (var lease = new FileStream(fixture.Path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Expect("firstUse.write_failed", () => fixture.Store.ConfirmIdentity(1, Op(), Proof(), () => true));
        Require(File.ReadAllBytes(fixture.Path).SequenceEqual(old), "CAS, repeated operations and busy writers never overwrite.");
        Expect("firstUse.invalid_request", () => fixture.Store.ConfirmIdentity(long.MaxValue, Op(), Proof(), () => true));
    }

    private static void CorruptionNeverOverwrites()
    {
        using var fixture = new Fixture();
        fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => true);
        foreach (var bad in new[] { new byte[] { 1, 2, 3 }, new byte[0], new byte[128 * 1024 + 1] })
        {
            File.WriteAllBytes(fixture.Path, bad);
            Expect("firstUse.read_failed", () => fixture.Store.Read());
            Expect("firstUse.read_failed", () => fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => true));
            Require(File.ReadAllBytes(fixture.Path).SequenceEqual(bad), "Unknown is not empty; corrupt data is preserved.");
        }
    }

    private static void StrictProtectedDocument()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Folder);
        var entropy = Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1");
        foreach (var invalid in new[] {
            "{\"schemaVersion\":1,\"schemaVersion\":1,\"value\":null}",
            "{\"schemaVersion\":2,\"value\":null}",
            "{\"schemaVersion\":1,\"value\":{\"revision\":0}}",
            "{\"schemaVersion\":1,\"value\":null,\"unexpected\":true}",
            "{\"schemaVersion\":1,\"value\":{\"revision\":0,\"operationId\":null,\"savedAt\":null,\"profiles\":[],\"activeProfileId\":null,\"progress\":{\"step\":\"summary\",\"mode\":\"local\",\"sourceKey\":null,\"evidenceKey\":null,\"profileId\":null}}}"
        })
        {
            var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(invalid), entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(fixture.Path, bytes);
            Expect("firstUse.read_failed", () => fixture.Store.Read());
        }
        var wrongPurpose = ProtectedData.Protect("{}"u8.ToArray(), "Other.purpose"u8.ToArray(), DataProtectionScope.CurrentUser);
        File.WriteAllBytes(fixture.Path, wrongPurpose);
        Expect("firstUse.read_failed", () => fixture.Store.Read());
    }

    private static void ForgetOnlySelectedIdentity()
    {
        using var fixture = new Fixture();
        var first = fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => true);
        var id1 = first.ActiveProfileId!;
        var second = fixture.Store.ConfirmIdentity(1, Op(), Proof("Other-Pilot"), () => true);
        var id2 = second.ActiveProfileId!;
        fixture.Store.SaveProgress(2, Op(), new("identity", "local", "fixture-source-live-1", null, id2), () => true);
        var forgotten = fixture.Store.ForgetProfile(3, Op(), id2, () => true);
        Require(forgotten.Profiles.Count == 1 && forgotten.Profiles[0].Id == id1 &&
            forgotten.ActiveProfileId is null && forgotten.Progress is null, "Explicit forgetting does not select a different profile.");
        Expect("firstUse.profile_changed", () => fixture.Store.ForgetProfile(4, Op(), id2, () => true));
        Require(fixture.NewStore().Read().Profiles[0].Handle == "Pilot-Example", "Other profile survives.");
    }

    private static void LinkedStorageRejected()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Root);
        var target = Path.Combine(fixture.Root, "target"); Directory.CreateDirectory(target);
        try { Directory.CreateSymbolicLink(fixture.Folder, target); }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException)
        {
            // Directory junctions exercise the same reparse guard without
            // changing developer mode, privileges or machine/user permissions.
            var start = new ProcessStartInfo("powershell.exe") {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            };
            start.ArgumentList.Add("-NoProfile"); start.ArgumentList.Add("-NonInteractive");
            start.ArgumentList.Add("-Command");
            start.ArgumentList.Add("New-Item -ItemType Junction -Path $env:STARBRIDGE_TEST_LINK -Target $env:STARBRIDGE_TEST_TARGET -ErrorAction Stop | Out-Null");
            start.Environment["STARBRIDGE_TEST_LINK"] = fixture.Folder;
            start.Environment["STARBRIDGE_TEST_TARGET"] = target;
            using var process = Process.Start(start) ?? throw new Exception("Fixture junction helper did not start");
            if (!process.WaitForExit(10000)) { process.Kill(true); throw new Exception("Fixture junction helper timed out"); }
            Require(process.ExitCode == 0, "Fixture-only junction creation must succeed, otherwise reparse coverage is incomplete.");
        }
        try
        {
            Require(File.GetAttributes(fixture.Folder).HasFlag(FileAttributes.ReparsePoint), "Fixture is a real reparse point.");
            Expect("firstUse.read_failed", () => fixture.Store.Read());
            Expect("firstUse.write_failed", () => fixture.Store.ConfirmIdentity(0, Op(), Proof(), () => true));
            Require(!Directory.EnumerateFileSystemEntries(target).Any(), "Linked target is not written.");
        }
        finally { Directory.Delete(fixture.Folder); } // Fixture link only, never its target.
    }

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new Exception("Expected " + code);
    }
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "starbridge-first-use-tests", Op());
        internal string Folder => System.IO.Path.Combine(Root, "local-first-use-v1");
        internal string Path => System.IO.Path.Combine(Folder, "state.bin");
        internal LocalFirstUseStore Store => NewStore();
        internal LocalFirstUseStore NewStore() => new(Root, new Clock());
        public void Dispose()
        {
            var resolved = System.IO.Path.GetFullPath(Root);
            var expectedParent = System.IO.Path.GetFullPath(System.IO.Path.Combine(
                System.IO.Path.GetTempPath(), "starbridge-first-use-tests"));
            if (System.IO.Path.GetDirectoryName(resolved) != expectedParent ||
                !Guid.TryParseExact(System.IO.Path.GetFileName(resolved), "N", out _))
                throw new Exception("Refusing cleanup outside the single test fixture");
            if (Directory.Exists(resolved)) Directory.Delete(resolved, true);
        }
    }
}
