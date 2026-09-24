using System.Text.Json;

namespace StarBridge.HostRuntime.Storage;

public sealed record StorageMigrationResult(string Nonce, string State,
    string Source, string Destination, DateTimeOffset CompletedAt);

public sealed class StorageMigrationResultStore(string bootstrap)
{
    private readonly string _bootstrap = StorageRootLocator.Normalize(bootstrap);

    public StorageMigrationResult? Read()
    {
        var path = Path.Combine(_bootstrap, StorageMigrationPlanFile.ResultName);
        if (!File.Exists(path)) return null;
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 || new FileInfo(path).Length > 65536)
            throw new InvalidDataException("Invalid migration result file.");
        var value = JsonSerializer.Deserialize<StorageMigrationResultDocument>(File.ReadAllText(path), StorageMigrationPlanFile.Json)
            ?? throw new InvalidDataException("Missing migration result.");
        if (value.SchemaVersion != 1 || !Guid.TryParseExact(value.Nonce, "N", out _) ||
            value.State is not ("migrated" or "migration-failed") ||
            value.Source != StorageRootLocator.Normalize(value.Source) ||
            value.Destination != StorageRootLocator.Normalize(value.Destination)) throw new InvalidDataException("Invalid migration result.");
        return new(value.Nonce, value.State, value.Source, value.Destination, value.CompletedAt);
    }

    public void Acknowledge(string nonce)
    {
        var current = Read() ?? throw new InvalidOperationException("Migration result unavailable.");
        if (!string.Equals(current.Nonce, nonce, StringComparison.Ordinal)) throw new InvalidOperationException("Migration result changed.");
        File.Delete(Path.Combine(_bootstrap, StorageMigrationPlanFile.ResultName));
    }

    private sealed record StorageMigrationResultDocument(int SchemaVersion, string Nonce,
        string State, string Source, string Destination, DateTimeOffset CompletedAt);
}
