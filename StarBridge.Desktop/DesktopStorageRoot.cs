using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace StarBridge.Desktop;

internal sealed record DesktopStorageMigrationResult(
    string SourceRoot,
    string DestinationRoot,
    int FileCount,
    long ByteCount,
    bool SourceCleanupCompleted);

internal static class DesktopStorageRoot
{
    internal const string DebugDataRootEnvironmentVariable = "STARBRIDGE_DEBUG_DATA_ROOT";
    internal const string LocatorFileName = "data-root.path";
    internal const string PendingLocatorFileName = "pending-data-root.path";
    internal const string FailedPendingLocatorFileName = "failed-data-root.path";

    private static readonly StringComparer PathComparer = StringComparer.OrdinalIgnoreCase;
    private static readonly UTF8Encoding StrictUtf8 = new(
        encoderShouldEmitUTF8Identifier: false,
        throwOnInvalidBytes: true);
    private static string? _currentRoot;

    internal static string BootstrapDirectory { get; } = ResolveBootstrapDirectory();

    internal static string DefaultRoot => BootstrapDirectory;

    internal static string CurrentRoot =>
        _currentRoot ??= ResolveConfiguredRoot(BootstrapDirectory);

    private static string ResolveBootstrapDirectory()
    {
#if DEBUG
        var debugRoot = Environment.GetEnvironmentVariable(DebugDataRootEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(debugRoot))
        {
            return NormalizeDirectory(debugRoot);
        }
#endif

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "StarBridge");
    }

    internal static void SetCurrentRootForTests(string root)
    {
        _currentRoot = NormalizeDirectory(root);
        Directory.CreateDirectory(_currentRoot);
    }

    internal static bool TryPrepareForStartup(
        out DesktopStorageMigrationResult? migration,
        out string? warning,
        out string? error)
    {
        migration = null;
        warning = null;
        error = null;

        try
        {
            Directory.CreateDirectory(BootstrapDirectory);
            var sourceRoot = ResolveConfiguredRoot(BootstrapDirectory);
            var pendingPath = GetPendingLocatorPath(BootstrapDirectory);
            if (File.Exists(pendingPath))
            {
                try
                {
                    migration = ApplyPendingSelection(BootstrapDirectory, sourceRoot);
                    sourceRoot = migration.DestinationRoot;
                }
                catch (Exception ex)
                {
                    TryPreserveFailedPendingSelection(BootstrapDirectory);
                    warning = UserFacingError.Describe(
                        ex,
                        "数据目录迁移没有完成，星海舰桥将继续使用原目录。请确认目标磁盘可用且有足够空间后重试。");
                }
            }

            EnsureRootAvailable(sourceRoot);
            if (ContainsDamagedPathMarker(sourceRoot))
            {
                warning = "检测到数据目录路径曾被旧版安装器错误转码。现有数据仍会保留使用；请在“设置 → 常规与数据”中选择名称正常的空文件夹完成安全迁移。";
            }

            _currentRoot = sourceRoot;
            return true;
        }
        catch (Exception ex)
        {
            error = UserFacingError.Describe(
                ex,
                "星海舰桥的数据目录不可用。请重新连接对应磁盘，或恢复数据目录后再启动应用。");
            return false;
        }
    }

    internal static string ValidateMigrationDestination(string destinationRoot)
    {
        var sourceRoot = CurrentRoot;
        return ValidateMigrationDestination(sourceRoot, destinationRoot);
    }

    internal static void ScheduleMigration(string destinationRoot)
    {
        var normalized = ValidateMigrationDestination(destinationRoot);
        Directory.CreateDirectory(BootstrapDirectory);
        WriteTextAtomically(GetPendingLocatorPath(BootstrapDirectory), normalized);
    }

    internal static string ResolveConfiguredRoot(string bootstrapDirectory)
    {
        var normalizedBootstrap = NormalizeDirectory(bootstrapDirectory);
        var locatorPath = GetLocatorPath(normalizedBootstrap);
        if (!File.Exists(locatorPath))
        {
            return normalizedBootstrap;
        }

        var configured = ReadPathFile(locatorPath);
        if (string.IsNullOrWhiteSpace(configured))
        {
            throw new InvalidDataException("数据目录指针为空。请恢复 data-root.path 的有效绝对路径。");
        }

        return NormalizeDirectory(configured);
    }

    internal static DesktopStorageMigrationResult ApplyPendingSelection(
        string bootstrapDirectory,
        string sourceRoot)
    {
        var normalizedBootstrap = NormalizeDirectory(bootstrapDirectory);
        var normalizedSource = NormalizeDirectory(sourceRoot);
        var pendingPath = GetPendingLocatorPath(normalizedBootstrap);
        if (!File.Exists(pendingPath))
        {
            throw new FileNotFoundException("没有待处理的数据目录迁移请求。", pendingPath);
        }

        var requested = ReadPathFile(pendingPath);
        var destinationRoot = ValidateMigrationDestination(normalizedSource, requested);
        if (PathEquals(normalizedSource, destinationRoot))
        {
            File.Delete(pendingPath);
            return new DesktopStorageMigrationResult(
                normalizedSource,
                destinationRoot,
                FileCount: 0,
                ByteCount: 0,
                SourceCleanupCompleted: true);
        }

        var copied = CopyAndVerify(normalizedBootstrap, normalizedSource, destinationRoot);
        var pointerSwitched = false;
        try
        {
            WriteTextAtomically(GetLocatorPath(normalizedBootstrap), destinationRoot);
            pointerSwitched = true;
            File.Delete(pendingPath);
        }
        catch
        {
            if (!pointerSwitched)
            {
                TryDeleteDirectory(destinationRoot);
            }

            throw;
        }

        var cleanupCompleted = TryCleanupSource(normalizedBootstrap, normalizedSource);
        return copied with { SourceCleanupCompleted = cleanupCompleted };
    }

    internal static string ValidateMigrationDestination(string sourceRoot, string destinationRoot)
    {
        var normalizedSource = NormalizeDirectory(sourceRoot);
        var normalizedDestination = NormalizeDirectory(destinationRoot);
        if (ContainsDamagedPathMarker(normalizedDestination))
        {
            throw new InvalidOperationException("所选路径包含损坏的替换字符，请重新选择名称正常的文件夹。中文目录本身受支持。");
        }

        var root = Path.GetPathRoot(normalizedDestination);
        if (PathEquals(normalizedDestination, root))
        {
            throw new InvalidOperationException("不能直接使用磁盘根目录，请选择或新建一个专用文件夹。");
        }

        if (PathEquals(normalizedSource, normalizedDestination))
        {
            return normalizedDestination;
        }

        if (IsNestedPath(normalizedSource, normalizedDestination) ||
            IsNestedPath(normalizedDestination, normalizedSource))
        {
            throw new InvalidOperationException("新旧数据目录不能互相包含，请选择另一个独立文件夹。");
        }

        EnsureDriveAvailable(normalizedDestination);
        if (Directory.Exists(normalizedDestination))
        {
            var attributes = File.GetAttributes(normalizedDestination);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidOperationException("数据目录不能是符号链接或重解析点。");
            }

            if (Directory.EnumerateFileSystemEntries(normalizedDestination).Any())
            {
                throw new InvalidOperationException("目标文件夹必须为空，避免覆盖其他文件或混入旧数据。");
            }
        }

        return normalizedDestination;
    }

    private static DesktopStorageMigrationResult CopyAndVerify(
        string bootstrapDirectory,
        string sourceRoot,
        string destinationRoot)
    {
        EnsureRootAvailable(sourceRoot);
        EnsureDestinationWritable(destinationRoot);

        var stagingRoot = destinationRoot + $".starbridge-migration-{Guid.NewGuid():N}";
        Directory.CreateDirectory(stagingRoot);
        try
        {
            var sourceFiles = EnumerateMovableFiles(bootstrapDirectory, sourceRoot)
                .Select(path => new FileSnapshot(path, Path.GetRelativePath(sourceRoot, path)))
                .OrderBy(item => item.RelativePath, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            long byteCount = 0;

            foreach (var item in sourceFiles)
            {
                var targetPath = Path.Combine(stagingRoot, item.RelativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
                File.Copy(item.SourcePath, targetPath, overwrite: false);
                byteCount += new FileInfo(item.SourcePath).Length;
            }

            foreach (var item in sourceFiles)
            {
                var copiedPath = Path.Combine(stagingRoot, item.RelativePath);
                if (!File.Exists(copiedPath) || !HashesMatch(item.SourcePath, copiedPath))
                {
                    throw new IOException($"迁移校验失败：{item.RelativePath}");
                }
            }

            if (Directory.Exists(destinationRoot))
            {
                Directory.Delete(destinationRoot, recursive: false);
            }

            Directory.Move(stagingRoot, destinationRoot);
            return new DesktopStorageMigrationResult(
                sourceRoot,
                destinationRoot,
                sourceFiles.Length,
                byteCount,
                SourceCleanupCompleted: false);
        }
        catch
        {
            TryDeleteDirectory(stagingRoot);
            throw;
        }
    }

    private static IEnumerable<string> EnumerateMovableFiles(string bootstrapDirectory, string sourceRoot)
    {
        if (!Directory.Exists(sourceRoot))
        {
            yield break;
        }

        foreach (var path in Directory.EnumerateFiles(sourceRoot, "*", SearchOption.AllDirectories))
        {
            if (PathEquals(sourceRoot, bootstrapDirectory) && IsBootstrapOwnedPath(sourceRoot, path))
            {
                continue;
            }

            yield return path;
        }
    }

    private static bool TryCleanupSource(string bootstrapDirectory, string sourceRoot)
    {
        try
        {
            foreach (var file in EnumerateMovableFiles(bootstrapDirectory, sourceRoot).ToArray())
            {
                File.Delete(file);
            }

            foreach (var directory in Directory
                         .EnumerateDirectories(sourceRoot, "*", SearchOption.AllDirectories)
                         .OrderByDescending(path => path.Length))
            {
                if (PathEquals(sourceRoot, bootstrapDirectory) && IsBootstrapOwnedPath(sourceRoot, directory))
                {
                    continue;
                }

                if (!Directory.EnumerateFileSystemEntries(directory).Any())
                {
                    Directory.Delete(directory, recursive: false);
                }
            }

            if (!PathEquals(sourceRoot, bootstrapDirectory) &&
                Directory.Exists(sourceRoot) &&
                !Directory.EnumerateFileSystemEntries(sourceRoot).Any())
            {
                Directory.Delete(sourceRoot, recursive: false);
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsBootstrapOwnedPath(string bootstrapDirectory, string path)
    {
        var relative = Path.GetRelativePath(bootstrapDirectory, path);
        var firstSegment = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
        if (firstSegment.Equals("Updates", StringComparison.OrdinalIgnoreCase) ||
            firstSegment.Equals("Installer", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return relative.Equals(LocatorFileName, StringComparison.OrdinalIgnoreCase) ||
               relative.Equals(PendingLocatorFileName, StringComparison.OrdinalIgnoreCase) ||
               relative.Equals(FailedPendingLocatorFileName, StringComparison.OrdinalIgnoreCase) ||
               relative.Equals("desktop-crash.log", StringComparison.OrdinalIgnoreCase) ||
               relative.Equals("desktop-overlay-diagnostics.log", StringComparison.OrdinalIgnoreCase);
    }

    private static void TryPreserveFailedPendingSelection(string bootstrapDirectory)
    {
        try
        {
            var pendingPath = GetPendingLocatorPath(bootstrapDirectory);
            if (!File.Exists(pendingPath))
            {
                return;
            }

            File.Move(
                pendingPath,
                Path.Combine(bootstrapDirectory, FailedPendingLocatorFileName),
                overwrite: true);
        }
        catch
        {
            // The migration error remains the primary failure. Leaving the
            // pending file in place is safer than masking it with bookkeeping.
        }
    }

    private static void EnsureRootAvailable(string root)
    {
        EnsureDriveAvailable(root);
        Directory.CreateDirectory(root);
        var attributes = File.GetAttributes(root);
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException("数据目录不能是符号链接或重解析点。");
        }
    }

    private static void EnsureDestinationWritable(string destinationRoot)
    {
        Directory.CreateDirectory(destinationRoot);
        var probePath = Path.Combine(destinationRoot, $".starbridge-write-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(probePath, "StarBridge");
            File.Delete(probePath);
        }
        catch
        {
            TryDeleteFile(probePath);
            throw;
        }
    }

    private static void EnsureDriveAvailable(string path)
    {
        var root = Path.GetPathRoot(path);
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
        {
            throw new DirectoryNotFoundException($"数据目录所在磁盘不可用：{root ?? path}");
        }
    }

    private static bool HashesMatch(string firstPath, string secondPath)
    {
        using var first = File.OpenRead(firstPath);
        using var second = File.OpenRead(secondPath);
        return SHA256.HashData(first).AsSpan().SequenceEqual(SHA256.HashData(second));
    }

    private static void WriteTextAtomically(string path, string value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = path + $".{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllText(temporaryPath, value + Environment.NewLine, StrictUtf8);
            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            TryDeleteFile(temporaryPath);
        }
    }

    private static string ReadPathFile(string path)
    {
        var bytes = File.ReadAllBytes(path);
        string value;
        try
        {
            value = StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            var ansiCodePage = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ANSICodePage;
            value = Encoding.GetEncoding(
                ansiCodePage,
                EncoderFallback.ExceptionFallback,
                DecoderFallback.ExceptionFallback).GetString(bytes);
        }

        return value.Trim().TrimStart('\uFEFF');
    }

    private static bool ContainsDamagedPathMarker(string path) =>
        path.Contains('\uFFFD');

    private static string NormalizeDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new ArgumentException("数据目录不能为空。", nameof(path));
        }

        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(
            Environment.ExpandEnvironmentVariables(path.Trim())));
    }

    private static bool IsNestedPath(string parent, string candidate)
    {
        var parentWithSeparator = Path.EndsInDirectorySeparator(parent)
            ? parent
            : parent + Path.DirectorySeparatorChar;
        return candidate.StartsWith(parentWithSeparator, StringComparison.OrdinalIgnoreCase);
    }

    private static bool PathEquals(string? first, string? second)
    {
        if (string.IsNullOrWhiteSpace(first) || string.IsNullOrWhiteSpace(second))
        {
            return false;
        }

        return PathComparer.Equals(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(first)),
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(second)));
    }

    private static string GetLocatorPath(string bootstrapDirectory) =>
        Path.Combine(bootstrapDirectory, LocatorFileName);

    private static string GetPendingLocatorPath(string bootstrapDirectory) =>
        Path.Combine(bootstrapDirectory, PendingLocatorFileName);

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Best effort cleanup only.
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Best effort cleanup only.
        }
    }

    private sealed record FileSnapshot(string SourcePath, string RelativePath);
}
