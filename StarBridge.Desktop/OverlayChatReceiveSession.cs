namespace StarBridge.Desktop;

public sealed class OverlayChatReceiveSession
{
    private string _roomId = "";
    private long _version;
    private long _baselineSequence;
    private bool _baselineReady;

    public long Version => _version;

    public long Begin(string? roomId)
    {
        _version++;
        _roomId = roomId?.Trim() ?? "";
        _baselineSequence = 0;
        _baselineReady = false;
        return _version;
    }

    public bool TryEstablishBaseline(string roomId, long version, long latestSequence)
    {
        if (!IsCurrent(roomId, version))
        {
            return false;
        }

        if (!_baselineReady)
        {
            _baselineSequence = System.Math.Max(0, latestSequence);
            _baselineReady = true;
        }

        return true;
    }

    public bool Accepts(string roomId, long sequence) =>
        _baselineReady &&
        _roomId.Equals(roomId, System.StringComparison.OrdinalIgnoreCase) &&
        sequence > _baselineSequence;

    private bool IsCurrent(string roomId, long version) =>
        version == _version &&
        !string.IsNullOrWhiteSpace(_roomId) &&
        _roomId.Equals(roomId, System.StringComparison.OrdinalIgnoreCase);
}
