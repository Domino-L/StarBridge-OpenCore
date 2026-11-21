internal static class RestrictedSamples
{
    internal static string Read(string fileName) =>
        ReadFile(Path.Combine(HostTestSource.Root, "contracts", "achievements", fileName), fileName);

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
}

internal sealed class RestrictedSampleAbsentException(string name, string kind = "sample")
    : Exception($"open-core restricted {kind} {name} absent")
{
    internal void Report(string testName) => Console.WriteLine($"SKIP {testName}: {Message}");
}
