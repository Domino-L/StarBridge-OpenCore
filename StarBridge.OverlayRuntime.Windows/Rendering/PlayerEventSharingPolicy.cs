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
        (PlayerSharedEventTypes)SharedEventChoice.Normalize((SharedActivityEventTypes)value);
}

