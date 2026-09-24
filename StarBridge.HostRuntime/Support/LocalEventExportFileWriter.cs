using System.Text;

namespace StarBridge.HostRuntime.Support;

// Kept separate from the frozen JSON gameplay exporter. Only normalized journal
// text reaches this writer; paths never come from a Bridge payload.
internal sealed class LocalEventExportFileWriter(string protectedDataRoot)
{
    private readonly string _root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(protectedDataRoot));

    internal void WriteNew(string destination, string text, Func<bool> current, CancellationToken cancellation)
    {
        if (!Path.IsPathFullyQualified(destination) || destination.StartsWith("\\\\", StringComparison.Ordinal) ||
            !string.Equals(Path.GetExtension(destination), ".txt", StringComparison.OrdinalIgnoreCase) ||
            Path.GetFileName(destination).IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
            throw new LocalEventExportException("invalid_destination");
        destination = Path.GetFullPath(destination);
        if (destination.Equals(_root, StringComparison.OrdinalIgnoreCase) ||
            destination.StartsWith(_root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new LocalEventExportException("invalid_destination");
        var parent = Path.GetDirectoryName(destination)!;
        CheckParents(parent);
        if (File.Exists(destination) || Directory.Exists(destination)) throw new LocalEventExportException("file_exists");
        string? temporary = null;
        try
        {
            Guard();
            temporary = Path.Combine(parent, $".starbridge-events-{Guid.NewGuid():N}.tmp");
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                       FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(Encoding.UTF8.GetPreamble());
                stream.Write(Encoding.UTF8.GetBytes(text));
                stream.Flush(true);
            }
            CheckParents(parent);
            Guard();
            File.Move(temporary, destination, overwrite: false);
            temporary = null;
        }
        catch (IOException) when (File.Exists(destination) || Directory.Exists(destination))
        { throw new LocalEventExportException("file_exists"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        void Guard()
        {
            cancellation.ThrowIfCancellationRequested();
            if (!current()) throw new LocalEventExportException("unavailable");
        }
    }

    private static void CheckParents(string directory)
    {
        for (var current = new DirectoryInfo(directory); current is not null; current = current.Parent)
            if (!current.Exists || current.Attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new LocalEventExportException("invalid_destination");
    }
}

internal sealed class LocalEventExportException(string code) : Exception(code)
{
    internal string Code { get; } = "localEventsExport." + code;
}
