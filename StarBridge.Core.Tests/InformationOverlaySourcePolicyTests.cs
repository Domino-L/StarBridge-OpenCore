using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class InformationOverlaySourcePolicyTests
{
    internal static void RunAll()
    {
        void Check(OverlayScenePreference preference, bool room, bool fleet, bool community,
            bool explicitCommunity, InformationOverlaySourceKind kind, bool available)
        {
            var actual = InformationOverlaySourcePolicy.Resolve(preference, room, fleet, community, explicitCommunity);
            if (actual != new InformationOverlaySourceSelection(kind, available))
                throw new Exception($"Unexpected source for {preference}: {actual}");
        }
        foreach (var room in new[] { false, true })
        foreach (var fleet in new[] { false, true })
        foreach (var community in new[] { false, true })
        {
            Check(OverlayScenePreference.Auto, room, fleet, community, false,
                room ? InformationOverlaySourceKind.PartyRoom : fleet ? InformationOverlaySourceKind.Fleet :
                community ? InformationOverlaySourceKind.Community : InformationOverlaySourceKind.Local, true);
            Check(OverlayScenePreference.PartyRoom, room, fleet, community, false,
                InformationOverlaySourceKind.PartyRoom, room);
            Check(OverlayScenePreference.Fleet, room, fleet, community, false,
                InformationOverlaySourceKind.Fleet, fleet);
            Check(OverlayScenePreference.Auto, room, fleet, community, true,
                InformationOverlaySourceKind.Community, community);
        }
        Check((OverlayScenePreference)999, true, true, true, false, InformationOverlaySourceKind.Local, false);
    }
}
