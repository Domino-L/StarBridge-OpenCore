using System.Diagnostics;
using System.Security.Cryptography;

namespace StarBridge.HostRuntime.Updates;

internal sealed class InstalledUpdateWindowsOperations : IInstalledUpdateOperations, IDisposable
{
    private readonly InstalledUpdatePlan _plan;
    private readonly string _root, _installer;
    private readonly FlutterInstallerUpdateSource.Manifest _manifest;
    private readonly Process? _client, _host;
    private readonly FlutterUpdateProcessActivation _activation = new();
    private readonly bool _recovery;
    private FileStream? _installerLease;
    private Process? _installProcess;
    private string Executable => Path.Combine(_plan.Installation, "starbridge_flutter.exe");

    internal InstalledUpdateWindowsOperations(InstalledUpdatePlan plan, string root, bool recovery = false)
    {
        _plan = plan; _root = root; _recovery = recovery;
        plan.Validate(root);
        _installer = Path.Combine(root, plan.InstallerName);
        _manifest = InstalledUpdateFiles.Read<FlutterInstallerUpdateSource.Manifest>(Path.Combine(root, "installer-manifest.json"), 65536);
        if (FlutterInstallerUpdateSource.VerifyManifest(_manifest, "windows-x64", FlutterReleaseUpdateSource.ReadTrustedKeys()) <=
            ApplicationUpdateVersion.Parse(plan.CurrentVersion)) throw new InvalidDataException("Not a newer installed update.");
        if (!recovery) {
            _client = InstalledUpdatePlan.Pin(plan.ClientPid, plan.ClientStartTicks, Executable);
            try { _host = InstalledUpdatePlan.Pin(plan.HostPid, plan.HostStartTicks, Path.Combine(plan.Installation, "native_host", "StarBridge.NativeHost.exe")); }
            catch { _client.Dispose(); throw; }
        }
    }

    internal async Task VerifyInstallerAsync(CancellationToken cancellation)
    {
        InstalledUpdateFiles.Plain(_installer);
        _installerLease = new FileStream(_installer, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (_installerLease.Length <= 0 || _installerLease.Length > FlutterUpdateManifestVerifier.MaximumPackageBytes ||
            !CryptographicOperations.FixedTimeEquals(await SHA256.HashDataAsync(_installerLease, cancellation), Convert.FromHexString(_manifest.DownloadSha256)))
            throw new InvalidDataException("Installer changed before handoff.");
        await FlutterInstallerPublisherVerifier.VerifyAsync(_installer, _manifest.Version, cancellation);
    }

    public void ValidateOriginal()
    {
        var record = InstalledUpdateRegistration.Read();
        if (!InstalledUpdateRegistration.Same(record.Directory, _plan.Installation) || record.Version != _plan.CurrentVersion)
            throw new InvalidDataException("Installation changed before update.");
        record.Require(Executable, Path.Combine(_plan.Installation, "native_host", "StarBridge.NativeHost.exe"), _plan.DataRoot);
    }
    public void CaptureRegistration(string path) => InstalledUpdateFiles.Write(path, InstalledUpdateRegistrySnapshot.Capture());
    public void RestoreRegistration(string path)
    {
        var entries = InstalledUpdateFiles.Read<InstalledUpdateRegistrySnapshot.Entry[]>(path);
        string Value(string name) => entries.Single(e => e.Name == name && e.Kind == 1 && e.Data.Length == 1).Data[0];
        var snapshot = new InstalledUpdateRegistration(InstalledUpdateFiles.Normalize(Value("InstallLocation")), Value("DisplayVersion"),
            Value("StarBridgeProduct"), Value("UninstallString"));
        snapshot.RequireShape();
        if (!InstalledUpdateRegistration.Same(snapshot.Directory, _plan.Installation) || snapshot.Version != _plan.CurrentVersion)
            throw new InvalidDataException("Registration snapshot does not belong to the original client.");
        InstalledUpdateRegistrySnapshot.Restore(entries, _plan.Installation);
    }

    public async Task WaitForOwnersAsync(CancellationToken cancellation)
    {
        if (_recovery) { RequireNoInstaller(); RequireStopped(); return; }
        await Task.WhenAll(_client!.WaitForExitAsync(cancellation), _host!.WaitForExitAsync(cancellation));
        RequireStopped();
    }

    public async Task InstallAsync(CancellationToken cancellation)
    {
        if (_recovery || _installerLease is null) throw new InvalidOperationException();
        RequireStopped();
        var start = CreateInstallerStart(_installer, _plan.Installation, _root);
        _installProcess = Process.Start(start) ?? throw new IOException("Installer did not start.");
        InstalledUpdateFiles.Write(Path.Combine(_root, "installer-process.json"), new InstallerProcess(_installProcess.Id,
            _installProcess.StartTime.ToUniversalTime().Ticks, _installer));
        // Do not infer child-process quiescence from killing an Inno loader.
        // Keep the journal/backup if the trusted installer is still active;
        // recovery refuses to touch files until it has exited normally.
        await _installProcess.WaitForExitAsync(cancellation);
        if (_installProcess.ExitCode != 0) throw new IOException("Installer did not complete.");
    }

    internal static ProcessStartInfo CreateInstallerStart(string installer, string installation, string root)
    {
        var start = new ProcessStartInfo(installer) { UseShellExecute = false, WorkingDirectory = root,
            CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
        // https://jrsoftware.org/ishelp/topic_setupcmdline.htm
        // Only our original owners have exited. Do not let Restart Manager close
        // unrelated applications or restart Windows behind the user's consent.
        foreach (var argument in new[] { "/SP-", "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/RESTARTEXITCODE=9",
            "/NOCLOSEAPPLICATIONS", "/NOFORCECLOSEAPPLICATIONS", "/NORESTARTAPPLICATIONS",
            "/DIR=" + installation, "/LOG=" + Path.Combine(root, "installer.log") }) start.ArgumentList.Add(argument);
        return start;
    }

    public async Task<bool> ProbeAsync(string version, string nonce, CancellationToken cancellation)
    {
        var record = InstalledUpdateRegistration.Read();
        if (!InstalledUpdateRegistration.Same(record.Directory, _plan.Installation) ||
            ApplicationUpdateVersion.Parse(record.Version) != ApplicationUpdateVersion.Parse(version)) return false;
        record.Require(Executable, Path.Combine(_plan.Installation, "native_host", "StarBridge.NativeHost.exe"), _plan.DataRoot);
        await FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(Executable, version, cancellation);
        await FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(Path.Combine(_plan.Installation, "native_host", "StarBridge.NativeHost.exe"), version, cancellation);
        var receipt = await _activation.StartAndProbeAsync(Executable, nonce, cancellation);
        return receipt.Nonce == nonce && ApplicationUpdateVersion.ParseInstalled(receipt.Version) == ApplicationUpdateVersion.Parse(version) &&
            receipt.BridgeProtocol == 1 && receipt.FirstFrameRendered && receipt.HostReady;
    }

    public async Task StopCandidateAsync(CancellationToken cancellation)
    {
        // Recovery does not regain kill authority from a recorded PID.
        if (_recovery) { RequireNoInstaller(); RequireStopped(); }
        else { if (_installProcess is { HasExited: false }) throw new IOException("Installer still running.");
            await _activation.QuiesceAsync(cancellation); RequireStopped(); }
    }
    public Task RestartRestoredAsync(CancellationToken cancellation) {
        ValidateOriginal(); RequireStopped(); return _activation.StartRestoredAsync(Executable, cancellation);
    }

    private void RequireStopped()
    {
        foreach (var name in new[] { "starbridge_flutter", "StarBridge.NativeHost" })
        foreach (var process in Process.GetProcessesByName(name))
        using (process) {
            if (process.HasExited) continue;
            if (InstalledUpdateRegistration.Contains(_plan.Installation, process.MainModule?.FileName ?? throw new IOException()))
                throw new IOException("Installed client is still running.");
        }
    }
    private sealed record InstallerProcess(int Pid, long StartTicks, string Path);
    private void RequireNoInstaller()
    {
        var path = Path.Combine(_root, "installer-process.json");
        if (!File.Exists(path)) {
            var state = InstalledUpdateFiles.Read<InstalledUpdateTransaction.State>(Path.Combine(_root, "installed-state.json"), 8192);
            if (state.Phase == "installing") throw new IOException("Installer exit cannot be proved.");
            return;
        }
        var record = InstalledUpdateFiles.Read<InstallerProcess>(path, 16384);
        if (record.Path != _installer || record.Pid <= 0 || record.StartTicks <= 0) throw new InvalidDataException();
        try { using var process = Process.GetProcessById(record.Pid);
            if (!process.HasExited && process.StartTime.ToUniversalTime().Ticks == record.StartTicks) throw new IOException("Installer must exit before recovery."); }
        catch (ArgumentException) { }
    }
    public void Dispose() { _installerLease?.Dispose(); _client?.Dispose(); _host?.Dispose(); _installProcess?.Dispose(); _activation.Dispose(); }
}
