namespace StarBridge.Core.LogWatching;

public sealed class GameLogWatcher : IDisposable
{
    private readonly string _path;
    private readonly Action<string> _onLine;

    private readonly Timer _timer;

    private long _position;
    private int _polling;

    private bool _disposed;

    public GameLogWatcher(
        string path,
        bool replayExistingLines,
        Action<string> onLine)
    {
        _path = Path.GetFullPath(path);
        _onLine = onLine;

        var directory = Path.GetDirectoryName(_path);

        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new ArgumentException(
                "Log path must include a directory.",
                nameof(path));
        }

        Directory.CreateDirectory(directory);

        if (!File.Exists(_path))
        {
            File.WriteAllText(_path, string.Empty);
        }

        _position = replayExistingLines
            ? 0
            : new FileInfo(_path).Length;

        _timer = new Timer(
            PollLog,
            null,
            Timeout.Infinite,
            Timeout.Infinite);
    }

    public void Start()
    {
        PollLog(null);

        _timer.Change(
            dueTime: 100,
            period: 100);
    }

    private void PollLog(object? state)
    {
        if (_disposed || Interlocked.CompareExchange(ref _polling, 1, 0) != 0)
        {
            return;
        }

        try
        {
            ReadAvailableLines();
        }
        catch
        {
            // optional logging
        }
        finally
        {
            Volatile.Write(ref _polling, 0);
        }
    }

    private void ReadAvailableLines()
    {
        if (!File.Exists(_path))
        {
            return;
        }

        using var stream = new FileStream(
            _path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);

        if (stream.Length < _position)
        {
            _position = 0;
        }

        if (stream.Length == _position)
        {
            return;
        }

        stream.Position = _position;

        using var reader = new StreamReader(stream);

        while (reader.ReadLine() is { } line)
        {
            _onLine(line);
        }

        _position = stream.Position;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        _timer.Dispose();
    }
}
