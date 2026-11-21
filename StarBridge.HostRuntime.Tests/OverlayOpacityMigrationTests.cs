using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

/// <summary>
/// 0.7.3: the overall opacity takes effect (it never did before; the overlay was always drawn full). User, 11-10:
/// "默认改成 100%" - nobody's overlay may turn fainter. Each preset still at its old default (default and own presets
/// 0.85, compact 0.78, command 0.9) moves to full once per data root; any other saved value is kept; a value chosen later
/// (even 0.85) stays.
/// </summary>
internal static class OverlayOpacityMigrationTests
{
    internal static void Run()
    {
        Rules();
        StoredCsv(enableSourcePresets: false);
        StoredCsv(enableSourcePresets: true);
        EmptyStore();
        OtherPreset();
        RetiredBuiltIns();
        RetiredInGlobalFiles();
        TwoInstances();
        InterruptedWrite();
        JournalFailures();
        Console.WriteLine("PASS overlay opacity migration");
    }

    private static void Rules()
    {
        OverlayDisplaySettings At(double opacity) => OverlayDisplaySettings.Default with { Opacity = opacity };
        Check(OverlayDisplaySettings.Default.Opacity == 1 &&
              InformationOverlayDefaults.CreateSettings("compact").Opacity == 1 &&
              InformationOverlayDefaults.CreateSettings("command").Opacity == 1,
            "every preset's default overall opacity is full");
        Check(InformationOverlayDefaults.MigrateLegacyOpacity(InformationOverlayPresetCodec.DefaultPresetId, At(0.85)).Opacity == 1 &&
              InformationOverlayDefaults.MigrateLegacyOpacity("my-own", At(0.85)).Opacity == 1 &&
              InformationOverlayDefaults.MigrateLegacyOpacity("compact", At(0.78)).Opacity == 1 &&
              InformationOverlayDefaults.MigrateLegacyOpacity("command", At(0.9)).Opacity == 1,
            "each preset's old default moves to full (default and own 85%, compact 78%, command 90%)");
        Check(InformationOverlayDefaults.MigrateLegacyOpacity(InformationOverlayPresetCodec.DefaultPresetId, At(0.6)).Opacity == 0.6 &&
              InformationOverlayDefaults.MigrateLegacyOpacity("compact", At(0.85)).Opacity == 0.85 &&
              InformationOverlayDefaults.MigrateLegacyOpacity("command", At(0.78)).Opacity == 0.78,
            "any other saved value is kept (another preset's old default is a choice here)");
        Check(OverlayDisplaySettings.Parse(At(0.85).Serialize()).Opacity == 0.85, "reading a saved value never changes it by itself");
    }

    private static void StoredCsv(bool enableSourcePresets)
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "overlay.preset1.settings"),
                (OverlayDisplaySettings.Default with { Opacity = 0.85, ShowChat = false }).Serialize());
            var store = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets);
            var before = Directory.GetFiles(root).Length;
            var state = store.Load();
            var marked = File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile));
            // a read shows it moved; it writes only when the v2 move writes anyway (source presets), with the marker
            Check(state.Settings.Opacity == 1 && !state.Settings.ShowChat &&
                  (enableSourcePresets ? marked : !marked && Directory.GetFiles(root).Length == before),
                $"a stored old default reads as full; a read alone writes nothing (source presets {enableSourcePresets})");
            // the user's next change (here only the chat) writes the moved value and the marker with it
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings with { ShowChat = true },
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            var reopened = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets).Load();
            Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)) && reopened.Settings.Opacity == 1 && reopened.Settings.ShowChat,
                $"the next write keeps it full and marks the move as done (source presets {enableSourcePresets})");
            // the user now chooses 85% on purpose: it stays
            state = store.Apply(new(reopened.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: reopened.Settings with { Opacity = 0.85 },
                Layout: reopened.Layout, RenderMode: reopened.RenderMode, Hotkey: reopened.Hotkey));
            var again = new OverlayWorkspaceStore(root, enableSourcePresets: enableSourcePresets).Load();
            Check(state.Settings.Opacity == 0.85 && again.Settings.Opacity == 0.85,
                $"a value chosen after the move (even 85%) stays (source presets {enableSourcePresets})");

            // a value the user chose before is kept by the move
            var other = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(other);
            try
            {
                File.WriteAllText(Path.Combine(other, "overlay.preset1.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize());
                Check(new OverlayWorkspaceStore(other, enableSourcePresets: enableSourcePresets).Load().Settings.Opacity == 0.6,
                    $"a stored chosen value (60%) is kept (source presets {enableSourcePresets})");
            }
            finally { Directory.Delete(other, true); }
        }
        finally { Directory.Delete(root, true); }
    }

    private static void EmptyStore()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new OverlayWorkspaceStore(root);
            var state = store.Load();
            Check(state.Settings.Opacity == 1 && !Directory.Exists(root), "a new data root reads full and writes nothing on read");
            state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings with { Opacity = 0.85 },
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            Check(File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)) &&
                  new OverlayWorkspaceStore(root).Load().Settings.Opacity == 0.85,
                "the first save of a new data root marks the move as done: a chosen 85% stays");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    /// <summary>A preset that is not active moves too, written with the first write (here a change to another preset).</summary>
    private static void OtherPreset()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
            [
                new(InformationOverlayPresetCodec.DefaultPresetId, "默认预设"),
                new("compact", "紧凑"),
            ]));
            File.WriteAllText(Path.Combine(root, "overlay.active-preset"), InformationOverlayPresetCodec.DefaultPresetId);
            File.WriteAllText(Path.Combine(root, "overlay.preset1.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize());
            File.WriteAllText(Path.Combine(root, "overlay.compact.settings"),
                InformationOverlayDefaults.CreateSettings("compact").With(0.78).Serialize());
            var store = new OverlayWorkspaceStore(root);
            var state = store.Load();
            double Compact(OverlayWorkspaceReadResult r) => r.Presets.Single(p => p.Id == "compact").Settings.Opacity;
            Check(Compact(state) == 1 && state.Settings.Opacity == 0.6, "a stored compact preset at its old 78% reads as full; the active 60% is kept");
            store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings with { ShowChat = false },
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            var after = new OverlayWorkspaceStore(root).Load();
            Check(Compact(after) == 1 && after.Settings.Opacity == 0.6 && File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)),
                "the first write carries the other preset's move too, and marks it");
        }
        finally { Directory.Delete(root, true); }
    }

    /// <summary>
    /// The earlier built-in layouts (user, 11-10: "3套预设布局只是之前遗留下来的废弃代码"): one never saved is dropped and,
    /// in use, the default takes over; one the user saved stays as their own preset, name and content unchanged. A read
    /// writes nothing; the next write carries the list.
    /// </summary>
    private static void RetiredBuiltIns()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
            [
                new(InformationOverlayPresetCodec.DefaultPresetId, "默认预设"),
                new("compact", "紧凑"),
                new("command", "指挥"),
                new("combat", "战斗"),
            ]));
            File.WriteAllText(Path.Combine(root, "overlay.active-preset"), "compact");
            var commandLayout = "Notice,0.285,0,0.43,0.075;Squads,0.01,0.30,0.18,0.42;Members,0.78,0.54,0.21,0.26;Chat,0.35,0.75,0.30,0.21";
            File.WriteAllText(Path.Combine(root, "overlay.command.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.6, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(root, "overlay.command.layout"), commandLayout);
            var before = Directory.GetFiles(root).Length;
            var store = new OverlayWorkspaceStore(root);
            var state = store.Load();
            var ids = string.Join(",", state.Presets.Select(p => p.Id));
            var command = state.Presets.SingleOrDefault(p => p.Id == "command");
            Check(ids == "preset1,command" && state.ActivePresetId == InformationOverlayPresetCodec.DefaultPresetId && state.StorageState != "recoveredDefaults" &&
                  command is { Name: "指挥" } && command.Settings.Opacity == 0.6 && !command.Settings.ShowChat &&
                  InformationOverlayLayoutItem.SerializeMany(command.Layout).StartsWith("Notice,0.285", StringComparison.Ordinal),
                "retired built-ins: never saved ones (compact, combat) are dropped and the default takes over; a saved one stays as the user's own",
                new { ids, state.ActivePresetId, state.StorageState });
            Check(Directory.GetFiles(root).Length == before, "retired built-ins: a read writes nothing");
            store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings,
                Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
            var manifest = File.ReadAllText(Path.Combine(root, "overlay.presets"));
            var after = new OverlayWorkspaceStore(root).Load();
            Check(!manifest.Contains("compact") && !manifest.Contains("combat") && manifest.Contains("command") &&
                  File.ReadAllText(Path.Combine(root, "overlay.active-preset")).Trim() == InformationOverlayPresetCodec.DefaultPresetId &&
                  File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)) &&
                  string.Join(",", after.Presets.Select(p => p.Id)) == "preset1,command",
                "retired built-ins: the next write carries the list without them, the default active, and the marker");
        }
        finally { Directory.Delete(root, true); }
    }

    /// <summary>A retired built-in in use that saved only into the global files is the user's own (review R2).</summary>
    private static void RetiredInGlobalFiles()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "overlay.presets"), InformationOverlayPresetCodec.SerializeManifest(
                [new(InformationOverlayPresetCodec.DefaultPresetId, "默认预设"), new("compact", "紧凑")]));
            File.WriteAllText(Path.Combine(root, "overlay.active-preset"), "compact");
            File.WriteAllText(Path.Combine(root, "overlay.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.78, ShowChat = false }).Serialize());
            var state = new OverlayWorkspaceStore(root).Load();
            Check(state.ActivePresetId == "compact" && state.Presets.Any(p => p.Id == "compact" && p.Name == "紧凑") &&
                  state.Settings.Opacity == 1 && !state.Settings.ShowChat,
                "retired built-ins: one in use saved only in the global files stays the user's own, its old 78% moved to full",
                new { state.ActivePresetId, state.Settings.Opacity });
        }
        finally { Directory.Delete(root, true); }
    }

    /// <summary>
    /// Two instances read before the move is written; one chooses 85% on purpose (writing the marker); the other saves
    /// from its older snapshot: refused as stale, so it cannot put back the moved 100% (review R2).
    /// </summary>
    private static void TwoInstances()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "overlay.preset1.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.85 }).Serialize());
            var a = new OverlayWorkspaceStore(root);
            var b = new OverlayWorkspaceStore(root);
            var sa = a.Load();
            var sb = b.Load();
            a.Apply(new(sa.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: sa.Settings with { Opacity = 0.85 },
                Layout: sa.Layout, RenderMode: sa.RenderMode, Hotkey: sa.Hotkey));
            var refused = false;
            try
            {
                b.Apply(new(sb.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: sb.Settings with { ShowChat = false },
                    Layout: sb.Layout, RenderMode: sb.RenderMode, Hotkey: sb.Hotkey));
            }
            catch (OverlaySettingsException error) when (error.Code == "overlay.workspace_revision_conflict") { refused = true; }
            Check(refused && new OverlayWorkspaceStore(root).Load().Settings.Opacity == 0.85,
                "two instances: a save from a snapshot older than the marker is refused; the chosen 85% stays");
        }
        finally { Directory.Delete(root, true); }
    }

    /// <summary>
    /// A write that set the marker was cut off after the marker but before the settings (review R3): the next load
    /// finishes it from its journal, so the move is not lost, and a value the user chose in it is not moved again.
    /// </summary>
    private static void InterruptedWrite()
    {
        foreach (var (decided, expected, name) in new[] { (1.0, 1.0, "the move"), (0.85, 0.85, "the user's chosen 85%") })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var file = "overlay.preset1.settings";
                File.WriteAllText(Path.Combine(root, file), (OverlayDisplaySettings.Default with { Opacity = 0.85, ShowChat = false }).Serialize());
                // the marker is in place, the settings file is not: the crash state
                File.WriteAllText(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile), "1");
                File.WriteAllText(Path.Combine(root, OverlayWorkspaceStore.MigrationJournalFile), System.Text.Json.JsonSerializer.Serialize(new
                {
                    Writes = new Dictionary<string, string>
                    {
                        [file] = (OverlayDisplaySettings.Default with { Opacity = decided, ShowChat = false }).Serialize(),
                        [OverlayWorkspaceStore.MigrationMarkerFile] = "1",
                    },
                    Binary = new Dictionary<string, string>(),
                    Deletes = new List<string>(),
                }));
                var inspected = new OverlayWorkspaceStore(root).Inspect();
                var state = new OverlayWorkspaceStore(root).Load();
                Check(state.Settings.Opacity == expected && !state.Settings.ShowChat &&
                      !File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationJournalFile)) &&
                      File.Exists(Path.Combine(root, OverlayWorkspaceStore.MigrationMarkerFile)) &&
                      new OverlayWorkspaceStore(root).Load().Settings.Opacity == expected,
                    $"interrupted write: the next load finishes it from the journal ({name} is in place, the journal gone)",
                    new { state.Settings.Opacity, inspected = inspected.Settings.Opacity });
            }
            finally { Directory.Delete(root, true); }
        }
        // a journal that cannot be read is dropped and the marker is not trusted while it was there
        var broken = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(broken);
        try
        {
            File.WriteAllText(Path.Combine(broken, "overlay.preset1.settings"), (OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize());
            File.WriteAllText(Path.Combine(broken, OverlayWorkspaceStore.MigrationJournalFile), "{ not json");
            var state = new OverlayWorkspaceStore(broken).Load();
            Check(state.Settings.Opacity == 0.6 && !File.Exists(Path.Combine(broken, OverlayWorkspaceStore.MigrationJournalFile)),
                "interrupted write: an unreadable journal is dropped, nothing else changes");
        }
        finally { Directory.Delete(broken, true); }
    }

    /// <summary>
    /// Review R4: a replay that fails keeps its journal and blocks every other write until it is finished; a journal whose
    /// binary part does not decode is dropped before anything is replaced; a failed first write leaves no journal or temp.
    /// </summary>
    private static void JournalFailures()
    {
        const string file = "overlay.preset1.settings";
        string NewRoot()
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-opacity-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return root;
        }
        string Journal(string? binaryValue, double decided = 1.0) => System.Text.Json.JsonSerializer.Serialize(new
        {
            Writes = new Dictionary<string, string>
            {
                [file] = (OverlayDisplaySettings.Default with { Opacity = decided, ShowChat = false }).Serialize(),
                [OverlayWorkspaceStore.MigrationMarkerFile] = "1",
            },
            Binary = binaryValue == "" ? new Dictionary<string, string?>() : new Dictionary<string, string?> { ["overlay.layout"] = binaryValue },
            Deletes = new List<string>(),
        });
        bool Leftovers(string root) => Directory.GetFiles(root).Any(path => Path.GetFileName(path).Contains(".tmp", StringComparison.OrdinalIgnoreCase));

        // 1. the replay fails (the settings file is held): the journal stays, the store reports a pending move and refuses saves
        var held = NewRoot();
        try
        {
            File.WriteAllText(Path.Combine(held, file), (OverlayDisplaySettings.Default with { Opacity = 0.85, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(held, OverlayWorkspaceStore.MigrationMarkerFile), "1");
            File.WriteAllText(Path.Combine(held, OverlayWorkspaceStore.MigrationJournalFile), Journal(""));
            OverlayWorkspaceReadResult pending;
            var refused = false;
            using (new FileStream(Path.Combine(held, file), FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var store = new OverlayWorkspaceStore(held);
                pending = store.Load();
                try
                {
                    store.Apply(new(pending.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: pending.Settings with { Opacity = 0.5 },
                        Layout: pending.Layout, RenderMode: pending.RenderMode, Hotkey: pending.Hotkey));
                }
                catch (OverlaySettingsException error) when (error.Code == "overlay.workspace_migration_pending") { refused = true; }
            }
            var journalKept = File.Exists(Path.Combine(held, OverlayWorkspaceStore.MigrationJournalFile));
            var after = new OverlayWorkspaceStore(held).Load();
            // while pending the files are shown as they are (nothing moved in memory): the stored 85% reads as 85%
            Check(journalKept && refused && pending.StorageState == "migrationPending" && pending.Settings.Opacity == 0.85 && !Leftovers(held) &&
                  after.Settings.Opacity == 1.0 && !after.Settings.ShowChat &&
                  !File.Exists(Path.Combine(held, OverlayWorkspaceStore.MigrationJournalFile)),
                "failed replay: the journal stays, saves are refused until it is finished, the next load finishes it",
                new { journalKept, refused, pending.StorageState, after.Settings.Opacity });
        }
        finally { Directory.Delete(held, true); }

        // 2. valid JSON whose binary part is not Base64: dropped before anything is replaced, the load does not throw
        var badBinary = NewRoot();
        try
        {
            File.WriteAllText(Path.Combine(badBinary, file), (OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize());
            File.WriteAllText(Path.Combine(badBinary, OverlayWorkspaceStore.MigrationJournalFile), Journal("!!not base64!!"));
            var state = new OverlayWorkspaceStore(badBinary).Load();
            Check(state.Settings.Opacity == 0.6 && !File.Exists(Path.Combine(badBinary, OverlayWorkspaceStore.MigrationJournalFile)) &&
                  !File.Exists(Path.Combine(badBinary, OverlayWorkspaceStore.MigrationMarkerFile)),
                "broken journal binary: dropped before any file is replaced, the load reads normally");
        }
        finally { Directory.Delete(badBinary, true); }

        // 2b. valid JSON with a null binary value: dropped the same way, the load does not throw (review R5)
        var nullBinary = NewRoot();
        try
        {
            File.WriteAllText(Path.Combine(nullBinary, file), (OverlayDisplaySettings.Default with { Opacity = 0.6 }).Serialize());
            File.WriteAllText(Path.Combine(nullBinary, OverlayWorkspaceStore.MigrationJournalFile), Journal(null));
            var state = new OverlayWorkspaceStore(nullBinary).Load();
            Check(state.Settings.Opacity == 0.6 && !File.Exists(Path.Combine(nullBinary, OverlayWorkspaceStore.MigrationJournalFile)),
                "null journal binary: dropped before any file is replaced, the load reads normally");
        }
        finally { Directory.Delete(nullBinary, true); }

        // 2c. the write was complete (the user's chosen 85% and the marker in place) but the journal was not removed and its
        // replay fails: the pending snapshot shows 85%, not a moved 100%, and a save from it after the replay is refused as
        // stale, so the chosen 85% is never overwritten (review R5)
        var chosen = NewRoot();
        try
        {
            File.WriteAllText(Path.Combine(chosen, file), (OverlayDisplaySettings.Default with { Opacity = 0.85, ShowChat = false }).Serialize());
            File.WriteAllText(Path.Combine(chosen, OverlayWorkspaceStore.MigrationMarkerFile), "1");
            File.WriteAllText(Path.Combine(chosen, OverlayWorkspaceStore.MigrationJournalFile), Journal("", decided: 0.85));
            OverlayWorkspaceReadResult pending;
            using (new FileStream(Path.Combine(chosen, file), FileMode.Open, FileAccess.Read, FileShare.Read))
                pending = new OverlayWorkspaceStore(chosen).Load();
            var stale = false;
            try
            {
                new OverlayWorkspaceStore(chosen).Apply(new(pending.Revision, OverlayWorkspaceMutationKind.SaveActive,
                    Settings: pending.Settings with { ShowChat = true }, Layout: pending.Layout, RenderMode: pending.RenderMode, Hotkey: pending.Hotkey));
            }
            catch (OverlaySettingsException error) when (error.Code == "overlay.workspace_revision_conflict") { stale = true; }
            var after = new OverlayWorkspaceStore(chosen).Load();
            Check(pending.Settings.Opacity == 0.85 && stale && after.Settings.Opacity == 0.85 &&
                  !File.Exists(Path.Combine(chosen, OverlayWorkspaceStore.MigrationJournalFile)),
                "pending journal over a chosen 85%: shown as 85%, a save from the pending snapshot is refused as stale, 85% stays",
                new { pending = pending.Settings.Opacity, stale, after = after.Settings.Opacity });
        }
        finally { Directory.Delete(chosen, true); }

        // 3. the first write that sets the marker fails part way and rolls back whole: no journal, no marker, no temp left
        var firstWrite = NewRoot();
        try
        {
            File.WriteAllText(Path.Combine(firstWrite, file), (OverlayDisplaySettings.Default with { Opacity = 0.85 }).Serialize());
            var store = new OverlayWorkspaceStore(firstWrite);
            var state = store.Load();
            var failed = false;
            using (new FileStream(Path.Combine(firstWrite, file), FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                try
                {
                    store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: state.Settings with { ShowChat = false },
                        Layout: state.Layout, RenderMode: state.RenderMode, Hotkey: state.Hotkey));
                }
                catch (Exception) { failed = true; }
            }
            var clean = !File.Exists(Path.Combine(firstWrite, OverlayWorkspaceStore.MigrationJournalFile)) &&
                        !File.Exists(Path.Combine(firstWrite, OverlayWorkspaceStore.MigrationMarkerFile)) && !Leftovers(firstWrite);
            var again = new OverlayWorkspaceStore(firstWrite).Load();
            Check(failed && clean && again.Settings.Opacity == 1.0 && again.StorageState != "migrationPending",
                "failed first write: rolled back whole, no journal, marker or temp file left; the move is still pending for the next write",
                new { failed, clean, again.Settings.Opacity, again.StorageState });
        }
        finally { Directory.Delete(firstWrite, true); }
    }

    private static OverlayDisplaySettings With(this OverlayDisplaySettings settings, double opacity) => settings with { Opacity = opacity };

    private static void Check(bool value, string message, object? evidence = null)
    {
        if (!value) throw new InvalidOperationException("FAIL " + message + " " + evidence);
        Console.WriteLine("PASS " + message);
    }
}
