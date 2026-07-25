namespace StarBridge.Desktop;

internal readonly record struct SyncPrivacySwitchSummary(int EnabledCount, int DisabledCount);

internal static class SyncPrivacySummaryPresentation
{
    public static SyncPrivacySwitchSummary Build(
        SyncPrivacySettings syncSettings,
        PlayerEventSharingSettings eventSharingSettings)
    {
        var switches = new[]
        {
            syncSettings.SyncOnlineStatus,
            syncSettings.SyncShipStatus,
            syncSettings.SyncLocationStatus,
            syncSettings.SyncServerInfo,
            syncSettings.PersonalHangarVisible,
            syncSettings.FriendsCanViewPresence,
            eventSharingSettings.Enabled,
            syncSettings.HideLowConfidenceLocation
        };

        var enabledCount = 0;
        if (syncSettings.SyncEnabled)
        {
            foreach (var isEnabled in switches)
            {
                if (isEnabled)
                {
                    enabledCount++;
                }
            }
        }

        return new SyncPrivacySwitchSummary(enabledCount, switches.Length - enabledCount);
    }
}
