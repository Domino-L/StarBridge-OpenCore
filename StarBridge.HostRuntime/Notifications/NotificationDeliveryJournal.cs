namespace StarBridge.HostRuntime.Notifications;

using System.Runtime.CompilerServices;
using StarBridge.NativeBridge;

internal enum NotificationDeliveryChannel { Audio, Desktop, Activity }
internal enum NotificationDeliveryStage
{
    NoFreshEvent, FreshEvent, SourceMuted, ChannelDisabled, EnvironmentSuppressed,
    Throttled, CueUnavailable, NativeAccepted, NativeRejected, Failed, Stale,
    BaselineEstablished, ContractUnavailable, InvalidResponse, NonAdvancingSnapshot, ContinuityReset, NativeLifecycle
}

/// <summary>Bounded local reason codes only: no owner, message, path or exception text.</summary>
internal sealed class NotificationDeliveryJournal(string root)
{
    private static readonly object Gate = new();
    private readonly string _root = Path.GetFullPath(root);
    private NotificationDeliveryStage? _last;
    private DateTimeOffset _lastAt;
    private string? _lastTrace;
    private NotificationDeliveryChannel? _lastChannel;
    private string? _lastResult;
    private static readonly ConditionalWeakTable<BridgeEnvelope, Trace> Traces = new();
    private sealed class Trace { internal readonly string Id = Guid.NewGuid().ToString("N"); }
    // Process-local opaque ID for one authenticated read batch, not an account/message identifier.
    internal static string TraceFor(BridgeEnvelope request) => Traces.GetValue(request, _ => new Trace()).Id;
    internal void Record(NotificationDeliveryChannel channel, NotificationDeliveryStage stage,
        string? trace = null, string? transport = null, string? result = null, string? defaultEndpoint = null)
    {
        try {
            lock (Gate) {
                var now = DateTimeOffset.UtcNow;
                if (_last == stage && _lastChannel == channel && _lastTrace == trace && _lastResult == result && now - _lastAt < TimeSpan.FromSeconds(15)) return;
                var path = Path.Combine(_root, "notification-delivery-diagnostics.log");
                for (var directory = new DirectoryInfo(_root); directory is not null; directory = directory.Parent)
                    if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
                Directory.CreateDirectory(_root);
                var safeTrace = Guid.TryParseExact(trace, "N", out var id) ? id.ToString("N") : "none";
                var safeTransport = transport is "winmmPlaySound" or "wpfCard" ? transport : "unknown";
                var safeResult = result is "submitted" or "unavailable" or "expired" or "queueFull" or
                    "acceptedUnverified" or "rejected" or "queued" or "windowShown" or "systemSuppressed" or
                    "appForeground" or "gameRunning" or "doNotDisturb" or "systemBusy" or "fullScreen" or
                    "inactiveDesktop" or "quietTime" or "unsupported" or "gameActiveOrUnknown" or "appActiveOrUnknown" or
                    "contentRendered" or "showFailed" or "removed" or "elapsed" or "cleared" or "placementFailed" or
                    "sourceChanged" or "environmentUnknown" or "Online" or "Offline" or "StartedGame" or "StoppedGame" or
                    "avatarMissing" or "avatarDecodeFailed" or "avatarDecoded"
                    ? result : "unknown";
                var endpoint = defaultEndpoint is { Length: 16 } && defaultEndpoint.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F')
                    ? defaultEndpoint : "unavailable";
                var line = $"{now:O} {channel} {stage} trace={safeTrace} transport={safeTransport} result={safeResult} defaultMultimediaEndpoint={endpoint}{Environment.NewLine}";
                if (File.Exists(path) && new FileInfo(path).Length >= 256 * 1024)
                    File.WriteAllText(path, line);
                else File.AppendAllText(path, line);
                _last = stage; _lastAt = now; _lastTrace = trace; _lastChannel = channel; _lastResult = result;
            }
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) {
            // Diagnostics never changes notification or message delivery.
        }
    }
}
