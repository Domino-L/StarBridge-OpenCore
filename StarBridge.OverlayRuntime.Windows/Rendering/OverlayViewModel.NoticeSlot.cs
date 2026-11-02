namespace StarBridge.Desktop;

public sealed partial class OverlayViewModel
{
    // The top slot's own transient item (a communication event or reminder) is showing.
    internal bool NoticeItemActive => _noticeSecondsRemaining > 0 && FleetNoticeTitle.Length > 0;
    internal int NoticeQueueCount => _pendingCommunicationEvents.Count;

    // The communication event on show goes back to the head of the queue, unchanged.
    private bool YieldSlotToLiveReminder()
    {
        if (_noticeSecondsRemaining <= 0 || FleetNoticeTitle.Length == 0) return true;
        var waiting = _pendingCommunicationEvents.ToArray();
        _pendingCommunicationEvents.Clear();
        // An announcement that has not reached the screen yet keeps its identity, so it is
        // recorded when it comes back; one already shown comes back without it, so the
        // shown-once check does not drop it.
        var waitingForScreen = AnnouncementAwaitingScreen(FleetNoticeTitle, FleetNotice) is { } awaiting &&
            !AnnouncementShown(awaiting.Key, awaiting.Receipt) ? awaiting : ((string Key, string Receipt)?)null;
        _pendingCommunicationEvents.Enqueue(new PendingCommunicationEvent(FleetNoticeTitle, FleetNotice, default,
            waitingForScreen?.Key, waitingForScreen?.Receipt));
        foreach (var item in waiting.Take(19)) _pendingCommunicationEvents.Enqueue(item);
        return true;
    }

    // An announcement shows once per app run: reopening the overlay or coming back to the
    // channel does not show it again. The record is per account and channel, keeps only the
    // latest announcement's hash (never the text) and drops its oldest channel past 64.
    // The notification module is where an announcement is read again.
    private const int ShownAnnouncementCapacity = 64;
    private static readonly Dictionary<string, (string Receipt, long Order)> s_shownAnnouncements = new(StringComparer.Ordinal);
    private static long s_shownAnnouncementOrder;

    // The module scope key is "<owner>:<generation>"; a new sign-in of the same account keeps its record.
    private static string AnnouncementKey(string scopeKey, string channel)
    {
        var cut = scopeKey.LastIndexOf(':');
        var owner = cut > 0 ? scopeKey[..cut] : scopeKey;
        return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes($"{owner}\n{channel}")));
    }

    private static bool AnnouncementShown(string? key, string receipt)
    {
        if (key is null) return false;
        lock (s_shownAnnouncements) return s_shownAnnouncements.TryGetValue(key, out var shown) && shown.Receipt == receipt;
    }

    private (string Key, string Receipt, string Title, string Detail)? _announcementAwaitingScreen;

    /// <summary>The announcement in the slot that has not yet reached the screen, when the frame
    /// shows exactly it. The window confirms it once that frame is committed.</summary>
    internal (string Key, string Receipt)? AnnouncementAwaitingScreen(string title, string detail) =>
        _announcementAwaitingScreen is { } item && _noticeSecondsRemaining > 0 && item.Title == title && item.Detail == detail
            ? (item.Key, item.Receipt) : null;

    // Called from the render thread after a committed frame showed the announcement.
    internal static void ConfirmAnnouncementShown(string key, string receipt) => NoteAnnouncementShown(key, receipt);

    private static void NoteAnnouncementShown(string key, string receipt)
    {
        lock (s_shownAnnouncements)
        {
            if (s_shownAnnouncements.Count >= ShownAnnouncementCapacity && !s_shownAnnouncements.ContainsKey(key))
                s_shownAnnouncements.Remove(s_shownAnnouncements.MinBy(item => item.Value.Order).Key);
            s_shownAnnouncements[key] = (receipt, ++s_shownAnnouncementOrder);
        }
    }
}
