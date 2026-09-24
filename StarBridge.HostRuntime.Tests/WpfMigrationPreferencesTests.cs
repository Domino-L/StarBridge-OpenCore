using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Updates;
using StarBridge.NativeBridge;

internal static class WpfMigrationPreferencesTests
{
    internal static Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-preferences-check-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            Check("not-present");
            if (Directory.EnumerateFileSystemEntries(root).Any()) throw new Exception("Check created defaults.");
            var legacy = Path.Combine(root, "application-behavior.json");
            File.WriteAllText(legacy, """{"LaunchAtStartup":true,"KeepRunningInBackground":true,"StartMinimized":false,"BackgroundHintShown":true}""");
            var before = File.ReadAllBytes(legacy);
            Check("compatible");
            if (!File.ReadAllBytes(legacy).SequenceEqual(before) || Directory.GetFiles(root).Length != 1)
                throw new Exception("Legacy preferences were modified or promoted.");
            File.WriteAllText(legacy, "{}");
            Check("needs-review");
            File.WriteAllText(legacy, """{"LaunchAtStartup":true,"launchatstartup":false}""");
            Check("needs-review");
            var modern = Path.Combine(root, "application-preferences.v1.json");
            File.WriteAllText(modern, JsonSerializer.Serialize(ApplicationPreferencesSnapshot.Default with {
                LocaleOverride = "zh-TW", LaunchAtStartup = true, AppearanceMode = "light"
            }, BridgeProtocol.JsonOptions));
            var fingerprint = WpfMigrationPreferencesCheck.Inspect(root).SourceSha256;
            if (fingerprint != Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(modern))))
                throw new Exception("Check did not fingerprint the selected preferences.");
            Check("compatible"); // Modern reader takes precedence, even with old unsupported data present.
            File.WriteAllText(modern, JsonSerializer.Serialize(ApplicationPreferencesSnapshot.Default with { SchemaVersion = 999 }, BridgeProtocol.JsonOptions));
            Check("needs-review");
            File.WriteAllText(modern, JsonSerializer.Serialize(ApplicationPreferencesSnapshot.Default with { LocaleOverride = "unknown" }, BridgeProtocol.JsonOptions));
            Check("needs-review");
            File.WriteAllText(modern, "broken");
            Check("unavailable");
            using (var locked = new FileStream(modern, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                Check("unavailable");
            File.WriteAllBytes(modern, new byte[1024 * 1024 + 1]);
            Check("needs-review");
            if (WpfMigrationPreferencesCheck.Inspect(Path.Combine(root, "missing")).State != "unavailable")
                throw new Exception("Missing root was accepted.");
            Console.WriteLine("PASS read-only settings compatibility: legacy, modern, defaults, corruption, lock and size safeguards");
            return Task.CompletedTask;

            void Check(string expected)
            {
                if (WpfMigrationPreferencesCheck.Inspect(root).State != expected)
                    throw new Exception("Unexpected preference compatibility state: " + expected);
            }
        }
        finally { Directory.Delete(root, recursive: true); }
    }
}
