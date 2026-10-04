namespace StarBridge.Core.PartyRooms;

/// <summary>Room admission is only a ceiling; individual profile privacy must also authorize each target.</summary>
public static class PartyRoomProfilePreviewPolicy
{
    public static bool Allows(bool passwordRequired, string? admissionMode, string? eligibility) =>
        !passwordRequired && (admissionMode is "direct" or "approval") &&
        (eligibility is "everyone" or "friends" or "fleet");
}
