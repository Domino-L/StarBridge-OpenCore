namespace StarBridge.HostRuntime.Overlay;

// Only trusted Host events cross this seam; Flutter cannot supply text or ownership.
public sealed record InformationOverlayReminder(Guid Id, int Invitations, int Applications,
    string Preview, Func<bool> IsCurrent);

public interface IInformationOverlayReminderSink
{
    // True means submitted to the existing visible renderer, not proof of a visible frame.
    // Never opens a window, queues for later, plays audio, or changes unread/business state.
    ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken cancellationToken);
    void ClearReminder();
}
