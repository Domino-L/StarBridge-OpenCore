namespace StarBridge.HostRuntime.HealthReading;

// The player's own health, read from the bottom-left helmet HUD on this machine only.
// It is shown on the visor's own row and is never shared, relayed or uploaded.
internal enum SelfHealthState
{
    Unknown,
    Normal,
    Downed,
    Dead,
}

// Percent is 0..100, or null when there is no reading (the visor then draws no ring).
internal sealed record SelfHealthReading(int? Percent, SelfHealthState State, DateTimeOffset ObservedAt)
{
    public static readonly SelfHealthReading None = new(null, SelfHealthState.Unknown, DateTimeOffset.MinValue);

    public bool SameValueAs(SelfHealthReading other) => Percent == other.Percent && State == other.State;

    // The visor's own-row ring (面罩线 OverlayVisorVitals): health 0..1 only means something when
    // alive; downed and dead are drawn from the state alone; no reading (switch off, not reading) is
    // Unknown, and the visor then draws no ring at all (user 11-10).
    public (SelfHealthVisorKind Kind, float Health) ToVisor() => State switch
    {
        SelfHealthState.Dead => (SelfHealthVisorKind.Dead, 0f),
        SelfHealthState.Downed => (SelfHealthVisorKind.Downed, Percent is { } d ? Math.Clamp(d, 0, 100) / 100f : 0f),
        _ when Percent is { } p => (SelfHealthVisorKind.Alive, Math.Clamp(p, 0, 100) / 100f),
        _ => (SelfHealthVisorKind.Unknown, 0f),
    };
}

// Same order as the visor's OverlayVisorVitals, so the overlay can cast.
internal enum SelfHealthVisorKind
{
    Unknown,
    Alive,
    Downed,
    Dead,
}

// One capture of the bottom-left HUD panel, scaled to the 2560x1440 layout (HudPanelFrame,
// 900x490 BGR). Implementations own every native object they create and release all of
// them in Dispose.
internal interface IHudFrameSource : IDisposable
{
    // False while no frame has arrived yet. A frame identical to the last one is still true.
    bool TryCapture(HudPanelFrame frame);

    // After a true TryCapture: whether that image was new (false: the previous image stood in). Only new
    // images keep the ring up: with none for 2 seconds the reader shows "no reading".
    bool LastFrameWasNew => true;

    // After a false TryCapture: the window being captured may no longer be read (another window is now the
    // game's, or it is gone). The reader releases this source and starts a new one for the current window.
    bool TargetLost => false;

    // After a true TryCapture: the game window's picture size (client area, pixels). 0 x 0: unknown. Only used to
    // remember where clear digits have been read before (11-17 new-life rule).
    (int Width, int Height) CaptureSize => (0, 0);
}

internal interface IHudFrameSourceFactory
{
    // Null when capture cannot start now (for example the game window is on no output).
    IHudFrameSource? TryCreate();
}
