using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;
using StarBridge.Core.Overlay;
using System.Text;

internal static class OverlaySettingsTests
{
    internal static async Task ReadsFullLegacyWorkspaceWithoutMutation()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-workspace-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var activeSettings = InformationOverlayDefaults.DefaultSettings with
            {
                Opacity = 0.73,
                ShowCrosshair = true,
                CrosshairMode = OverlayCrosshairMode.Dot,
                MemberScopeMode = OverlayMemberScopeMode.AllFleet,
                ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage
            };
            var activeLayout = InformationOverlayDefaults.CreateLayout(
                InformationOverlayPresetCodec.CommandPresetId);
            Write(root, "overlay.presets",
                "{\"Presets\":[{\"Id\":\"preset1\",\"Name\":\"舰桥标准\"}," +
                "{\"Id\":\"ops\",\"Name\":\"作战值班\"}]}");
            Write(root, "overlay.active-preset", "ops");
            Write(root, "overlay.settings", activeSettings.Serialize());
            Write(root, "overlay.layout", InformationOverlayLayoutItem.SerializeMany(activeLayout));
            Write(root, "overlay.ops.settings", activeSettings.Serialize());
            Write(root, "overlay.ops.layout", InformationOverlayLayoutItem.SerializeMany(activeLayout));
            Write(root, "overlay.preset1.settings", InformationOverlayDefaults.DefaultSettings.Serialize());
            Write(root, "overlay.preset1.layout", InformationOverlayDefaults.DefaultLayoutPayload);
            Write(root, "overlay.render-mode", "DirectComposition");
            Write(root, "desktop.config", string.Join(Environment.NewLine,
            [
                "", "", "", "", "Alt+F9", "", "", "", "", "",
                "secret-server-key-must-not-leak", "", "secret-auth-token-must-not-leak", "", "True", "False", "", ""
            ]));
            var before = Directory.GetFiles(root).ToDictionary(
                path => Path.GetFileName(path)!,
                File.ReadAllBytes,
                StringComparer.OrdinalIgnoreCase);

            using var dispatcher = new OverlayBridgeDispatcher(
                root,
                () => 6,
                () => GameLogSessionSnapshot.Empty);
            var batch = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace",
                6,
                new { schemaVersion = 1 }));

            Require(batch.Response.Status == BridgeResponseStatuses.Ok, "workspace read should succeed");
            var payload = batch.Response.Payload;
            Require(payload.GetProperty("schemaVersion").GetInt32() == 1, "workspace schema");
            Require(payload.GetProperty("revision").GetInt64() > 0, "persisted workspace revision");
            Require(payload.GetProperty("activePresetId").GetString() == "ops", "active preset");
            Require(payload.GetProperty("renderMode").GetString() == "DirectComposition", "render mode");
            Require(payload.GetProperty("hotkey").GetProperty("binding").GetString() == "Alt+F9",
                "information hotkey binding");
            Require(!payload.GetProperty("hotkey").GetProperty("enabled").GetBoolean(),
                "information hotkey enablement");
            Require(!payload.GetRawText().Contains("secret-", StringComparison.Ordinal),
                "desktop secrets never enter the workspace response");
            var settings = payload.GetProperty("settings");
            var expectedFieldCount = typeof(OverlayDisplaySettings).GetConstructors().Single()
                .GetParameters().Length;
            Require(settings.EnumerateObject().Count() == expectedFieldCount, "all settings are projected");
            Require(Math.Abs(settings.GetProperty("opacity").GetDouble() - 0.73) < 0.001, "opacity projected");
            Require(settings.GetProperty("crosshairMode").GetString() == "Dot", "enum projected by name");
            Require(settings.GetProperty("eventNotificationDurations").ValueKind ==
                    System.Text.Json.JsonValueKind.Object,
                "duration overrides stay structured");
            Require(payload.GetProperty("layout").GetArrayLength() == 4, "complete active layout");
            Require(payload.GetProperty("presets").GetArrayLength() == 2, "all manifest presets");
            Require(payload.GetProperty("presets")[0].GetProperty("name").GetString() == "默认预设",
                "legacy default name normalized");

            var afterFiles = Directory.GetFiles(root);
            Require(afterFiles.Length == before.Count, "workspace read creates no files");
            foreach (var path in afterFiles)
            {
                var name = Path.GetFileName(path);
                Require(before.TryGetValue(name, out var bytes), $"unexpected file {name}");
                Require(File.ReadAllBytes(path).SequenceEqual(bytes!), $"workspace read changed {name}");
            }
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task DefaultsFullWorkspaceWithoutWriting()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-workspace-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var dispatcher = new OverlayBridgeDispatcher(
                root,
                () => 2,
                () => GameLogSessionSnapshot.Empty);
            var batch = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace",
                2,
                new { schemaVersion = 1 }));
            Require(batch.Response.Status == BridgeResponseStatuses.Ok, "default workspace read");
            Require(batch.Response.Payload.GetProperty("storageState").GetString() == "defaulted",
                "default workspace state");
            Require(batch.Response.Payload.GetProperty("revision").GetInt64() == 0,
                "default workspace revision");
            Require(batch.Response.Payload.GetProperty("layout").GetArrayLength() == 4,
                "default workspace layout");
            Require(!Directory.EnumerateFileSystemEntries(root).Any(), "default read remains read only");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task SavesWorkspaceLoadedFromLegacyExperimentalRenderMode()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-render-mode-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            Write(root, "overlay.presets", InformationOverlayPresetCodec.SerializeManifest(
                [new InformationOverlayPresetEntry("preset1", "默认预设")]));
            Write(root, "overlay.active-preset", "preset1");
            Write(root, "overlay.preset1.settings", InformationOverlayDefaults.DefaultSettings.Serialize());
            Write(root, "overlay.preset1.layout", InformationOverlayDefaults.DefaultLayoutPayload);
            Write(root, "overlay.render-mode", "experimental");

            using var dispatcher = new OverlayBridgeDispatcher(
                root,
                () => 7,
                () => GameLogSessionSnapshot.Empty);
            var initial = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace", 7, new { schemaVersion = 1 }));
            Require(initial.Response.Payload.GetProperty("renderMode").GetString() == "DirectComposition",
                "legacy render mode is projected as the supported runtime before editing");
            var saved = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 7, new
            {
                schemaVersion = 1,
                expectedRevision = initial.Response.Payload.GetProperty("revision").GetInt64(),
                action = "saveActive",
                settings = initial.Response.Payload.GetProperty("settings"),
                layout = initial.Response.Payload.GetProperty("layout"),
                renderMode = initial.Response.Payload.GetProperty("renderMode").GetString(),
                hotkey = new { binding = "Ctrl+Shift+O", enabled = true }
            }));

            Require(saved.Response.Status == BridgeResponseStatuses.Ok,
                "workspace loaded from the legacy experimental render mode can be saved");
            Require(saved.Response.Payload.GetProperty("renderMode").GetString() == "DirectComposition",
                "legacy render mode is projected as the supported runtime");
            Require(File.ReadAllText(Path.Combine(root, "overlay.render-mode")).Trim() == "DirectComposition",
                "first user save upgrades the legacy render mode");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task WritesFullWorkspaceWithBackupAndRevisionGuard()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-write-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            Write(root, "overlay.presets", InformationOverlayPresetCodec.SerializeManifest(
                [new InformationOverlayPresetEntry("preset1", "默认预设")]));
            Write(root, "overlay.active-preset", "preset1");
            Write(root, "overlay.preset1.settings", InformationOverlayDefaults.DefaultSettings.Serialize());
            Write(root, "overlay.preset1.layout", InformationOverlayDefaults.DefaultLayoutPayload);
            var desktop = string.Join("\r\n",
            [
                "log", "player", "id", "avatar", "Ctrl+Shift+O", "layout", "callsign", "settings",
                "zh-CN", "server", "protected-server-secret", "account", "protected-auth-secret", "fleet",
                "True", "True", "account-id", "cached"
            ]) + "\r\n";
            Write(root, "desktop.config", desktop);
            var originalDesktop = File.ReadAllBytes(Path.Combine(root, "desktop.config"));

            using var dispatcher = new OverlayBridgeDispatcher(root, () => 9, () => GameLogSessionSnapshot.Empty);
            var initial = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace", 9, new { schemaVersion = 1 }));
            var revision = initial.Response.Payload.GetProperty("revision").GetInt64();
            var saved = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 9, new
            {
                schemaVersion = 1,
                expectedRevision = revision,
                action = "saveActive",
                settings = initial.Response.Payload.GetProperty("settings"),
                layout = initial.Response.Payload.GetProperty("layout"),
                renderMode = "DirectComposition",
                hotkey = new { binding = "Alt+F9", enabled = false }
            }));

            Require(saved.Response.Status == BridgeResponseStatuses.Ok, "full workspace save");
            Require(saved.Response.Payload.GetProperty("revision").GetInt64() != revision,
                "workspace revision changes after save");
            Require(saved.Response.Payload.GetProperty("hotkey").GetProperty("binding").GetString() == "Alt+F9",
                "saved hotkey projected");
            Require(!saved.Response.Payload.GetProperty("hotkey").GetProperty("enabled").GetBoolean(),
                "saved hotkey enablement projected");
            Require(!saved.Response.Payload.GetRawText().Contains("protected-", StringComparison.Ordinal),
                "desktop secrets remain outside the wire response");

            var backupRoot = Path.Combine(root, "overlay.workspace-backup-v1");
            Require(Directory.Exists(backupRoot), "first write creates recovery backup");
            Require(File.ReadAllBytes(Path.Combine(backupRoot, "desktop.config")).SequenceEqual(originalDesktop),
                "recovery backup preserves desktop config exactly");
            var savedDesktop = File.ReadAllLines(Path.Combine(root, "desktop.config"));
            Require(savedDesktop[4] == "Alt+F9" && savedDesktop[15] == "False",
                "only overlay hotkey fields change");
            Require(savedDesktop[10] == "protected-server-secret" && savedDesktop[12] == "protected-auth-secret",
                "unrelated protected desktop values are preserved");

            var beforeStale = Directory.GetFiles(root, "overlay.*", SearchOption.TopDirectoryOnly)
                .ToDictionary(path => Path.GetFileName(path)!, File.ReadAllBytes, StringComparer.OrdinalIgnoreCase);
            var stale = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 9, new
            {
                schemaVersion = 1,
                expectedRevision = revision,
                action = "saveActive",
                settings = saved.Response.Payload.GetProperty("settings"),
                layout = saved.Response.Payload.GetProperty("layout"),
                renderMode = "DirectComposition",
                hotkey = new { binding = "Ctrl+F10", enabled = true }
            }));
            Require(stale.Response.Error?.Code == "overlay.workspace_revision_conflict",
                "stale full workspace write rejected");
            foreach (var (name, bytes) in beforeStale)
            {
                Require(File.ReadAllBytes(Path.Combine(root, name!)).SequenceEqual(bytes),
                    $"stale write changed {name}");
            }

            var invalidHotkey = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 9, new
            {
                schemaVersion = 1,
                expectedRevision = saved.Response.Payload.GetProperty("revision").GetInt64(),
                action = "saveActive",
                settings = saved.Response.Payload.GetProperty("settings"),
                layout = saved.Response.Payload.GetProperty("layout"),
                renderMode = "DirectComposition",
                hotkey = 42
            }));
            Require(invalidHotkey.Response.Error?.Code == "overlay.workspace_invalid_hotkey",
                "malformed hotkey receives a precise rejection");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task ManagesEveryPresetAction()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-presets-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var dispatcher = new OverlayBridgeDispatcher(root, () => 10, () => GameLogSessionSnapshot.Empty);
            var current = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace", 10, new { schemaVersion = 1 }));
            current = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 10, new
            {
                schemaVersion = 1,
                expectedRevision = current.Response.Payload.GetProperty("revision").GetInt64(),
                action = "saveActive",
                settings = current.Response.Payload.GetProperty("settings"),
                layout = current.Response.Payload.GetProperty("layout"),
                renderMode = "DirectComposition",
                hotkey = new { binding = "Ctrl+Shift+O", enabled = true }
            }));
            Require(current.Response.Status == BridgeResponseStatuses.Ok, "materialize default preset");

            current = await PresetAction(dispatcher, current, "createPreset",
                new { name = "新预设" });
            Require(current.Response.Payload.GetProperty("presets").GetArrayLength() == 2,
                "create adds a preset");
            var created = current.Response.Payload.GetProperty("presets").EnumerateArray()
                .Single(preset => preset.GetProperty("name").GetString() == "新预设");
            var createdId = created.GetProperty("id").GetString()!;
            Require(current.Response.Payload.GetProperty("activePresetId").GetString() == createdId,
                "create activates the new preset");
            Require(created.GetProperty("settings").GetProperty("showNotice").GetBoolean(),
                "create starts from default settings");
            current = await PresetAction(dispatcher, current, "deletePreset",
                new { presetId = createdId });

            current = await PresetAction(dispatcher, current, "duplicatePreset",
                new { presetId = "preset1", name = "作战" });
            Require(current.Response.Payload.GetProperty("presets").GetArrayLength() == 2,
                "duplicate creates preset");
            var duplicated = current.Response.Payload.GetProperty("presets").EnumerateArray()
                .Single(preset => preset.GetProperty("name").GetString() == "作战")
                .GetProperty("id").GetString()!;

            current = await PresetAction(dispatcher, current, "renamePreset",
                new { presetId = duplicated, name = "突击" });
            Require(current.Response.Payload.GetProperty("presets").EnumerateArray()
                .Any(preset => preset.GetProperty("name").GetString() == "突击"), "rename preset");
            current = await PresetAction(dispatcher, current, "activatePreset",
                new { presetId = duplicated });
            Require(current.Response.Payload.GetProperty("activePresetId").GetString() == duplicated,
                "activate preset");
            current = await PresetAction(dispatcher, current, "resetPreset",
                new { presetId = duplicated });
            Require(current.Response.Status == BridgeResponseStatuses.Ok, "reset preset");

            current = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 10, new
            {
                schemaVersion = 1,
                expectedRevision = current.Response.Payload.GetProperty("revision").GetInt64(),
                action = "importPreset",
                name = "导入",
                settings = current.Response.Payload.GetProperty("settings"),
                layout = current.Response.Payload.GetProperty("layout")
            }));
            Require(current.Response.Status == BridgeResponseStatuses.Ok, "import preset");
            var imported = current.Response.Payload.GetProperty("presets").EnumerateArray()
                .Single(preset => preset.GetProperty("name").GetString() == "导入")
                .GetProperty("id").GetString()!;
            current = await PresetAction(dispatcher, current, "deletePreset",
                new { presetId = imported });
            current = await PresetAction(dispatcher, current, "deletePreset",
                new { presetId = duplicated });
            Require(current.Response.Payload.GetProperty("presets").GetArrayLength() == 1,
                "delete keeps remaining preset");
            var lastDelete = await PresetAction(dispatcher, current, "deletePreset",
                new { presetId = "preset1" }, expectSuccess: false);
            Require(lastDelete.Response.Error?.Code == "overlay.workspace_last_preset",
                "last preset cannot be deleted");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task PersistsAndProjectsCurrentSession()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-" + Guid.NewGuid().ToString("N"));
        try
        {
            var session = new GameLogSessionSnapshot(
                new GameLogServerSnapshot("connected", "US", "pub_use1b_12545750_070"),
                new GameLogLocationSnapshot("confirmed", "Orison", "奥里森"),
                new GameLogShipSnapshot("confirmed", "f8c-lightning", "F8C Lightning", "F8C 闪电"));
            using (var dispatcher = new OverlayBridgeDispatcher(root, () => 4, () => session))
            {
                var initial = await dispatcher.DispatchAsync(Request("overlay.getState", 4, new { schemaVersion = 1 }));
                Require(initial.Response.Status == BridgeResponseStatuses.Ok, "initial read should succeed");
                Require(initial.Response.Payload.GetProperty("revision").GetInt64() == 0, "default revision");
                Require(initial.Response.Payload.GetProperty("settings").GetProperty("enabled").GetBoolean(), "enabled default");
                Require(initial.Response.Payload.GetProperty("session").GetProperty("server")
                    .GetProperty("shard").GetString() == "pub_use1b_12545750_070", "full shard projection");

                var saved = await dispatcher.DispatchAsync(Request("overlay.update", 4, new
                {
                    schemaVersion = 1,
                    expectedRevision = 0,
                    settings = new { enabled = false, opacity = 0.7, position = "bottomLeft", showTeam = false }
                }));
                Require(saved.Response.Status == BridgeResponseStatuses.Ok, "update should succeed");
                Require(saved.Response.Payload.GetProperty("revision").GetInt64() == 1, "saved revision");
            }

            using var reopened = new OverlayBridgeDispatcher(root, () => 4, () => GameLogSessionSnapshot.Empty);
            var persisted = await reopened.DispatchAsync(Request("overlay.getState", 4, new { schemaVersion = 1 }));
            var settings = persisted.Response.Payload.GetProperty("settings");
            Require(!settings.GetProperty("enabled").GetBoolean(), "enabled should persist");
            Require(settings.GetProperty("position").GetString() == "bottomLeft", "position should persist");
            Require(Math.Abs(settings.GetProperty("opacity").GetDouble() - 0.7) < 0.001, "opacity should persist");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task ExposesRuntimeLifecycle()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-runtime-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var runtime = new RecordingOverlayRuntime();
            using var dispatcher = new OverlayBridgeDispatcher(
                root,
                () => 12,
                () => GameLogSessionSnapshot.Empty,
                runtime);

            await dispatcher.InitializeRuntimeAsync();
            Require(runtime.Commands.SequenceEqual([InformationOverlayRuntimeCommand.Sync]),
                "runtime initializes from saved workspace");

            var persistedBefore = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace",
                12,
                new { schemaVersion = 1 }));
            var persistedPayload = persistedBefore.Response.Payload;
            var appearances = persistedPayload.GetProperty("appearances");
            Require(appearances.GetArrayLength() == 3,
                "workspace projects released and announced runtime appearances");
            var nightShadow = appearances.EnumerateArray().Single(item =>
                item.GetProperty("id").GetString() == "NightShadow");
            Require(nightShadow.GetProperty("requiresEntitlement").GetBoolean(),
                "commercial appearance keeps its server lock");
            Require(nightShadow.GetProperty("isReleased").GetBoolean(),
                "Night Shadow is released for preview and qualified application");
            Require(nightShadow.GetProperty("isPreviewAvailable").GetBoolean(),
                "older runtime profiles default preview visibility to release state");
            Require(!nightShadow.GetProperty("isAvailable").GetBoolean(),
                "locked appearance is not locally available");
            var verdict = appearances.EnumerateArray().Single(item =>
                item.GetProperty("id").GetString() == "Verdict");
            Require(!verdict.GetProperty("isReleased").GetBoolean(),
                "unfinished appearance is announced without publication");
            Require(!verdict.GetProperty("isAvailable").GetBoolean(),
                "an entitlement cannot make an unfinished appearance selectable");
            Require(verdict.GetProperty("isPreviewAvailable").GetBoolean(),
                "an explicitly preview-ready profile stays independent of publication and application");
            var draftSettings = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object?>>(
                persistedPayload.GetProperty("settings").GetRawText(),
                BridgeProtocol.JsonOptions)!;
            draftSettings["showNotice"] = false;

            var opened = await dispatcher.DispatchAsync(Request(
                "overlay.runtime.open",
                12,
                new
                {
                    schemaVersion = 1,
                    language = "zh-CN",
                    workspace = new
                    {
                        expectedRevision = persistedPayload.GetProperty("revision").GetInt64(),
                        settings = draftSettings,
                        layout = persistedPayload.GetProperty("layout"),
                        hotkey = new { binding = "Alt+F9", enabled = true }
                    }
                }));
            Require(opened.Response.Status == BridgeResponseStatuses.Ok, "runtime open succeeds");
            Require(opened.Response.Payload.GetProperty("windowState").GetString() == "open",
                "runtime projects open state");
            Require(opened.Response.Payload.GetProperty("isVisible").GetBoolean(),
                "runtime projects visibility");
            Require(runtime.LastWorkspace?.Language == "zh", "runtime language is normalized");
            Require(runtime.LastWorkspace?.Layout.Count == 4, "runtime receives complete layout");
            Require(runtime.LastWorkspace?.Settings.ShowNotice == false,
                "runtime open applies the unsaved workspace draft");
            var persistedAfter = await dispatcher.DispatchAsync(Request(
                "overlay.getWorkspace",
                12,
                new { schemaVersion = 1 }));
            Require(persistedAfter.Response.Payload.GetProperty("settings")
                    .GetProperty("showNotice").GetBoolean(),
                "runtime draft never mutates the saved workspace");
            Require(persistedAfter.Response.Payload.GetProperty("revision").GetInt64() ==
                    persistedPayload.GetProperty("revision").GetInt64(),
                "runtime draft never advances the saved revision");

            var closed = await dispatcher.DispatchAsync(Request(
                "overlay.runtime.close",
                12,
                new { schemaVersion = 1 }));
            Require(closed.Response.Payload.GetProperty("windowState").GetString() == "closed",
                "runtime close succeeds");
            Require(!closed.Response.Payload.GetProperty("isVisible").GetBoolean(),
                "runtime close clears visibility");

            var rejected = await dispatcher.DispatchAsync(Request(
                "overlay.runtime.getState",
                12,
                new { schemaVersion = 1, implementation = "WPF" }));
            Require(rejected.Response.Error?.Code == BridgeErrorCodes.InvalidEnvelope,
                "runtime rejects unknown fields");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task RejectsStaleAndUnsupportedRequests()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var dispatcher = new OverlayBridgeDispatcher(root, () => 8, () => GameLogSessionSnapshot.Empty);
            var stale = await dispatcher.DispatchAsync(Request("overlay.update", 8, new
            {
                schemaVersion = 1,
                expectedRevision = 3,
                settings = new { enabled = true, opacity = 0.85, position = "topRight", showTeam = true }
            }));
            Require(stale.Response.Error?.Code == "overlay.revision_conflict", "stale update error");

            var preview = await dispatcher.DispatchAsync(Request("overlay.preview", 8, new { schemaVersion = 1 }));
            Require(preview.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "preview stays unavailable");

            var accountRequest = BridgeEnvelope.Request(
                "overlay.getState",
                Guid.NewGuid().ToString("N"),
                8,
                new { schemaVersion = 1 },
                new BridgeAccountContext("test", "scm", "subject"));
            var rejected = await dispatcher.DispatchAsync(accountRequest);
            Require(rejected.Response.Error?.Code == BridgeErrorCodes.InvalidEnvelope, "account context rejected");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static BridgeEnvelope Request(string name, long generation, object payload) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, payload);

    private static async Task<BridgeDispatchBatch> PresetAction(
        OverlayBridgeDispatcher dispatcher,
        BridgeDispatchBatch current,
        string action,
        object fields,
        bool expectSuccess = true)
    {
        var payload = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object?>>(
            System.Text.Json.JsonSerializer.Serialize(fields, BridgeProtocol.JsonOptions),
            BridgeProtocol.JsonOptions)!;
        payload["schemaVersion"] = 1;
        payload["expectedRevision"] = current.Response.Payload.GetProperty("revision").GetInt64();
        payload["action"] = action;
        var result = await dispatcher.DispatchAsync(Request("overlay.updateWorkspace", 10, payload));
        if (expectSuccess) Require(result.Response.Status == BridgeResponseStatuses.Ok, action);
        return result;
    }

    private static void Write(string root, string name, string value) =>
        File.WriteAllText(Path.Combine(root, name), value, new UTF8Encoding(false));

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class RecordingOverlayRuntime :
        IInformationOverlayRuntime,
        IInformationOverlayAppearanceCatalog
    {
        internal List<InformationOverlayRuntimeCommand> Commands { get; } = [];
        internal InformationOverlayRuntimeWorkspace? LastWorkspace { get; private set; }

        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(
            InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Commands.Add(command);
            LastWorkspace = workspace;
            var visible = command is InformationOverlayRuntimeCommand.Open or
                InformationOverlayRuntimeCommand.Retry;
            return ValueTask.FromResult(new InformationOverlayRuntimeSnapshot(
                visible ? "open" : "closed",
                visible,
                workspace.Revision,
                workspace.HotkeyEnabled ? "registered" : "disabled",
                "waitingForGame",
                workspace.Settings.EffectiveRequestedSkin.ToString(),
                OverlaySkin.Default.ToString(),
                workspace.Settings.EffectiveRequestedSkin != OverlaySkin.Default));
        }

        public IReadOnlyList<InformationOverlayAppearanceProfile> GetAppearances() =>
        [
            new(
                "Default",
                "舰队标准",
                "Fleet Standard",
                "标准浮层",
                "Standard overlay",
                ["厂商配色", "精密导轨", "高信息密度"],
                ["Manufacturer colors", "Precision rails", "Dense information"],
                "#081722",
                "#29AFFF",
                "#69CCFF",
                LocksTheme: false,
                SupportsBloom: false,
                StartupTransition: "BridgeTerminal",
                RequiresEntitlement: false,
                IsReleased: true,
                IsAvailable: true),
            new(
                "NightShadow",
                "夜影",
                "Night Shadow",
                "深黑低反射界面",
                "Low-reflection black interface",
                ["深黑面板", "红色脉冲", "窄边泛光"],
                ["Black panels", "Crimson pulse", "Edge bloom"],
                "#08090C",
                "#FF3045",
                "#9E1E30",
                LocksTheme: true,
                SupportsBloom: true,
                StartupTransition: "NightShadowFlowField",
                RequiresEntitlement: true,
                IsReleased: true,
                IsAvailable: false),
            new(
                "Verdict",
                "裁决",
                "Verdict",
                "裁决轴界面",
                "Verdict axis interface",
                ["裁决轴", "白色夹持", "判印节点"],
                ["Verdict axis", "White clamps", "Seal nodes"],
                "#080A0D",
                "#FF1917",
                "#F7F5F0",
                LocksTheme: true,
                SupportsBloom: true,
                StartupTransition: "VerdictProtocol",
                RequiresEntitlement: true,
                IsReleased: false,
                IsAvailable: false,
                IsPreviewAvailable: true)
        ];

        public void Dispose()
        {
        }
    }
}
