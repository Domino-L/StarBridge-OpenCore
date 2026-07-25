using System.Windows;

namespace StarBridge.Desktop;

public interface IOverlayHost
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
        IEnumerable<SquadRow> squads,
        IEnumerable<PlayerRow> players,
        IEnumerable<OverlayChatMessage> chatMessages,
        OverlayDisplaySettings settings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        string localShard,
        Rect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext);
}
