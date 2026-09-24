using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

internal sealed record FlutterUpdateReady(string Nonce, string Version, int BridgeProtocol,
    bool FirstFrameRendered, bool HostReady);

/// <summary>Implemented by an external helper, never by the process being replaced.
/// Quiesce must prove both the client and its Host have stopped, including a timed-out candidate.</summary>
internal interface IFlutterUpdateActivation
{
    Task QuiesceAsync(CancellationToken cancellation);
    Task<FlutterUpdateReady> StartAndProbeAsync(string executable, string nonce, CancellationToken cancellation);
    Task StartRestoredAsync(string executable, CancellationToken cancellation);
}

/// <summary>Internal transaction engine. Caller supplies a verified, complete candidate in
/// TransactionRoot/candidate and owns the process helper. No Bridge or arbitrary-path install API.</summary>
internal sealed class FlutterUpdateTransaction
{
    private sealed record Journal(int SchemaVersion, string InstallationName, string Version, string Nonce, string Phase);
    private readonly string _installation;
    private readonly string _root;
    private readonly TimeSpan _deadline;
    private string Candidate => Path.Combine(_root, "candidate");
    private string Backup => Path.Combine(_root, "backup");
    private string Failed => Path.Combine(_root, "failed");
    private string StateFile => Path.Combine(_root, "state.json");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };

    internal FlutterUpdateTransaction(string installation, string transactionRoot, TimeSpan? deadline = null)
    {
        _installation = Path.TrimEndingDirectorySeparator(Path.GetFullPath(installation));
        _root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(transactionRoot));
        _deadline = deadline ?? TimeSpan.FromSeconds(45);
        if (!Path.IsPathFullyQualified(installation) || !Path.IsPathFullyQualified(transactionRoot) ||
            _deadline <= TimeSpan.Zero || _deadline > TimeSpan.FromMinutes(2) ||
            !string.Equals(Path.GetDirectoryName(_installation), Path.GetDirectoryName(_root), StringComparison.OrdinalIgnoreCase) ||
            string.Equals(_installation, _root, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(_root).StartsWith(".starbridge-update-", StringComparison.Ordinal))
            throw new InvalidDataException("Update transaction paths are not sibling owned directories.");
        RequirePlainTree(_root);
    }

    internal async Task<string> ApplyAsync(string version, IFlutterUpdateActivation activation,
        CancellationToken cancellation = default, Func<CancellationToken, Task>? prepared = null)
    {
        cancellation.ThrowIfCancellationRequested();
        using var lease = Lock();
        if (File.Exists(StateFile) || Directory.Exists(Backup) || Directory.Exists(Failed))
            throw new InvalidOperationException("Recover the existing transaction first.");
        if (!Version.TryParse(version, out _)) throw new InvalidDataException("Invalid candidate version.");
        RequireApplication(_installation);
        RequireApplication(Candidate);
        var state = new Journal(1, Path.GetFileName(_installation), version,
            Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), "prepared");
        Write(state);
        // A failed handoff must leave the still-running original untouched. Do not
        // enter rollback (which could wait for or restart it) before this succeeds.
        if (prepared is not null) await Bound(prepared, cancellation);
        try
        {
            await Bound(activation.QuiesceAsync, cancellation);
            cancellation.ThrowIfCancellationRequested();
            // Re-check paths after waiting: never follow a substituted junction.
            RequireApplication(_installation);
            RequireApplication(Candidate);
            Write(state with { Phase = "backing-up" });
            Directory.Move(_installation, Backup);
            Write(state with { Phase = "activating" });
            Directory.Move(Candidate, _installation);
            Write(state with { Phase = "awaiting-ready" });
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(_deadline);
            var ready = await activation.StartAndProbeAsync(Executable, state.Nonce, timeout.Token).WaitAsync(timeout.Token);
            if (ready.Nonce != state.Nonce || ready.Version != version || ready.BridgeProtocol != 1 ||
                !ready.FirstFrameRendered || !ready.HostReady)
                throw new InvalidDataException("Candidate startup did not confirm this transaction.");
            cancellation.ThrowIfCancellationRequested();
            Write(state with { Phase = "committed" });
            return "committed"; // Backup retained until a separately authorized cleanup policy.
        }
        catch
        {
            // Once replacement begins, caller cancellation must not abandon recovery.
            await RollBackAsync(state, activation);
            return "rolled-back";
        }
    }

    internal async Task<string> RecoverAsync(IFlutterUpdateActivation activation)
    {
        using var lease = Lock();
        var state = Read();
        if (state.Phase is "committed" or "rolled-back") return state.Phase;
        await RollBackAsync(state, activation);
        return "rolled-back";
    }

    private async Task RollBackAsync(Journal state, IFlutterUpdateActivation activation)
    {
        // If quiescence fails, keep the journal and backup. Never rename a live app,
        // kill an unrelated process, or start a second owner to force a rollback.
        await Bound(activation.QuiesceAsync, CancellationToken.None);
        RequirePlainTree(_root);
        if (Directory.Exists(_installation)) RequirePlainTree(_installation);
        var hadBackup = Directory.Exists(Backup);
        if (!hadBackup && (!Directory.Exists(_installation) ||
            Read().Phase is not ("prepared" or "backing-up" or "rolling-back" or "restoring")))
            throw new InvalidDataException("Transaction recovery cannot identify the old installation.");
        Write(state with { Phase = "rolling-back" });
        if (hadBackup)
        {
            if (Directory.Exists(_installation))
            {
                if (Directory.Exists(Failed)) throw new IOException("Failed candidate slot already exists.");
                Directory.Move(_installation, Failed);
            }
            Directory.Move(Backup, _installation);
        }
        RequireApplication(_installation);
        Write(state with { Phase = "restoring" });
        await Bound(token => activation.StartRestoredAsync(Executable, token), CancellationToken.None);
        Write(state with { Phase = "rolled-back" });
    }

    private string Executable => Path.Combine(_installation, "starbridge_flutter.exe");
    private FileStream Lock()
    {
        RequirePlainTree(_root);
        return new FileStream(Path.Combine(_root, "transaction.lock"), FileMode.OpenOrCreate,
            FileAccess.ReadWrite, FileShare.None);
    }
    private async Task Bound(Func<CancellationToken, Task> action, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(_deadline);
        await action(timeout.Token).WaitAsync(timeout.Token);
    }
    private Journal Read()
    {
        if (!File.Exists(StateFile) || new FileInfo(StateFile).Length > 4096) throw new InvalidDataException("Missing transaction journal.");
        var value = JsonSerializer.Deserialize<Journal>(File.ReadAllText(StateFile), Json);
        if (value is null || value.SchemaVersion != 1 || value.InstallationName != Path.GetFileName(_installation) ||
            !Version.TryParse(value.Version, out _) || value.Nonce is null || value.Nonce.Length != 64 ||
            value.Nonce.Any(character => !Uri.IsHexDigit(character)) ||
            value.Phase is not ("prepared" or "backing-up" or "activating" or "awaiting-ready" or "committed" or "rolling-back" or "restoring" or "rolled-back"))
            throw new InvalidDataException("Invalid transaction journal.");
        return value;
    }
    private void Write(Journal state)
    {
        var temporary = Path.Combine(_root, "journal-" + Guid.NewGuid().ToString("N") + ".tmp");
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, state, Json);
            stream.Flush(flushToDisk: true);
        }
        File.Move(temporary, StateFile, overwrite: true);
    }
    private static void RequireApplication(string directory)
    {
        RequirePlainTree(directory);
        foreach (var file in FlutterUpdateStager.RequiredFiles)
            if (!File.Exists(Path.Combine(directory, file))) throw new InvalidDataException("Incomplete installation.");
    }
    private static void RequirePlainTree(string root)
    {
        if (!Directory.Exists(root)) throw new IOException("Missing transaction directory.");
        for (var parent = new DirectoryInfo(root); parent is not null; parent = parent.Parent)
            if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update path.");
        foreach (var entry in Directory.EnumerateFileSystemEntries(root))
        {
            var attributes = File.GetAttributes(entry);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update entry.");
            if ((attributes & FileAttributes.Directory) != 0) RequirePlainTree(entry);
        }
    }
}
