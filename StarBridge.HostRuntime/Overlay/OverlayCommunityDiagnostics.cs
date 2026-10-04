using System.Diagnostics.Tracing;

namespace StarBridge.HostRuntime.Overlay;

// Opt-in local timing evidence. No organization, account, message, URL or token
// fields; disabled by default and does not create persistent application logs.
[EventSource(Name = "StarBridge-OverlayCommunity")]
internal sealed class OverlayCommunityDiagnostics : EventSource
{
    internal static readonly OverlayCommunityDiagnostics Log = new();
    [Event(1, Level = EventLevel.Informational)]
    public void Read(string phase, string reason, long elapsedMs, long leaseRemainingMs)
    { if (IsEnabled()) WriteEvent(1, phase, reason, elapsedMs, leaseRemainingMs); }
}
