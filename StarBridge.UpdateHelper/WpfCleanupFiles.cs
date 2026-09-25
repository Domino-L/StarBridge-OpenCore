using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

internal sealed record WpfCleanupFile(string Path, long Length, string Sha256);
internal sealed record WpfCleanupCatalog(string Version, string PackageSha256, WpfCleanupFile[] Files)
{
    internal static WpfCleanupCatalog Released0661()
    {
        using var stream = typeof(WpfCleanupCatalog).Assembly.GetManifestResourceStream(
            "StarBridge.WpfCleanup.0.6.6.1.json") ?? throw new InvalidDataException("Missing release inventory.");
        var catalog = JsonSerializer.Deserialize<WpfCleanupCatalog>(stream, WpfCleanupFiles.Json)
            ?? throw new InvalidDataException();
        if (catalog.Version != "0.6.6.1" || catalog.PackageSha256 !=
            "d5cd3aa24f0aedd2a20758ae0137bb4029c5f70617a9ce457b07b426aa0c8ef0") throw new InvalidDataException();
        return catalog;
    }
}
internal sealed record WpfCleanupPlan(string Installation, string[] ProtectedRoots, WpfCleanupFile[] Files);
internal sealed record WpfCleanupFileResult(string State, int QuarantinedFiles);

// The file-only removal module. The coordinator must separately establish the
// registered old installation, stopped old processes and healthy new client.
// Never executes an uninstaller or recursively deletes an installation. Only
// release-matching files move to a recoverable, non-shell directory. Unknown
// files (including WebView/account state) remain untouched at their old paths.
internal static class WpfCleanupFiles
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    internal static WpfCleanupPlan Prepare(WpfCleanupCatalog catalog, string installation,
        string newInstallation, params string[] dataRoots)
    {
        RequireRoot(installation);
        if (Exists(System.IO.Path.Combine(installation, ".git")) ||
            Exists(System.IO.Path.Combine(installation, "StarBridge.sln"))) throw new InvalidDataException("Source checkout is not an installed client.");
        if (dataRoots.Length == 0) throw new InvalidDataException("Data roots must be established.");
        var protectedRoots = new[] { newInstallation }.Concat(dataRoots).ToArray();
        foreach (var root in protectedRoots) {
            RequireRoot(root);
            if (Overlaps(installation, root)) throw new InvalidDataException("Installation overlaps protected data.");
        }
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var files = new List<WpfCleanupFile>();
        foreach (var file in catalog.Files) {
            Validate(file);
            if (!seen.Add(file.Path.Replace('/', '\\'))) throw new InvalidDataException("Duplicate release entry.");
            var path = Resolve(installation, file.Path);
            if (!Exists(path)) continue;
            Verify(path, file); // Any modified known file blocks the whole plan before mutation.
            files.Add(file);
        }
        if (!files.Any(f => f.Path == "Star Bridge.exe")) throw new InvalidDataException("Recognized old executable required.");
        // Retire the launch entry first, then immediately let the coordinator
        // recheck old processes before moving the remaining payload.
        return new(installation, protectedRoots, files.OrderBy(f => f.Path == "Star Bridge.exe" ? 0 : 1).ToArray());
    }

    internal static WpfCleanupFileResult Quarantine(WpfCleanupPlan plan, string backup,
        Action<int>? beforeMove = null)
    {
        RequirePlan(plan, backup);
        if (Directory.EnumerateFileSystemEntries(backup).Any()) throw new InvalidDataException("Fresh recovery directory required.");
        // A durable complete plan exists before any move. It is local evidence,
        // not authority: recovery must revalidate it against the release catalog.
        using (var record = new FileStream(System.IO.Path.Combine(backup, "files.json"), FileMode.CreateNew,
            FileAccess.Write, FileShare.None)) {
            JsonSerializer.Serialize(record, plan, Json); record.Flush(true);
        }
        var moved = 0;
        try {
            foreach (var file in plan.Files) {
                beforeMove?.Invoke(moved); // Coordinator safety check or deterministic test fault.
                RequirePlan(plan, backup);
                var source = Resolve(plan.Installation, file.Path);
                var target = Resolve(backup, "program/" + file.Path);
                using var lease = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
                Verify(source, file);
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(target)!);
                if (!WpfShortcutHandoff.PlainPath(System.IO.Path.GetDirectoryName(target)!)) throw new InvalidDataException();
                File.Move(source, target, overwrite: false);
                Verify(target, file);
                moved++;
            }
            return new("quarantined", moved); // NOT proof that installation registration has been retired.
        }
        catch {
            return new(Restore(plan, backup) ? "restored" : "needs-review", moved);
        }
    }

    internal static bool Restore(WpfCleanupPlan plan, string backup)
    {
        var complete = true;
        foreach (var file in plan.Files.Reverse()) {
            try {
                RequirePlan(plan, backup);
                var source = Resolve(plan.Installation, file.Path);
                var saved = Resolve(backup, "program/" + file.Path);
                if (Exists(source)) {
                    Verify(source, file);
                    if (Exists(saved)) complete = false; // Preserve both; never erase a concurrent replacement.
                    continue;
                }
                Verify(saved, file);
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(source)!);
                if (!WpfShortcutHandoff.PlainPath(System.IO.Path.GetDirectoryName(source)!)) throw new InvalidDataException();
                File.Move(saved, source, overwrite: false);
                Verify(source, file);
            }
            catch { complete = false; }
        }
        return complete;
    }

    internal static WpfCleanupPlan ReadRecovery(WpfCleanupCatalog catalog, string installation,
        string newInstallation, string[] dataRoots, string backup)
    {
        RequireRoot(backup);
        var record = System.IO.Path.Combine(backup, "files.json");
        if (!WpfShortcutHandoff.PlainPath(record) || new FileInfo(record).Length > 4 * 1024 * 1024) throw new InvalidDataException();
        var plan = JsonSerializer.Deserialize<WpfCleanupPlan>(File.ReadAllBytes(record), Json) ?? throw new InvalidDataException();
        var roots = new[] { newInstallation }.Concat(dataRoots).ToArray();
        if (!string.Equals(plan.Installation, installation, StringComparison.OrdinalIgnoreCase) ||
            !plan.ProtectedRoots.SequenceEqual(roots, StringComparer.OrdinalIgnoreCase)) throw new InvalidDataException("Recovery identity changed.");
        RequirePlan(plan, backup);
        var trusted = catalog.Files.ToDictionary(f => f.Path, StringComparer.OrdinalIgnoreCase);
        if (plan.Files.Length == 0 || !plan.Files.Any(f => f.Path == "Star Bridge.exe") ||
            plan.Files.Select(f => f.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count() != plan.Files.Length ||
            plan.Files.Any(f => !trusted.TryGetValue(f.Path, out var expected) || f != expected))
            throw new InvalidDataException("Recovery entries are not approved release files.");
        return plan;
    }

    private static void RequirePlan(WpfCleanupPlan plan, string backup)
    {
        RequireRoot(plan.Installation); RequireRoot(backup);
        if (Overlaps(plan.Installation, backup)) throw new InvalidDataException();
        foreach (var root in plan.ProtectedRoots) {
            RequireRoot(root);
            if (Overlaps(root, plan.Installation) || Overlaps(root, backup)) throw new InvalidDataException();
        }
    }
    private static void Validate(WpfCleanupFile file)
    {
        var parts = file.Path.Replace('\\', '/').Split('/');
        if (parts.Length == 0 || parts.Any(p => string.IsNullOrWhiteSpace(p) || p is "." or ".." ||
            p.TrimEnd(' ', '.') != p || p.IndexOfAny(System.IO.Path.GetInvalidFileNameChars()) >= 0) ||
            file.Length < 0 || file.Sha256.Length != 64 || !file.Sha256.All(Uri.IsHexDigit)) throw new InvalidDataException("Invalid release entry.");
    }
    private static string Resolve(string root, string relative)
    {
        Validate(new(relative, 0, new string('0', 64)));
        var path = System.IO.Path.GetFullPath(System.IO.Path.Combine(root, relative.Replace('/', '\\')));
        if (!path.StartsWith(root + System.IO.Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException();
        // Check existing ancestors even when the leaf is absent: never traverse a junction.
        for (var part = path; part is not null; part = System.IO.Path.GetDirectoryName(part))
            if (Exists(part) && (File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
        return path;
    }
    private static void RequireRoot(string root)
    {
        if (!Directory.Exists(root) || !WpfShortcutHandoff.PlainPath(root) ||
            System.IO.Path.GetPathRoot(root) == root || System.IO.Path.TrimEndingDirectorySeparator(root) != root)
            throw new InvalidDataException("Unsafe root.");
    }
    private static bool Overlaps(string a, string b) =>
        string.Equals(a, b, StringComparison.OrdinalIgnoreCase) ||
        a.StartsWith(b + '\\', StringComparison.OrdinalIgnoreCase) || b.StartsWith(a + '\\', StringComparison.OrdinalIgnoreCase);
    private static bool Exists(string path)
    {
        try { _ = File.GetAttributes(path); return true; }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
    private static void Verify(string path, WpfCleanupFile file)
    {
        if (!WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (stream.Length != file.Length || !Convert.ToHexString(SHA256.HashData(stream)).Equals(file.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Installed file differs from reviewed release.");
    }
}
