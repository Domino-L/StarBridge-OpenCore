using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Updates;

// Launch and verified shortcut handoff only. No installation, data deletion or WPF uninstall authority.
internal static class InstalledStartup
{
    internal static async Task<int> Run(string expectedVersion, Func<string, bool>? handoff = null)
    {
        try
        {
            var maintenance = new DirectoryInfo(AppContext.BaseDirectory);
            if (maintenance.Name != "maintenance" || maintenance.Parent?.Name != "native_host") return 3;
            var root = maintenance.Parent.Parent?.FullName ?? throw new InvalidDataException();
            for (var part = maintenance; part is not null; part = part.Parent)
                if ((part.Attributes & FileAttributes.ReparsePoint) != 0) return 3;
            var executable = Path.Combine(root, "starbridge_flutter.exe");
            if ((File.GetAttributes(executable) & FileAttributes.ReparsePoint) != 0 ||
                !Version.TryParse(expectedVersion, out var expected) ||
                !Version.TryParse(FileVersionInfo.GetVersionInfo(executable).ProductVersion?.Split('+')[0], out var actual) ||
                Normalize(expected) != Normalize(actual)) return 3;
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(root.ToUpperInvariant())));
            using var gate = new Semaphore(1, 1, "Local\\StarBridge.InstalledStartup." + key);
            if (!gate.WaitOne(0)) return 4;
            try
            {
                foreach (var name in new[] { "starbridge_flutter", "StarBridge.NativeHost" })
                {
                    var processes = Process.GetProcessesByName(name);
                    try
                    {
                        foreach (var process in processes)
                            if (!process.HasExited && (process.MainModule?.FileName ?? throw new IOException())
                                .StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return 4;
                    }
                    finally { foreach (var process in processes) process.Dispose(); }
                }
                using var activation = new FlutterUpdateProcessActivation();
                using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
                await activation.StartAndProbeAsync(executable, Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), timeout.Token);
                // Dispose releases handles only. Never terminate a slow or newly usable client.
                // 6 means healthy startup, but one or more legacy entries remain unchanged.
                try { return (handoff ?? WpfShortcutHandoff.Run)(executable) ? 0 : 6; }
                catch { return 6; }
            }
            finally { gate.Release(); }
        }
        catch { return 5; } // No paths, credentials or exception text escape to the installer.
    }

    private static Version Normalize(Version value) =>
        new(value.Major, value.Minor, Math.Max(0, value.Build), Math.Max(0, value.Revision));
}
