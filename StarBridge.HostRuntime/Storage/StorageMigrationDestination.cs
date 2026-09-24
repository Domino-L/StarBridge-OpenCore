namespace StarBridge.HostRuntime.Storage;

/// <summary>Shared, read-only migration preflight. Does not create, copy or delete data.</summary>
public static class StorageMigrationDestination
{
    public static string Validate(string sourceRoot, string destinationRoot)
    {
        var source = Normalize(sourceRoot);
        var destination = Normalize(destinationRoot);
        if (destination.Contains('\uFFFD'))
            throw new InvalidOperationException("所选路径包含损坏字符，请重新选择名称正常的文件夹。中文目录受支持。");
        var root = Path.GetPathRoot(destination);
        if (Equal(destination, root))
            throw new InvalidOperationException("不能使用磁盘根目录，请选择一个专用文件夹。");
        if (Equal(source, destination)) return destination;
        if (Nested(source, destination) || Nested(destination, source))
            throw new InvalidOperationException("新旧数据目录不能互相包含。");
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            throw new DirectoryNotFoundException("目标磁盘不可用。");
        // Reject reparse points on every existing ancestor, not only the leaf.
        for (var current = destination; current is not null; current = Path.GetDirectoryName(current))
        {
            if (!Path.Exists(current)) continue;
            var attributes = File.GetAttributes(current);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("数据目录不能经过符号链接或重解析点。");
            if ((attributes & FileAttributes.Directory) == 0)
                throw new InvalidOperationException("目标路径必须是文件夹。");
        }
        if (Directory.Exists(destination) && Directory.EnumerateFileSystemEntries(destination).Any())
            throw new InvalidOperationException("目标文件夹必须为空，避免覆盖其他文件或混入旧数据。");
        return destination;
    }

    private static string Normalize(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("数据目录不能为空。");
        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        if (!Path.IsPathFullyQualified(expanded))
            throw new ArgumentException("数据目录必须是绝对路径。");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(expanded));
    }
    private static bool Equal(string first, string? second) =>
        string.Equals(first, second, StringComparison.OrdinalIgnoreCase);
    private static bool Nested(string parent, string child) =>
        child.StartsWith(Path.TrimEndingDirectorySeparator(parent) + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase);
}
