using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

internal sealed record LegacyRegistration(string Scope, string Directory, string Uninstall);
internal sealed record ShortcutData(string Target, string Arguments, string WorkingDirectory, string Icon);

// Shared by both installers through InstalledStartup, after a live startup receipt.
// Never executes uninstall commands or reads account/data files.
internal static class WpfShortcutHandoff
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F}_is1";
    internal static bool Run(string executable)
    {
        try
        {
            // Different installation roots must not concurrently replace the same old links.
            using var gate = new Semaphore(1, 1, @"Local\StarBridge.LegacyShortcutHandoff.v1");
            if (!gate.WaitOne(0)) return false;
            try
            {
                return Run(ReadRegistrations(), executable,
                    Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                    Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), ReadShortcut, WriteShortcut);
            }
            finally { gate.Release(); }
        }
        catch { return false; }
    }

    internal static bool Run(IReadOnlyList<LegacyRegistration> registrations, string executable,
        string programs, string desktop, Func<string, ShortcutData> read, Action<string, ShortcutData> write,
        string? recoveryRoot = null)
    {
        try
        {
            if (registrations.Count == 0) return true;
            if (registrations.Count != 1 || registrations[0].Scope != "current-user") return false;
            var old = registrations[0];
            if (!PlainPath(old.Directory) || !Directory.Exists(old.Directory) ||
                !string.Equals(old.Uninstall, '"' + Path.Combine(old.Directory, "unins000.exe") + '"', StringComparison.OrdinalIgnoreCase)) return false;
            foreach (var name in new[] { "Star Bridge.exe", "unins000.exe", "unins000.dat" })
                if (!File.Exists(Path.Combine(old.Directory, name)) || !PlainPath(Path.Combine(old.Directory, name))) return false;
            if (!File.Exists(executable) || !PlainPath(executable)) return false;
            var target = Path.Combine(old.Directory, "Star Bridge.exe");
            const string nameCn = "星海舰桥";
            var group = Path.Combine(programs, nameCn);
            var menuOk = !Exists(group) || TryOne(Path.Combine(group, nameCn + ".lnk"), target, executable, read, write, recoveryRoot: recoveryRoot);
            var desktopOk = TryOne(Path.Combine(desktop, nameCn + ".lnk"), target, executable, read, write, recoveryRoot: recoveryRoot);
            return menuOk && desktopOk;
        }
        catch { return false; }
    }

    internal static bool TryOne(string path, string oldTarget, string newTarget,
        Func<string, ShortcutData> read, Action<string, ShortcutData> write,
        Action<string, string>? replace = null, string? recoveryRoot = null)
    {
        try
        {
            if (!PlainPath(Path.GetDirectoryName(path)!)) return false;
            if (!Exists(path)) return true; // A deleted optional icon stays deleted.
            if (!PlainPath(path) || !File.Exists(path)) return false;
            var current = read(path);
            if (PointsTo(current, newTarget)) return ArchiveBackup(path, oldTarget, newTarget, read, recoveryRoot);
            if (!PointsTo(current, oldTarget)) return false;
            var backup = path + ".starbridge-wpf-backup";
            var stage = path + ".starbridge-new.lnk";
            var hash = Digest(path);
            // Resume only a byte-identical original backup. Foreign or changed files block.
            if (Exists(backup))
            {
                if (!PlainPath(backup) || !File.Exists(backup) || Digest(backup) != hash) return false;
            }
            else File.Copy(path, backup, overwrite: false);
            if (Digest(backup) != hash) return false;
            var expected = new ShortcutData(newTarget, "", Path.GetDirectoryName(newTarget)!, newTarget + ",0");
            if (Exists(stage))
            {
                if (!PlainPath(stage) || !File.Exists(stage) || !Equivalent(read(stage), expected)) return false;
            }
            else write(stage, expected);
            if (!PlainPath(stage) || !Equivalent(read(stage), expected)) return false;
            var stagedHash = Digest(stage);
            if (!PlainPath(path) || Digest(path) != hash || !PlainPath(backup) || Digest(backup) != hash) return false;
            (replace ?? ((source, destination) => File.Move(source, destination, overwrite: true)))(stage, path);
            return PlainPath(path) && Digest(path) == stagedHash && Equivalent(read(path), expected) &&
                ArchiveBackup(path, oldTarget, newTarget, read, recoveryRoot);
        }
        catch { return false; } // Leave original/backup/stage available for a verified retry.
    }

    // Content-addressed copies retain the original shortcut bytes outside shell folders.
    // The source-path hash distinguishes a desktop link from a same-named menu link.
    internal static string RecoveryBackupPath(string root, string shortcut, string digest) =>
        Path.Combine(root, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            shortcut.ToUpperInvariant()))) + "-" + digest + ".lnk");

    private static bool ArchiveBackup(string path, string oldTarget, string newTarget,
        Func<string, ShortcutData> read, string? recoveryRoot)
    {
        var backup = path + ".starbridge-wpf-backup";
        if (!Exists(backup)) return true;
        if (!PlainPath(backup) || !File.Exists(backup)) return false;
        var hash = Digest(backup);
        if (!PointsTo(read(backup), oldTarget) || Digest(backup) != hash) return false;
        var root = recoveryRoot ?? Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData), "StarBridge", "InstallerRecovery", "shortcut-handoff");
        if (!CreatePlainDirectory(root)) return false;
        var archived = RecoveryBackupPath(root, path, hash);
        if (Exists(archived))
        {
            if (!PlainPath(archived) || !File.Exists(archived) || Digest(archived) != hash) return false;
        }
        else File.Copy(backup, archived, overwrite: false);
        // Never remove an edited backup or archive, or clean up after a user changes the link.
        if (!PlainPath(archived) || Digest(archived) != hash ||
            !PlainPath(backup) || Digest(backup) != hash ||
            !PlainPath(path) || !PointsTo(read(path), newTarget)) return false;
        File.Delete(backup); // Only the verified duplicate; original bytes remain in recovery storage.
        return true;
    }

    private static bool CreatePlainDirectory(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
            !string.Equals(Path.GetFullPath(path), path, StringComparison.OrdinalIgnoreCase)) return false;
        if (Exists(path)) return Directory.Exists(path) && PlainPath(path);
        var parent = Path.GetDirectoryName(path);
        if (parent is null || !CreatePlainDirectory(parent)) return false;
        Directory.CreateDirectory(path);
        return PlainPath(path);
    }

    private static bool PointsTo(ShortcutData link, string target) =>
        string.Equals(link.Target, target, StringComparison.OrdinalIgnoreCase) && link.Arguments.Length == 0;
    private static bool Equivalent(ShortcutData a, ShortcutData b) => PointsTo(a, b.Target) &&
        string.Equals(a.WorkingDirectory, b.WorkingDirectory, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(a.Icon, b.Icon, StringComparison.OrdinalIgnoreCase);
    private static string Digest(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
    private static bool Exists(string path)
    {
        try { _ = File.GetAttributes(path); return true; }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
    internal static bool PlainPath(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) ||
            !string.Equals(Path.GetFullPath(path), path, StringComparison.OrdinalIgnoreCase)) return false;
        for (string? part = path; !string.IsNullOrEmpty(part); part = Path.GetDirectoryName(part))
            if ((File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0) return false;
        return true;
    }

    internal static IReadOnlyList<LegacyRegistration> ReadRegistrations()
    {
        var records = new List<LegacyRegistration>();
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var key = root.OpenSubKey(Key, writable: false);
            if (key is null) continue;
            var record = new LegacyRegistration(hive == RegistryHive.CurrentUser ? "current-user" : "all-users",
                Path.TrimEndingDirectorySeparator(key.GetValue("InstallLocation") as string ?? ""), key.GetValue("UninstallString") as string ?? "");
            if (!records.Contains(record)) records.Add(record);
        }
        return records;
    }

    internal static ShortcutData ReadShortcut(string path) => WithShortcut(link =>
    {
        ((System.Runtime.InteropServices.ComTypes.IPersistFile)link).Load(path, 0);
        var target = new StringBuilder(32768); var arguments = new StringBuilder(32768);
        var working = new StringBuilder(32768); var icon = new StringBuilder(32768);
        link.GetPath(target, target.Capacity, IntPtr.Zero, 4);
        link.GetArguments(arguments, arguments.Capacity); link.GetWorkingDirectory(working, working.Capacity);
        link.GetIconLocation(icon, icon.Capacity, out var index);
        return new ShortcutData(target.ToString(), arguments.ToString(), working.ToString(), icon + "," + index);
    });
    internal static void WriteShortcut(string path, ShortcutData value) => WithShortcut(link =>
    {
        link.SetPath(value.Target); link.SetArguments(value.Arguments);
        link.SetWorkingDirectory(value.WorkingDirectory);
        var comma = value.Icon.LastIndexOf(',');
        var indexed = comma >= 0 && int.TryParse(value.Icon[(comma + 1)..], out _);
        link.SetIconLocation(indexed ? value.Icon[..comma] : value.Icon, indexed ? int.Parse(value.Icon[(comma + 1)..]) : 0);
        ((System.Runtime.InteropServices.ComTypes.IPersistFile)link).Save(path, true);
        return true;
    });
    private static T WithShortcut<T>(Func<IShellLinkW, T> operation)
    {
        object? shortcut = null;
        try
        {
            shortcut = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046"))!);
            return operation((IShellLinkW)shortcut!);
        }
        finally
        {
            if (shortcut is not null) Marshal.FinalReleaseComObject(shortcut);
        }
    }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, IntPtr data, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int count);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string path);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int count);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int command);
        void SetShowCmd(int command);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }
}
