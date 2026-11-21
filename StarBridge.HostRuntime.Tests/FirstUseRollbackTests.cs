using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Onboarding;
using Old = StarBridge.HostRuntime.Onboarding.Rollback0721;

internal static class FirstUseRollbackTests
{
    private static string Op() => Guid.NewGuid().ToString("N");
    internal static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "first-use-rollback-" + Op());
        Directory.CreateDirectory(root);
        try
        {
            OrdinaryCompletion(Path.Combine(root, "ordinary"));
            DeferredLocal(Path.Combine(root, "deferred"));
            InvalidUnreleased(Path.Combine(root, "unreleased"));
            Console.WriteLine("PASS rollback 0.7.2.1: frozen strict readers, identical ordinary payload, deferred supplement and old rewrite invalidation");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void OrdinaryCompletion(string root)
    {
        var store = new FirstUseCompletionStore(root);
        var value = store.Save(null, Op(), "local", Op(), "synthetic-source-0001", () => true);
        var old = new Old.FirstUseCompletionStore(root).Read();
        Check(old is not null && old.Revision == value.Revision && old.ProfileId == value.ProfileId,
            "The actual 9156873f strict reader accepts ordinary completion");
        var path = Path.Combine(root, "first-use-completion-v1", "state.bin");
        var clear = ProtectedData.Unprotect(File.ReadAllBytes(path),
            Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1"), DataProtectionScope.CurrentUser);
        try
        {
            var expected = JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1,
                value = new { revision = value.Revision, operationId = value.OperationId,
                    completedAt = value.CompletedAt, mode = value.Mode, profileId = value.ProfileId, sourceKey = value.SourceKey } });
            Check(clear.SequenceEqual(expected), "All legacy fields, order and schema are identical before nondeterministic DPAPI encryption");
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
        Check(!Directory.Exists(Path.Combine(root, "first-use-completion-deferred-v1")), "Ordinary completion writes only v1");
    }

    private static void DeferredLocal(string root)
    {
        var store = new LocalFirstUseStore(root);
        // Retain an actual historical source to exercise the old reader's
        // selected-source invariant as well as its progress/profile invariant.
        var selected = store.SelectSource(0, Op(), Path.Combine(root, "LIVE", "Game.log"), "LIVE", () => true);
        var state = store.DeferLog(selected.Revision, Op(), () => true);
        state = store.SetDeferredStatistics(state.Revision, Op(), true, () => true);
        state = store.SaveProgress(state.Revision, Op(), new("summary", "local", null, null, null), () => true);
        new FirstUseCompletionStore(root).Save(null, Op(), "local", null, null, () => true, logDeferred: true);
        Check(!File.Exists(Path.Combine(root, "first-use-completion-v1", "state.bin")) &&
            new Old.FirstUseCompletionStore(root).Read() is null, "Old completion reader sees no receipt, never unreadable completion");
        var oldStore = new Old.LocalFirstUseStore(root);
        var old = oldStore.Read();
        Check(old.Revision == state.Revision && old.Progress?.Step == "log" && old.Sources.Count == 0,
            "Unlogged completion main file satisfies every 9156873f invariant");
        Check(new Old.FirstUseStartupReader(root, () => new("fresh", "0.7.2.1")).Read() is
            { Eligibility: "firstUse", Reason: "resume", HasProgress: true },
            "The actual old startup reader resumes the guide instead of reporting unreadableProgress");
        Check(store.Read() is { LogDeferred: true, DeferredStatisticsAllowed: true, Progress.Step: "summary" } &&
            store.Read().Sources.Count == 1, "Matching extension preserves deferred choices, UI progress and retained source");
        var extension = Path.Combine(root, "local-first-use-deferred-v1");
        File.Move(Path.Combine(extension, "state.bin"), Path.Combine(extension, "pending.bin"));
        Check(store.Read().DeferredStatisticsAllowed == true, "Interrupted final rename reads its exact matching pending extension");
        var guards = 0;
        try { store.SetDeferredStatistics(state.Revision, Op(), false, () => ++guards < 2); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.context_changed") { }
        Check(store.Read().DeferredStatisticsAllowed == true, "A failed next write preserves the interrupted previous choice");

        // Old serialization is byte-identical, including the body properties
        // before positional record properties. DPAPI bytes themselves are random.
        var mainPath = Path.Combine(root, "local-first-use-v1", "state.bin");
        var clear = ProtectedData.Unprotect(File.ReadAllBytes(mainPath),
            Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1"), DataProtectionScope.CurrentUser);
        try
        {
            var json = new JsonSerializerOptions(JsonSerializerDefaults.Web) { PropertyNameCaseInsensitive = false,
                UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow, MaxDepth = 12 };
            Check(clear.SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 3, value = old }, json)),
                "Local main payload also matches the frozen snapshot's field order and schema");
        }
        finally { CryptographicOperations.ZeroMemory(clear); }

        // Old version modifies the main file without knowing any extension.
        oldStore.SaveProgress(old.Revision, Op(), new("mode", "local", null, null, null), () => true);
        Check(store.Read() is { LogDeferred: false, DeferredStatisticsAllowed: null, Progress.Step: "mode" },
            "0.7.3 -> 0.7.2.1 -> 0.7.3 ignores the obsolete extension and reads valid main state");
        // Same revision, new ciphertext: hash binding cannot be fooled by a
        // rollback writer restoring an old revision number.
        state = store.DeferLog(store.Read().Revision, Op(), () => true);
        store.SetDeferredStatistics(state.Revision, Op(), false, () => true);
        var bytes = File.ReadAllBytes(mainPath);
        clear = ProtectedData.Unprotect(bytes, Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1"), DataProtectionScope.CurrentUser);
        try { File.WriteAllBytes(mainPath, ProtectedData.Protect(clear,
            Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1"), DataProtectionScope.CurrentUser)); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        Check(store.Read().DeferredStatisticsAllowed is null && !store.Read().LogDeferred,
            "Changing ciphertext alone invalidates deferred state even at identical revision");

        // Supplemented log files are still read by the frozen old code.
        state = store.SelectSource(store.Read().Revision, Op(), Path.Combine(root, "LIVE", "Game.log"), "LIVE", () => true);
        state = store.ConfirmIdentity(state.Revision, Op(), new(state.SelectedSourceKey!, "synthetic-evidence-0001",
            "Pilot-Example", DateTimeOffset.UtcNow.AddMinutes(-1), "current", true, false), () => true);
        Check(oldStore.Read().ActiveProfileId == state.ActiveProfileId, "Old reader accepts supplemented log and confirmed identity");
        Check(state.LogSetupPending && new LocalFirstUseStore(root).Read().LogSetupPending,
            "Unfinished setup survives reopening only in the matching extension while the frozen old reader accepts main");
        // Original v1 always wins even if a valid no-log historical sidecar exists.
        new Old.FirstUseCompletionStore(root).Save(null, Op(), "local", state.ActiveProfileId!, state.SelectedSourceKey!, () => true);
        Check(new FirstUseCompletionStore(root).Read() is { LogDeferred: false }, "Original v1 completion takes precedence");
        old = oldStore.Read();
        oldStore.SaveProgress(old.Revision, Op(), new("identity", "local", old.SelectedSourceKey, null, null), () => true);
        Check(!new LocalFirstUseStore(root).Read().LogSetupPending,
            "An old-version rewrite invalidates the setup marker with the same ciphertext hash boundary");
    }

    private static void InvalidUnreleased(string root)
    {
        var path = Path.Combine(root, "first-use-completion-v1", "state.bin");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 2, value = new {
            revision = 1, operationId = Op(), completedAt = DateTimeOffset.UtcNow,
            mode = "local", profileId = (string?)null, sourceKey = (string?)null, logDeferred = true } });
        File.WriteAllBytes(path, ProtectedData.Protect(bytes,
            Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1"), DataProtectionScope.CurrentUser));
        try { new FirstUseCompletionStore(root).Read(); throw new InvalidOperationException("Expected unreadable v2"); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.completion_read_failed") { }
        Check(new FirstUseStartupReader(root, () => new("fresh", "0.7.3")).Read() is
            { Eligibility: "unknown", Reason: "unreadableProgress" }, "Unreleased v2 goes through the existing recovery route");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
