using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Installed-product composition only. The downloaded EXE and helper are
/// leased/verified independently on both sides of the guarded exit handshake.</summary>
public sealed class FlutterInstalledUpdateInstallation : IDisposable
{
    private readonly FlutterInstallerUpdateSource _source;
    private readonly InstalledUpdateRegistration _registration;
    private readonly Process _client;
    private readonly string _dataRoot;
    private VerifiedInstallerDownload? _download;
    private string? _root;
    private Process? _helper;
    private bool _handedOff, _disposed;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly SemaphoreSlim _work = new(1, 1);
    public FlutterUpdateInstallation Installation { get; }

    private FlutterInstalledUpdateInstallation(FlutterInstallerUpdateSource source, InstalledUpdateRegistration registration,
        Process client, string dataRoot)
    {
        _source = source; _registration = registration; _client = client; _dataRoot = dataRoot;
        Installation = new FlutterUpdateInstallation(StageAsync, HandoffAsync);
    }

    public static FlutterInstalledUpdateInstallation? TryCreate(IApplicationUpdateSource source, Process client, string dataRoot)
    {
        if (!OperatingSystem.IsWindows() || source is not FlutterInstallerUpdateSource installer) return null;
        try {
            var record = InstalledUpdateRegistration.Read(); record.RequireShape();
            var root = record.Directory;
            if (!InstalledUpdateRegistration.Same(client.MainModule?.FileName, Path.Combine(root, "starbridge_flutter.exe")) ||
                !InstalledUpdateRegistration.Same(Environment.ProcessPath, Path.Combine(root, "native_host", "StarBridge.NativeHost.exe"))) return null;
            return new(installer, record, client, InstalledUpdateFiles.Normalize(dataRoot));
        } catch { return null; }
    }

    private void RequireOriginal()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_registration != InstalledUpdateRegistration.Read()) throw new InvalidDataException("Installation registration changed.");
        _client.Refresh();
        if (_client.HasExited) throw new IOException("Original client exited.");
        _registration.Require(_client.MainModule?.FileName ?? "", Environment.ProcessPath ?? "", _dataRoot);
    }

    private async Task<string> StageAsync(string version, Action<FlutterUpdateProgress>? progress, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token);
        var token = timeout.Token;
        if (!await _work.WaitAsync(0, token)) throw new InvalidOperationException("Update already active.");
        try {
            RequireOriginal();
            if (_handedOff) throw new InvalidOperationException("Update handoff already accepted.");
            ReleaseUnhandedAttempt();
            using var gate = AcquirePreparationGate(_registration.Directory);
            PruneCompleted(_registration.Directory);
            var root = Path.Combine(Path.GetDirectoryName(_registration.Directory)!, InstalledUpdateFiles.Prefix + Guid.NewGuid().ToString("N"));
            InstalledUpdateFiles.RequireSibling(_registration.Directory, root);
            if (Directory.Exists(root)) throw new IOException();
            Directory.CreateDirectory(root); _root = root;
            _download = await _source.DownloadAsync(root, version, progress, token);
            token.ThrowIfCancellationRequested();
            RequireOriginal();
            return _download.Path;
        }
        catch { ReleaseUnhandedAttempt(); throw; }
        finally { _work.Release(); }
    }

    private async Task HandoffAsync(string artifact, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token);
        timeout.CancelAfter(TimeSpan.FromMinutes(2));
        var token = timeout.Token;
        if (!await _work.WaitAsync(0, token)) throw new InvalidOperationException("Update already active.");
        try {
            RequireOriginal();
            if (_handedOff || _root is null || _download is null || artifact != _download.Path) throw new InvalidOperationException("Prepared installer is no longer available.");
            using var gate = AcquirePreparationGate(_registration.Directory);
            var maintenance = Path.Combine(_registration.Directory, "native_host", "maintenance");
            var helperSource = Path.Combine(maintenance, "StarBridge.UpdateHelper.exe");
            await FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(helperSource, _registration.Version, token);
            InstalledUpdateFiles.Tree(maintenance);
            var helperRoot = Path.Combine(_root, "helper");
            Directory.CreateDirectory(helperRoot);
            // Copy the complete helper runtime out of the directory Inno replaces.
            // The current package owns these dependencies; no remote helper URL.
            foreach (var source in Directory.EnumerateFiles(maintenance, "*", SearchOption.AllDirectories)) {
                token.ThrowIfCancellationRequested();
                InstalledUpdateFiles.Plain(source);
                var target = Path.Combine(helperRoot, Path.GetRelativePath(maintenance, source));
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read);
                using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                await input.CopyToAsync(output, token); output.Flush(true);
            }
            var helper = Path.Combine(helperRoot, "StarBridge.UpdateHelper.exe");
            await FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(helper, _registration.Version, token);
            using var helperLease = new FileStream(helper, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var host = Process.GetCurrentProcess();
            var plan = new InstalledUpdatePlan(1, _registration.Directory, _registration.Version, _dataRoot,
                _client.Id, _client.StartTime.ToUniversalTime().Ticks, host.Id, host.StartTime.ToUniversalTime().Ticks, Path.GetFileName(artifact));
            plan.Validate(_root);
            InstalledUpdateFiles.Write(Path.Combine(_root, "installer-manifest.json"), _download.Manifest);
            InstalledUpdateFiles.Write(Path.Combine(_root, InstalledUpdatePlan.FileName), plan);
            _helper = await FlutterUpdateHandoff.StartInstalledAsync(helper, Path.Combine(_root, InstalledUpdatePlan.FileName), token);
            _handedOff = true;
            // The helper's independent validated read lease now owns the artifact.
            _download.Dispose(); _download = null;
        }
        catch {
            // Never remove a journal which may be needed to explain an uncertain
            // handoff. A new attempt cannot silently replace it.
            if (_root is not null && !File.Exists(Path.Combine(_root, "installed-state.json"))) ReleaseUnhandedAttempt();
            throw;
        }
        finally { _work.Release(); }
    }

    private void ReleaseUnhandedAttempt()
    {
        if (_handedOff) return;
        _download?.Dispose(); _download = null;
        if (_root is null) return;
        if (File.Exists(Path.Combine(_root, "installed-state.json"))) { _root = null; return; }
        DeleteOwnedWorkspace(_registration.Directory, _root);
        _root = null;
    }

    // At most one pending workspace per installed product. Completed upgrades,
    // completed rollbacks and untouched failed handoffs retire on the NEXT update.
    internal static void PruneCompleted(string installation, Func<InstalledUpdateRegistration>? readRegistration = null)
    {
        foreach (var directory in Directory.EnumerateDirectories(Path.GetDirectoryName(installation)!, InstalledUpdateFiles.Prefix + "*")) {
            InstalledUpdateFiles.RequireSibling(installation, directory);
            var planPath = Path.Combine(directory, InstalledUpdatePlan.FileName);
            if (!File.Exists(planPath)) throw new IOException("An incomplete update workspace needs inspection.");
            var plan = InstalledUpdateFiles.Read<InstalledUpdatePlan>(planPath, 16384); plan.Validate(directory);
            if (!InstalledUpdateRegistration.Same(plan.Installation, installation)) continue;
            var state = InstalledUpdateFiles.Read<InstalledUpdateTransaction.State>(Path.Combine(directory, "installed-state.json"), 8192);
            var current = (readRegistration ?? InstalledUpdateRegistration.Read)();
            var final = state.Phase == "committed" && ApplicationUpdateVersion.Parse(state.Version) == ApplicationUpdateVersion.Parse(current.Version) ||
                state.Phase == "rolled-back" && current.Version == plan.CurrentVersion;
            var untouched = state.Phase is "prepared" or "not-started" && current.Version == plan.CurrentVersion &&
                !Directory.Exists(Path.Combine(directory, "previous")) && !Directory.Exists(Path.Combine(directory, "failed"));
            if (state.SchemaVersion != 1 || state.Installation != installation || !final && !untouched)
                throw new IOException("Previous update requires recovery.");
            // A live external helper retains this same named installation gate.
            using var idle = AcquireGate(installation, "");
            DeleteOwnedWorkspace(installation, directory);
        }
    }

    internal static void DeleteOwnedWorkspace(string installation, string root)
    {
        InstalledUpdateFiles.RequireSibling(installation, root);
        if (!Directory.Exists(root)) return;
        InstalledUpdateFiles.Tree(root);
        // Targets are checked before any deletion, and again at each step.
        var controls = new[] { Path.Combine(root, InstalledUpdatePlan.FileName), Path.Combine(root, "installed-state.json") };
        var files = Directory.GetFiles(root, "*", SearchOption.AllDirectories)
            .OrderBy(path => controls.Contains(path, StringComparer.OrdinalIgnoreCase) ? 1 : 0).ToArray();
        foreach (var file in files)
            if ((File.GetAttributes(file) & FileAttributes.ReadOnly) != 0) throw new IOException("Update cache contains a read-only file.");
        var directories = Directory.GetDirectories(root, "*", SearchOption.AllDirectories).OrderByDescending(p => p.Length).ToArray();
        foreach (var file in files) { InstalledUpdateFiles.Plain(file); File.Delete(file); }
        foreach (var directory in directories) { InstalledUpdateFiles.Plain(directory); Directory.Delete(directory, recursive: false); }
        Directory.Delete(root, recursive: false);
    }

    private static IDisposable AcquirePreparationGate(string installation) => AcquireGate(installation, "Prepare.");
    private static IDisposable AcquireGate(string installation, string suffix)
    {
        var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(installation.ToUpperInvariant())));
        var semaphore = new Semaphore(1, 1, "Local\\StarBridge.InstalledUpdate." + suffix + id);
        if (!semaphore.WaitOne(0)) { semaphore.Dispose(); throw new IOException("An installed update is already active."); }
        return new Gate(semaphore);
    }
    private sealed class Gate(Semaphore semaphore) : IDisposable { public void Dispose() { semaphore.Release(); semaphore.Dispose(); } }

    public void Dispose()
    {
        _disposed = true; _lifetime.Cancel();
        if (_work.Wait(0)) {
            try { if (!_handedOff && (_root is null || !File.Exists(Path.Combine(_root, "installed-state.json")))) ReleaseUnhandedAttempt(); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
            finally { _work.Release(); }
        }
        _helper?.Dispose();
    }
}
