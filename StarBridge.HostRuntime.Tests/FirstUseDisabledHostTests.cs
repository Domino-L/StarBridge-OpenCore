using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class FirstUseDisabledHostTests
{
    internal static async Task Run()
    {
        foreach (var phase in new[] { "offline", "offlinePending", "onlinePending", "local", "localPending", "corrupt" })
        foreach (var retainedSession in new[] { false, true })
        {
            using var f = new LocalAccountStopTests.Fixture(initialSession: retainedSession);
            var path = Path.Combine(f.Root, "first-use-mode-v1", "state.bin");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            if (phase == "corrupt")
            {
                File.WriteAllBytes(path, [1, 2, 3]);
            }
            else
            {
                // Synthetic cold-start input, not a product transition receipt.
                var clear = JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, value = new {
                    revision = 1, operationId = Guid.NewGuid().ToString("N"), savedAt = DateTimeOffset.UtcNow, phase } });
                File.WriteAllBytes(path, ProtectedData.Protect(clear, Encoding.UTF8.GetBytes("StarBridge.first-use-mode.v1"),
                    DataProtectionScope.CurrentUser));
                CryptographicOperations.ZeroMemory(clear);
                Require(new FirstUseModeStore(f.Root).Read().Phase == phase, "fixture must exercise a valid persisted mode");
            }
            var bytes = File.ReadAllBytes(path);
            var calls = 0;
            using var runtime = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root,
                _ => { calls++; return Task.FromResult(f.Runtime); }, enableFirstUseModes: false);
            Require(calls == 1 && ReferenceEquals(runtime, f.Runtime), "ordinary account factory must run despite experimental " + phase);
            Require(runtime.FirstUseMode is null && runtime.FirstUseGame is null && runtime.FirstUseStatistics is null &&
                runtime.FirstUseOverlaySource is null && runtime.FirstUseOnlineReviewDispatcher is null,
                "a Host built without first-use must not construct local or recovery owners");
            await using var binding = new NativeAccountRuntimeBinding(runtime);
            using var mode = binding.CreateModeDispatcher();
            Require(mode is null, "no offline or installation route owner may exist");
            var current = await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Guid.NewGuid().ToString("N"),
                runtime.Generation, new { schemaVersion = 1 }));
            Require(current.Response.Error?.Code != "account.local_mode", "legacy mode must not pause ordinary account reads");
            Require(retainedSession || f.Vault.Loads > 0 && f.Host.CurrentContext is null,
                "ordinary credential lookup still runs and cannot invent a signed-in account");
            using var lease = runtime.DeviceNetwork.Enter();
            Require(lease?.IsCurrent == true, "ordinary device admission must not depend on the excluded mode");
            Require(bytes.SequenceEqual(File.ReadAllBytes(path)), "excluded mode file must remain byte-identical");
            Require(!f.Vault.Deleted, "exclusion must not clear credentials");
            f.RequireLocalStateUnchanged();
            runtime.Dispose();
            Require(lease?.IsCurrent == false && runtime.DeviceNetwork.Enter() is null, "ordinary device lifetime still retires");
            Console.WriteLine("PASS first-use disabled Host: " + phase + (retainedSession ? " / existing session" : " / cold credential lookup"));
        }
    }
    private static void Require(bool value, string label)
    { if (!value) throw new InvalidOperationException(label); }
}
