using System.IO;
using System.Text;

namespace StarBridge.Desktop;

public static class GameLogInitialReplayReader
{
    public static IReadOnlyList<string> ReadHeadLines(string path, int maxBytes, int maxLines)
    {
        if (maxBytes <= 0 || maxLines <= 0)
        {
            return Array.Empty<string>();
        }

        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        var requestedLength = (int)Math.Min(stream.Length, maxBytes);
        var buffer = new byte[requestedLength];
        var bytesRead = 0;
        while (bytesRead < requestedLength)
        {
            var read = stream.Read(buffer, bytesRead, requestedLength - bytesRead);
            if (read == 0)
            {
                break;
            }

            bytesRead += read;
        }

        using var memory = new MemoryStream(buffer, 0, bytesRead, writable: false);
        using var reader = new StreamReader(memory, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        var lines = new List<string>(Math.Min(maxLines, 1024));
        while (lines.Count < maxLines && reader.ReadLine() is { } line)
        {
            lines.Add(line);
        }

        return lines;
    }

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
