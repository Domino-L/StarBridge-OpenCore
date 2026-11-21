internal static class HostTestSource
{
    private const string ProjectPath = "StarBridge.HostRuntime.Tests/StarBridge.HostRuntime.Tests.csproj";

    internal static string Root
    {
        get
        {
            var explicitRoot = Environment.GetEnvironmentVariable("STARBRIDGE_HOST_TEST_SOURCE_ROOT");
            if (string.IsNullOrWhiteSpace(explicitRoot)) return FindRoot(AppContext.BaseDirectory);
            if (!Path.IsPathFullyQualified(explicitRoot) || !IsTestCheckout(explicitRoot))
                throw new InvalidOperationException("Invalid explicit Host test source root.");
            return Path.GetFullPath(explicitRoot);
        }
    }

    internal static string FindRoot(string start)
    {
        for (var directory = new DirectoryInfo(start); directory is not null; directory = directory.Parent)
        {
            var root = directory.FullName;
            if (IsTestCheckout(root)) return root;
            var git = Path.Combine(root, ".git");
            if (Directory.Exists(git) || File.Exists(git) || File.Exists(Path.Combine(root, "StarBridge.sln")))
                break;
        }

        throw new InvalidOperationException("Could not locate the Host test source tree from " + start);
    }

    private static bool IsTestCheckout(string path) => File.Exists(Path.Combine(path, ProjectPath));
}
