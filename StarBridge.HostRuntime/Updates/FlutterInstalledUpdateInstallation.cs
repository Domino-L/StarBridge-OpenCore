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
    // Three times the ten-minute limit on preparing an update.
    private static readonly TimeSpan AbandonedAfter = TimeSpan.FromMinutes(30);
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
            var statePath = Path.Combine(directory, "installed-state.json");
            var hasPlan = File.Exists(planPath);
            if (hasPlan) {
                InstalledUpdatePlan owner;
                try { owner = InstalledUpdateFiles.Read<InstalledUpdatePlan>(planPath, 16384); }
                catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { continue; } // Another installation's cleanup got there first.
                owner.Validate(directory);
                if (!InstalledUpdateRegistration.Same(owner.Installation, installation)) continue;
            }
            if (!File.Exists(statePath)) { RetireAbandoned(installation, directory); continue; }
            if (!hasPlan) throw new IOException("An incomplete update workspace needs inspection.");
            var plan = InstalledUpdateFiles.Read<InstalledUpdatePlan>(planPath, 16384);
            var state = InstalledUpdateFiles.Read<InstalledUpdateTransaction.State>(statePath, 8192);
            var current = (readRegistration ?? InstalledUpdateRegistration.Read)();
            current.RequireShape();
            if (!InstalledUpdateRegistration.Same(current.Directory, installation) ||
                state.SchemaVersion != 1 || state.Installation != installation)
                throw new IOException("Previous update requires recovery.");
            // A later independently installed version can supersede a committed
            // transaction. Preserve its entire recovery tree outside the active
            // transaction namespace; never treat incomplete/rolled-back work as such.
            if (state.Phase == "committed" &&
                ApplicationUpdateVersion.Parse(state.Version) > ApplicationUpdateVersion.Parse(plan.CurrentVersion) &&
                ApplicationUpdateVersion.Parse(current.Version) > ApplicationUpdateVersion.Parse(state.Version)) {
                using var idleArchive = AcquireGate(installation, "");
                if (current != (readRegistration ?? InstalledUpdateRegistration.Read)())
                    throw new IOException("Installation registration changed.");
                InstalledUpdateFiles.Tree(directory);
                var archive = Path.Combine(Path.GetDirectoryName(installation)!, ".starbridge-retired-update-" + Guid.NewGuid().ToString("N"));
                InstalledUpdateFiles.Plain(archive);
                if (Directory.Exists(archive) || File.Exists(archive)) throw new IOException("Recovery archive already exists.");
                Directory.Move(directory, archive);
                continue;
            }
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

    // The helper journals before it touches the installation, so a workspace with no
    // journal is a download cache a stopped Host left behind. Left in place it would
    // refuse every later update. Its name and age prove nothing about who owns it, so
    // anything an update attempt does not create, a recent workspace or a leased
    // installer keeps it, and blocks nothing. The gate refuses while a helper runs.
    private static void RetireAbandoned(string installation, string directory)
    {
        try {
            if (Directory.Exists(Path.Combine(directory, "previous")) || Directory.Exists(Path.Combine(directory, "failed")))
                throw new IOException("An incomplete update workspace needs inspection.");
            var listed = UpdateCacheFiles(installation, directory);
            if (listed is null || DateTime.UtcNow - Directory.GetCreationTimeUtc(directory) < AbandonedAfter) return;
            using var idle = AcquireGate(installation, "");
            foreach (var file in listed.Where(file => Path.GetFileName(file).StartsWith("installer-", StringComparison.Ordinal) && file.EndsWith(".exe", StringComparison.Ordinal))) {
                try { using var unleased = new FileStream(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None); }
                catch (IOException) { return; }
            }
            RetireListed(directory, listed);
        }
        catch (DirectoryNotFoundException) { } // Another installation's cleanup got there first.
    }

    // Deletes only what was checked. Anything added since stays, and so does its folder.
    internal static void RetireListed(string directory, IReadOnlyList<string> listed)
    {
        try {
            foreach (var file in listed)
                if (File.Exists(file) && (File.GetAttributes(file) & FileAttributes.ReadOnly) != 0) return;
            foreach (var file in listed) { InstalledUpdateFiles.Plain(file); File.Delete(file); }
            var helper = Path.Combine(directory, "helper");
            if (Directory.Exists(helper)) { InstalledUpdateFiles.Plain(helper); Directory.Delete(helper, recursive: false); }
            Directory.Delete(directory, recursive: false);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static readonly string[] AttemptRecords = [InstalledUpdatePlan.FileName, "installer-manifest.json", "registration.json", "installed-state.json"];

    // Exactly what StageAsync, HandoffAsync and the helper's first steps can leave, or
    // null if anything else is there. Helper files must carry this installation's own
    // helper file names. Records go last, so a partial delete is still recognized.
    private static List<string>? UpdateCacheFiles(string installation, string directory)
    {
        static bool Guid32(string value) => Guid.TryParseExact(value, "N", out _);
        var maintenance = Path.Combine(installation, "native_host", "maintenance");
        var helperNames = Directory.Exists(maintenance)
            ? Directory.EnumerateFiles(maintenance).Select(Path.GetFileName).ToHashSet(StringComparer.OrdinalIgnoreCase)
            : [];
        var first = new List<string>();
        var last = new List<string>();
        foreach (var entry in Directory.EnumerateFileSystemEntries(directory)) {
            InstalledUpdateFiles.Plain(entry);
            var name = Path.GetFileName(entry);
            if (Directory.Exists(entry)) {
                if (name != "helper") return null;
                foreach (var item in Directory.GetFileSystemEntries(entry)) {
                    InstalledUpdateFiles.Plain(item);
                    if (!File.Exists(item) || !helperNames.Contains(Path.GetFileName(item))) return null;
                    first.Add(item);
                }
                continue;
            }
            var installer = name.StartsWith("installer-", StringComparison.Ordinal) && name.EndsWith(".exe", StringComparison.Ordinal) &&
                Guid32(name["installer-".Length..^".exe".Length]);
            var temporary = name.EndsWith(".tmp", StringComparison.Ordinal) && name.Length > 37 && name[^37] == '.' &&
                Guid32(name[^36..^4]) && AttemptRecords.Contains(name[..^37]);
            if (installer) first.Add(entry);
            else if (temporary || name == "installed-transaction.lock" || (name != "installed-state.json" && AttemptRecords.Contains(name))) last.Add(entry);
            else return null;
        }
        first.AddRange(last);
        return first;
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
