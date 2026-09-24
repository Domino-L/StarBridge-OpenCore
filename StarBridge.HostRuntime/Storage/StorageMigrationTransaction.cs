using System.Text.Json;

namespace StarBridge.HostRuntime.Storage;

/// <summary>Internal offline migration. The caller MUST keep all WPF and Flutter
/// writers stopped for the entire call; the activity lease excludes participating
/// clients but cannot detect older binaries that predate this protocol.
/// Source files are never deleted. No production Bridge entry until writer handoff exists.</summary>
internal sealed class StorageMigrationTransaction(string bootstrap)
{
    internal const string JournalName = "flutter-data-migration.json";
    internal const string LeaseName = "flutter-data-migration.lock";
    private sealed record Journal(int SchemaVersion, string Source, string Destination, string Phase);
    private readonly string _bootstrap = StorageRootLocator.Normalize(bootstrap);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };

    internal void Apply(string destination, CancellationToken cancellation = default, string? expectedSource = null)
    {
        using var lease = Lock();
        using var activity = StorageActivityLease.AcquireMigration(_bootstrap);
        cancellation.ThrowIfCancellationRequested();
        var source = StorageRootLocator.Read(_bootstrap);
        // A helper must bind the offline operation to the source confirmed in
        // the UI, not silently migrate another root selected during shutdown.
        if (expectedSource is not null && !Equal(source, StorageRootLocator.Normalize(expectedSource)))
            throw new IOException("Confirmed migration source changed.");
        if (File.Exists(Path.Combine(_bootstrap, JournalName)))
        {
            var previous = Read();
            if (previous.Phase != "committed" || !Equal(StorageRootLocator.Read(_bootstrap), previous.Destination))
                throw new InvalidOperationException("Resolve existing migration first.");
            File.Move(Path.Combine(_bootstrap, JournalName), Path.Combine(_bootstrap, JournalName + ".completed-" + Guid.NewGuid().ToString("N")));
        }
        destination = StorageMigrationDestination.Validate(source, destination);
        if (Equal(source, destination)) return;
        if (!Equal(source, _bootstrap) && (Equal(destination, _bootstrap) || Nested(destination, _bootstrap) || Nested(_bootstrap, destination)))
            throw new InvalidDataException("Destination overlaps migration control files.");
        var journal = new Journal(1, source, destination, "copying");
        Write(journal);
        VerifiedStorageCopy.Copy(source, destination, Include(source), cancellation);
        Write(journal with { Phase = "copied" });
        Commit(journal, cancellation);
    }

    internal string Recover(CancellationToken cancellation = default)
    {
        using var lease = Lock();
        using var activity = StorageActivityLease.AcquireMigration(_bootstrap);
        cancellation.ThrowIfCancellationRequested();
        var state = Read();
        var current = StorageRootLocator.Read(_bootstrap);
        if (Equal(current, state.Destination))
        {
            // A pointer may have switched before the final journal write. Do not
            // compare mutable live data against an old backup or switch backwards.
            if (!Directory.Exists(current)) throw new IOException("Committed destination unavailable.");
            Write(state with { Phase = "committed" });
            return "committed";
        }
        if (!Equal(current, state.Source) || state.Phase == "committed") throw new IOException("Data root changed outside migration.");
        if (!Directory.Exists(state.Destination)) return "source-retained";
        // Never overwrite a partial or externally changed target. Verify both sets.
        Commit(state, cancellation);
        return "committed";
    }

    private Journal Read()
    {
        var path = Path.Combine(_bootstrap, JournalName);
        if (new FileInfo(path).Length > 131072) throw new InvalidDataException("Oversized migration journal.");
        var state = JsonSerializer.Deserialize<Journal>(File.ReadAllText(path), Json) ?? throw new InvalidDataException();
        if (state.SchemaVersion != 1 || state.Phase is not ("copying" or "copied" or "committed") ||
            state.Source != StorageRootLocator.Normalize(state.Source) || state.Destination != StorageRootLocator.Normalize(state.Destination) ||
            Equal(state.Source, state.Destination) || Nested(state.Source, state.Destination) || Nested(state.Destination, state.Source))
            throw new InvalidDataException("Invalid migration journal.");
        if (Equal(state.Destination, Path.TrimEndingDirectorySeparator(Path.GetPathRoot(state.Destination)!)) ||
            (!Equal(state.Source, _bootstrap) && (Equal(state.Destination, _bootstrap) || Nested(state.Destination, _bootstrap) || Nested(_bootstrap, state.Destination))))
            throw new InvalidDataException("Unsafe migration recovery destination.");
        return state;
    }

    private void Commit(Journal state, CancellationToken cancellation)
    {
        VerifiedStorageCopy.Verify(state.Source, state.Destination, Include(state.Source), cancellation);
        if (!Equal(StorageRootLocator.Read(_bootstrap), state.Source)) throw new IOException("Source locator changed.");
        cancellation.ThrowIfCancellationRequested();
        StorageRootLocator.Write(_bootstrap, state.Destination);
        Write(state with { Phase = "committed" });
    }

    private Func<string, bool>? Include(string source) => !Equal(source, _bootstrap) ? null : relative =>
        !StorageMigrationFiles.IsBootstrapOwned(relative);

    private FileStream Lock()
    {
        for (var directory = new DirectoryInfo(_bootstrap); directory is not null; directory = directory.Parent)
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected migration control directory.");
        foreach (var name in new[] { JournalName, LeaseName, StorageRootLocator.FileName })
            if (Path.Exists(Path.Combine(_bootstrap, name)) && (File.GetAttributes(Path.Combine(_bootstrap, name)) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Redirected migration control file.");
        return new FileStream(Path.Combine(_bootstrap, LeaseName), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private void Write(Journal state)
    {
        var path = Path.Combine(_bootstrap, JournalName);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        { JsonSerializer.Serialize(stream, state, Json); stream.Flush(flushToDisk: true); }
        File.Move(temporary, path, overwrite: true);
    }
    private static bool Equal(string left, string right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    private static bool Nested(string parent, string child) => child.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
}
