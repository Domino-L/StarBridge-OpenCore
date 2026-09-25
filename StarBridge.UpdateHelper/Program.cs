using System.Diagnostics;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;

// This executable must be staged outside the installation it renames.
// The production trust/channel is deliberately unconfigured, not taken from a
// downloaded manifest, arbitrary UI JSON, or the retired WPF update endpoint.
if (args is ["--start-installed-client", var installedVersion]) return await InstalledStartup.Run(installedVersion);
if (args is ["--retire-wpf", var cleanupPipe]) return await WpfCleanup.Run(cleanupPipe);
if (args is ["--installed-plan", var installedPlan]) return await InstalledUpdate.Run(installedPlan, recovery: false);
if (args is ["--installed-recover", var installedRecovery]) return await InstalledUpdate.Run(installedRecovery, recovery: true);
if (args is ["--inspect-wpf-migration"])
{
    Console.WriteLine(JsonSerializer.Serialize(WpfMigrationPreflight.Inspect()));
    return 0; // Read-only classification; inspect the state, not exit code, for eligibility.
}
if (args is ["--storage-plan", var productionStoragePlan]) return await StorageMigration.Run(productionStoragePlan);
if (args is ["--isolated-storage-plan", var storagePlan]) return await IsolatedStorageMigration.Run(storagePlan);
if (args.Length != 2 || args[0] is not ("--isolated-plan" or "--isolated-recover")) return 2;
try
{
    var planPath = Path.GetFullPath(args[1]);
    var root = Path.GetDirectoryName(planPath)!;
    var parent = Path.GetDirectoryName(root)!;
    var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
    if (!string.Equals(Path.GetDirectoryName(parent), temp, StringComparison.OrdinalIgnoreCase) ||
        !Path.GetFileName(parent).StartsWith("starbridge-update-integration-", StringComparison.Ordinal) ||
        !Path.GetFileName(root).StartsWith(".starbridge-update-", StringComparison.Ordinal) ||
        Path.GetFileName(planPath) != "plan.json") return 3;
    for (var directory = new DirectoryInfo(root); directory is not null; directory = directory.Parent)
        if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) return 3;
    var json = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };
    var plan = Read<IsolatedPlan>(planPath, json);
    if (plan.SchemaVersion != 1 || plan.InstallationName != "client" ||
        !Version.TryParse(plan.CurrentVersion, out _) || plan.ClientPid <= 0 || plan.HostPid <= 0) return 4;
    var installation = Path.Combine(parent, "client");
    if (args[0] == "--isolated-recover")
    {
        using var recovery = FlutterUpdateProcessActivation.ForRecovery(installation);
        var recovered = await new FlutterUpdateTransaction(installation, root).RecoverAsync(recovery);
        return recovered == "committed" ? 0 : 5;
    }
    using var client = Process.GetProcessById(plan.ClientPid);
    using var host = Process.GetProcessById(plan.HostPid);
    if (client.StartTime.ToUniversalTime().Ticks != plan.ClientStartTicks ||
        host.StartTime.ToUniversalTime().Ticks != plan.HostStartTicks) return 4;
    if (!string.Equals(client.MainModule?.FileName, Path.Combine(installation, "starbridge_flutter.exe"), StringComparison.OrdinalIgnoreCase) ||
        !string.Equals(host.MainModule?.FileName, Path.Combine(installation, "native_host", "StarBridge.NativeHost.exe"), StringComparison.OrdinalIgnoreCase)) return 4;
    var manifest = Read<FlutterUpdateManifest>(Path.Combine(root, "manifest.json"), json);
    var trust = Read<Dictionary<string, string>>(Path.Combine(root, "isolated-public-keys.json"), json);
    var verifier = new FlutterUpdateManifestVerifier(trust);
    var candidate = FlutterUpdateStager.Prepare(Path.Combine(root, "package.zip"), root, manifest, verifier,
        new FlutterUpdateTarget(plan.Architecture, plan.Channel, plan.CurrentVersion), DateTimeOffset.UtcNow);
    Directory.Move(candidate, Path.Combine(root, "candidate"));
    using var activation = new FlutterUpdateProcessActivation(client, host);
    var transaction = new FlutterUpdateTransaction(installation, root);
    var result = await transaction.ApplyAsync(manifest.Version, activation,
        prepared: FlutterUpdateHandoff.ReportPreparedAsync);
    return result == "committed" ? 0 : 5;
}
catch { return 6; } // No user paths, identifiers or credentials in helper output.

static T Read<T>(string path, JsonSerializerOptions json)
{
    if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || new FileInfo(path).Length > 65536)
        throw new InvalidDataException();
    return JsonSerializer.Deserialize<T>(File.ReadAllText(path), json) ?? throw new InvalidDataException();
}
internal sealed record IsolatedPlan(int SchemaVersion, string InstallationName, string Architecture,
    string Channel, string CurrentVersion, int ClientPid, long ClientStartTicks, int HostPid, long HostStartTicks);
