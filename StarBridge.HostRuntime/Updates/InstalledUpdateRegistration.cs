using System.Diagnostics;
using Microsoft.Win32;
using StarBridge.HostRuntime.Support;

namespace StarBridge.HostRuntime.Updates;

internal sealed record InstalledUpdateRegistration(string Directory, string Version, string Product, string UninstallCommand)
{
    internal static InstalledUpdateRegistration Read()
    {
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = hive.OpenSubKey(FlutterInstallationIdentity.RegistryPath) ?? throw new InvalidDataException("Installation is not registered.");
        return new(InstalledUpdateFiles.Normalize(key.GetValue("InstallLocation") as string ?? ""),
            key.GetValue("DisplayVersion") as string ?? "", key.GetValue("StarBridgeProduct") as string ?? "",
            key.GetValue("UninstallString") as string ?? "");
    }

    internal void Require(string client, string host, string dataRoot)
    {
        RequireShape();
        InstalledUpdateFiles.Tree(Directory);
        if (!Same(client, Path.Combine(Directory, "starbridge_flutter.exe")) ||
            !Same(host, Path.Combine(Directory, "native_host", "StarBridge.NativeHost.exe")) ||
            Contains(Directory, dataRoot) || Contains(dataRoot, Directory) ||
            File.Exists(Path.Combine(Directory, "StarBridge.sln")) || System.IO.Directory.Exists(Path.Combine(Directory, ".git")) ||
            File.Exists(Path.Combine(Directory, "Star Bridge.exe"))) throw new InvalidDataException("Not this installed client.");
        foreach (var file in new[] { "starbridge_flutter.exe", "flutter_windows.dll", "unins000.exe", "unins000.dat",
            "native_host/StarBridge.NativeHost.exe", "native_host/maintenance/StarBridge.UpdateHelper.exe" })
            if (!File.Exists(Path.Combine(Directory, file))) throw new InvalidDataException("Incomplete installation.");
        if (ApplicationUpdateVersion.ParseInstalled(FileVersionInfo.GetVersionInfo(client).ProductVersion) !=
            ApplicationUpdateVersion.Parse(Version)) throw new InvalidDataException("Registered version does not match.");
    }

    internal void RequireShape()
    {
        if (InstalledUpdateFiles.Normalize(Directory) != Directory || Product != FlutterInstallationIdentity.Product ||
            !Same(UninstallCommand, "\"" + Path.Combine(Directory, "unins000.exe") + "\"")) throw new InvalidDataException("Unverified installation.");
        _ = ApplicationUpdateVersion.Parse(Version);
    }

    internal static bool Same(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    internal static bool Contains(string parent, string child) => Same(parent, child) ||
        child.StartsWith(parent.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
}

// Only the fixed, per-user Flutter uninstall leaf. Restoring it must accompany
// restoring the old binaries/uninstaller, never a WPF key or shared registry parent.
internal static class InstalledUpdateRegistrySnapshot
{
    internal sealed record Entry(string Name, int Kind, string[] Data);
    internal static Entry[] Capture()
    {
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = hive.OpenSubKey(FlutterInstallationIdentity.RegistryPath) ?? throw new InvalidDataException();
        if (key.SubKeyCount != 0 || key.ValueCount > 128) throw new InvalidDataException();
        var entries = key.GetValueNames().Select(name => {
            var kind = key.GetValueKind(name);
            var value = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            var data = kind switch {
                RegistryValueKind.String or RegistryValueKind.ExpandString => new[] { (string)value! },
                RegistryValueKind.DWord => new[] { ((int)value!).ToString(System.Globalization.CultureInfo.InvariantCulture) },
                RegistryValueKind.QWord => new[] { ((long)value!).ToString(System.Globalization.CultureInfo.InvariantCulture) },
                RegistryValueKind.Binary => new[] { Convert.ToBase64String((byte[])value!) },
                RegistryValueKind.MultiString => (string[])value!,
                _ => throw new InvalidDataException()
            };
            return new Entry(name, (int)kind, data);
        }).ToArray();
        foreach (var entry in entries) _ = Decode(entry);
        if (System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(entries, InstalledUpdateFiles.Json).Length > 131072)
            throw new InvalidDataException("Registration snapshot is too large.");
        return entries;
    }

    internal static void Restore(Entry[] entries, string expectedDirectory)
    {
        if (entries.Length > 128 || entries.Select(e => e.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != entries.Length)
            throw new InvalidDataException();
        // Validate all values before the first registry mutation.
        var values = entries.Select(entry => (entry.Name, Kind: (RegistryValueKind)entry.Kind, Value: Decode(entry))).ToArray();
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = hive.CreateSubKey(FlutterInstallationIdentity.RegistryPath);
        if (key.SubKeyCount != 0) throw new InvalidDataException();
        var directory = key.GetValue("InstallLocation") as string;
        var product = key.GetValue("StarBridgeProduct") as string;
        if (directory is not null && !InstalledUpdateRegistration.Same(InstalledUpdateFiles.Normalize(directory), expectedDirectory) ||
            product is not null && product != FlutterInstallationIdentity.Product)
            throw new InvalidDataException("Another installation owns the registration.");
        foreach (var value in values) key.SetValue(value.Name, value.Value, value.Kind);
        foreach (var name in key.GetValueNames())
            if (!values.Any(value => string.Equals(value.Name, name, StringComparison.OrdinalIgnoreCase))) key.DeleteValue(name);
        key.Flush();
    }

    private static object Decode(Entry entry)
    {
        if (entry.Name is null || entry.Name.Length > 256 || entry.Data is null || entry.Data.Length > 128 ||
            entry.Data.Any(value => value is null || value.Length > 16384)) throw new InvalidDataException();
        if ((RegistryValueKind)entry.Kind == RegistryValueKind.MultiString) return entry.Data;
        if (entry.Data.Length != 1) throw new InvalidDataException();
        return (RegistryValueKind)entry.Kind switch {
            RegistryValueKind.String or RegistryValueKind.ExpandString => entry.Data[0],
            RegistryValueKind.DWord => int.Parse(entry.Data[0], System.Globalization.CultureInfo.InvariantCulture),
            RegistryValueKind.QWord => long.Parse(entry.Data[0], System.Globalization.CultureInfo.InvariantCulture),
            RegistryValueKind.Binary => Convert.FromBase64String(entry.Data[0]),
            _ => throw new InvalidDataException()
        };
    }
}
