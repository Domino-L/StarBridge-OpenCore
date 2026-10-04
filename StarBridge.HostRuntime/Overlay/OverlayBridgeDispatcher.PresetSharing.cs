namespace StarBridge.HostRuntime.Overlay;

using StarBridge.Core.Chat;
using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;
using System.Text.Json;

public sealed partial class OverlayBridgeDispatcher
{
    private BridgeEnvelope SharePreset(BridgeEnvelope request, string action, long revision)
    {
        RejectUnknown(request.Payload, "schemaVersion", "action", "expectedRevision",
            action == "exportSharedPreset" ? "presetId" : "package");
        var current = _workspaceStore.Load();
        if (current.Revision != revision) throw new OverlaySettingsException("overlay.revision_conflict");
        if (action == "exportSharedPreset")
        {
            var id = OptionalString(request.Payload, "presetId");
            var preset = current.Presets.FirstOrDefault(p => p.Id == id)
                ?? throw new OverlaySettingsException("overlay.workspace_preset_not_found");
            if (preset.StorageState == "corrupt") throw new OverlaySettingsException("overlay.workspace_invalid_preset");
            var transfer = current.SourcePresetsEnabled
                ? OverlayPresetSourcesCodec.ForTransfer(preset.Sources ?? OverlayPresetSources.Default) : null;
            var package = OverlaySharedPreset.Parse(new OverlaySharedPreset(transfer is null ? 1 : 2, preset.Name,
                preset.Settings.Serialize(), InformationOverlayLayoutItem.SerializeMany(preset.Layout),
                transfer is null ? null : JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(transfer.Sources)),
                transfer?.RemovedOrganizationBindings == true).Serialize());
            return BridgeEnvelope.Response(request, new
            {
                schemaVersion = 1,
                attachment = new ChatAttachmentContract(ChatAttachmentKinds.OverlayPreset, package.Name,
                    package.Name, OverlayPresetPackage: package.Serialize())
            });
        }

        var imported = OverlaySharedPreset.Parse(OptionalString(request.Payload, "package"));
        if (imported.Version == 2 && !current.SourcePresetsEnabled)
            throw new OverlaySettingsException("overlay.shared_preset_invalid");
        if (action == "inspectSharedPreset")
        {
            var sources = current.SourcePresetsEnabled ? imported.Sources ??
                JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(
                    OverlayPresetSourcesCodec.FromLegacy(OverlayDisplaySettings.Parse(imported.Settings).ScenePreference))) : (JsonElement?)null;
            var preview = new Dictionary<string, object?> {
                ["schemaVersion"] = sources is null ? 1 : 2,
                ["name"] = imported.Name,
                ["settings"] = OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Parse(imported.Settings)),
                ["layout"] = InformationOverlayLayoutItem.ParseMany(imported.Layout).Select(OverlayWorkspaceWireProjection.Layout).ToArray()
            };
            if (sources is not null) { preview["sources"] = sources; preview["removedOrganizationBindings"] = imported.RemovedOrganizationBindings; }
            // Same validation and sanitization as import, but no writes or runtime calls.
            return BridgeEnvelope.Response(request, new { schemaVersion = 1, preset = preview });
        }
        var workspace = _workspaceStore.Apply(new OverlayWorkspaceMutation(revision,
            OverlayWorkspaceMutationKind.ImportPreset, Name: imported.Name,
            Settings: OverlayDisplaySettings.Parse(imported.Settings),
            Layout: InformationOverlayLayoutItem.ParseMany(imported.Layout).ToArray(),
            Sources: imported.Sources is null ? null : OverlayPresetSourcesCodec.Parse(imported.Sources.Value.GetRawText())));
        var added = workspace.Presets.Single(p => current.Presets.All(old => old.Id != p.Id));
        // Import is additive; do not sync/activate and disturb a live, unsaved overlay draft.
        return BridgeEnvelope.Response(request, new { schemaVersion = 1, presetId = added.Id, name = added.Name,
            removedOrganizationBindings = imported.RemovedOrganizationBindings });
    }
}
