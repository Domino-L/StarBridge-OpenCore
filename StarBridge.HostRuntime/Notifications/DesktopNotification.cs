namespace StarBridge.HostRuntime.Notifications;

/// <summary>Host-owned content, never arbitrary text supplied by Flutter.</summary>
public sealed record DesktopNotification(Guid Id, bool Test, int Invitations, int Applications,
    string Preview, string Position, string Locale, string Appearance, Func<bool> IsCurrent, bool ReduceMotion = false,
    Action? Activated = null, PlayerActivityNotificationContent? Activity = null,
    bool BackgroundOnly = true, DirectMessageNotificationContent? DirectMessage = null,
    CommunityNotificationContent? Community = null);

public sealed record CommunityNotificationContent(string Name, string Callsign, string Text, bool Management);

public sealed record DirectMessageNotificationContent(string Callsign, string Text, int Conversations);

public sealed record PlayerActivityNotificationContent(string Callsign, string GameId,
    string Kind, string Audience, string? AvatarImageData = null,
    string? MemberKey = null, string[]? Sources = null);

public interface IDesktopNotificationSink : IDisposable
{
    ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken cancellationToken);
    async ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notification, CancellationToken cancellationToken) =>
        new(await TryPresentAsync(notification, cancellationToken), "unavailable");
    void Clear();
    // Legacy single-channel sinks may clear all; the shared native sink preserves activity cards.
    void ClearMessages() => Clear();
}

public sealed record DesktopNotificationResult(bool Submitted, string Reason);
