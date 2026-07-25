namespace StarBridge.Desktop;

internal static class OverlayDefaultPreset
{
    // Curated from the owner's validated production preset on 2026-07-20.
    // Existing accounts keep their saved preset; this is used only for a new
    // preset and for an explicit reset of the built-in default preset.
    private const string SettingsPayload =
        "0,CallsignAndGameName,1,1,1,1.00,1,1,0,1,Default,0,0,Simple,0,#FFFFFF,52.48,1.57,1,1,BridgeTerminal,1,1,120,1,Right,5.03,0.291,1,Auto,0,Default,AllFleet,0.456,2047,3,0,Slow,0;0;0;0;0;0;0;0;0;0;0,1,3.1,12.12,0,Default,Strong,0,0,0,60,3,Auto,1,FullScreenBarrage,Right,4,12,1,1,1,0,16,UpperMiddle,Standard,1,Strong,1,0,5,All";

    public const string LayoutPayload =
        "Notice,0.34,0,0.32,0.055,Center,Top,0,1,0.5;" +
        "Squads,0,0.4211,0.1327,0.1042,Left,Middle,0,1,0.5;" +
        "Members,0,0.5253,0.1327,0.1557,Right,Middle,0,1,0.5;" +
        "Chat,0,0.681,0.1327,0.1069,Center,Bottom,0,1,1";

    public static OverlayDisplaySettings Settings { get; } = OverlayDisplaySettings.Parse(SettingsPayload);
}
