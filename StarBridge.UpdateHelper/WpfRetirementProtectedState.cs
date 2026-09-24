using Microsoft.Win32;
using System.Text.Json;

internal sealed record RetirementStartupValue(string Command, string Kind);

// Only preserves known entries already owned by this verified new installation.
// A different startup target or link blocks capture instead of claiming ownership.
internal sealed class WpfRetirementProtectedState
{
    private readonly string _newExecutable, _journal, _programs, _desktop;
    private readonly Func<RetirementStartupValue?> _readStartup;
    private readonly Action<RetirementStartupValue> _writeStartup;
    private string StartupCommand => '"' + _newExecutable + "\" --startup";

    internal WpfRetirementProtectedState(string newExecutable, string ownedJournal,
        string programs, string desktop, Func<RetirementStartupValue?> readStartup,
        Action<RetirementStartupValue> writeStartup)
    {
        _newExecutable = newExecutable; _journal = ownedJournal;
        _programs = programs; _desktop = desktop;
        _readStartup = readStartup; _writeStartup = writeStartup;
        RequireRoots();
    }

    internal static WpfRetirementProtectedState ForCurrentUser(string newExecutable, string ownedJournal) =>
        new(newExecutable, ownedJournal, Environment.GetFolderPath(Environment.SpecialFolder.Programs),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), ReadStartup, WriteStartup);

    // WpfRetirementRecovery holds the shared startup-registration lease across
    // capture, uninstall and restore. Direct calls require the same exclusion.
    internal RetirementEntry[] Capture()
    {
        RequireRoots();
        var entries = new List<RetirementEntry>();
        var startup = _readStartup();
        if (startup is not null)
        {
            ValidateStartup(startup);
            entries.Add(new(RetirementSlot.Startup, JsonSerializer.SerializeToUtf8Bytes(startup)));
        }
        foreach (var slot in new[] { RetirementSlot.DesktopShortcut, RetirementSlot.MenuShortcut })
        {
            var path = SlotPath(slot);
            if (!Exists(path)) continue;
            RequireOwnedLink(path);
            var info = new FileInfo(path);
            if (info.Length > 196608) throw new InvalidDataException("Oversized shortcut.");
            entries.Add(new(slot, File.ReadAllBytes(path)));
        }
        return entries.ToArray();
    }

    internal RetirementRepair RestoreMissing(RetirementSlot slot, byte[] content)
    {
        RequireRoots();
        if (content.Length is 0 or > 196608) return RetirementRepair.Failed;
        if (slot == RetirementSlot.Startup)
        {
            var saved = JsonSerializer.Deserialize<RetirementStartupValue>(content) ?? throw new InvalidDataException();
            ValidateStartup(saved);
            var current = _readStartup();
            if (current is not null) return current == saved ? RetirementRepair.AlreadyPresent : RetirementRepair.Conflict;
            _writeStartup(saved);
            return _readStartup() == saved ? RetirementRepair.Restored : RetirementRepair.Failed;
        }
        var path = SlotPath(slot);
        if (Exists(path))
            return WpfShortcutHandoff.PlainPath(path) && File.Exists(path) && File.ReadAllBytes(path).SequenceEqual(content)
                ? RetirementRepair.AlreadyPresent : RetirementRepair.Conflict;
        var temp = Path.Combine(_journal, Guid.NewGuid().ToString("N") + ".lnk");
        using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            stream.Write(content); stream.Flush(true);
        }
        RequireOwnedLink(temp); // Reject corrupted or arbitrary-target journal bytes.
        var parent = Path.GetDirectoryName(path)!;
        if (!Exists(parent)) Directory.CreateDirectory(parent); // Only the fixed old menu group.
        if (!WpfShortcutHandoff.PlainPath(parent)) return RetirementRepair.Failed;
        try { File.Move(temp, path, overwrite: false); } // Never clobber a user-created replacement.
        catch (IOException) { return RetirementRepair.Conflict; }
        return RetirementRepair.Restored;
    }

    private string SlotPath(RetirementSlot slot) => slot switch
    {
        RetirementSlot.DesktopShortcut => Path.Combine(_desktop, "星海舰桥.lnk"),
        RetirementSlot.MenuShortcut => Path.Combine(_programs, "星海舰桥", "星海舰桥.lnk"),
        _ => throw new InvalidDataException("Unknown protected slot.")
    };
    private void RequireOwnedLink(string path)
    {
        if (!WpfShortcutHandoff.PlainPath(path) || !File.Exists(path)) throw new InvalidDataException();
        var link = WpfShortcutHandoff.ReadShortcut(path);
        if (!string.Equals(link.Target, _newExecutable, StringComparison.OrdinalIgnoreCase) || link.Arguments.Length != 0)
            throw new InvalidDataException("Shortcut is not owned by the new installation.");
    }
    private void RequireRoots()
    {
        if (Path.GetFileName(_newExecutable) != "starbridge_flutter.exe" || !File.Exists(_newExecutable) ||
            !WpfShortcutHandoff.PlainPath(_newExecutable)) throw new InvalidDataException("New installation unavailable.");
        foreach (var path in new[] { _journal, _programs, _desktop })
            if (!Directory.Exists(path) || !WpfShortcutHandoff.PlainPath(path)) throw new InvalidDataException("Protection directory unavailable.");
    }
    private void ValidateStartup(RetirementStartupValue value)
    {
        if (value.Kind is not ("String" or "ExpandString") ||
            !string.Equals(value.Command, StartupCommand, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Startup target belongs to another installation; manual review required.");
    }
    private static bool Exists(string path)
    {
        try { _ = File.GetAttributes(path); return true; }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private static RetirementStartupValue? ReadStartup()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
        if (key is null || !key.GetValueNames().Contains("StarBridge")) return null;
        return new(key.GetValue("StarBridge", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string
            ?? throw new InvalidDataException(), key.GetValueKind("StarBridge").ToString());
    }
    private static void WriteStartup(RetirementStartupValue value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
        // Preserve a concurrent nonempty value. Settings exclusivity is a prerequisite,
        // not something registry read-then-write can establish by itself.
        if (!key.GetValueNames().Contains("StarBridge"))
            key.SetValue("StarBridge", value.Command, Enum.Parse<RegistryValueKind>(value.Kind));
    }
}
