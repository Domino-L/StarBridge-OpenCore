using System.Security.Cryptography;

namespace StarBridge.HostRuntime.Updates;

internal interface IInstalledUpdateOperations
{
    void ValidateOriginal();
    void CaptureRegistration(string path);
    void RestoreRegistration(string path);
    Task WaitForOwnersAsync(CancellationToken cancellation);
    Task InstallAsync(CancellationToken cancellation);
    Task<bool> ProbeAsync(string version, string nonce, CancellationToken cancellation);
    Task StopCandidateAsync(CancellationToken cancellation);
    Task RestartRestoredAsync(CancellationToken cancellation);
}

/// <summary>Inno-managed upgrade, not a portable ZIP swap. The old directory,
/// uninstaller and registry snapshot remain together until healthy startup.
/// This helper runs outside both old and new installations.</summary>
internal sealed class InstalledUpdateTransaction
{
    internal sealed record State(int SchemaVersion, string Installation, string Version, string Nonce, string Phase);
    private readonly string _installation, _root;
    private readonly TimeSpan _deadline;
    private string StatePath => Path.Combine(_root, "installed-state.json");
    private string Backup => Path.Combine(_root, "previous");
    private string Failed => Path.Combine(_root, "failed");
    private string Registration => Path.Combine(_root, "registration.json");
    internal InstalledUpdateTransaction(string installation, string root, TimeSpan? deadline = null)
    {
        _installation = InstalledUpdateFiles.Normalize(installation);
        _root = InstalledUpdateFiles.Normalize(root);
        InstalledUpdateFiles.RequireSibling(_installation, _root);
        _deadline = deadline ?? TimeSpan.FromMinutes(2);
        if (_deadline <= TimeSpan.Zero || _deadline > TimeSpan.FromMinutes(2)) throw new ArgumentOutOfRangeException(nameof(deadline));
    }

    internal async Task<string> ApplyAsync(string version, IInstalledUpdateOperations operations,
        Func<CancellationToken, Task> prepared, CancellationToken cancellation = default)
    {
        _ = ApplicationUpdateVersion.Parse(version);
        using var gate = Lock();
        if (File.Exists(StatePath) || Directory.Exists(Backup) || Directory.Exists(Failed))
            throw new InvalidOperationException("Existing update requires recovery.");
        operations.ValidateOriginal();
        operations.CaptureRegistration(Registration);
        var state = new State(1, _installation, version, Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), "prepared");
        Write(state);
        await Bound(prepared, cancellation);
        // Failure to stop both original owners never permits moving files,
        // restoring registration, killing them, or starting a duplicate client.
        try { await Bound(operations.WaitForOwnersAsync, cancellation); }
        catch { Write(state with { Phase = "not-started" }); return "not-started"; }
        try { operations.ValidateOriginal(); }
        catch { Write(state with { Phase = "not-started" }); throw; }
        try
        {
            InstalledUpdateFiles.Tree(_installation);
            InstalledUpdateFiles.Tree(_root);
            Write(state with { Phase = "moving-old" });
            Directory.Move(_installation, Backup);
            Write(state with { Phase = "installing" });
            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation)) {
                timeout.CancelAfter(TimeSpan.FromMinutes(10));
                // Cancellation may leave the installer active. StopCandidateAsync
                // must prove it exited before rollback can touch any files.
                await operations.InstallAsync(timeout.Token);
            }
            InstalledUpdateFiles.Tree(_installation);
            Write(state with { Phase = "probing" });
            using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation)) {
                timeout.CancelAfter(_deadline);
                if (!await operations.ProbeAsync(version, state.Nonce, timeout.Token))
                    throw new InvalidDataException("New client did not confirm startup.");
            }
            cancellation.ThrowIfCancellationRequested();
            Write(state with { Phase = "committed" });
            return "committed";
        }
        catch
        {
            await RollbackAsync(state, operations);
            return "rolled-back";
        }
    }

    internal async Task<string> RecoverAsync(IInstalledUpdateOperations operations)
    {
        using var gate = Lock();
        var state = Read();
        if (state.Phase is "committed" or "rolled-back" or "not-started") return state.Phase;
        await Bound(operations.WaitForOwnersAsync, CancellationToken.None);
        await RollbackAsync(state, operations);
        return "rolled-back";
    }

    private async Task RollbackAsync(State state, IInstalledUpdateOperations operations)
    {
        await Bound(operations.StopCandidateAsync, CancellationToken.None);
        InstalledUpdateFiles.Tree(_root);
        if (Directory.Exists(_installation)) InstalledUpdateFiles.Tree(_installation);
        var backupExists = Directory.Exists(Backup);
        var phase = Read().Phase;
        if (!backupExists && phase is not ("prepared" or "moving-old" or "restored"))
            throw new InvalidDataException("Previous installation is not recoverable.");
        if (backupExists)
        {
            // Durable intent permits recovery after a crash between the two moves.
            Write(state with { Phase = "rolling-back" });
            if (Directory.Exists(_installation)) {
                if (Directory.Exists(Failed)) throw new IOException("Failed installation slot occupied.");
                Directory.Move(_installation, Failed);
            }
            // Persist restoration intent BEFORE moving: if backup disappears on
            // a crash, the destination is the original only in this phase.
            Write(state with { Phase = "restored" });
            Directory.Move(Backup, _installation);
        }
        if (!File.Exists(Path.Combine(_installation, "starbridge_flutter.exe"))) throw new InvalidDataException();
        operations.RestoreRegistration(Registration);
        await Bound(operations.RestartRestoredAsync, CancellationToken.None);
        Write(state with { Phase = "rolled-back" });
    }

    private State Read()
    {
        var state = InstalledUpdateFiles.Read<State>(StatePath, 8192);
        if (state.SchemaVersion != 1 || state.Installation != _installation || state.Nonce is null ||
            state.Nonce.Length != 64 || state.Nonce.Any(c => !Uri.IsHexDigit(c)) ||
            state.Phase is not ("prepared" or "not-started" or "moving-old" or "installing" or "probing" or
                "committed" or "rolling-back" or "restored" or "rolled-back")) throw new InvalidDataException();
        _ = ApplicationUpdateVersion.Parse(state.Version);
        return state;
    }

    private FileStream Lock()
    {
        InstalledUpdateFiles.RequireSibling(_installation, _root);
        InstalledUpdateFiles.Tree(_root);
        return new FileStream(Path.Combine(_root, "installed-transaction.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private void Write(State state) => InstalledUpdateFiles.Write(StatePath, state, replace: true);
    private async Task Bound(Func<CancellationToken, Task> operation, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(_deadline);
        await operation(timeout.Token);
    }
}
