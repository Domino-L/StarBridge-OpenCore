namespace StarBridge.Core.Overlay;

public enum InformationOverlaySceneKind
{
    Fleet,
    PartyRoom
}

public readonly record struct InformationOverlaySceneSelection(
    InformationOverlaySceneKind Kind,
    bool IsFallback);

public readonly record struct InformationOverlayContentState(
    bool NoticeHasContent,
    bool ChatHasContent,
    bool EventNotificationsHaveContent);

public readonly record struct InformationOverlayVisibility(
    bool ShowNotice,
    bool ShowSquads,
    bool ShowMembers,
    bool ShowChat,
    bool ShowCrosshair,
    bool ShowEventNotifications)
{
    public bool IsLayoutModuleVisible(string? key) => key?.Trim() switch
    {
        "Notice" => ShowNotice,
        "Squads" => ShowSquads,
        "Members" => ShowMembers,
        "Chat" => ShowChat,
        _ => false
    };
}

/// <summary>
/// Projects saved settings plus ephemeral content into renderer-facing scene
/// and visibility facts. It contains no WPF or Flutter presentation types.
/// </summary>
public static class InformationOverlayRuntimeProjection
{
    public static InformationOverlaySceneSelection ResolveScene(
        OverlayScenePreference preference,
        bool hasCurrentPartyRoom)
    {
        var usePartyRoom = preference == OverlayScenePreference.PartyRoom ||
                           preference == OverlayScenePreference.Auto && hasCurrentPartyRoom;
        return usePartyRoom && hasCurrentPartyRoom
            ? new InformationOverlaySceneSelection(InformationOverlaySceneKind.PartyRoom, false)
            : new InformationOverlaySceneSelection(
                InformationOverlaySceneKind.Fleet,
                preference == OverlayScenePreference.PartyRoom);
    }

    public static InformationOverlayVisibility ResolveVisibility(
        OverlayDisplaySettings settings,
        InformationOverlayContentState content)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return new InformationOverlayVisibility(
            settings.ShowNotice && content.NoticeHasContent,
            settings.ShowSquads,
            settings.ShowMembers,
            settings.ShowChat && content.ChatHasContent,
            settings.ShowCrosshair,
            settings.ShowEventNotifications && content.EventNotificationsHaveContent);
    }
}
