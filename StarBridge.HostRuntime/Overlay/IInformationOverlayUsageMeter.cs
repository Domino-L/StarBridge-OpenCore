namespace StarBridge.HostRuntime.Overlay;

// Time the information overlay has been open on this device, for the anonymous app-stats
// heartbeat. Open means opened by the user, shown or hidden behind the game; sleep and
// stalled periods are never counted.
public interface IInformationOverlayUsageMeter
{
    bool IsOverlayOpen { get; }

    // Whole seconds of open time since the previous call; the fraction carries over.
    long TakeOpenSeconds();
}
