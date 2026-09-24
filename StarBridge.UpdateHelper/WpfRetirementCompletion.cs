using System.Security.Cryptography;

// Read-only postcondition evidence, NOT authority to execute an uninstaller.
// The coordinator must separately establish trusted installation identity,
// successful new-client startup and termination of the entire uninstall operation.
internal sealed class WpfRetirementCompletion
{
    private readonly string _oldDirectory, _dataRoot;
    private readonly Dictionary<string, string> _protected;
    private readonly Func<IReadOnlyList<LegacyRegistration>> _registrations;

    internal WpfRetirementCompletion(string oldDirectory, string newExecutable,
        string dataRoot, string locator, Func<IReadOnlyList<LegacyRegistration>>? registrations = null)
    {
        _oldDirectory = oldDirectory;
        _dataRoot = dataRoot;
        _registrations = registrations ?? WpfShortcutHandoff.ReadRegistrations;
        var newRoot = Path.GetDirectoryName(newExecutable) ?? throw new InvalidDataException();
        foreach (var directory in new[] { oldDirectory, newRoot, dataRoot })
            if (!Directory.Exists(directory) || !WpfShortcutHandoff.PlainPath(directory)) throw new InvalidDataException();
        if (Path.GetFileName(newExecutable) != "starbridge_flutter.exe" ||
            Overlaps(oldDirectory, newRoot) || Overlaps(oldDirectory, dataRoot) || Overlaps(newRoot, dataRoot) ||
            Within(oldDirectory, locator) || Within(newRoot, locator)) throw new InvalidDataException("Overlapping installation or data paths.");
        _protected = new(StringComparer.OrdinalIgnoreCase);
        foreach (var path in new[] { newExecutable, Path.Combine(newRoot, "native_host", "StarBridge.NativeHost.exe"), locator })
            _protected.Add(path, Hash(path));
    }

    internal bool Verify()
    {
        try
        {
            // Missing registration alone is insufficient; queries must actually succeed.
            if (_registrations().Count != 0 || !Directory.Exists(_dataRoot) ||
                !WpfShortcutHandoff.PlainPath(_dataRoot)) return false;
            foreach (var name in new[] { "Star Bridge.exe", "unins000.exe", "unins000.dat" })
                if (!DefinitelyAbsent(Path.Combine(_oldDirectory, name))) return false;
            return _protected.All(pair => Hash(pair.Key) == pair.Value);
        }
        catch { return false; } // Access errors and unknown states are never absence.
    }

    private static string Hash(string path)
    {
        if (!WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException();
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexString(SHA256.HashData(file));
    }
    private static bool DefinitelyAbsent(string path)
    {
        // Walk extant ancestors too: a replaced junction is not proof of removal.
        for (var parent = Directory.GetParent(path); parent is not null; parent = parent.Parent)
        {
            try { if ((File.GetAttributes(parent.FullName) & FileAttributes.ReparsePoint) != 0) return false; }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
        try { _ = File.GetAttributes(path); return false; }
        catch (FileNotFoundException) { return true; }
        catch (DirectoryNotFoundException) { return true; }
    }
    private static bool Within(string parent, string child) =>
        string.Equals(parent, child, StringComparison.OrdinalIgnoreCase) ||
        child.StartsWith(Path.TrimEndingDirectorySeparator(parent) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static bool Overlaps(string a, string b) => Within(a, b) || Within(b, a);
}
