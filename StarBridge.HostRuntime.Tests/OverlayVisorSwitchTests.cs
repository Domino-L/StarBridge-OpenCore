using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

// 0.7.3 overlay v2 storage (user, 11-07: "我觉得需要把之前浮层存的全部重置掉，这完全是一个新的东西了"):
// v2 keeps its own files in OverlayWorkspaceStore.V2Folder and starts from defaults on the visor. The earlier
// overlay files are never read, written or deleted, so 0.7.2.1 still finds them as they were. The overlay hotkey
// stays in the shared desktop.config. The one-time line shows once for users who had the earlier overlay.
// (The 11-06 one-time switch to the visor is gone; this file used to test it.)
internal static class OverlayVisorSwitchTests
{
    private const string OldHotkey = "Ctrl+Alt+F9";

    internal static Task Run()
    {
        foreach (var versioned in new[] { false, true })
        {
            var tag = versioned ? " (source presets)" : "";

            // A fresh install: the visor, no line, and a read writes nothing.
            WithRoot(root =>
            {
                var state = V2(root, versioned).Load();
                Check(state.Settings.Skin == OverlaySkin.Visor && state.Settings.EffectiveRequestedSkin == OverlaySkin.Visor,
                    "a fresh install starts on the visor" + tag);
                Check(!Directory.Exists(root) && !state.VisorSwitchNotice, "a fresh install writes nothing and shows no line" + tag);
                Check(state.Presets.All(preset => preset.Settings.CalmDisplay == OverlayCalmDisplay.Off),
                    "v2 starts with calm display off (user, 11-07)" + tag);
                Check(new OverlayWorkspaceStore(root, enableSourcePresets: versioned).Load().Settings.CalmDisplay != OverlayCalmDisplay.Off,
                    "the earlier storage keeps its own default" + tag);
                V2(root, versioned).DismissVisorNotice();
                Check(!Directory.Exists(root), "dismissing without a line writes nothing" + tag);
            });

            // A user of the earlier overlay: v2 starts from defaults, the old files stay byte for byte.
            WithRoot(root =>
            {
                OldUser(root);
                var before = Snapshot(root);
                var state = V2(root, versioned).Load();
                Check(state.Settings.Skin == OverlaySkin.Visor, "the old user starts on the visor" + tag);
                var fresh = V2(Path.Combine(root, "fresh-never-created"), versioned).Load().Settings;
                Check(state.Settings == Kept(fresh, true), "only the four game-linked choices are carried over" + tag);
                Check(state.Presets.All(preset => preset.Settings.AutoOpenOverlayOnGameStart && preset.Settings.AutoFocusGameWindowOnOpen),
                    "every preset v2 has not saved shows the kept choices" + tag);
                Check(state.Hotkey.Binding == OldHotkey && !state.Hotkey.Enabled, "the overlay hotkey and its switch stay" + tag);
                Check(state.VisorSwitchNotice, "the old user gets the one-time line" + tag);
                Check(Same(before, Snapshot(root)) && !Directory.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder)),
                    "a read writes nothing" + tag);

                state = V2(root, versioned).Apply(Save(state, state.Settings with { Opacity = 0.5 }));
                Check(Math.Abs(state.Settings.Opacity - 0.5) < 0.001 && state.VisorSwitchNotice, "a save keeps the pending line" + tag);
                Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder, OverlayWorkspaceStore.CarriedFile)),
                    "the first save stores the kept choices in the v2 folder" + tag);
                Check(Same(before, Snapshot(root)), "a save leaves every earlier file as it was, desktop.config included" + tag);
                Check(File.Exists(Path.Combine(root, "desktop.registered-hotkey.json")) &&
                    !File.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder, "desktop.registered-hotkey.json")),
                    "the shared hotkey file stays shared, as before v2" + tag);
                var v2Files = Directory.GetFiles(Path.Combine(root, OverlayWorkspaceStore.V2Folder)).Select(Path.GetFileName).ToArray();
                Check(v2Files.Length > 0 && v2Files.All(name => name!.StartsWith("overlay.", StringComparison.Ordinal)),
                    "the save went into the v2 folder" + tag);
                Check(!v2Files.Any(name => name!.Contains(".tmp", StringComparison.Ordinal) || name!.Contains(".rollback", StringComparison.Ordinal)),
                    "no temporary files are left" + tag);

                V2(root, versioned).DismissVisorNotice();
                state = V2(root, versioned).Load();
                Check(!state.VisorSwitchNotice && Math.Abs(state.Settings.Opacity - 0.5) < 0.001 && state.Settings.Skin == OverlaySkin.Visor,
                    "the line shows once; the v2 save stays" + tag);
                Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder, OverlayWorkspaceStore.V2NoticeFile)),
                    "the marker lives in the v2 folder" + tag);
                Check(Same(before, Snapshot(root)), "dismissing leaves the earlier files as they were" + tag);

                // The copy happened once: a later change to the earlier file is not read.
                File.WriteAllText(Path.Combine(root, "overlay.settings"),
                    string.Join(",", Kept(OverlayDisplaySettings.Default, false).Serialize().Split(',').Take(80)));
                state = V2(root, versioned).Load();
                Check(state.Presets.All(preset => preset.Settings.AutoOpenOverlayOnGameStart && preset.Settings.AutoCloseOverlayOnGameBackground),
                    "after the copy the earlier file is not read again" + tag);
                File.WriteAllText(Path.Combine(root, "overlay.settings"), OldCsv());

                // Rolled back: the earlier storage reads exactly what the user had.
                var old = new OverlayWorkspaceStore(root, enableSourcePresets: versioned).Load();
                Check(Math.Abs(old.Settings.Opacity - 0.66) < 0.001 && old.Settings.EffectiveRequestedSkin == OverlaySkin.Default,
                    "the earlier storage still reads the user's old settings" + tag);
            });

            // Dismissing the line first also stores the copy.
            WithRoot(root =>
            {
                OldUser(root);
                V2(root, versioned).DismissVisorNotice();
                Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder, OverlayWorkspaceStore.CarriedFile)),
                    "dismissing the line stores the kept choices" + tag);
                File.Delete(Path.Combine(root, "overlay.settings"));
                Check(V2(root, versioned).Load().Settings.AutoOpenOverlayOnGameForeground, "the copy stays after the earlier file is gone" + tag);
            });

            // Missing or damaged earlier settings: the defaults.
            foreach (var (kind, content) in new[] { ("missing", (string?)null), ("damaged", "{ not a settings row"), ("empty", "") })
            WithRoot(root =>
            {
                OldUser(root);
                if (content is null) File.Delete(Path.Combine(root, "overlay.settings"));
                else File.WriteAllText(Path.Combine(root, "overlay.settings"), content);
                var before = Snapshot(root);
                var state = V2(root, versioned).Load();
                var fresh = V2(Path.Combine(root, "fresh-never-created"), versioned).Load().Settings;
                Check(state.Settings == fresh, $"{kind} earlier settings give the defaults" + tag);
                state = V2(root, versioned).Apply(Save(state, state.Settings with { Opacity = 0.5 }));
                Check(Same(before, Snapshot(root)), $"{kind}: the earlier files stay as they were" + tag);
                Check(!state.Settings.AutoOpenOverlayOnGameStart, $"{kind}: the stored copy holds the defaults" + tag);
            });

            // A choice the user changes in v2 stays.
            WithRoot(root =>
            {
                OldUser(root);
                var state = V2(root, versioned).Load();
                V2(root, versioned).Apply(Save(state, state.Settings with { AutoOpenOverlayOnGameStart = false }));
                state = V2(root, versioned).Load();
                Check(!state.Settings.AutoOpenOverlayOnGameStart && state.Settings.AutoOpenOverlayOnGameForeground,
                    "a kept choice the user turns off in v2 stays off" + tag);
            });

            // Reset and new presets use the v2 defaults; calm display can still be turned on and stays on.
            WithRoot(root =>
            {
                OldUser(root);
                var state = V2(root, versioned).Load();
                state = V2(root, versioned).Apply(Save(state, state.Settings with
                {
                    CalmDisplay = OverlayCalmDisplay.On, Opacity = 0.4, Skin = OverlaySkin.Default, RequestedSkin = OverlaySkin.Default
                }));
                Check(V2(root, versioned).Load().Settings.CalmDisplay == OverlayCalmDisplay.On, "calm display turned on stays on" + tag);
                state = V2(root, versioned).Apply(new OverlayWorkspaceMutation(state.Revision, OverlayWorkspaceMutationKind.ResetPreset,
                    PresetId: state.ActivePresetId));
                state = V2(root, versioned).Load();
                Check(state.Settings.CalmDisplay == OverlayCalmDisplay.Off && state.Settings.Skin == OverlaySkin.Visor &&
                    Math.Abs(state.Settings.Opacity - 0.4) > 0.001 && state.Settings.AutoOpenOverlayOnGameStart,
                    "a reset preset gets the v2 defaults and the kept choices" + tag);
                state = V2(root, versioned).Apply(new OverlayWorkspaceMutation(state.Revision, OverlayWorkspaceMutationKind.CreatePreset,
                    Name: "新预设"));
                var created = state.Presets.First(preset => preset.Name == "新预设");
                Check(created.Settings.CalmDisplay == OverlayCalmDisplay.Off && created.Settings.Skin == OverlaySkin.Visor &&
                    created.Settings.AutoFocusGameWindowOnOpen, "a new preset gets the v2 defaults and the kept choices" + tag);
            });

            // Shipped defaults in the install folder (the fallback root) are defaults, not saves: v2 still applies its own.
            WithRoot(root =>
            {
                OldUser(root);
                var shipped = Path.Combine(root, "install-config");
                Directory.CreateDirectory(shipped);
                File.WriteAllText(Path.Combine(shipped, "overlay.settings"),
                    (OverlayDisplaySettings.Default with { CalmDisplay = OverlayCalmDisplay.On, Opacity = 0.9 }).Serialize());
                var store = new OverlayWorkspaceStore(root, shipped, versioned, OverlayWorkspaceStore.V2Folder);
                var state = store.Load();
                Check(state.Settings.Skin == OverlaySkin.Visor && state.Settings.CalmDisplay == OverlayCalmDisplay.Off &&
                    state.Settings.AutoOpenOverlayOnGameStart, "shipped defaults still get the v2 defaults and the kept choices" + tag);
                Check(Math.Abs(state.Settings.Opacity - 0.66) > 0.001, "the earlier user's settings do not come in through the fallback" + tag);
            });

            // An oversized earlier settings file is not read: the defaults.
            WithRoot(root =>
            {
                OldUser(root);
                File.WriteAllText(Path.Combine(root, "overlay.settings"), OldCsv() + new string(' ', 70 * 1024));
                Check(!V2(root, versioned).Load().Settings.AutoOpenOverlayOnGameStart, "an oversized earlier file gives the defaults" + tag);
            });

            // A write that fails on the shared desktop.config leaves no v2 file behind (one transaction over both folders).
            // desktop.config is held open for reading only: the store can still read it (same revision), but cannot
            // replace it, so the failure happens inside the write transaction.
            WithRoot(root =>
            {
                OldUser(root);
                V2(root, versioned).DismissVisorNotice(); // the v2 folder exists with its two markers
                var v2 = Path.Combine(root, OverlayWorkspaceStore.V2Folder);
                var v2Before = Directory.GetFiles(v2).ToDictionary(path => Path.GetFileName(path)!, File.ReadAllBytes);
                var before = Snapshot(root);
                var state = V2(root, versioned).Load();
                string? code = null;
                using (new FileStream(Path.Combine(root, "desktop.config"), FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    try
                    {
                        V2(root, versioned).Apply(new OverlayWorkspaceMutation(state.Revision, OverlayWorkspaceMutationKind.SaveActive,
                            Settings: state.Settings with { Opacity = 0.3 }, Layout: state.Layout, RenderMode: state.RenderMode,
                            Hotkey: state.Hotkey with { Binding = "Ctrl+Shift+F11" }));
                    }
                    catch (OverlaySettingsException error) { code = error.Code; }
                }
                Check(code == "overlay.workspace_write_failed", $"the write itself fails (got {code ?? "no error"})" + tag);
                var v2After = Directory.GetFiles(v2).Select(Path.GetFileName)
                    .Where(name => !name!.StartsWith("overlay.workspace-backup", StringComparison.Ordinal)).ToArray();
                Check(v2After.Length == v2Before.Count && v2Before.All(pair => File.ReadAllBytes(Path.Combine(v2, pair.Key)).AsSpan().SequenceEqual(pair.Value)),
                    "the v2 folder is exactly as before the failed write: " + string.Join(", ", v2After) + tag);
                Check(!Directory.GetFiles(root, "*.tmp", SearchOption.AllDirectories).Any() &&
                    !Directory.GetFiles(root, "*.rollback", SearchOption.AllDirectories).Any(), "no temporary or rollback files are left: " + string.Join(", ", Directory.GetFiles(root, "*.tmp", SearchOption.AllDirectories).Concat(Directory.GetFiles(root, "*.rollback", SearchOption.AllDirectories)).Select(f => Path.GetRelativePath(root, f))) + tag);
                Check(Same(before, Snapshot(root)), "the earlier files and desktop.config are unchanged after the failed write" + tag);
                Check(Math.Abs(V2(root, versioned).Load().Settings.Opacity - 0.3) > 0.001, "the failed save is not visible" + tag);
            });

            // The automatic migration of a v2 settings row stores the kept choices with its first write; later changes
            // to the earlier file do not reach new or reset presets.
            if (versioned)
            WithRoot(root =>
            {
                OldUser(root);
                var v2 = Path.Combine(root, OverlayWorkspaceStore.V2Folder);
                Directory.CreateDirectory(v2);
                File.WriteAllText(Path.Combine(v2, "overlay.settings"), OverlayDisplaySettings.Default.Serialize());
                var state = V2(root, versioned).Load(); // migrates the row into a v2 document
                Check(Directory.GetFiles(v2, "overlay.*.workspace.json").Length > 0, "the v2 row was migrated" + tag);
                Check(File.Exists(Path.Combine(v2, OverlayWorkspaceStore.CarriedFile)), "the migration stored the kept choices" + tag);
                File.WriteAllText(Path.Combine(root, "overlay.settings"),
                    string.Join(",", Kept(OverlayDisplaySettings.Default, false).Serialize().Split(',').Take(80)));
                state = V2(root, versioned).Apply(new OverlayWorkspaceMutation(state.Revision, OverlayWorkspaceMutationKind.ResetPreset,
                    PresetId: state.ActivePresetId));
                Check(state.Settings.AutoOpenOverlayOnGameStart && state.Settings.AutoOpenOverlayOnGameForeground &&
                    state.Settings.AutoCloseOverlayOnGameBackground && state.Settings.AutoFocusGameWindowOnOpen,
                    "a reset after the migration uses the stored copy, not the changed earlier file" + tag);
            });

            // A look the user picks in v2 stays; v2 never switches what the user saved.
            WithRoot(root =>
            {
                OldUser(root);
                var state = V2(root, versioned).Load();
                V2(root, versioned).Apply(Save(state, state.Settings with { Skin = OverlaySkin.Default, RequestedSkin = OverlaySkin.Default }));
                state = V2(root, versioned).Load();
                Check(state.Settings.EffectiveRequestedSkin == OverlaySkin.Default, "the user's own choice in v2 stays" + tag);
            });

            // Changing the hotkey in v2 writes the shared desktop.config, not a copy in the v2 folder.
            WithRoot(root =>
            {
                OldUser(root);
                var state = V2(root, versioned).Load();
                V2(root, versioned).Apply(new OverlayWorkspaceMutation(state.Revision, OverlayWorkspaceMutationKind.SaveActive,
                    Settings: state.Settings, Layout: state.Layout, RenderMode: state.RenderMode,
                    Hotkey: state.Hotkey with { Binding = "Ctrl+Shift+F10", Enabled = true }));
                Check(File.ReadAllLines(Path.Combine(root, "desktop.config"))[4] == "Ctrl+Shift+F10", "the hotkey is written to the shared file" + tag);
                Check(!File.Exists(Path.Combine(root, OverlayWorkspaceStore.V2Folder, "desktop.config")), "no desktop.config in the v2 folder" + tag);
                Check(V2(root, versioned).Load().Hotkey.Binding == "Ctrl+Shift+F10", "v2 reads it back" + tag);
            });
        }

        // Other looks saved in the earlier storage stay saved there (the folder-less store is what 0.7.2.1 reads).
        foreach (var skin in new[] { OverlaySkin.NightShadow, OverlaySkin.Verdict, OverlaySkin.HajiCitizen })
        WithRoot(root =>
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "overlay.settings"),
                (OverlayDisplaySettings.Default with { Skin = skin, RequestedSkin = skin }).Serialize());
            var state = new OverlayWorkspaceStore(root).Load();
            Check(state.Settings.EffectiveRequestedSkin == skin && !state.VisorSwitchNotice, skin + " is not switched");
            Check(Directory.GetFiles(root).Length == 1, skin + ": a read writes nothing");
            state = new OverlayWorkspaceStore(root).Apply(Save(state, state.Settings with { Opacity = 0.7 }));
            state = new OverlayWorkspaceStore(root).Load();
            Check(state.Settings.Skin == skin && state.Settings.EffectiveRequestedSkin == skin && Math.Abs(state.Settings.Opacity - 0.7) < 0.001,
                skin + ": a save while it is put away keeps it saved");
            Check(!new OverlayWorkspaceStore(root, overlayFolder: OverlayWorkspaceStore.V2Folder).Load().Settings.Skin.Equals(skin),
                skin + ": v2 does not pick it up");
        });
        Console.WriteLine("PASS 0.7.3 overlay v2 storage: starts from defaults, four game-linked choices copied once, earlier files untouched, hotkey kept, line once");
        return Task.CompletedTask;
    }

    private static OverlayWorkspaceStore V2(string root, bool versioned) =>
        new(root, enableSourcePresets: versioned, overlayFolder: OverlayWorkspaceStore.V2Folder);

    private static OverlayWorkspaceMutation Save(OverlayWorkspaceReadResult state, OverlayDisplaySettings settings) =>
        new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: settings,
            Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey);

    private static OverlayDisplaySettings Kept(OverlayDisplaySettings value, bool on) => value with
    {
        AutoOpenOverlayOnGameStart = on, AutoOpenOverlayOnGameForeground = on,
        AutoCloseOverlayOnGameBackground = on, AutoFocusGameWindowOnOpen = on
    };

    // 0.7.2 wrote 80 columns; the old user turned on all four game-linked choices.
    private static string OldCsv() => string.Join(",",
        Kept(OverlayDisplaySettings.Default with { Opacity = 0.66, ShowMembers = !OverlayDisplaySettings.Default.ShowMembers }, true)
            .Serialize().Split(',').Take(80));

    private static void OldUser(string root)
    {
        Directory.CreateDirectory(root);
        var csv = OldCsv();
        File.WriteAllText(Path.Combine(root, "overlay.settings"), csv);
        File.WriteAllText(Path.Combine(root, "overlay.default.settings"), csv);
        File.WriteAllText(Path.Combine(root, "overlay.layout"),
            InformationOverlayLayoutItem.SerializeMany(InformationOverlayDefaults.CreateLayout("default")));
        File.WriteAllText(Path.Combine(root, "overlay.active-preset"), "default");
        var lines = Enumerable.Repeat("", 16).ToArray();
        lines[4] = OldHotkey;
        lines[15] = "False";
        File.WriteAllLines(Path.Combine(root, "desktop.config"), lines);
    }

    /// <summary>
    /// Every file under the root except the v2 folder and the shared registered-hotkey record, which a save writes
    /// whether or not v2 is on (it is not an overlay file).
    /// </summary>
    private static Dictionary<string, byte[]> Snapshot(string root)
    {
        var v2 = Path.Combine(root, OverlayWorkspaceStore.V2Folder) + Path.DirectorySeparatorChar;
        return Directory.GetFiles(root, "*", SearchOption.AllDirectories)
            .Where(path => !path.StartsWith(v2, StringComparison.OrdinalIgnoreCase) &&
                !Path.GetFileName(path).Equals("desktop.registered-hotkey.json", StringComparison.OrdinalIgnoreCase))
            .ToDictionary(path => Path.GetRelativePath(root, path), File.ReadAllBytes, StringComparer.OrdinalIgnoreCase);
    }

    private static bool Same(Dictionary<string, byte[]> before, Dictionary<string, byte[]> after) =>
        before.Count == after.Count &&
        before.All(pair => after.TryGetValue(pair.Key, out var bytes) && bytes.AsSpan().SequenceEqual(pair.Value));

    private static void WithRoot(Action<string> body)
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-v2-storage-" + Guid.NewGuid().ToString("N"));
        try { body(root); }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
