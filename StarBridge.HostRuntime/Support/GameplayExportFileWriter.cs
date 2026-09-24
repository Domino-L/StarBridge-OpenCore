using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

internal sealed class GameplayExportFileWriter(string protectedDataRoot)
{
    private readonly string _protectedRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(protectedDataRoot));

    internal void WriteNew(string destination, GameplayExportData data, Func<bool> canCommit,
        CancellationToken cancellation)
    {
        if (!Path.IsPathFullyQualified(destination) ||
            !string.Equals(Path.GetExtension(destination), ".json", StringComparison.OrdinalIgnoreCase))
            throw new GameplayExportException("gameplayExport.invalid_destination");
        destination = Path.GetFullPath(destination);
        if (destination.Equals(_protectedRoot, StringComparison.OrdinalIgnoreCase) ||
            destination.StartsWith(_protectedRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new GameplayExportException("gameplayExport.invalid_destination");
        var parent = Path.GetDirectoryName(destination)!;
        CheckParents(parent);
        if (File.Exists(destination) || Directory.Exists(destination))
            throw new GameplayExportException("gameplayExport.file_exists");
        string? temporary = null;
        try
        {
            cancellation.ThrowIfCancellationRequested();
            if (!canCommit()) throw new GameplayExportException("gameplayExport.account_changed");
            temporary = Path.Combine(parent, $".starbridge-export-{Guid.NewGuid():N}.tmp");
            var bytes = JsonSerializer.SerializeToUtf8Bytes(data,
                new JsonSerializerOptions(JsonSerializerDefaults.Web) { WriteIndented = true });
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                       FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckParents(parent);
            cancellation.ThrowIfCancellationRequested();
            if (!canCommit()) throw new GameplayExportException("gameplayExport.account_changed");
            // Atomic publication of a new file; never replace any existing user file.
            File.Move(temporary, destination, overwrite: false);
            temporary = null;
        }
        catch (IOException) when (File.Exists(destination) || Directory.Exists(destination))
        { throw new GameplayExportException("gameplayExport.file_exists"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    private static void CheckParents(string directory)
    {
        for (var current = new DirectoryInfo(directory); current is not null; current = current.Parent)
        {
            if (!current.Exists || current.Attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new GameplayExportException("gameplayExport.invalid_destination");
        }
    }
}
