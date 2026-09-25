using System.Diagnostics;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace StarBridge.HostRuntime.Updates;

public sealed record LegacyCleanupReady(int ClientPid, long ClientStartTicks, int HostPid,
    long HostStartTicks, string DataRoot, bool FirstFrameRendered);

// Release-only and one attempt per Host lease. First-frame handling never waits
// for hashing, shell work or retirement; background failure cannot block startup.
public sealed class LegacyCleanupLauncher : IDisposable
{
    private readonly Process _client;
    private readonly InstalledUpdateRegistration _registration;
    private readonly string _dataRoot;
    private readonly CancellationTokenSource _lifetime = new();
    private int _queued;
    private LegacyCleanupLauncher(Process client, InstalledUpdateRegistration registration, string dataRoot)
    { _client = client; _registration = registration; _dataRoot = dataRoot; }

    public static bool Enabled(Assembly assembly) => assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
        .Where(a => a.Key == "StarBridgeEnableLegacyCleanup").Select(a => a.Value).SequenceEqual(new[] { "true" });

    public static LegacyCleanupLauncher? TryCreate(Assembly assembly, Process client, string dataRoot)
    {
        if (!OperatingSystem.IsWindows() || !Enabled(assembly)) return null;
        try {
            var registration = InstalledUpdateRegistration.Read();
            registration.RequireShape();
            if (ApplicationUpdateVersion.Parse(registration.Version) < new Version(0, 7, 0, 2) ||
                !InstalledUpdateRegistration.Same(client.MainModule?.FileName, Path.Combine(registration.Directory, "starbridge_flutter.exe")) ||
                !InstalledUpdateRegistration.Same(Environment.ProcessPath, Path.Combine(registration.Directory, "native_host", "StarBridge.NativeHost.exe"))) return null;
            return new(client, registration, dataRoot);
        } catch { return null; }
    }
    public void FirstFrameReady()
    {
        if (Interlocked.CompareExchange(ref _queued, 1, 0) != 0) return;
        _ = Task.Run(async () => {
            try { await LaunchAsync(_lifetime.Token); }
            catch { /* Defer to next healthy startup. No user data or exception text logged. */ }
        });
    }
    private async Task LaunchAsync(CancellationToken cancellation)
    {
        if (InstalledUpdateRegistration.Read() != _registration) throw new IOException();
        _registration.Require(_client.MainModule?.FileName ?? "", Environment.ProcessPath ?? "", _dataRoot);
        var helper = Path.Combine(_registration.Directory, "native_host", "maintenance", "StarBridge.UpdateHelper.exe");
        using var lease = new FileStream(helper, FileMode.Open, FileAccess.Read, FileShare.Read);
        await FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(helper, _registration.Version, cancellation);
        var name = "starbridge-legacy-cleanup-" + Guid.NewGuid().ToString("N");
        using var pipe = new NamedPipeServerStream(name, PipeDirection.Out, 1, PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var start = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = Path.GetDirectoryName(helper)! };
        start.ArgumentList.Add("--retire-wpf"); start.ArgumentList.Add(name);
        using var process = Process.Start(start) ?? throw new IOException();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        await pipe.WaitForConnectionAsync(timeout.Token);
        if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle, out var pid) || pid != process.Id) throw new IOException();
        _client.Refresh();
        if (_client.HasExited) throw new IOException();
        using var host = Process.GetCurrentProcess();
        var ready = new LegacyCleanupReady(_client.Id, _client.StartTime.ToUniversalTime().Ticks,
            host.Id, host.StartTime.ToUniversalTime().Ticks, _dataRoot, true);
        await pipe.WriteAsync(JsonSerializer.SerializeToUtf8Bytes(ready), timeout.Token);
        await pipe.FlushAsync(timeout.Token);
        // Closing this pipe completes a bounded receipt. The helper owns cleanup
        // and its recovery record; Host disposal never kills it mid-transaction.
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out int clientProcessId);
    public void Dispose() => _lifetime.Cancel();
}
