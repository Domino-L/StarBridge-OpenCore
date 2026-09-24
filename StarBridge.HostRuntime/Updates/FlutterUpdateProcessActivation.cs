using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Real process/IPC side of the transaction. Runs outside the replaced app.
/// Original owners are only waited for; only the candidate started here may be stopped.</summary>
internal sealed class FlutterUpdateProcessActivation : IFlutterUpdateActivation, IDisposable
{
    private readonly Process[] _original;
    private Process? _candidate;
    private Process? _candidateHost;
    private string? _candidateDirectory;
    private readonly SemaphoreSlim _launchGate = new(1, 1);
    private bool _stopping;
    private string? _recoveryDirectory;

    internal FlutterUpdateProcessActivation(params Process[] original) => _original = original;

    // A restarted helper no longer owns the candidate process object. Never regain
    // kill authority by looking up its PID; recovery requires the app to be stopped.
    internal static FlutterUpdateProcessActivation ForRecovery(string installation)
        => new() { _recoveryDirectory = Path.GetFullPath(installation) };

    public async Task QuiesceAsync(CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        RequireRecoveryStopped();
        foreach (var process in _original) await process.WaitForExitAsync(cancellation);
        await _launchGate.WaitAsync(cancellation);
        try
        {
            _stopping = true;
            // Kill only the exact process object launched by this coordinator, not
            // a PID looked up later or every process sharing an executable name.
            var hosts = CaptureInstallationHosts();
            try
            {
                if (_candidate is { HasExited: false }) _candidate.Kill(entireProcessTree: true);
                if (_candidate is not null) await _candidate.WaitForExitAsync(cancellation);
                foreach (var host in hosts) await host.WaitForExitAsync(cancellation);
                // Kill(tree) waiting on the root alone does not prove its children
                // exited. Recheck the exact installation Host path before renaming.
                var remaining = CaptureInstallationHosts();
                try { foreach (var host in remaining) await host.WaitForExitAsync(cancellation); }
                finally { foreach (var host in remaining) host.Dispose(); }
            }
            finally { foreach (var host in hosts) host.Dispose(); }
            _stopping = false;
        }
        finally { _launchGate.Release(); }
    }

    public Task<FlutterUpdateReady> StartAndProbeAsync(string executable, string nonce, CancellationToken cancellation)
        => StartAndProbeCoreAsync(executable, nonce, cancellation);

    // Called only after the installer and destination have been independently verified.
    // This method neither installs nor removes anything, and failure leaves WPF alone.
    internal async Task<FlutterUpdateReady> StartMigrationAndProbeAsync(string executable,
        WpfMigrationConfirmationStore store, string confirmationId, WpfMigrationBinding binding,
        CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        var confirmation = store.Inspect();
        if (confirmation is null || confirmation.Id != confirmationId || confirmation.Binding != binding ||
            confirmation.State != "install-started")
            throw new InvalidOperationException("Migration is not ready for its first startup.");
        if (!Path.IsPathFullyQualified(executable) ||
            !Version.TryParse(binding.Version, out var expected) ||
            !Version.TryParse(FileVersionInfo.GetVersionInfo(executable).ProductVersion?.Split('+')[0], out var actual) ||
            actual != expected)
            throw new InvalidDataException("Installed client version does not match confirmation.");
        var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromMinutes(2));
        store.ReserveStartup(confirmationId, binding);
        return await StartAndProbeCoreAsync(executable, nonce, timeout.Token,
            pid => store.AwaitStartup(confirmationId, binding, nonce, pid),
            receipt => store.MatchStartupReceipt(confirmationId, binding, receipt));
    }

    private async Task<FlutterUpdateReady> StartAndProbeCoreAsync(string executable, string nonce,
        CancellationToken cancellation, Action<int>? started = null,
        Action<FlutterUpdateStartupReceipt>? verified = null)
    {
        var pipeName = "starbridge-update-ready-" + Guid.NewGuid().ToString("N");
        using var pipe = new NamedPipeServerStream(pipeName, PipeDirection.In, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        await _launchGate.WaitAsync(cancellation);
        try
        {
            cancellation.ThrowIfCancellationRequested();
            if (_stopping || _candidate is not null) throw new InvalidOperationException("Candidate launch already used.");
            var start = new ProcessStartInfo(executable)
            {
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(executable)!,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            start.Environment[FlutterUpdateStartupReporter.PipeVariable] = pipeName;
            start.Environment[FlutterUpdateStartupReporter.NonceVariable] = nonce;
            _candidate = Process.Start(start) ?? throw new IOException("Candidate did not start.");
            _candidateDirectory = Path.GetDirectoryName(executable);
            started?.Invoke(_candidate.Id);
        }
        finally { _launchGate.Release(); }
        using var probe = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        using var watching = new CancellationTokenSource();
        async Task WatchExitAsync()
        {
            try
            {
                await _candidate.WaitForExitAsync(watching.Token);
                probe.Cancel();
            }
            catch (OperationCanceledException) when (watching.IsCancellationRequested) { }
        }
        var exitWatch = WatchExitAsync();
        try
        {
            await pipe.WaitForConnectionAsync(probe.Token);
            using var bytes = new MemoryStream();
            var buffer = new byte[1024];
            int count;
            while ((count = await pipe.ReadAsync(buffer, probe.Token)) != 0)
            {
                if (bytes.Length + count > 4096) throw new InvalidDataException("Oversized startup receipt.");
                bytes.Write(buffer, 0, count);
            }
            var receipt = JsonSerializer.Deserialize<FlutterUpdateStartupReceipt>(bytes.ToArray())
                ?? throw new InvalidDataException("Missing startup receipt.");
            if (_candidate.HasExited)
                throw new InvalidDataException("Receipt belongs to a different process.");
            var expectedVersion = FileVersionInfo.GetVersionInfo(executable).ProductVersion?.Split('+')[0] ?? "";
            FlutterStartupReceiptValidator.RequireMatch(receipt, nonce, expectedVersion, _candidate.Id);
            var host = Process.GetProcessById(receipt.HostProcessId);
            var expectedHost = Path.Combine(Path.GetDirectoryName(executable)!, "native_host", "StarBridge.NativeHost.exe");
            try
            {
                if (host.HasExited || host.StartTime.ToUniversalTime() < _candidate.StartTime.ToUniversalTime() ||
                    !string.Equals(host.MainModule?.FileName, expectedHost, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Receipt does not identify the candidate Host.");
                _candidateHost = host;
            }
            catch { host.Dispose(); throw; }
            cancellation.ThrowIfCancellationRequested();
            if (_candidate.HasExited || host.HasExited)
                throw new InvalidDataException("Candidate exited before startup was confirmed.");
            verified?.Invoke(receipt);
            return new(receipt.Nonce, receipt.Version, receipt.BridgeProtocol, receipt.FirstFrameRendered, receipt.HostReady);
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested && _candidate.HasExited)
        {
            throw new InvalidDataException("Candidate exited before startup was confirmed.");
        }
        finally
        {
            watching.Cancel();
            await exitWatch;
        }
    }

    public Task StartRestoredAsync(string executable, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        RequireRecoveryStopped();
        var start = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(executable)!,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        start.Environment.Remove(FlutterUpdateStartupReporter.PipeVariable);
        start.Environment.Remove(FlutterUpdateStartupReporter.NonceVariable);
        using var restored = Process.Start(start) ?? throw new IOException("Restored client did not start.");
        return Task.CompletedTask;
    }
    public void Dispose() { _candidate?.Dispose(); _candidateHost?.Dispose(); }

    private void RequireRecoveryStopped()
    {
        if (_recoveryDirectory is null) return;
        foreach (var name in new[] { "starbridge_flutter", "StarBridge.NativeHost" })
        {
            var processes = Process.GetProcessesByName(name);
            try
            {
                foreach (var process in processes)
                {
                    if (process.HasExited) continue;
                    // Failure to inspect a potentially relevant process fails closed.
                    var path = process.MainModule?.FileName ?? throw new IOException("Cannot inspect update owner.");
                    if (path.StartsWith(Path.TrimEndingDirectorySeparator(_recoveryDirectory) +
                        Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("Stop the installation before recovering its update.");
                }
            }
            finally { foreach (var process in processes) process.Dispose(); }
        }
    }

    private List<Process> CaptureInstallationHosts()
    {
        var result = new List<Process>();
        if (_candidateDirectory is null) return result;
        var expected = Path.Combine(_candidateDirectory, "native_host", "StarBridge.NativeHost.exe");
        try
        {
            foreach (var process in Process.GetProcessesByName("StarBridge.NativeHost"))
            {
                var retain = false;
                try
                {
                    if (!process.HasExited && string.Equals(process.MainModule?.FileName, expected, StringComparison.OrdinalIgnoreCase))
                    {
                        _ = process.SafeHandle; // Pin this process, not a future reuse of its PID.
                        result.Add(process);
                        retain = true;
                    }
                }
                finally { if (!retain) process.Dispose(); }
            }
            return result;
        }
        catch { foreach (var process in result) process.Dispose(); throw; }
    }
}
