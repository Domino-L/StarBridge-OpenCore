namespace StarBridge.HostRuntime.Onboarding;

// One line per change of the installed game-identity gate's reason code.
// Reason codes only: never a handle, profile, source, path or account value.
internal static class FirstUseIdentityDiagnostics
{
    internal const string FileName = "first-use-identity-diagnostics.log";
    private const long MaximumBytes = 64 * 1024;
    private static readonly object Gate = new();
    private static string? _last;

    internal static string? Last { get { lock (Gate) return _last; } }

    internal static void Note(string reason)
    {
        lock (Gate)
        {
            if (reason == _last) return;
            var previous = _last;
            _last = reason;
            try
            {
                var directory = HostDataRoot.CurrentRoot;
                Directory.CreateDirectory(directory);
                var path = Path.Combine(directory, FileName);
                if (File.Exists(path) && new FileInfo(path).Length > MaximumBytes) File.Delete(path);
                File.AppendAllText(path, $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz}] installedIdentity " +
                    $"from={previous ?? "start"} to={reason}" + Environment.NewLine);
            }
            catch
            {
                // Diagnostics never change the gate's answer.
            }
        }
    }
}
