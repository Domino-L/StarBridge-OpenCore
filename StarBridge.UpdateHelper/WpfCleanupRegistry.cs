using Microsoft.Win32;
using System.Globalization;

// Only this per-user Inno leaf. No HKLM, shared parent or arbitrary registry path.
internal sealed class WpfCleanupRegistry : IWpfCleanupRegistration
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F}_is1";
    public WpfCleanupRegistrationRecord? Read()
    {
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = root.OpenSubKey(Key);
        if (key is null) return null;
        if (key.SubKeyCount != 0 || key.ValueCount > 128) throw new InvalidDataException();
        var values = key.GetValueNames().Order(StringComparer.Ordinal).Select(name => {
            var kind = key.GetValueKind(name);
            var value = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            var data = kind switch {
                RegistryValueKind.String or RegistryValueKind.ExpandString => new[] { (string)value! },
                RegistryValueKind.DWord => new[] { ((int)value!).ToString(CultureInfo.InvariantCulture) },
                RegistryValueKind.QWord => new[] { ((long)value!).ToString(CultureInfo.InvariantCulture) },
                RegistryValueKind.Binary => new[] { Convert.ToBase64String((byte[])value!) },
                RegistryValueKind.MultiString => (string[])value!,
                _ => throw new InvalidDataException()
            };
            return new WpfCleanupRegistrationValue(name, (int)kind, data);
        }).ToArray();
        var directory = Path.TrimEndingDirectorySeparator(key.GetValue("InstallLocation") as string ?? "");
        var record = new WpfCleanupRegistrationRecord(directory, values);
        Validate(record);
        return record;
    }
    public void RemoveIfUnchanged(WpfCleanupRegistrationRecord expected)
    {
        Validate(expected);
        if (Read() is not { } current || !WpfCleanupTransaction.Equivalent(current, expected)) throw new IOException();
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        root.DeleteSubKey(Key, throwOnMissingSubKey: true); // Fails if subkeys appeared; never DeleteSubKeyTree.
        root.Flush();
    }
    public bool RestoreIfAbsent(WpfCleanupRegistrationRecord expected)
    {
        Validate(expected);
        if (Read() is { } current) return WpfCleanupTransaction.Equivalent(current, expected);
        using var root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = root.CreateSubKey(Key, writable: true);
        if (key.SubKeyCount != 0 || key.ValueCount != 0) return false;
        foreach (var entry in expected.Values) key.SetValue(entry.Name, Decode(entry), (RegistryValueKind)entry.Kind);
        key.Flush();
        return Read() is { } restored && WpfCleanupTransaction.Equivalent(restored, expected);
    }
    private static void Validate(WpfCleanupRegistrationRecord record)
    {
        if (!Path.IsPathFullyQualified(record.Directory) || record.Directory.StartsWith(@"\\", StringComparison.Ordinal) ||
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(record.Directory)) != record.Directory ||
            record.Directory == Path.GetPathRoot(record.Directory) || record.Values.Length > 128 ||
            record.Values.Select(v => v.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != record.Values.Length)
            throw new InvalidDataException();
        foreach (var entry in record.Values) _ = Decode(entry);
        string? Value(string name) => record.Values.SingleOrDefault(v => v.Name == name) is { } entry
            && entry.Kind == (int)RegistryValueKind.String && entry.Data.Length == 1 ? entry.Data[0] : null;
        if (Path.TrimEndingDirectorySeparator(Value("InstallLocation") ?? "") != record.Directory ||
            Value("DisplayVersion") != "0.6.6.1" ||
            !string.Equals(Value("UninstallString"), '"' + Path.Combine(record.Directory, "unins000.exe") + '"', StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Not the supported registered WPF release.");
        if (System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(record).Length > 131072) throw new InvalidDataException();
    }
    private static object Decode(WpfCleanupRegistrationValue value)
    {
        if (value.Name.Length > 256 || value.Data.Length > 128 || value.Data.Any(s => s.Length > 16384)) throw new InvalidDataException();
        if ((RegistryValueKind)value.Kind == RegistryValueKind.MultiString) return value.Data;
        if (value.Data.Length != 1) throw new InvalidDataException();
        return (RegistryValueKind)value.Kind switch {
            RegistryValueKind.String or RegistryValueKind.ExpandString => value.Data[0],
            RegistryValueKind.DWord => int.Parse(value.Data[0], CultureInfo.InvariantCulture),
            RegistryValueKind.QWord => long.Parse(value.Data[0], CultureInfo.InvariantCulture),
            RegistryValueKind.Binary => Convert.FromBase64String(value.Data[0]),
            _ => throw new InvalidDataException()
        };
    }
}
