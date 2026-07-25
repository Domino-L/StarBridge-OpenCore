namespace StarBridge.Desktop;

using StarBridge.Core.Presence;
using System.IO;
using System.Text.Json;

internal enum SyncPrivacyVisibilityScope
{
    Private,
    AdminOnly,
    Squad,
    Fleet
}

internal sealed record SyncPrivacySettings(
    bool SyncOnlineStatus = true,
    bool SyncShipStatus = true,
    bool SyncLocationStatus = true,
    bool SyncServerInfo = true,
    bool SyncOnlyInGame = true,
    SyncPrivacyVisibilityScope VisibilityScope = SyncPrivacyVisibilityScope.Fleet,
    bool FleetMembersVisible = true,
    bool SquadMembersVisible = true,
    bool AdminOnlyVisible = false,
    bool PersonalHangarVisible = false,
    bool TaskOnlineStatusVisible = true,
    bool TaskShipStatusVisible = true,
    bool TaskLocationStatusVisible = true,
    bool CommandReadinessSummaryVisible = true,
    bool HideStatusBeforeGameStart = true,
    bool HideServerInfoBeforePu = true,
    bool StopSyncAfterGameExit = true,
    bool HideLowConfidenceLocation = false,
    bool SyncConsentCompleted = false,
    int SyncConsentVersion = 0,
    bool SyncEnabled = true,
    PlayerPresenceVisibilityMode PresenceVisibilityMode = PlayerPresenceVisibilityMode.Online,
    bool FriendsCanViewPresence = true)
{
    public static readonly SyncPrivacySettings Default = new();

    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "sync-privacy.settings.json");

    public SyncPrivacyVisibilityScope EffectiveVisibilityScope =>
        VisibilityScope is SyncPrivacyVisibilityScope.Private
            or SyncPrivacyVisibilityScope.AdminOnly
            or SyncPrivacyVisibilityScope.Squad
            or SyncPrivacyVisibilityScope.Fleet
                ? VisibilityScope
                : SyncPrivacyVisibilityScope.Fleet;

    public SyncPrivacySettings NormalizeVisibilityScope()
    {
        var scope = EffectiveVisibilityScope;
        return this with
        {
            VisibilityScope = scope,
            FleetMembersVisible = scope == SyncPrivacyVisibilityScope.Fleet,
            SquadMembersVisible = scope is SyncPrivacyVisibilityScope.Squad or SyncPrivacyVisibilityScope.Fleet,
            AdminOnlyVisible = scope == SyncPrivacyVisibilityScope.AdminOnly,
            HideStatusBeforeGameStart = true,
            HideServerInfoBeforePu = true,
            StopSyncAfterGameExit = true,
            PresenceVisibilityMode = Enum.IsDefined(PresenceVisibilityMode)
                ? PresenceVisibilityMode
                : PlayerPresenceVisibilityMode.Online
        };
    }

    public static SyncPrivacySettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return Default;
            }

            var json = File.ReadAllText(SettingsPath);
            var settings = JsonSerializer.Deserialize<SyncPrivacySettings>(json) ?? Default;

            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.TryGetProperty(nameof(VisibilityScope), out _))
            {
                settings = settings with { VisibilityScope = GetLegacyVisibilityScope(settings) };
            }

            return settings.NormalizeVisibilityScope();
        }
        catch
        {
            return Default;
        }
    }

    public static void Save(SyncPrivacySettings settings)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings.NormalizeVisibilityScope(), new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }

    private static SyncPrivacyVisibilityScope GetLegacyVisibilityScope(SyncPrivacySettings settings)
    {
        if (settings.AdminOnlyVisible)
        {
            return SyncPrivacyVisibilityScope.AdminOnly;
        }

        if (settings.FleetMembersVisible)
        {
            return SyncPrivacyVisibilityScope.Fleet;
        }

        if (settings.SquadMembersVisible)
        {
            return SyncPrivacyVisibilityScope.Squad;
        }

        return SyncPrivacyVisibilityScope.Private;
    }
}
