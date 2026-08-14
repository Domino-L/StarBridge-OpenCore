namespace StarBridge.Desktop;

using System.IO;
using System.Text.Json;

internal enum PlayerActivityNotificationScope
{
    PartyRoom = 1,
    Fleet = 2
}

internal enum DesktopNotificationPosition
{
    TopLeft,
    BottomLeft,
    TopRight,
    BottomRight
}

internal sealed record NotificationSettings(
    bool EnableInAppNotifications = true,
    bool EnableOverlayNotifications = true,
    bool EnableEmailNotifications = true,
    bool EnableSoundAlerts = false,
    bool EnableDesktopNotifications = false,
    bool NotifyFleetOrders = true,
    bool NotifyMissionUpdates = true,
    bool NotifyRallyPointUpdates = true,
    int ActionPlanReminderMinutes = 15,
    bool NotifyUrgentOrders = true,
    bool NotifySquadOrders = true,
    bool NotifySquadMemberOnline = false,
    bool NotifySquadMemberOffline = false,
    bool NotifyMemberAnomalies = true,
    bool NotifyApplicationsAndInvites = true,
    bool DoNotDisturb = false,
    bool ReduceAlertsInGame = true,
    int NotificationCooldownSeconds = 60,
    int EmailHourlyLimit = 3,
    bool EmailOnlyCritical = true,
    bool EnablePlayerActivityNotifications = false,
    PlayerActivityNotificationScope PlayerActivityScope = PlayerActivityNotificationScope.Fleet,
    bool NotifyPlayerOnline = true,
    bool NotifyPlayerOffline = false,
    bool NotifyPlayerStartedGame = true,
    bool NotifyPlayerStoppedGame = false,
    bool PlayerActivityBackgroundOnly = true,
    bool ReducePlayerActivityNotificationsInGame = true,
    DesktopNotificationPosition PlayerActivityPosition = DesktopNotificationPosition.BottomRight)
{
    public static readonly NotificationSettings Default = new();

    public NotificationSettings Normalize() => this with
    {
        PlayerActivityScope = Enum.IsDefined(PlayerActivityScope)
            ? PlayerActivityScope
            : PlayerActivityNotificationScope.Fleet,
        PlayerActivityPosition = Enum.IsDefined(PlayerActivityPosition)
            ? PlayerActivityPosition
            : DesktopNotificationPosition.BottomRight
    };

    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "notification.settings.json");

    public static NotificationSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return Default;
            }

            return (JsonSerializer.Deserialize<NotificationSettings>(File.ReadAllText(SettingsPath)) ?? Default).Normalize();
        }
        catch
        {
            return Default;
        }
    }

    public static void Save(NotificationSettings settings)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings.Normalize(), new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }
}
