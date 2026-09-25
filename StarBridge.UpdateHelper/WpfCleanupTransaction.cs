using System.Security.Cryptography;
using System.Text.Json;

internal sealed record WpfCleanupRegistrationValue(string Name, int Kind, string[] Data);
internal sealed record WpfCleanupRegistrationRecord(string Directory, WpfCleanupRegistrationValue[] Values);
internal interface IWpfCleanupRegistration
{
    WpfCleanupRegistrationRecord? Read();
    void RemoveIfUnchanged(WpfCleanupRegistrationRecord expected);
    bool RestoreIfAbsent(WpfCleanupRegistrationRecord expected);
}
internal sealed record WpfCleanupJournal(int Schema, string Installation, string NewInstallation,
    string[] DataRoots, WpfCleanupRegistrationRecord Registration, WpfCleanupFile[] InstallerFiles, string Phase);

// One transaction seam for both production and inert fixtures. The caller owns
// the cross-process lease and establishes a healthy registered new installation.
// No historical uninstaller is executed, no recursive delete is ever performed.
internal sealed class WpfCleanupTransaction(IWpfCleanupRegistration registration,
    Action requireSafeEnvironment, Func<bool> healthy, Func<bool> handoffShell)
{
    internal string Run(WpfCleanupCatalog catalog, string installation, string newInstallation,
        string[] dataRoots, string recovery, Action<string>? checkpoint = null)
    {
        RequireDirectory(recovery);
        foreach (var protectedRoot in new[] { installation, newInstallation }.Concat(dataRoots))
            if (Overlaps(recovery, protectedRoot)) throw new InvalidDataException("Recovery overlaps installation or data.");
        var journalPath = Path.Combine(recovery, "cleanup.json");
        var filesDirectory = Path.Combine(recovery, "files");
        if (File.Exists(journalPath))
            return Recover(catalog, installation, newInstallation, dataRoots, recovery);
        if (Directory.EnumerateFileSystemEntries(recovery).Any()) throw new InvalidDataException("Unowned recovery directory.");
        RequireHealthy();
        var original = registration.Read() ?? throw new InvalidDataException("Old registration missing.");
        if (!Same(original.Directory, installation)) throw new InvalidDataException("Old registration changed.");
        var installerFiles = CaptureInstallerFiles(installation);
        var policy = WithInstallerFiles(catalog, installerFiles);
        var plan = WpfCleanupFiles.Prepare(policy, installation, newInstallation, dataRoots);
        // Shortcut repair is safe even if file retirement is deferred. We never
        // revert a working new shortcut or a user's newer startup preference.
        if (!handoffShell()) return "shell-review-required";
        RequireHealthy();
        RequireSameRegistration(original);
        var journal = new WpfCleanupJournal(1, installation, newInstallation, dataRoots,
            original, installerFiles, "prepared");
        Write(journalPath, journal);
        Directory.CreateDirectory(filesDirectory);
        RequireDirectory(filesDirectory);
        try {
            Write(journalPath, journal with { Phase = "moving" });
            checkpoint?.Invoke("before-files");
            var moved = WpfCleanupFiles.Quarantine(plan, filesDirectory, moved => {
                if (moved <= 1) requireSafeEnvironment();
            });
            if (moved.State != "quarantined") {
                Write(journalPath, journal with { Phase = moved.State });
                return moved.State;
            }
            Write(journalPath, journal with { Phase = "files-quarantined" });
            checkpoint?.Invoke("after-files");
            RequireHealthy();
            RequireSameRegistration(original);
            registration.RemoveIfUnchanged(original);
            checkpoint?.Invoke("after-registration");
            if (registration.Read() is not null || plan.Files.Any(f => File.Exists(Path.Combine(installation, f.Path))))
                throw new IOException("Retirement was not confirmed.");
            RequireHealthy();
            Write(journalPath, journal with { Phase = "committed" });
            return "committed";
        }
        catch {
            // Also handles a registry operation that succeeded before throwing.
            // Uncertain operations are reconciled, never replayed blindly.
            return Restore(journalPath, journal, plan, filesDirectory);
        }
    }

    internal string Recover(WpfCleanupCatalog catalog, string installation, string newInstallation,
        string[] dataRoots, string recovery)
    {
        RequireDirectory(recovery);
        var path = Path.Combine(recovery, "cleanup.json");
        if (!WpfShortcutHandoff.PlainPath(path) || new FileInfo(path).Length > 256 * 1024) throw new InvalidDataException();
        var journal = JsonSerializer.Deserialize<WpfCleanupJournal>(File.ReadAllBytes(path), WpfCleanupFiles.Json)
            ?? throw new InvalidDataException();
        if (journal.Schema != 1 || !Same(journal.Installation, installation) ||
            !Same(journal.NewInstallation, newInstallation) || !Same(journal.Registration.Directory, installation) ||
            !journal.DataRoots.SequenceEqual(dataRoots, StringComparer.OrdinalIgnoreCase) ||
            journal.Phase is not ("prepared" or "moving" or "files-quarantined" or "committed" or "restored" or "needs-review"))
            throw new InvalidDataException("Recovery ownership changed.");
        var policy = WithInstallerFiles(catalog, journal.InstallerFiles);
        requireSafeEnvironment();
        // A later installation/repair may have recreated the key. Do not hide it.
        var current = registration.Read();
        if (current is not null && !Equivalent(current, journal.Registration)) return "needs-review";
        var files = Path.Combine(recovery, "files");
        if (!File.Exists(Path.Combine(files, "files.json"))) {
            // Before the durable file plan, no file operation was authorized.
            if (journal.Phase is not ("prepared" or "moving" or "restored") || current is null) return "needs-review";
            _ = WpfCleanupFiles.Prepare(policy, installation, newInstallation, dataRoots);
            Write(path, journal with { Phase = "restored" });
            return "restored";
        }
        var plan = WpfCleanupFiles.ReadRecovery(policy, installation, newInstallation, dataRoots, files);
        if (journal.Phase == "committed")
            return current is null && plan.Files.All(f => !File.Exists(Path.Combine(installation, f.Path)))
                ? "committed" : "needs-review";
        if (journal.Phase == "restored") return "restored"; // No automatic replay after an interrupted attempt.
        return Restore(path, journal, plan, files);
    }

    private string Restore(string path, WpfCleanupJournal journal, WpfCleanupPlan plan, string files)
    {
        var restored = false;
        try {
            requireSafeEnvironment();
            restored = WpfCleanupFiles.Restore(plan, files);
            if (restored) restored = registration.RestoreIfAbsent(journal.Registration);
        } catch { restored = false; }
        var state = restored ? "restored" : "needs-review";
        Write(path, journal with { Phase = state });
        return state;
    }

    private void RequireSameRegistration(WpfCleanupRegistrationRecord expected)
    {
        var current = registration.Read();
        if (current is null || !Equivalent(current, expected)) throw new IOException("Old registration changed.");
    }
    private void RequireHealthy()
    {
        requireSafeEnvironment();
        if (!healthy()) throw new IOException("New client is not healthy.");
    }
    private static bool Overlaps(string a, string b) => Same(a, b) ||
        a.StartsWith(b + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
        b.StartsWith(a + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    internal static bool Equivalent(WpfCleanupRegistrationRecord a, WpfCleanupRegistrationRecord b) =>
        JsonSerializer.Serialize(a, WpfCleanupFiles.Json) == JsonSerializer.Serialize(b, WpfCleanupFiles.Json);
    private static bool Same(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    private static WpfCleanupFile[] CaptureInstallerFiles(string installation) =>
        new[] { "unins000.exe", "unins000.dat" }.Select(name => {
            var path = Path.Combine(installation, name);
            if (!WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException();
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is <= 0 or > 67108864) throw new InvalidDataException();
            return new WpfCleanupFile(name, file.Length, Convert.ToHexString(SHA256.HashData(file)));
        }).ToArray();
    private static WpfCleanupCatalog WithInstallerFiles(WpfCleanupCatalog catalog, WpfCleanupFile[] files)
    {
        // These two installation-owned files are captured, never executed. They
        // are not release-policy authority for removing any other file.
        if (files.Length != 2 || files[0].Path != "unins000.exe" || files[1].Path != "unins000.dat" ||
            files.Any(f => f.Length is <= 0 or > 67108864 || f.Sha256.Length != 64 || !f.Sha256.All(Uri.IsHexDigit)) ||
            catalog.Files.Any(f => f.Path.Equals("unins000.exe", StringComparison.OrdinalIgnoreCase) ||
                f.Path.Equals("unins000.dat", StringComparison.OrdinalIgnoreCase))) throw new InvalidDataException();
        return catalog with { Files = [.. catalog.Files, .. files] };
    }
    private static void RequireDirectory(string directory)
    {
        if (!Directory.Exists(directory) || !WpfShortcutHandoff.PlainPath(directory)) throw new InvalidDataException();
    }
    private static void Write(string path, WpfCleanupJournal journal)
    {
        RequireDirectory(Path.GetDirectoryName(path)!);
        if (Path.Exists(path) && !WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException();
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
            JsonSerializer.Serialize(file, journal, WpfCleanupFiles.Json); file.Flush(true);
        }
        File.Move(temporary, path, overwrite: true);
    }
}
