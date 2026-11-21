namespace StarBridge.HostRuntime.HealthReading;

// The latest own-health reading inside this process, for the visor's own row only.
// Nothing here is serialized, relayed or shared; it lives in memory and is gone on exit.
internal sealed class SelfHealthReadingHub
{
    SelfHealthReading _current = SelfHealthReading.None;

    public SelfHealthReading Current => Volatile.Read(ref _current);

    // Raised on the reader thread; handlers must be quick and must not block.
    public event Action<SelfHealthReading>? Changed;

    public void Publish(SelfHealthReading reading)
    {
        Volatile.Write(ref _current, reading);
        try { Changed?.Invoke(reading); } catch (Exception) { }
    }
}
