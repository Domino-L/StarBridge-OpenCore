using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Storage;
using StarBridge.HostRuntime.Updates;
using System.Diagnostics;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class WpfCleanup
{
    internal static async Task<int> Run(string pipeName)
    {
        if (!LegacyCleanupLauncher.Enabled(Assembly.GetExecutingAssembly()) ||
            !pipeName.StartsWith("starbridge-legacy-cleanup-", StringComparison.Ordinal) ||
            !Guid.TryParseExact(pipeName["starbridge-legacy-cleanup-".Length..], "N", out _)) return 3;
        try {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            using var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.In, PipeOptions.Asynchronous);
            await pipe.ConnectAsync(timeout.Token);
            if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle, out var serverPid)) return 3;
            using var bytes = new MemoryStream();
            var buffer = new byte[4096];
            int read;
            while ((read = await pipe.ReadAsync(buffer, timeout.Token)) != 0) {
                if (bytes.Length + read > 16384) return 3;
                bytes.Write(buffer, 0, read);
            }
            var ready = JsonSerializer.Deserialize<LegacyCleanupReady>(bytes.ToArray()) ?? throw new InvalidDataException();
            if (!ready.FirstFrameRendered || ready.HostPid != serverPid || ready.ClientPid <= 0) return 3;
            using var host = Process.GetProcessById(ready.HostPid);
            using var client = Process.GetProcessById(ready.ClientPid);
            using var storage = StorageActivityLease.AcquireWriter(HostDataRoot.BootstrapDirectory);
            var current = InstalledUpdateRegistration.Read();
            if (ApplicationUpdateVersion.Parse(current.Version) < new Version(0, 7, 0, 2)) return 3;
            var data = StorageRootLocator.Read(HostDataRoot.BootstrapDirectory);
            if (!Same(ready.DataRoot, data)) return 3;
            var newExecutable = Path.Combine(current.Directory, "starbridge_flutter.exe");
            var newHost = Path.Combine(current.Directory, "native_host", "StarBridge.NativeHost.exe");
            var self = Path.Combine(current.Directory, "native_host", "maintenance", "StarBridge.UpdateHelper.exe");
            if (!Same(Environment.ProcessPath, self)) return 3; // Installed helper only, never a copied/development binary.
            current.Require(newExecutable, newHost, data);
            bool Healthy() {
                host.Refresh(); client.Refresh();
                return !host.HasExited && !client.HasExited && host.StartTime.ToUniversalTime().Ticks == ready.HostStartTicks &&
                    client.StartTime.ToUniversalTime().Ticks == ready.ClientStartTicks &&
                    Same(host.MainModule?.FileName, newHost) && Same(client.MainModule?.FileName, newExecutable);
            }
            if (!Healthy()) return 4;
            using var selfLease = new FileStream(self, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var clientLease = new FileStream(newExecutable, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var hostLease = new FileStream(newHost, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var verification = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            await Task.WhenAll(new[] { self, newExecutable, newHost }.Select(path =>
                FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(path, current.Version, verification.Token)));
            var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(current.Directory.ToUpperInvariant())));
            using var updateGate = new Semaphore(1, 1, "Local\\StarBridge.InstalledUpdate." + id);
            if (!updateGate.WaitOne(0)) return 4;
            try {
                using var settingsLease = ApplicationStartupLease.Acquire();
                var recovery = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "StarBridgeMaintenance", "legacy-0661", id);
                // One per-user file lock also excludes other Windows sessions.
                CreatePlainDirectory(Path.GetDirectoryName(recovery)!);
                if (Path.Exists(recovery + ".lock") && !WpfShortcutHandoff.PlainPath(recovery + ".lock")) return 3;
                using var cleanupLock = new FileStream(recovery + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                var registry = new WpfCleanupRegistry();
                var old = registry.Read();
                string oldDirectory;
                if (old is not null) oldDirectory = old.Directory;
                else {
                    var path = Path.Combine(recovery, "cleanup.json");
                    if (!File.Exists(path)) return 0; // No supported legacy installation, no cleanup needed.
                    if (!WpfShortcutHandoff.PlainPath(path) || new FileInfo(path).Length > 256 * 1024) return 3;
                    oldDirectory = JsonSerializer.Deserialize<WpfCleanupJournal>(File.ReadAllBytes(path), WpfCleanupFiles.Json)?.Installation
                        ?? throw new InvalidDataException();
                }
                void RequireSafe() {
                    if (InstalledUpdateRegistration.Read() != current || !Same(StorageRootLocator.Read(HostDataRoot.BootstrapDirectory), data))
                        throw new IOException("Installation/data ownership changed.");
                    current.Require(newExecutable, newHost, data);
                    if (!WpfShortcutHandoff.PlainPath(oldDirectory)) throw new IOException();
                    var registrations = WpfShortcutHandoff.ReadRegistrations();
                    if (registrations.Any(r => r.Scope != "current-user" || !Same(r.Directory, oldDirectory))) throw new IOException();
                    RequireStopped(oldDirectory);
                }
                RequireSafe();
                CreatePlainDirectory(recovery);
                var transaction = new WpfCleanupTransaction(registry, RequireSafe, Healthy,
                    () => Handoff(oldDirectory, newExecutable));
                var result = transaction.Run(WpfCleanupCatalog.Released0661(), oldDirectory, current.Directory,
                    new[] { HostDataRoot.BootstrapDirectory, data }.Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), recovery);
                return result == "committed" ? 0 : 6;
            }
            finally { updateGate.Release(); }
        }
        catch { return 5; } // No private paths or account data escape to console.
    }

    private static bool Handoff(string oldDirectory, string newExecutable)
    {
        if (!WpfShortcutHandoff.Run(newExecutable)) return false;
        const string path = @"Software\Microsoft\Windows\CurrentVersion\Run";
        using var key = Registry.CurrentUser.OpenSubKey(path, writable: true);
        if (key is null || !key.GetValueNames().Contains("StarBridge")) return true; // OFF stays OFF.
        var kind = key.GetValueKind("StarBridge");
        if (kind is not (RegistryValueKind.String or RegistryValueKind.ExpandString)) return false;
        var value = key.GetValue("StarBridge", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
        var next = '"' + newExecutable + "\" --startup";
        if (Same(value, next)) return true;
        if (!Same(value, '"' + Path.Combine(oldDirectory, "Star Bridge.exe") + "\" --startup")) return false;
        key.SetValue("StarBridge", next, kind); key.Flush();
        return Same(key.GetValue("StarBridge") as string, next);
    }
    private static void RequireStopped(string installation)
    {
        // Running old apps are deferred, never killed. A sharing violation or an
        // inaccessible candidate also blocks cleanup instead of guessing.
        foreach (var name in new[] { "Star Bridge", "unins000", "unins000.tmp" }) {
            var processes = Process.GetProcessesByName(name);
            try {
                foreach (var process in processes) {
                    if (process.HasExited) continue;
                    var file = process.MainModule?.FileName ?? throw new IOException();
                    if (file.StartsWith(installation + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("Legacy installation is still running.");
                }
            } finally { foreach (var process in processes) process.Dispose(); }
        }
    }
    private static void CreatePlainDirectory(string path)
    {
        if (!Path.IsPathFullyQualified(path) || Path.GetFullPath(path) != path || path.StartsWith(@"\\", StringComparison.Ordinal)) throw new IOException();
        if (!Directory.Exists(path)) CreatePlainDirectory(Path.GetDirectoryName(path) ?? throw new IOException());
        Directory.CreateDirectory(path);
        if (!WpfShortcutHandoff.PlainPath(path)) throw new IOException();
    }
    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out int serverProcessId);
}
