using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

public readonly record struct FleetPresencePrivacyProjection(
    bool CanShareRealtime,
    bool Online,
    string LiveStatus);

public readonly record struct FleetLocationPrivacyProjection(
    string Location,
    string Confidence);

public static class FleetPresencePrivacyPolicy
{
    public static FleetLocationPrivacyProjection ProjectLocation(
        string? location,
        string? confidence,
        bool canPublish,
        bool hideNonHighConfidence)
    {
        var projectedLocation = canPublish && !string.IsNullOrWhiteSpace(location)
            ? location
            : "Unknown";
        var projectedConfidence = canPublish && !string.IsNullOrWhiteSpace(confidence)
            ? confidence
            : "None";

        if (!LocationNameLocalizer.CanPersistOrSynchronize(projectedLocation))
        {
            return new FleetLocationPrivacyProjection("Unknown", "None");
        }

        if (hideNonHighConfidence &&
            !projectedConfidence.Equals("High", StringComparison.OrdinalIgnoreCase))
        {
            return new FleetLocationPrivacyProjection("Unknown", "None");
        }

        return new FleetLocationPrivacyProjection(projectedLocation, projectedConfidence);
    }

    public static FleetPresencePrivacyProjection Resolve(
        PlayerPresenceKind automaticPresence,
        PlayerPresenceVisibilityMode visibilityMode,
        bool syncEnabled,
        bool visibilityShared,
        bool liveStatusAvailable,
        bool syncOnlineStatus)
    {
        var sharing = PlayerPresence.DecideSharing(automaticPresence, visibilityMode);
        if (visibilityMode is PlayerPresenceVisibilityMode.Invisible or PlayerPresenceVisibilityMode.Offline)
        {
            return new FleetPresencePrivacyProjection(false, false, "Offline");
        }

        var canPublishPresence = sharing.CanPublishRealtime &&
                                 syncEnabled &&
                                 visibilityShared;
        var canShareRealtime = canPublishPresence && liveStatusAvailable;
        var online = canPublishPresence &&
                     syncOnlineStatus &&
                     PlayerPresence.IsOnline(sharing.PublicPresence);
        var liveStatus = !canPublishPresence
            ? "Offline"
            : online
                ? PlayerPresence.ToWireValue(sharing.PublicPresence)
                : "Offline";
        return new FleetPresencePrivacyProjection(canShareRealtime, online, liveStatus);
    }
}
