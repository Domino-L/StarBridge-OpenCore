using System.Text.Json;

namespace StarBridge.HostRuntime.Storage;

internal sealed record StorageMigrationPlan(int SchemaVersion, string Nonce,
    string Bootstrap, string Source, string Destination,
    int ClientPid, long ClientStartTicks, string ClientPath,
    int HostPid, long HostStartTicks, string HostPath);

internal static class StorageMigrationPlanFile
{
    internal const string Name = "flutter-data-migration-plan.json";
    internal const string ResultName = "flutter-data-migration-result.json";
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };

    internal static string Write(string bootstrap, StorageMigrationPlan plan)
    {
        bootstrap = StorageRootLocator.Normalize(bootstrap);
        var path = Path.Combine(bootstrap, Name);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        Directory.CreateDirectory(bootstrap);
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        { JsonSerializer.Serialize(stream, plan, Json); stream.Flush(true); }
        File.Move(temporary, path, overwrite: true);
        return path;
    }

    internal static StorageMigrationPlan Read(string path, string expectedBootstrap)
    {
        var plan = ReadOwned(path, expectedBootstrap);
        StorageMigrationDestination.Validate(plan.Source, plan.Destination);
        return plan;
    }

    private static StorageMigrationPlan ReadOwned(string path, string expectedBootstrap)
    {
        path = Path.GetFullPath(path);
        expectedBootstrap = StorageRootLocator.Normalize(expectedBootstrap);
        if (!string.Equals(path, Path.Combine(expectedBootstrap, Name), StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 ||
            new FileInfo(path).Length > 65536) throw new InvalidDataException("Invalid migration plan file.");
        var plan = JsonSerializer.Deserialize<StorageMigrationPlan>(File.ReadAllText(path), Json)
            ?? throw new InvalidDataException("Missing migration plan.");
        if (plan.SchemaVersion != 1 || !Guid.TryParseExact(plan.Nonce, "N", out _) ||
            plan.Bootstrap != StorageRootLocator.Normalize(plan.Bootstrap) ||
            !string.Equals(plan.Bootstrap, expectedBootstrap, StringComparison.OrdinalIgnoreCase) ||
            plan.Source != StorageRootLocator.Normalize(plan.Source) ||
            plan.Destination != StorageRootLocator.Normalize(plan.Destination) ||
            plan.ClientPid <= 0 || plan.HostPid <= 0 || plan.ClientPid == plan.HostPid ||
            !Path.IsPathFullyQualified(plan.ClientPath) || !Path.IsPathFullyQualified(plan.HostPath))
            throw new InvalidDataException("Invalid migration plan.");
        return plan;
    }

    internal static void DeleteIfOwned(string path, string expectedBootstrap, string nonce)
    {
        if (ReadOwned(path, expectedBootstrap).Nonce != nonce)
            throw new InvalidOperationException("Migration plan changed.");
        File.Delete(Path.GetFullPath(path));
    }
}
