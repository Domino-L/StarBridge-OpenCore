using System.Windows;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

internal interface IOverlayHost
{
    event EventHandler? Closed;

    bool IsVisible { get; }

    void Show();

    void BeginStartupTransition(int settleDelayMs = 0);

    void Close();

    void SetVisible(bool visible);

    void QueueGameEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        bool important,
        bool positive);

    void QueueCommunicationEvent(string title, string detail);

    void Refresh(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        Rect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext);
}
