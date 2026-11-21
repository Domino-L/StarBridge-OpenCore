using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.HealthReading;

// 11-17 user ("这台电脑在这个画面尺寸下清楚读出过数字，才启用"): the capture sizes at which this computer has read clear
// health digits. The new-life full from the log (SelfHealthFullHold) shows only at such a size, so a picture size the
// reader cannot read never shows a full it cannot check. Only sizes are kept ("1350x735", one per line), no image and
// no value: self-health-readable-sizes.txt in the data root (with no data root, for this run only).
internal sealed class SelfHealthReadableSizes
{
    internal const string FileName = "self-health-readable-sizes.txt";
    internal const int MaximumSizes = 32;
    internal const int SmallestSide = 32, LargestSide = 20000;
    internal const int MaximumFileBytes = 4096;
    // One size per line, as written: digits without a leading zero, "x", digits (review R1 P3).
    static readonly Regex Line = new(@"^([1-9][0-9]{1,4})x([1-9][0-9]{1,4})$", RegexOptions.CultureInvariant);

    readonly string? _root;
    readonly object _gate = new();
    readonly HashSet<(int Width, int Height)> _sizes = new();
    bool _loaded;

    public SelfHealthReadableSizes(string? root) { _root = root; }

    internal static bool Valid((int Width, int Height) size) =>
        size.Width is >= SmallestSide and <= LargestSide && size.Height is >= SmallestSide and <= LargestSide;

    public bool Contains((int Width, int Height) size)
    {
        if (!Valid(size)) return false;
        lock (_gate) { Load(); return _sizes.Contains(size); }
    }

    // Clear digits were read at this size.
    public void Add((int Width, int Height) size)
    {
        if (!Valid(size)) return;
        lock (_gate)
        {
            Load();
            if (_sizes.Count >= MaximumSizes || !_sizes.Add(size)) return;
            Save();
        }
    }

    string? PathOrNull()
    {
        if (_root == null) return null;
        try
        {
            var directory = Path.GetFullPath(_root);
            for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return null;
            var path = Path.Combine(directory, FileName);
            if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return null;
            return path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException
            or ArgumentException or NotSupportedException) { return null; }
    }

    // Called under _gate.
    void Load()
    {
        if (_loaded) return;
        _loaded = true;
        var path = PathOrNull();
        if (path == null) return;
        try
        {
            if (!File.Exists(path)) return;
            // At most MaximumFileBytes are used: one byte more is read only to tell that the file is larger, and then
            // nothing in it is used (review R1 P3).
            var buffer = new byte[MaximumFileBytes + 1];
            int length = 0;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                for (int n; length < buffer.Length && (n = stream.Read(buffer, length, buffer.Length - length)) > 0;) length += n;
            if (length > MaximumFileBytes) return;
            foreach (var line in Encoding.ASCII.GetString(buffer, 0, length).Split('\n'))
            {
                if (_sizes.Count >= MaximumSizes) break;
                // one "\r" before the "\n" at most, as Windows tools write it (review R2 P3)
                var match = Line.Match(line.EndsWith('\r') ? line[..^1] : line);
                if (match.Success
                    && int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var width)
                    && int.TryParse(match.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var height)
                    && Valid((width, height)))
                    _sizes.Add((width, height));
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }

    // Called under _gate.
    void Save()
    {
        var path = PathOrNull();
        if (path == null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var text = string.Concat(_sizes.Select(s => string.Create(CultureInfo.InvariantCulture, $"{s.Width}x{s.Height}\n")));
            // A new temporary file each time, created only if nothing is there (review R1 P2: never write through an
            // existing file or link), then moved over the list.
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    stream.Write(Encoding.ASCII.GetBytes(text));
                File.Move(temporary, path, overwrite: true);
            }
            finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { } }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
