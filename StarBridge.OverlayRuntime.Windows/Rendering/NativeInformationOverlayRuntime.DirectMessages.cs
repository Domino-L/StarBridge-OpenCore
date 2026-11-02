namespace StarBridge.Desktop;

using System.Globalization;
using System.Windows.Threading;
using StarBridge.HostRuntime.Overlay;

// Unread direct messages are a quiet mark on the open overlay, never a notice. The Host
// sends the summary whenever it changes; the mark follows the open window.
public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayDirectUnreadSink
{
    private InformationOverlayDirectUnread? _directUnread;
    private (OverlayCompositionHudWindow Window, string? Mark)? _directUnreadShown;

    public void UpdateDirectUnread(InformationOverlayDirectUnread? unread)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        dispatcher.BeginInvoke(() =>
        {
            _directUnread = unread;
            SyncDirectUnread();
        }, DispatcherPriority.Send);
    }

    private void SyncDirectUnread()
    {
        if (_disposed || _window is not { IsVisible: true } window) { _directUnreadShown = null; return; }
        var mark = _workspace?.Settings.CommunicationFriendEvents == true ? DirectUnreadMark(_directUnread) : null;
        if (_directUnreadShown is { } shown && ReferenceEquals(shown.Window, window) && shown.Mark == mark) return;
        window.SetDirectUnread(mark);
        _directUnreadShown = (window, mark);
    }

    internal static string? DirectUnreadMark(InformationOverlayDirectUnread? unread)
    {
        if (unread is not { Conversations: > 0 } value) return null;
        var callsign = value.Callsign.Trim();
        if (value.Conversations != 1 || callsign.Length == 0) return $"✉ {value.Conversations}";
        var text = new StringInfo(callsign);
        return text.LengthInTextElements <= 14 ? "✉ " + callsign : "✉ " + text.SubstringByTextElements(0, 13) + "…";
    }
}
