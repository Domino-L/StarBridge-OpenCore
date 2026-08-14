using System.IO;
using System.Text.Json;
using StarBridge.Core.Events;

namespace StarBridge.Desktop;

[Flags]
internal enum PlayerSharedEventTypes
{
    None = 0,
    Presence = 1 << 0,
    Server = 1 << 1,
    Ship = 1 << 2,
    Location = 1 << 3,
    // Bit 4 was the retired fleet-squad event. It remains reserved so the
    // Life bit and existing wire values never shift.
    RetiredSquad = 1 << 4,
    Life = 1 << 5,
    All = Presence | Server | Ship | Location | Life
}

internal sealed record PlayerEventSharingSettings(
    bool Enabled = true,
    PlayerSharedEventTypes EventTypes = PlayerSharedEventTypes.All)
{
    public static PlayerEventSharingSettings Default { get; } = new();

    public PlayerSharedEventTypes EffectiveTypes => Enabled
        ? NormalizeTypes(EventTypes)
        : PlayerSharedEventTypes.None;

    public bool Allows(PlayerSharedEventTypes eventType) =>
        eventType != PlayerSharedEventTypes.None && EffectiveTypes.HasFlag(eventType);

    public int ToWireValue() => (int)EffectiveTypes;

    public PlayerEventSharingSettings Normalize() => this with
    {
        EventTypes = NormalizeTypes(EventTypes)
    };

    public static PlayerSharedEventTypes FromWireValue(int value) =>
        NormalizeTypes((PlayerSharedEventTypes)value);

    private static PlayerSharedEventTypes NormalizeTypes(PlayerSharedEventTypes value) =>
        value & PlayerSharedEventTypes.All;
}

internal static class PlayerEventSharingSettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "player-event-sharing.settings.json");

    public static PlayerEventSharingSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return PlayerEventSharingSettings.Default;
            }

            return (JsonSerializer.Deserialize<PlayerEventSharingSettings>(File.ReadAllText(SettingsPath)) ??
                    PlayerEventSharingSettings.Default)
                .Normalize();
        }
        catch
        {
            return PlayerEventSharingSettings.Default;
        }
    }

    public static void Save(PlayerEventSharingSettings settings)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        var temporaryPath = $"{SettingsPath}.tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings.Normalize(), new JsonSerializerOptions
        {
            WriteIndented = true
        }));
        File.Move(temporaryPath, SettingsPath, overwrite: true);
    }
}

internal static class NetworkSharedLifeEventPolicy
{
    private static readonly TimeSpan MaximumEventAge = TimeSpan.FromMinutes(2);

    public static FleetEventType[] ResolveNew(
        NetworkPlayerSnapshot next,
        NetworkPlayerSnapshot? previous,
        DateTimeOffset now)
    {
        if (previous is null ||
            !PlayerEventSharingSettings.FromWireValue(next.SharedEventTypes).HasFlag(PlayerSharedEventTypes.Life))
        {
            return [];
        }

        var seenIds = (previous.SharedEvents ?? [])
            .Where(sharedEvent => !string.IsNullOrWhiteSpace(sharedEvent.Id))
            .Select(sharedEvent => sharedEvent.Id)
            .ToHashSet(StringComparer.Ordinal);
        return (next.SharedEvents ?? [])
            .Where(sharedEvent =>
                !string.IsNullOrWhiteSpace(sharedEvent.Id) &&
                !seenIds.Contains(sharedEvent.Id) &&
                sharedEvent.OccurredAt <= now.AddSeconds(15) &&
                now - sharedEvent.OccurredAt <= MaximumEventAge)
            .OrderBy(sharedEvent => sharedEvent.OccurredAt)
            .Select(sharedEvent => Enum.TryParse(sharedEvent.Type, ignoreCase: true, out FleetEventType eventType)
                ? eventType
                : (FleetEventType?)null)
            .Where(eventType => eventType is FleetEventType.PlayerDowned
                or FleetEventType.PlayerDied
                or FleetEventType.PlayerRevived
                or FleetEventType.PlayerRespawned)
            .Select(eventType => eventType!.Value)
            .ToArray();
    }
}
