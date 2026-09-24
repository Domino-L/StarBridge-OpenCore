using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;
using StarBridge.NativeBridge;

internal static class FlutterUpdateHelperIntegration
{
    internal static async Task Run(string helper, string fixture)
    {
        foreach (var failure in new[] { false, true }) await Case(helper, fixture, failure);
        await Case(helper, fixture, fail: true, interrupted: true);
        await Case(helper, fixture, fail: false, tampered: true);
    }
    private static async Task Case(string helper, string fixture, bool fail, bool interrupted = false, bool tampered = false)
    {
        var parent = Path.Combine(Path.GetTempPath(), "starbridge-update-integration-" + Guid.NewGuid().ToString("N"));
        var root = Path.Combine(parent, ".starbridge-update-test");
        var clientRoot = Path.Combine(parent, "client");
        var packageRoot = Path.Combine(parent, "package");
        Directory.CreateDirectory(root);
        Process? client = null, originalHost = null, updater = null;
        try
        {
            BuildFixture(clientRoot, fixture);
            BuildFixture(packageRoot, fixture);
            File.WriteAllText(Path.Combine(clientRoot, "old-only.txt"), "old version sentinel");
            if (fail) File.WriteAllText(Path.Combine(packageRoot, "native_host", "fail-startup"), "fixture deliberately omits receipt");
            var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
            File.WriteAllText(Path.Combine(packageRoot, FlutterUpdateStager.IdentityFile), JsonSerializer.Serialize(
                new FlutterPackageIdentity(1, "flutter", "win-x64", "preview", "0.6.7", "starbridge_flutter.exe"), json));
            var package = Path.Combine(root, "package.zip");
            ZipFile.CreateFromDirectory(packageRoot, package);
            var bytes = File.ReadAllBytes(package);
            using var rsa = RSA.Create(2048);
            var manifest = new FlutterUpdateManifest(1, "flutter", "win-x64", "preview", "portable-zip", "0.6.7",
                "https://example.invalid/isolated.zip", bytes.Length, Convert.ToHexString(SHA256.HashData(bytes)),
                DateTimeOffset.UtcNow.AddMinutes(-1), "Isolated process fixture", "temporary", "");
            manifest = manifest with { Signature = Convert.ToBase64String(rsa.SignData(
                Encoding.UTF8.GetBytes(FlutterUpdateManifestVerifier.BuildPayload(manifest)), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
            var trust = new Dictionary<string, string> { ["temporary"] = rsa.ToXmlString(false) };
            client = Process.Start(new ProcessStartInfo(Path.Combine(clientRoot, "starbridge_flutter.exe"))
                { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden })!;
            using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(90));
            var pidFile = Path.Combine(clientRoot, "fixture-host.pid");
            while (!File.Exists(pidFile)) await Task.Delay(50, limit.Token);
            originalHost = Process.GetProcessById(int.Parse(File.ReadAllText(pidFile)));
            // First prove a rejected plan never permits exit or changes the app.
            try
            {
                using var rejected = await FlutterUpdateHandoff.StartIsolatedAsync(helper,
                    Path.Combine(root, "missing-plan.json"), limit.Token);
                throw new Exception("Invalid handoff was accepted.");
            }
            catch (IOException) { }
            if (client.HasExited || originalHost.HasExited || File.Exists(Path.Combine(root, "state.json")))
                throw new Exception("Rejected handoff disturbed original owners.");
            var target = new FlutterUpdateTarget("win-x64", "preview", "0.6.6");
            using var runtime = new FlutterUpdateRuntime(new Uri("https://example.invalid/manifest"), target,
                new FlutterUpdateManifestVerifier(trust), new SignedTransport(manifest, bytes));
            var adapter = new FlutterUpdateIsolatedInstaller(runtime, helper, parent, target, client, originalHost, trust);
            using var bridge = new FlutterUpdateBridgeDispatcher(runtime, () => "0.6.6", () => 4, installation: adapter.Installation);
            async Task<BridgeEnvelope> Request(string name, object payload) => (await bridge.DispatchAsync(
                BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 4, payload), limit.Token)).Response;
            var offer = await Request(FlutterUpdateBridgeDispatcher.RequestName, new { schemaVersion = 1 });
            if (offer.Status != "ok" || offer.Payload.GetProperty("state").GetString() != "available")
                throw new Exception("Signed offer did not reach Bridge.");
            var prepared = await Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, new { schemaVersion = 1, version = "0.6.7" });
            if (prepared.Status != "ok" || adapter.HelperProcess is not null || client.HasExited || originalHost.HasExited)
                throw new Exception("Preparation launched an update or lost original owners.");
            root = adapter.TransactionRoot!;
            var ticket = prepared.Payload.GetProperty("ticket").GetString();
            if (tampered)
            {
                // Simulate an archive changed after Host preparation. The helper
                // must independently reject it before asking original owners to exit.
                var downloaded = Directory.GetFiles(root, "flutter-download-*.zip").Single();
                using var changed = new FileStream(downloaded, FileMode.Append, FileAccess.Write, FileShare.Read);
                changed.WriteByte(1);
            }
            var accepted = await Request(FlutterUpdateBridgeDispatcher.HandoffRequestName, new { schemaVersion = 1, ticket });
            if (tampered)
            {
                if (accepted.Status != "error" || client.HasExited || originalHost.HasExited ||
                    File.Exists(Path.Combine(root, "state.json")) || !File.Exists(Path.Combine(clientRoot, "old-only.txt")))
                    throw new Exception("Changed archive caused an installation or original exit.");
                Console.WriteLine("PASS helper independently rejects archive changed after preparation; original remains running");
                return;
            }
            if (accepted.Status != "ok" || !accepted.Payload.GetProperty("accepted").GetBoolean())
                throw new Exception("Bridge ticket did not reach the real helper.");
            updater = adapter.HelperProcess!;
            if ((await Request(FlutterUpdateBridgeDispatcher.HandoffRequestName, new { schemaVersion = 1, ticket })).Status != "error")
                throw new Exception("Real helper handoff was replayed.");
            Console.WriteLine("PASS signed download -> Bridge ticket -> durable real helper handoff; duplicate rejected");
            if (ReadPhase(Path.Combine(root, "state.json")) != "prepared" || client.HasExited || originalHost.HasExited)
                throw new Exception("Handoff acknowledged before a durable prepared state.");
            File.WriteAllText(Path.Combine(clientRoot, "stop-fixture"), "stop original fixture");
            if (interrupted)
            {
                var stateFile = Path.Combine(root, "state.json");
                while (ReadPhase(stateFile) != "awaiting-ready" || !File.Exists(pidFile))
                    await Task.Delay(50, limit.Token);
                // Readiness is intentionally withheld. Pin the new fixture Host
                // before crashing only the helper process launched by this test.
                using var candidateHost = Process.GetProcessById(int.Parse(File.ReadAllText(pidFile)));
                while (!File.Exists(Path.Combine(clientRoot, "host-ready-" + candidateHost.Id)))
                    await Task.Delay(50, limit.Token);
                updater.Kill();
                await updater.WaitForExitAsync(limit.Token);
                using (var blocked = StartRecovery(helper, root))
                {
                    await blocked.WaitForExitAsync(limit.Token);
                    if (blocked.ExitCode != 6 || candidateHost.HasExited || ReadPhase(stateFile) != "awaiting-ready" ||
                        !Directory.Exists(Path.Combine(root, "backup")))
                        throw new Exception("Recovery modified an installation with a live candidate.");
                }
                File.WriteAllText(Path.Combine(clientRoot, "stop-fixture"), "stop candidate fixture");
                await candidateHost.WaitForExitAsync(limit.Token);
                updater.Dispose();
                updater = StartRecovery(helper, root);
            }
            await updater.WaitForExitAsync(limit.Token);
            if (updater.ExitCode != (fail ? 5 : 0)) throw new Exception("Unexpected isolated helper result: " + updater.ExitCode);
            var phase = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "state.json"))).RootElement.GetProperty("phase").GetString();
            if (phase != (fail ? "rolled-back" : "committed") || File.Exists(Path.Combine(clientRoot, "old-only.txt")) != fail)
                throw new Exception("Update did not retain the expected installation.");
            Console.WriteLine(fail ? "PASS helper restores old installation after missing receipt" : "PASS helper commits only after real pipe receipt");
            if (interrupted)
            {
                using var repeated = StartRecovery(helper, root);
                await repeated.WaitForExitAsync(limit.Token);
                if (repeated.ExitCode != 5) throw new Exception("Completed recovery was not idempotent.");
                Console.WriteLine("PASS crashed helper recovery rejects live candidate, restores after exit, and is idempotent");
            }
        }
        finally
        {
            // Only fixtures under this exact freshly-created temp parent are stopped.
            for (var sweep = 0; sweep < 3; sweep++)
            {
                foreach (var process in Process.GetProcesses())
                {
                    using (process)
                    {
                        try
                        {
                            var path = process.MainModule?.FileName;
                            if (path?.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) == true && !process.HasExited)
                            { process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); }
                        }
                        catch (InvalidOperationException) { }
                        catch (System.ComponentModel.Win32Exception) { }
                    }
                }
                await Task.Delay(150); // Let terminated descendants finish unloading their DLLs.
            }
            if (updater is { HasExited: false }) { updater.Kill(); await updater.WaitForExitAsync(); }
            updater?.Dispose(); client?.Dispose(); originalHost?.Dispose();
            Directory.Delete(parent, recursive: true);
        }
    }
    private sealed class SignedTransport(FlutterUpdateManifest manifest, byte[] archive) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var content = request.RequestUri?.AbsoluteUri switch {
                "https://example.invalid/manifest" => JsonSerializer.SerializeToUtf8Bytes(manifest, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
                "https://example.invalid/isolated.zip" => archive,
                _ => throw new InvalidOperationException("Unexpected update request.")
            };
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new ByteArrayContent(content) });
        }
    }
    private static string? ReadPhase(string path)
    {
        using var json = JsonDocument.Parse(File.ReadAllText(path));
        return json.RootElement.GetProperty("phase").GetString();
    }
    private static Process StartRecovery(string helper, string root)
    {
        var start = new ProcessStartInfo(helper) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden };
        start.ArgumentList.Add("--isolated-recover");
        start.ArgumentList.Add(Path.Combine(root, "plan.json"));
        return Process.Start(start)!;
    }
    internal static void BuildFixture(string root, string source)
    {
        foreach (var directory in new[] { root, Path.Combine(root, "native_host") })
        {
            Directory.CreateDirectory(directory);
            foreach (var file in Directory.GetFiles(source)) File.Copy(file, Path.Combine(directory, Path.GetFileName(file)));
            File.Copy(Path.Combine(source, "StarBridge.UpdateFixture.exe"), Path.Combine(directory,
                directory == root ? "starbridge_flutter.exe" : "StarBridge.NativeHost.exe"));
        }
        foreach (var file in FlutterUpdateStager.RequiredFiles)
        {
            var path = Path.Combine(root, file);
            if (File.Exists(path)) continue;
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "inert fixture component");
        }
    }
}
