using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

/// <summary>
/// 0.7.3 (11-13 user, "背景可以"): a block's background opacity is the plate's real opacity (100% = solid). Before, 100%
/// drew only a faint plate, so each value the user saved is read once at 15% of itself (it looks as before), written so
/// with the next write together with a marker, and never scaled again; files shipped with the client are always read
/// that way.
/// </summary>
internal static class OverlayBackgroundScaleTests
{
    internal static void Run()
    {
        Rules();
        StoredCsv(enableSourcePresets: false);
        StoredCsv(enableSourcePresets: true);
        Shipped();
        Interrupted();
        V2MoveKeepsCsv();
        V2MoveKeepsVisorSidecar();
        Console.WriteLine("PASS overlay background scale");
    }

    private static Dictionary<string, byte[]> Csv(string root) => Directory.GetFiles(root)
        .Where(path => Path.GetFileName(path).StartsWith("overlay.", StringComparison.Ordinal) &&
                       (path.EndsWith(".settings", StringComparison.Ordinal) || path.EndsWith(".layout", StringComparison.Ordinal)))
        .ToDictionary(path => path, File.ReadAllBytes);

    /// <summary>
    /// Review CX-OVERLAY-M94-MIGRATION-R1: the v2 move writes the background scaling and the moved overall opacity only into
    /// the v2 documents; the earlier CSV files stay byte for byte (0.7.2.1 reads them as they were).
    /// </summary>
    private static void V2MoveKeepsCsv()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-background-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var oldDefault = InformationOverlayDefaults.LegacyDefaultOpacity(InformationOverlayPresetCodec.DefaultPresetId);
            File.WriteAllText(Path.Combine(root, "overlay.settings"),
                (OverlayDisplaySettings.Default with { Opacity = oldDefault, EventNotificationBackgroundOpacity = 1.0, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(root, "overlay.layout"), InformationOverlayLayoutItem.SerializeMany(
                InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload)
                    .Select(item => new InformationOverlayLayoutItem(item.Key, item.X, item.Y, item.Width, item.Height,
                        item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked, item.TextOpacity, 1.0, item.DecorationOpacity))));
            var csv = Csv(root);
            var state = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            var document = Path.Combine(root, $"overlay.{state.ActivePresetId}.workspace.json");
            Check(File.Exists(document) && File.Exists(Path.Combine(root, OverlayWorkspaceStore.BackgroundMarkerFile)) &&
                  File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)),
                "the v2 move writes the document and both markers");
            Check(csv.All(pair => File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)) && Csv(root).Count == csv.Count,
                "the v2 move leaves the earlier CSV files byte for byte, old overall opacity included");
            Check(state.Settings.EventNotificationBackgroundOpacity == 0.15 && state.Layout.All(item => item.BackgroundOpacity == 0.15) &&
                  !state.Settings.ShowChat, "the moved preset reads at the old look");
            var reopened = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            Check(reopened.Settings.EventNotificationBackgroundOpacity == 0.15 && reopened.Layout.All(item => item.BackgroundOpacity == 0.15) &&
                  reopened.Settings.Opacity == state.Settings.Opacity,
                "the v2 document is not scaled again");
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    /// <summary>
    /// Review CX-OVERLAY-M94-MIGRATION-R1: a v2 preset written before the marker (with its visor sidecar) is scaled once when
    /// another preset's CSV is moved; its sidecar goes with it, so the visor settings stay.
    /// </summary>
    private static void V2MoveKeepsVisorSidecar()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-background-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: true);
            var state = store.Load();
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive,
                Settings: state.Settings with { VisorChatPlate = false, VisorHolidayGold = true, EventNotificationBackgroundOpacity = 1.0 },
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            var active = state.ActivePresetId;
            // as an earlier build left it: no background marker, so this document is on the old scale
            File.Delete(Path.Combine(root, OverlayWorkspaceStore.BackgroundMarkerFile));
            var before = state.Layout.Select(item => item.BackgroundOpacity).ToArray();
            File.WriteAllText(Path.Combine(root, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
                [new(active, "Default"), new("second", "Second")]));
            File.WriteAllText(Path.Combine(root, "overlay.second.settings"),
                (OverlayDisplaySettings.Default with { EventNotificationBackgroundOpacity = 1.0 }).Serialize());
            var csv = Csv(root);
            var moved = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
            var first = moved.Presets.Single(preset => preset.Id == active);
            Check(File.Exists(Path.Combine(root, "overlay.second.workspace.json")) &&
                  File.Exists(Path.Combine(root, OverlayWorkspaceStore.BackgroundMarkerFile)),
                "the second preset is moved, with the marker");
            Check(!first.Settings.VisorChatPlate && first.Settings.VisorHolidayGold &&
                  first.Settings.EventNotificationBackgroundOpacity == 0.15 &&
                  first.Layout.Select(item => item.BackgroundOpacity).SequenceEqual(before.Select(InformationOverlayDefaults.ScaleLegacyBackground)),
                "the earlier v2 preset keeps its visor settings and is scaled once");
            var reopened = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load().Presets.Single(preset => preset.Id == active);
            Check(!reopened.Settings.VisorChatPlate && reopened.Settings.VisorHolidayGold &&
                  reopened.Settings.EventNotificationBackgroundOpacity == 0.15 &&
                  reopened.Layout.Select(item => item.BackgroundOpacity).SequenceEqual(first.Layout.Select(item => item.BackgroundOpacity)),
                "after the move the visor sidecar still matches its document and nothing is scaled again");
            Check(csv.All(pair => File.ReadAllBytes(pair.Key).SequenceEqual(pair.Value)), "the move leaves the CSV files as they were");
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static void Rules()
    {
        Check(InformationOverlayDefaults.ScaleLegacyBackground(1.0) == 0.15 &&
              InformationOverlayDefaults.ScaleLegacyBackground(0.5) == 0.08 &&
              InformationOverlayDefaults.ScaleLegacyBackground(0) == 0,
            "an old value reads at 15% of itself (100% -> 15%, 50% -> 8%)");
        Check(InformationOverlayDefaults.CreateLayout(InformationOverlayPresetCodec.DefaultPresetId).All(item => item.BackgroundOpacity <= 0.15) &&
              InformationOverlayDefaults.CreateSettings(InformationOverlayPresetCodec.DefaultPresetId).EventNotificationBackgroundOpacity == 0.15,
            "new presets start at the look the visor always had");
    }

    private static void StoredCsv(bool enableSourcePresets)
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-background-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var tag = $" (source presets {enableSourcePresets})";
            File.WriteAllText(Path.Combine(root, "overlay.preset1.settings"),
                (OverlayDisplaySettings.Default with { EventNotificationBackgroundOpacity = 1.0, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(root, "overlay.preset1.layout"), InformationOverlayLayoutItem.SerializeMany(
                InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload)
                    .Select(item => new InformationOverlayLayoutItem(item.Key, item.X, item.Y, item.Width, item.Height,
                        item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked, item.TextOpacity, 1.0, item.DecorationOpacity))));
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets);
            var state = store.Load();
            Check(state.Settings.EventNotificationBackgroundOpacity == 0.15 && state.Layout.All(item => item.BackgroundOpacity == 0.15),
                "a saved 100% reads at the old look (15%)" + tag);
            // the next write keeps it and marks the scaling as done
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings with { ShowChat = true },
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            var reopened = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets).Load();
            Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.BackgroundMarkerFile)) &&
                  reopened.Settings.EventNotificationBackgroundOpacity == 0.15 && reopened.Layout.All(item => item.BackgroundOpacity == 0.15) &&
                  reopened.Settings.ShowChat,
                "after the next write it is not scaled again" + tag);
            // the user now chooses a solid plate: it stays
            var solid = reopened.Layout.Select(item => new InformationOverlayLayoutItem(item.Key, item.X, item.Y, item.Width, item.Height,
                item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked, item.TextOpacity, 1.0, item.DecorationOpacity)).ToArray();
            store.Apply(new(reopened.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: reopened.Settings, Layout: solid,
                RenderMode: reopened.RenderMode, Hotkey: reopened.Hotkey));
            var again = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets).Load();
            Check(again.Layout.All(item => item.BackgroundOpacity == 1.0), "a solid plate chosen afterwards stays at 100%" + tag);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    /// <summary>
    /// Review CX-OVERLAY-TIDY-R3: a user past the earlier 0.7.3 move has its marker already; a crash while the background
    /// scaling is written (its marker in place, the scaled file not) is finished from the journal, never scaled twice.
    /// </summary>
    private static void Interrupted()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-background-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var file = "overlay.preset1.settings";
            File.WriteAllText(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile), "1");
            File.WriteAllText(Path.Combine(root, file),
                (OverlayDisplaySettings.Default with { EventNotificationBackgroundOpacity = 1.0, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(root, OverlayWorkspaceStore.BackgroundMarkerFile), "1");
            File.WriteAllText(Path.Combine(root, OverlayWorkspaceStore.MigrationJournalFile), System.Text.Json.JsonSerializer.Serialize(new
            {
                Writes = new Dictionary<string, string>
                {
                    [file] = (OverlayDisplaySettings.Default with { EventNotificationBackgroundOpacity = 0.15, ShowChat = false }).Serialize(),
                    [OverlayWorkspaceStore.BackgroundMarkerFile] = "1",
                },
                Binary = new Dictionary<string, string>(),
                Deletes = new List<string>(),
            }));
            var state = new OverlayWorkspaceStore(root).Load();
            Check(state.Settings.EventNotificationBackgroundOpacity == 0.15 && !state.Settings.ShowChat &&
                  !File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationJournalFile)) &&
                  new OverlayWorkspaceStore(root).Load().Settings.EventNotificationBackgroundOpacity == 0.15,
                "an interrupted background write is finished from its journal: 15%, not 2% and not 100%");
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static void Shipped()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-background-" + Guid.NewGuid().ToString("N"));
        var shipped = Path.Combine(root, "config");
        var data = Path.Combine(root, "data");
        Directory.CreateDirectory(shipped);
        Directory.CreateDirectory(data);
        try
        {
            // a shipped layout without opacities (each reads 100%, the old faint plate)
            File.WriteAllText(Path.Combine(shipped, "overlay.layout"), "Notice,0.34,0.02,0.3346,0.0795;Members,0,0.5703,0.144,0.1797");
            File.WriteAllText(Path.Combine(data, OverlayWorkspaceStore.BackgroundMarkerFile), "1");
            var state = new OverlayWorkspaceStore(data, shipped).Load();
            Check(state.Layout.Single(item => item.Key == "Members").BackgroundOpacity == 0.15,
                "a file shipped with the client always reads at the old look, marker or not");
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
