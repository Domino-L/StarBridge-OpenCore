using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

// 0.7.3 visor and rollback (CX-VISOR-073-R): every v2 preset document 0.7.3 writes must still pass
// 0.7.2.1's reader, which rejects unknown settings fields and unknown skin names. The visor part
// lives in a per-preset sidecar. (Overlay v2 writes its own folder; these rules still hold there.)
internal static class OverlayVisorRollbackTests
{
    // OverlayDisplaySettings fields as integration/0.7.2 (0.7.2.1) has them; "scenePreference" is
    // never written to a v2 document.
    private static readonly HashSet<string> Fields072 = new([
        "hideMissionWhenIdle", "memberNameMode", "hideOfflineMembers", "hideSquadIcons", "enableTrayMode", "opacity",
        "showNotice", "showSquads", "showMission", "showMembers", "skin", "theme", "autoThemeByShip", "showCrosshair",
        "crosshairMode", "crosshairUseThemeColor", "crosshairColor", "crosshairSize", "crosshairThickness",
        "crosshairOpacity", "crosshairShowCenterMark", "crosshairCenterMarkSize", "crosshairGap",
        "crosshairOutlineOpacity", "enableStartupTransition", "startupTransitionStyle", "autoFocusGameWindowOnOpen",
        "startupTransitionFollowOverlayTheme", "startupTransitionFrameRate", "autoOpenOverlayOnGameStart",
        "autoOpenOverlayOnGameForeground", "autoCloseOverlayOnGameBackground", "showEventNotifications",
        "eventNotificationSide", "eventNotificationDurationSeconds", "eventNotificationY", "hideMemberOnlineStatus",
        "squadStatusDisplayMode", "hideSelfMember", "memberPriorityMode", "memberScopeMode", "memberNameColumnRatio",
        "eventNotificationTypes", "eventNotificationMaxVisibleCount", "eventNotificationPinImportant",
        "eventNotificationAnimationSpeed", "eventNotificationDurations", "nightShadowBloom", "animationFrameRate",
        "scenePreference", "showChat", "chatDisplayMode", "chatSide", "chatMaxVisibleCount", "chatDurationSeconds",
        "chatShowSender", "chatShowTimestamp", "chatShowSystemMessages", "chatHideSelfMessages", "chatBarrageFontSize",
        "chatBarrageRegion", "chatBarrageDensity", "chatBarrageAvoidCenter", "chatTextEdgeStrength",
        "communicationFriendEvents", "communicationMessagePreview", "communicationEventDurationSeconds",
        "fleetChatScope", "eventNotificationTextOpacity", "eventNotificationBackgroundOpacity",
        "skipStartupTransitionWhenGameForeground", "requestedSkin", "eventNotificationDecorationOpacity", "calmDisplay",
        "calmWaitSeconds", "calmIdleOpacity", "calmLitOpacity", "calmLightWhen", "calmPeekHotkey"
    ], StringComparer.Ordinal);

    // OverlaySkin as 0.7.2 shipped it.
    private enum OldSkin { Default, NightShadow, Verdict = 3, HajiCitizen }

    internal static Task Run()
    {
        // The only fields 0.7.3 adds are the four visor ones, and none of them reaches a v2 document.
        var current = OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default).Keys.ToHashSet(StringComparer.Ordinal);
        Check(current.Except(Fields072).ToHashSet().SetEquals(OverlayPresetDocument.VisorFields), "0.7.3 adds exactly the visor fields");

        // A visor save: every document still reads in 0.7.2.1.
        WithRoot(root =>
        {
            OldUser(root);
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: true);
            var loaded = store.Load();
            store.Apply(Save(loaded, loaded.Settings with { Skin = OverlaySkin.Visor, RequestedSkin = OverlaySkin.Visor }));
            AllOldReadable(root, "after a visor save");
            var state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(state.Settings.Skin == OverlaySkin.Visor && state.Settings.EffectiveRequestedSkin == OverlaySkin.Visor,
                "the visor comes back from the sidecar");
            Check(state.Presets.All(preset => preset.StorageState != "corrupt"), "no preset reads as damaged");

            // Visor size and badge position round-trip through the sidecar; the document stays old-readable.
            state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Apply(Save(state, state.Settings with
            {
                VisorSize = OverlayVisorSize.Large, VisorHolidayGold = true, VisorBadgeX = 0.3, VisorBadgeY = 0.4, VisorTilt = 28, VisorChatPlate = false,
                VisorMembersAutoWidth = false, VisorMembersAutoHeight = false, VisorMembersWidth = 300, VisorMembersHeight = 540,
                VisorEventsAutoWidth = false, VisorChatAutoWidth = false, VisorEventsWidth = 330, VisorChatWidth = 260,
                VisorViewingDistance = 1650, VisorEventsX = 0.42
            }));
            AllOldReadable(root, "after a visor save");
            state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(state.Settings is { VisorSize: OverlayVisorSize.Large, VisorHolidayGold: true } &&
                Math.Abs(state.Settings.VisorBadgeX - 0.3) < 1e-9 && Math.Abs(state.Settings.VisorBadgeY - 0.4) < 1e-9 &&
                state.Settings.VisorTilt == 28 && !state.Settings.VisorChatPlate &&
                state.Settings is { VisorMembersAutoWidth: false, VisorMembersAutoHeight: false, VisorMembersWidth: 300, VisorMembersHeight: 540,
                    VisorEventsAutoWidth: false, VisorChatAutoWidth: false, VisorEventsWidth: 330, VisorChatWidth: 260,
                    VisorViewingDistance: 1650 } && Math.Abs(state.Settings.VisorEventsX - 0.42) < 1e-9,
                "visor size, gold, badge, tilt, chat plate, members size, viewing distance and events place across are read back");
            Check(state.Presets.First(preset => preset.IsActive).StorageState == "ready", "the missing visor fields are not a recovery");

            // A sidecar an earlier 0.7.3 build wrote has no fold angle: it still applies, with 15 degrees.
            var sidecar = Path.Combine(root, $"overlay.{state.ActivePresetId}.visor.json");
            var withoutTilt = System.Text.RegularExpressions.Regex.Replace(File.ReadAllText(sidecar), ",\"visorTilt\":[0-9.]+|,\"visorChatPlate\":(true|false)|,\"visor(Members|Events|Chat)[A-Za-z]+\":[a-z0-9.]+|,\"visorViewingDistance\":[0-9.]+", "");
            Check(withoutTilt != File.ReadAllText(sidecar), "test edit applied (tilt removed from the sidecar)");
            File.WriteAllText(sidecar, withoutTilt);
            var older = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(older.Settings is { VisorSize: OverlayVisorSize.Large, VisorTilt: 15, VisorChatPlate: true, VisorMembersAutoWidth: true, VisorMembersAutoHeight: true,
                    VisorMembersWidth: 364, VisorMembersHeight: 394, VisorEventsAutoWidth: true, VisorChatAutoWidth: true, VisorEventsWidth: 364, VisorChatWidth: 364,
                    VisorViewingDistance: 1000, VisorEventsX: -1 } && older.Settings.EffectiveRequestedSkin == OverlaySkin.Visor,
                "a sidecar from an earlier 0.7.3 build keeps the visor settings and reads the defaults for the later ones");

            // Review R2: a later field of the wrong type reads its default alone; the rest of the sidecar still applies.
            var mangled = File.ReadAllText(sidecar).TrimEnd().TrimEnd('}') +
                ",\"visorTilt\":\"steep\",\"visorChatPlate\":\"no\",\"visorMembersWidth\":null,\"visorMembersAutoHeight\":7,\"visorViewingDistance\":\"far\",\"visorEventsX\":\"mid\"}";
            File.WriteAllText(sidecar, mangled);
            var typed = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(typed.Settings is { VisorSize: OverlayVisorSize.Large, VisorTilt: 15, VisorChatPlate: true, VisorMembersWidth: 364, VisorMembersAutoHeight: true,
                    VisorViewingDistance: 1000, VisorEventsX: -1 } &&
                typed.Settings.EffectiveRequestedSkin == OverlaySkin.Visor,
                "a later sidecar field of the wrong type reads its default; the visor, its size and look still apply");

            // Rolled back, 0.7.2.1 saved the preset with another look: the stale sidecar is ignored.
            var file = Path.Combine(root, $"overlay.{state.ActivePresetId}.workspace.json");
            var text = File.ReadAllText(file).Replace("\"skin\":\"Default\"", "\"skin\":\"NightShadow\"")
                .Replace("\"requestedSkin\":\"Default\"", "\"requestedSkin\":\"NightShadow\"");
            Check(text != File.ReadAllText(file), "test edit applied");
            File.WriteAllText(file, text);
            state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(state.Settings.EffectiveRequestedSkin == OverlaySkin.NightShadow &&
                state.Settings.VisorSize == OverlayVisorSize.Medium, "an older client's later save wins over the sidecar");

            // A damaged sidecar only loses the visor part; the preset still loads.
            File.WriteAllText(Path.Combine(root, $"overlay.{state.ActivePresetId}.visor.json"), "{ not json");
            state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(state.Presets.First(preset => preset.IsActive).StorageState == "ready" &&
                state.Settings.EffectiveRequestedSkin == OverlaySkin.NightShadow, "a damaged sidecar does not block the preset");
        });

        Console.WriteLine("PASS 0.7.3 visor rollback: v2 documents stay 0.7.2.1-readable, the sidecar carries the visor, nothing switches on read");
        return Task.CompletedTask;
    }

    /// <summary>0.7.2.1's v2 rules: exact root, schema 2, settings a subset of its fields, skins it knows.</summary>
    private static void AllOldReadable(string root, string when)
    {
        var documents = Directory.GetFiles(root, "overlay.*.workspace.json");
        Check(documents.Length > 0, "there are v2 documents " + when);
        foreach (var path in documents)
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var top = document.RootElement;
            Check(top.EnumerateObject().Select(p => p.Name).ToHashSet()
                .SetEquals(["schemaVersion", "recoveredDefaults", "settings", "layout", "sources"]), "root fields " + when);
            Check(top.GetProperty("schemaVersion").GetInt32() == 2, "schema 2 " + when);
            foreach (var property in top.GetProperty("settings").EnumerateObject())
            {
                Check(Fields072.Contains(property.Name), $"0.7.2.1 knows settings field {property.Name} {when}");
                if (property.Name is "skin" or "requestedSkin")
                    Check(Enum.TryParse<OldSkin>(property.Value.GetString(), false, out var skin) && Enum.IsDefined(skin),
                        $"0.7.2.1 knows skin {property.Value} {when}");
            }
        }
    }

    private static OverlayWorkspaceMutation Save(OverlayWorkspaceReadResult state, OverlayDisplaySettings settings) =>
        new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: settings,
            Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey);

    private static void OldUser(string root)
    {
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "overlay.settings"),
            string.Join(",", (OverlayDisplaySettings.Default with { Opacity = 0.66, ShowMembers = true }).Serialize().Split(',').Take(80)));
        File.WriteAllText(Path.Combine(root, "overlay.layout"),
            InformationOverlayLayoutItem.SerializeMany(InformationOverlayDefaults.CreateLayout("default")));
    }

    private static void WithRoot(Action<string> body)
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-visor-rollback-" + Guid.NewGuid().ToString("N"));
        try { body(root); }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
