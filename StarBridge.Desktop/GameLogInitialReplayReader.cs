using System.IO;
using System.Text;

namespace StarBridge.Desktop;

public static class GameLogInitialReplayReader
{
    public static IReadOnlyList<string> ReadTailLines(string path, int maxBytes, int maxLines)
    {
        if (maxLines <= 0)
        {
            return Array.Empty<string>();
        }

        var lines = new Queue<string>(maxLines);
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);

        var startPosition = Math.Max(0, stream.Length - Math.Max(1, maxBytes));
        stream.Position = startPosition;

        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        if (startPosition > 0)
        {
            reader.ReadLine();
        }

        while (reader.ReadLine() is { } line)
        {
            if (lines.Count == maxLines)
            {
                lines.Dequeue();
            }

            lines.Enqueue(line);
        }

        return lines.ToArray();
    }
}
