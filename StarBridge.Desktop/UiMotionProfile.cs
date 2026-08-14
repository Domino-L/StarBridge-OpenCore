namespace StarBridge.Desktop;

public static class UiMotionProfile
{
    // Avionics-native response: the content stays stable while navigation and
    // real state changes carry the motion.
    public static readonly TimeSpan FastDuration = TimeSpan.FromMilliseconds(110);
    public static readonly TimeSpan NavigationDuration = TimeSpan.FromMilliseconds(190);
    public static readonly TimeSpan ContentDuration = TimeSpan.FromMilliseconds(120);
    public static readonly TimeSpan ModalDuration = TimeSpan.FromMilliseconds(180);
    public static readonly TimeSpan SignalDuration = TimeSpan.FromMilliseconds(360);
    public static readonly TimeSpan SceneDuration = TimeSpan.FromMilliseconds(420);
    public static readonly TimeSpan StateLoadingCycleDuration = TimeSpan.FromMilliseconds(900);
    public static readonly TimeSpan PresencePulseDuration = TimeSpan.FromMilliseconds(2600);

    public const double NavigationMarkerTravel = 4;
    public const double ContentStartOpacity = 0.9;
    public const double ModalStartOpacity = 0.88;
    public const double ModalStartOffset = 4;
    public const double ModalExitOffset = -2;
}
