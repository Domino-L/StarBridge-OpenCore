namespace StarBridge.HostRuntime.Reminders;

/// <summary>One device-local driver; never constructs a gameplay statistics recorder.</summary>
public sealed class ContinuousPlayReminderDriver : IDisposable
{
    private readonly ITimer _timer;
    private readonly CancellationTokenSource _stop = new();
    public ContinuousPlayReminderDriver(ContinuousPlayReminderRuntime runtime, TimeProvider? time = null)
    {
        _timer = (time ?? TimeProvider.System).CreateTimer(_ => _ = Tick(runtime), null, TimeSpan.Zero, TimeSpan.FromSeconds(5));
    }
    private async Task Tick(ContinuousPlayReminderRuntime runtime)
    {
        try { await runtime.TickAsync(_stop.Token); }
        catch (OperationCanceledException) { }
    }
    public void Dispose() { _timer.Dispose(); _stop.Cancel(); }
}
