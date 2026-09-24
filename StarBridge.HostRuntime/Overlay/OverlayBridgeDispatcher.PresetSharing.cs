namespace StarBridge.HostRuntime.Overlay;

using StarBridge.Core.Chat;
using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;

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
            var package = OverlaySharedPreset.Parse(new OverlaySharedPreset(1, preset.Name,
                preset.Settings.Serialize(), InformationOverlayLayoutItem.SerializeMany(preset.Layout)).Serialize());
            return BridgeEnvelope.Response(request, new
            {
                schemaVersion = 1,
                attachment = new ChatAttachmentContract(ChatAttachmentKinds.OverlayPreset, package.Name,
                    package.Name, OverlayPresetPackage: package.Serialize())
            });
        }

        var imported = OverlaySharedPreset.Parse(OptionalString(request.Payload, "package"));
        var workspace = _workspaceStore.Apply(new OverlayWorkspaceMutation(revision,
            OverlayWorkspaceMutationKind.ImportPreset, Name: imported.Name,
            Settings: OverlayDisplaySettings.Parse(imported.Settings),
            Layout: InformationOverlayLayoutItem.ParseMany(imported.Layout).ToArray()));
        var added = workspace.Presets.Single(p => current.Presets.All(old => old.Id != p.Id));
        // Import is additive; do not sync/activate and disturb a live, unsaved overlay draft.
        return BridgeEnvelope.Response(request, new { schemaVersion = 1, presetId = added.Id, name = added.Name });
    }
}
