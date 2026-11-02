namespace StarBridge.Desktop;

/// <summary>
/// Background renewal of the HUD's module sources while the game runs. Sources
/// lease for 30–40 seconds; without renewal, reopening the HUD (for example when
/// it closes with the game in the background) waits for a fresh read. Renewal
/// uses the same ordinary reads as an open HUD and never extends a lease itself.
/// </summary>
public sealed partial class NativeInformationOverlayRuntime
{
    // Written by the 750 ms game-window rule tick; read from Host driver threads.
    private volatile bool _standbyGameRunning;
    // The user has shown the HUD during this run, so it is in use.
    private volatile bool _shownThisRun;

    public bool HasStandbyDemand =>
        !_disposed && _shownThisRun && _standbyGameRunning && !HasDisplayDemand &&
        Volatile.Read(ref _moduleDemand) is not null;

    private void ObserveStandbyGameRunning(bool running) => _standbyGameRunning = running;

    private void ObserveShownForStandby() => _shownThisRun = true;
}
