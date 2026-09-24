namespace StarBridge.Core.Overlay;

public enum InformationOverlaySourceKind { Local, PartyRoom, Fleet, Community }

public readonly record struct InformationOverlaySourceSelection(
    InformationOverlaySourceKind Kind, bool IsAvailable);

/// <summary>
/// Display routing only. Availability must come from an authorized source, never
/// from a saved name, sharing preference, or cached membership address.
/// Kept separate from the legacy WPF scene projection to preserve its behavior.
/// </summary>
public static class InformationOverlaySourcePolicy
{
    public static InformationOverlaySourceSelection Resolve(
        OverlayScenePreference preference, bool hasRoom, bool hasFleet,
        bool hasCommunity, bool hasExplicitCommunity = false)
    {
        if (hasExplicitCommunity)
            return new(InformationOverlaySourceKind.Community, hasCommunity);
        if (preference == OverlayScenePreference.PartyRoom)
            return new(InformationOverlaySourceKind.PartyRoom, hasRoom);
        if (preference == OverlayScenePreference.Fleet)
            return new(InformationOverlaySourceKind.Fleet, hasFleet);
        if (preference != OverlayScenePreference.Auto)
            return new(InformationOverlaySourceKind.Local, false);
        if (hasRoom) return new(InformationOverlaySourceKind.PartyRoom, true);
        if (hasFleet) return new(InformationOverlaySourceKind.Fleet, true);
        if (hasCommunity) return new(InformationOverlaySourceKind.Community, true);
        return new(InformationOverlaySourceKind.Local, true);
    }
}
