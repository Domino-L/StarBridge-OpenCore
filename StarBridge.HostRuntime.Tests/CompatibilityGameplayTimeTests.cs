using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class CompatibilityGameplayTimeTests
{
    internal static Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("sb-compatible-time-").FullName;
        try
        {
            var legacy = new BridgeAccountContext("fixture", "legacy", "old-business");
            var scm = new BridgeAccountContext("fixture", "scm", "new-login");
            var current = (Context: legacy, Generation: 1L);
            var verified = true;
            var store = new GameplayTimeStore(root);
            using (var original = store.Open(legacy))
            {
                var empty = original.Read();
                original.Save(empty, empty with { Consent = GameplayRecordingConsent.Declined, Seconds = 3600, ShowOnProfile = false }, () => true);
            }
            var files = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).ToDictionary(p => p, File.ReadAllBytes);
            store.ResolveOwner = authentication => {
                if (!verified || authentication != current.Context)
                    throw new StarBridge.HostRuntime.Privacy.LocalPrivacyException("privacy_local.account_changed");
                return legacy;
            };
            using var runtime = new GameplayTimeRuntime(store, () => current, () => new(1, "notRunning"), startTimer: false);
            void CheckRead()
            {
                var reply = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read", Guid.NewGuid().ToString("N"), current.Generation,
                    new { schemaVersion = 1 }, current.Context)).Response;
                Check(reply.Error is null && (!reply.Payload.TryGetProperty("error", out var error) || error.ValueKind == System.Text.Json.JsonValueKind.Null) &&
                    reply.Payload.GetProperty("seconds").GetInt64() == 3600 &&
                    reply.Payload.GetProperty("consent").GetString() == "declined" &&
                    !reply.Payload.GetProperty("showOnProfile").GetBoolean(),
                    "Compatible login must retain original time, decline and hidden profile without lock contention");
            }
            CheckRead();
            current = (scm, 2);
            CheckRead();
            current = (legacy, 3);
            CheckRead();
            verified = false;
            var denied = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read", "revoked-cache", current.Generation,
                new { schemaVersion = 1 }, current.Context)).Response;
            Check(denied.Payload.GetProperty("error").GetString() == "gameplay.account_changed" &&
                (!denied.Payload.TryGetProperty("seconds", out var seconds) || seconds.ValueKind == System.Text.Json.JsonValueKind.Null),
                "Revoked ownership must not expose cached old-account time");
            verified = true;
            CheckRead();
            runtime.Suspend();
            verified = false;
            var suspendedDenied = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read", "revoked-after-suspend", current.Generation,
                new { schemaVersion = 1 }, current.Context)).Response;
            Check(suspendedDenied.Payload.GetProperty("error").GetString() == "gameplay.account_changed" &&
                (!suspendedDenied.Payload.TryGetProperty("seconds", out var suspendedSeconds) || suspendedSeconds.ValueKind == System.Text.Json.JsonValueKind.Null) &&
                (!suspendedDenied.Payload.TryGetProperty("savedSeconds", out var suspendedSaved) || suspendedSaved.ValueKind == System.Text.Json.JsonValueKind.Null),
                "Failed ownership recheck after suspension must discard cached old-account time");
            verified = true;
            CheckRead();
            runtime.Dispose();
            using (var lease = store.Open(current.Context))
            {
                var previous = lease.Read();
                var checks = 0;
                try
                {
                    lease.Save(previous, previous with { Seconds = 3601 }, () => { if (++checks == 2) verified = false; return true; });
                    throw new Exception("Revocation immediately before commit escaped");
                }
                catch (GameplayTimeException error) when (error.Code == "gameplay.account_changed") { }
            }
            verified = true;
            Check(files.Count == Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length &&
                files.All(p => p.Value.SequenceEqual(File.ReadAllBytes(p.Key))), "Switching login must not rewrite or duplicate time files");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
