namespace StarBridge.Desktop;

/// <summary>
/// Owns the persisted, user-facing role-category colours. These values are
/// domain data rather than interface-state tokens, so they deliberately stay
/// separate from the Bridge status palette.
/// </summary>
internal static class PersonalProfileRoleColorPalette
{
    public const string Command = "#D9A23B";
    public const string Ship = "#29AFFF";
    public const string AirCombat = "#E08A92";
    public const string GroundCombat = "#F15B65";
    public const string Recon = "#75C9D6";
    public const string Industry = "#D6B56A";
    public const string Medical = "#42CF7C";
    public const string Logistics = "#9A8FD8";
}
