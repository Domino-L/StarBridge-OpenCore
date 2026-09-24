using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

internal static class InstalledUpdateFiles
{
    internal const string Prefix = ".starbridge-installed-update-";
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };

    internal static string Normalize(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal)) throw new InvalidDataException();
        var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        if (full == Path.GetPathRoot(full)) throw new InvalidDataException();
        return full;
    }

    internal static void Plain(string path)
    {
        path = Normalize(path);
        for (var entry = new DirectoryInfo(path); entry is not null; entry = entry.Parent)
            if (entry.Exists && (entry.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update path.");
        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update file.");
    }

    internal static void Tree(string root)
    {
        Plain(root);
        if (!Directory.Exists(root)) throw new DirectoryNotFoundException();
        var pending = new Stack<string>();
        pending.Push(root);
        var count = 0;
        long bytes = 0;
        while (pending.TryPop(out var directory))
        foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
        {
            if (++count > 50000) throw new IOException("Update tree is too large.");
            var attributes = File.GetAttributes(entry);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update tree.");
            if ((attributes & FileAttributes.Directory) != 0) pending.Push(entry);
            else if ((bytes += new FileInfo(entry).Length) > 8L * 1024 * 1024 * 1024) throw new IOException("Update tree is too large.");
        }
    }

    internal static void RequireSibling(string installation, string root)
    {
        if (Normalize(installation) != installation || Normalize(root) != root ||
            !string.Equals(Path.GetDirectoryName(installation), Path.GetDirectoryName(root), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(root).StartsWith(Prefix, StringComparison.Ordinal) ||
            !Guid.TryParseExact(Path.GetFileName(root)[Prefix.Length..], "N", out _)) throw new InvalidDataException("Invalid update workspace.");
        Plain(installation); Plain(root);
    }

    internal static T Read<T>(string path, int maximum = 131072)
    {
        Plain(path);
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length > maximum) throw new InvalidDataException("Oversized update record.");
        using var document = JsonDocument.Parse(file);
        RejectDuplicates(document.RootElement);
        return document.RootElement.Deserialize<T>(Json) ?? throw new InvalidDataException();
    }

    private static void RejectDuplicates(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object) {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in value.EnumerateObject()) {
                if (!names.Add(item.Name)) throw new InvalidDataException("Ambiguous update record.");
                RejectDuplicates(item.Value);
            }
        } else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) RejectDuplicates(item);
    }

    internal static void Write<T>(string path, T value, bool replace = false)
    {
        Plain(Path.GetDirectoryName(path)!); Plain(path);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
            JsonSerializer.Serialize(file, value, Json); file.Flush(true);
        }
        File.Move(temporary, path, overwrite: replace);
    }
}
