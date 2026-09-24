namespace StarBridge.NativeHost;

internal sealed record NativeHostStartupOptions(
    string PipeName,
    int ParentProcessId)
{
    internal static bool TryParse(
        IReadOnlyList<string> arguments,
        out NativeHostStartupOptions? options)
    {
        options = null;
        string? pipeName = null;
        int? parentProcessId = null;
        foreach (var argument in arguments)
        {
            if (argument.StartsWith("--pipe-name=", StringComparison.Ordinal))
            {
                if (pipeName is not null)
                {
                    return false;
                }

                pipeName = argument["--pipe-name=".Length..].Trim();
                continue;
            }

            if (argument.StartsWith("--parent-pid=", StringComparison.Ordinal))
            {
                if (parentProcessId is not null ||
                    !int.TryParse(argument["--parent-pid=".Length..], out var parsed) ||
                    parsed <= 0)
                {
                    return false;
                }

                parentProcessId = parsed;
                continue;
            }

            return false;
        }

        if (string.IsNullOrWhiteSpace(pipeName) ||
            pipeName.Contains('\\') ||
            pipeName.Contains('/') ||
            parentProcessId is null)
        {
            return false;
        }

        options = new NativeHostStartupOptions(pipeName, parentProcessId.Value);
        return true;
    }
}
