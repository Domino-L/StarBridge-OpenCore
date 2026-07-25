using System.IO;
using System.IO.Compression;

namespace StarBridge.Desktop;

internal static class PortableUpdateStager
{
    private const string ApplicationExecutableName = "Star Bridge.exe";

    public static Task<string> PrepareAsync(
        string packagePath,
        string stagingDirectory,
        CancellationToken cancellationToken = default)
    {
        return Task.Run(
            () => Prepare(packagePath, stagingDirectory, cancellationToken),
            cancellationToken);
    }

    internal static string Prepare(
        string packagePath,
        string stagingDirectory,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(packagePath))
        {
            throw new FileNotFoundException("Portable update package was not found.", packagePath);
        }

        var fullStagingDirectory = Path.GetFullPath(stagingDirectory);
        var preparingDirectory = fullStagingDirectory + ".preparing";
        DeleteDirectoryIfPresent(preparingDirectory);
        Directory.CreateDirectory(preparingDirectory);

        try
        {
            ExtractSafely(packagePath, preparingDirectory, cancellationToken);
            var sourceDirectory = FindApplicationDirectory(preparingDirectory);
            var relativeSourceDirectory = Path.GetRelativePath(preparingDirectory, sourceDirectory);

            DeleteDirectoryIfPresent(fullStagingDirectory);
            Directory.Move(preparingDirectory, fullStagingDirectory);
            return relativeSourceDirectory == "."
                ? fullStagingDirectory
                : Path.Combine(fullStagingDirectory, relativeSourceDirectory);
        }
        catch
        {
            DeleteDirectoryIfPresent(preparingDirectory);
            throw;
        }
    }

    private static void ExtractSafely(
        string packagePath,
        string destinationRoot,
        CancellationToken cancellationToken)
    {
        var normalizedRoot = Path.GetFullPath(destinationRoot)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;

        using var archive = ZipFile.OpenRead(packagePath);
        foreach (var entry in archive.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationPath = Path.GetFullPath(Path.Combine(destinationRoot, entry.FullName));
            if (!destinationPath.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException($"Update package contains an unsafe path: {entry.FullName}");
            }

            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destinationPath);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath) ?? destinationRoot);
            entry.ExtractToFile(destinationPath, overwrite: true);
        }
    }

    private static string FindApplicationDirectory(string root)
    {
        var rootExecutable = Path.Combine(root, ApplicationExecutableName);
        if (File.Exists(rootExecutable))
        {
            return root;
        }

        var executable = Directory
            .EnumerateFiles(root, ApplicationExecutableName, SearchOption.AllDirectories)
            .FirstOrDefault();
        if (executable is null)
        {
            throw new InvalidDataException($"Update package does not contain {ApplicationExecutableName}.");
        }

        return Path.GetDirectoryName(executable)
            ?? throw new InvalidDataException("Update package application directory is invalid.");
    }

    private static void DeleteDirectoryIfPresent(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }
}
