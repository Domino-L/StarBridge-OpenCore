using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Onboarding;

internal static class FirstUseCompletionStoreTests
{
    internal static void Run()
    {
        FirstUseRollbackTests.Run();
        var root = Path.Combine(Path.GetTempPath(), "starbridge-completion-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var directory = Path.Combine(root, "first-use-completion-v1");
            var path = Path.Combine(directory, "state.bin");
            var store = new FirstUseCompletionStore(root);
            Expect("firstUse.invalid_state", () => LocalFirstUseValidation.Check(LocalFirstUseSnapshot.Empty with { LogDeferred = true }));
            var emptyLocal = new LocalFirstUseStore(Path.Combine(root, "empty-local"));
            var deferred = emptyLocal.DeferLog(0, Op(), () => true);
            emptyLocal.SetDeferredStatistics(deferred.Revision, Op(), false, () => true);
            Check(emptyLocal.Read() is { LogDeferred: true, DeferredStatisticsAllowed: false, ActiveProfileId: null, SelectedSourceKey: null } &&
                emptyLocal.Read().Sources.Count == 0 && emptyLocal.Read().Profiles.Count == 0,
                "A fresh empty device saves no-log choices without creating sources or profiles");
            Check(store.Read() is null && !Directory.Exists(directory), "Missing receipt is not completed and read creates no data");
            var profile = Guid.NewGuid().ToString("N");
            Expect("firstUse.context_changed", () => store.Save(null, Op(), "local", profile, "synthetic-source-0001", () => false));
            Check(!Directory.Exists(directory), "Unconfirmed completion creates no receipt");
            var local = store.Save(null, Op(), "local", profile, "synthetic-source-0001", () => true);
            Check(new FirstUseCompletionStore(root).Read() == local, "Local completion survives process reopen");
            var original = File.ReadAllBytes(path);
            // A real schema-1 payload predates the optional no-log marker.
            var legacy = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(new {
                schemaVersion = 1, value = new { revision = local.Revision, operationId = local.OperationId,
                    completedAt = local.CompletedAt, mode = local.Mode, profileId = local.ProfileId, sourceKey = local.SourceKey }
            });
            File.WriteAllBytes(path, ProtectedData.Protect(legacy, Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1"), DataProtectionScope.CurrentUser));
            Check(store.Read() == local, "Schema-1 completion without the new marker remains readable");
            File.WriteAllBytes(path, original);
            Expect("firstUse.invalid_request", () => store.Save(local, Op(), "online", null, null, () => true, logDeferred: true));
            Expect("firstUse.invalid_request", () => store.Save(local, Op(), "local", profile, null, () => true, logDeferred: true));
            Check(!Encoding.UTF8.GetString(original).Contains(profile), "Receipt stays protected and contains no Handle filename");
            Check(new FirstUseStartupReader(root, () => new("update", "0.7.2")).Read().Reason == "completedSetup", "Completed setup is not reopened by update");
            Check(new LocalFirstUseStore(root).Read().ActiveProfileId is null && new FirstUseModeStore(root).Read().Phase == "unchosen",
                "Historical display receipt grants no identity or installed mode");
            Expect("firstUse.revision_conflict", () => store.Save(null, Op(), "online", profile, "synthetic-source-0001", () => true));
            var checks = 0;
            Expect("firstUse.context_changed", () => store.Save(local, Op(), "online", profile, "synthetic-source-0001", () => ++checks < 2));
            Check(original.SequenceEqual(File.ReadAllBytes(path)) && !Directory.EnumerateFiles(directory, "*.tmp").Any(), "Late owner change preserves old receipt and cleans own temporary");
            using (var locked = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
                Expect("firstUse.completion_write_failed", () => store.Save(local, Op(), "online", profile, "synthetic-source-0001", () => true));
            var online = store.Save(local, Op(), "online", profile, "synthetic-source-0001", () => true);
            Check(online.Revision == 2 && new FirstUseCompletionStore(root).Read() == online, "Online supplement saves a distinct durable receipt");
            Expect("firstUse.revision_conflict", () => store.Save(online, online.OperationId, "online", profile, "synthetic-source-0001", () => true));
            Expect("firstUse.invalid_request", () => store.Save(online, Op(), "pending", profile, "synthetic-source-0001", () => true));
            File.WriteAllBytes(path, [7, 8, 9]);
            Expect("firstUse.completion_read_failed", () => store.Read());
            Check(new FirstUseStartupReader(root, () => new("fresh", "0.7.2")).Read().Eligibility == "unknown", "Corrupted completion cannot become fresh or complete");
            Expect("firstUse.completion_read_failed", () => store.Save(null, Op(), "local", profile, "synthetic-source-0001", () => true));
            Check(File.ReadAllBytes(path).SequenceEqual(new byte[] { 7, 8, 9 }), "Corrupted original is preserved");
            var malformed = Encoding.UTF8.GetBytes("{\"schemaVersion\":1,\"schemaVersion\":1,\"value\":null}");
            File.WriteAllBytes(path, ProtectedData.Protect(malformed, Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1"), DataProtectionScope.CurrentUser));
            Expect("firstUse.completion_read_failed", () => store.Read());
            Console.WriteLine("PASS completion store: protected reopen, independent local/online receipts, conflict, late guard, busy writer and corruption preservation");
        }
        finally { Directory.Delete(root, true); }
    }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static void Expect(string code, Action action)
    {
        try { action(); throw new InvalidOperationException("Expected " + code); }
        catch (LocalFirstUseException error) when (error.Code == code) { }
    }
}
