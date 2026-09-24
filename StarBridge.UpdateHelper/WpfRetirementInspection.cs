using System.Security.Cryptography;
using System.Text;

internal sealed record RetirementFingerprint(string Main, string Uninstaller, string Log);
internal sealed record RetirementInspection(string State, string? Binding = null);

// Read-only preparation, not execution authority. Approved fingerprints must come
// from an audited release policy, never from the files being inspected or the UI.
internal static class WpfRetirementInspection
{
    internal static RetirementInspection Inspect(
        Func<IReadOnlyList<LegacyRegistration>> registrations,
        IReadOnlyCollection<RetirementFingerprint> approved,
        Func<string, bool> oldProcessesStopped)
    {
        try
        {
            var records = registrations();
            if (records.Count == 0) return new("absent");
            if (records.Count != 1) return new("ambiguous");
            var record = records[0];
            if (record.Scope != "current-user") return new("other-scope");
            if (!Directory.Exists(record.Directory) || !WpfShortcutHandoff.PlainPath(record.Directory) ||
                Path.GetPathRoot(record.Directory) == record.Directory) return new("unsafe-path");
            var uninstaller = Path.Combine(record.Directory, "unins000.exe");
            if (!string.Equals(record.Uninstall, '"' + uninstaller + '"', StringComparison.OrdinalIgnoreCase))
                return new("unexpected-command");
            var fingerprint = new RetirementFingerprint(Hash(Path.Combine(record.Directory, "Star Bridge.exe")),
                Hash(uninstaller), Hash(Path.Combine(record.Directory, "unins000.dat")));
            // The data file drives what Inno removes: hashing the EXE alone is insufficient.
            if (!approved.Any(x => Same(x.Main, fingerprint.Main) && Same(x.Uninstaller, fingerprint.Uninstaller) && Same(x.Log, fingerprint.Log)))
                return new("unsupported-uninstaller");
            if (!oldProcessesStopped(record.Directory)) return new("old-process-running-or-unknown");
            var evidence = string.Join('\n', record.Scope, record.Directory.ToUpperInvariant(), record.Uninstall.ToUpperInvariant(),
                fingerprint.Main, fingerprint.Uninstaller, fingerprint.Log);
            return new("reviewed-snapshot", Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(evidence))));
        }
        catch { return new("inspection-unavailable"); }
    }

    internal static bool Recheck(RetirementInspection previous, Func<RetirementInspection> inspect)
    {
        if (previous.State != "reviewed-snapshot" || previous.Binding is null) return false;
        try { var current = inspect(); return current.State == previous.State && current.Binding == previous.Binding; }
        catch { return false; }
    }

    private static string Hash(string path)
    {
        if (!File.Exists(path) || !WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
    private static bool Same(string? a, string b) => a is { Length: 64 } &&
        a.All(Uri.IsHexDigit) && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
}
