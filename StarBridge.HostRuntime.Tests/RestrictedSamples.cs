internal static class RestrictedSamples
{
    internal static string Read(string fileName)
    {
        // Find the checkout even when the runner is started outside the repository.
        var sourceRoot = Environment.GetEnvironmentVariable("STARBRIDGE_HOST_TEST_SOURCE_ROOT");
        if (string.IsNullOrWhiteSpace(sourceRoot))
        {
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            {
                if (IsSourceRoot(dir.FullName))
                {
                    sourceRoot = dir.FullName;
                    break;
                }
            }
        }

        if (string.IsNullOrWhiteSpace(sourceRoot) || !IsSourceRoot(sourceRoot))
            throw new InvalidOperationException("Could not locate the Host test source tree.");

        return ReadFile(Path.Combine(sourceRoot, "contracts", "achievements", fileName), fileName);
    }

    internal static string ReadFile(string path, string sampleName)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (IOException error) when (error is FileNotFoundException or DirectoryNotFoundException)
        {
            throw new RestrictedSampleAbsentException(sampleName);
        }
    }

    internal static void RequireCityLocationCatalog()
    {
        var resources = typeof(StarBridge.HostRuntime.Presence.GameLogRuntime).Assembly.GetManifestResourceNames();
        if (!resources.Contains("StarBridge.LocationHierarchy.json") &&
            !resources.Contains("StarBridge.LocationCatalog.json"))
        {
            throw new RestrictedSampleAbsentException("city location catalog", "data");
        }
    }

    private static bool IsSourceRoot(string path) =>
        Path.IsPathFullyQualified(path) &&
        File.Exists(Path.Combine(path, "StarBridge.HostRuntime.Tests", "StarBridge.HostRuntime.Tests.csproj"));
}

internal sealed class RestrictedSampleAbsentException(string name, string kind = "sample")
    : Exception($"open-core restricted {kind} {name} absent")
{
    internal void Report(string testName) => Console.WriteLine($"SKIP {testName}: {Message}");
}
