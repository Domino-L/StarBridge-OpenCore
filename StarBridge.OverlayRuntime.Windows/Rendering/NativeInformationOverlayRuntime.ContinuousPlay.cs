namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;

public sealed partial class NativeInformationOverlayRuntime : IContinuousPlayReminderSink
{
    public Func<ContinuousPlayNotificationContent, Func<bool>, CancellationToken, Task<bool>>? ContinuousPlayCard { get; set; }

    public ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation) =>
        DispatchContinuousPlayAsync(notice, _disposed ? null : ContinuousPlayCard, cancellation);

    // A rejected card never falls back to either overlay event box.
    internal static async ValueTask<bool> DispatchContinuousPlayAsync(ContinuousPlayNotice notice,
        Func<ContinuousPlayNotificationContent, Func<bool>, CancellationToken, Task<bool>>? card,
        CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!notice.IsCurrent() || card is null) return false;
        return await card(new(notice.Duration), notice.IsCurrent, cancellation).ConfigureAwait(false);
    }
}
