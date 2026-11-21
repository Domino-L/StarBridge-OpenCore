namespace StarBridge.HostRuntime.Notifications;

/// <summary>Host-owned content, never arbitrary text supplied by Flutter.</summary>
public sealed record DesktopNotification(Guid Id, bool Test, int Invitations, int Applications,
    string Preview, string Position, string Locale, string Appearance, Func<bool> IsCurrent, bool ReduceMotion = false,
    Action? Activated = null, PlayerActivityNotificationContent? Activity = null,
    bool BackgroundOnly = true, DirectMessageNotificationContent? DirectMessage = null,
    CommunityNotificationContent? Community = null, int FriendRequests = 0,
    bool GameIdentityMismatch = false, ExecHangarNotificationContent? ExecHangar = null,
    GameStartupHintContent? GameStartupHint = null, TradeNotificationContent? Trade = null)
{
    public Action<string>? Diagnostic { get; init; }
    // 0.7.3 social cards (user: "windows提醒默认是需要都开的，无视免打扰也是"): Windows do-not-disturb and
    // quiet time do not hold this card back; lock, presentation and unknown states still do.
    public bool ShowDuringQuiet { get; init; }
    // Set by the native runtime while the game is the foreground window: clicks pass through the card.
    public bool InGameClickThrough { get; init; }
    public bool IsSocial => ContinuousPlay is null && Trade is null && ExecHangar is null && Activity is null && GameStartupHint is null;
    // Host-written quiet-time summary text; never text supplied by Flutter.
    public ReminderNotificationContent? Reminder { get; init; }
    public ContinuousPlayNotificationContent? ContinuousPlay { get; init; }
    public DateTimeOffset? PresentUntil { get; init; }
    public Func<CancellationToken, Task<bool>>? RevalidateBeforePresent { get; init; }
    // Both initial native presentation and a deferred queue drain use this seam.
    // Never hold the native Dispatcher or a settings lock during the read.
    public async Task<bool> CanPresentAsync(CancellationToken token)
    {
        try {
            if (token.IsCancellationRequested || !IsCurrent()) return false;
            return (RevalidateBeforePresent == null || await RevalidateBeforePresent(token).WaitAsync(token)) &&
                !token.IsCancellationRequested && IsCurrent();
        } catch { return false; }
    }
    public void ReportDiagnostic(string outcome)
    {
        try { Diagnostic?.Invoke(outcome); } catch { /* Diagnostics cannot affect delivery. */ }
    }
}

/// <summary>Kind is a closed status word (request/approved/shipped/receipt/completed/cancelled/review/message/update).
/// Item, peer and text are already redacted by the Host; quantity and amount are parsed digits only.</summary>
public sealed record TradeNotificationContent(string Title, string Body, string Kind = "", string Item = "",
    int Quantity = 0, string Amount = "", string Peer = "", string Text = "")
{
    // Set by the native runtime while the game runs: activity-sized, click-through card.
    public bool Compact { get; init; }
}

public enum OrganizationNotificationSourceKind { Community, OfficialFleet }
public sealed record CommunityNotificationContent(string Name, string Callsign, string Text, bool Management,
    OrganizationNotificationSourceKind SourceKind = OrganizationNotificationSourceKind.Community, bool Announcement = false,
    int AnnouncementSummaryCount = 0);
public sealed record GameStartupHintContent(string Binding, int ProcessId);
public sealed record ExecHangarNotificationContent(bool Opening, bool AtOpen, DateTimeOffset Boundary,
    StarBridge.Core.Tools.ExecHangarConfig? Config = null, DateTimeOffset? MonitoringEndsAt = null, Action? Mute = null,
    bool LeaveWarning = false, bool Test = false)
{
    public bool Compact { get; init; }
}

/// <summary>Label is the summary card's small source line ("免打扰期间").</summary>
public sealed record ReminderNotificationContent(string Label, string Title, string Body);

public sealed record DirectMessageNotificationContent(string Callsign, string Text, int Conversations,
    string? AvatarImageData = null);

public sealed record PlayerActivityNotificationContent(string Callsign, string GameId,
    string Kind, string Audience, string? AvatarImageData = null,
    string? MemberKey = null, string[]? Sources = null)
{
    // 0.7.3 grouped card (user 11-06: "合成一张"): set when several members came online or went
    // offline together; the single-member fields above are then empty.
    public string[]? GroupNames { get; init; }
    public int OnlineNow { get; init; }
    public int Tracked { get; init; }
}

public interface IDesktopNotificationSink : IDisposable
{
    string DiagnosticTransport => "unknown";
    ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken cancellationToken);
    async ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notification, CancellationToken cancellationToken) =>
        new(await TryPresentAsync(notification, cancellationToken), "unavailable");
    void Clear();
    // Legacy single-channel sinks may clear all; the shared native sink preserves activity cards.
    void ClearMessages() => Clear();
}

public sealed record DesktopNotificationResult(bool Submitted, string Reason)
{
    public string? DiagnosticOutcome { get; init; }
}
