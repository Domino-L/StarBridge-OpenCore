namespace StarBridge.HostRuntime.Support;

// Local reason-code journal. Diagnostics never affect business decisions.
// Records fixed stage/code tokens, booleans, enum names, HTTP status numbers and
// exception type names only. Never paths, handles, account ids, tokens, URLs or bodies.
internal static class IdentityGateJournal
{
    private static readonly object Gate = new();
    private static readonly AsyncLocal<Action<string, string>?> Sink = new();
    internal static IDisposable Capture(Action<string, string> sink)
    {
        var previous = Sink.Value;
        lock (Gate) Last.Clear(); // Each capture starts with fresh change tracking.
        Sink.Value = sink;
        return new CaptureScope(() => Sink.Value = previous);
    }
    private sealed class CaptureScope(Action restore) : IDisposable
    {
        public void Dispose() => restore();
    }
    private static string? _root;
    private static readonly Dictionary<string, string> Last = new(StringComparer.Ordinal);

    internal static void Configure(string? dataRoot)
    {
        lock (Gate) { _root = string.IsNullOrWhiteSpace(dataRoot) ? null : dataRoot; Last.Clear(); }
    }

    // Writes only when the value for this stage changed, so periodic paths stay quiet.
    internal static void Changed(string stage, string value)
    {
        lock (Gate)
        {
            if (_root is null && Sink.Value is null) return;
            if (Last.TryGetValue(stage, out var previous) && previous == value) return;
            Last[stage] = value;
            WriteCore(stage, value);
        }
    }

    internal static void Event(string stage, string value)
    {
        lock (Gate)
        {
            if (_root is null && Sink.Value is null) return;
            WriteCore(stage, value);
        }
    }

    internal static string Type(Exception error) => error.GetType().Name;

    private static void WriteCore(string stage, string value)
    {
        try
        {
            if (Sink.Value is { } sink) { sink(stage, value); return; }
            var directory = Path.GetFullPath(_root!);
            for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
            var path = Path.Combine(directory, "identity-gate-diagnostics.log");
            var backup = path + ".1";
            if (IsReparsePoint(path) || IsReparsePoint(backup)) return;
            var safe = new string(value.Where(c => c is >= ' ' and <= '~').Take(300).ToArray());
            var line = $"{DateTimeOffset.UtcNow:O} stage={stage} {safe}{Environment.NewLine}";
            if (File.Exists(path) && new FileInfo(path).Length + line.Length > 256 * 1024)
                File.Move(path, backup, overwrite: true);
            File.AppendAllText(path, line);
        }
        catch { /* Diagnostics must not affect business decisions, including injected sinks. */ }
    }

    private static bool IsReparsePoint(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
}
