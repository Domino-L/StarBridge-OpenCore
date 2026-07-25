namespace StarBridge.Desktop;

internal sealed class OverlayBarrageTextMeasurementCache
{
    private const int MaximumEntries = 512;
    private readonly Dictionary<MeasurementKey, float> _measurements = [];

    public float GetOrAdd(
        string text,
        float fontSize,
        int formatRole,
        Func<float> measure)
    {
        var key = new MeasurementKey(text ?? string.Empty, fontSize, formatRole);
        if (_measurements.TryGetValue(key, out var cached))
        {
            return cached;
        }

        if (_measurements.Count >= MaximumEntries)
        {
            _measurements.Clear();
        }

        var value = measure();
        _measurements[key] = value;
        return value;
    }

    public void Clear()
    {
        _measurements.Clear();
    }

    private readonly record struct MeasurementKey(string Text, float FontSize, int FormatRole);
}
