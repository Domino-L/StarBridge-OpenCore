namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;

public sealed partial class OverlayBridgeDispatcher
{
    private (string PresetId, OverlayTemporarySource Source)? _temporarySelection;

    private OverlayTemporarySource? CurrentTemporarySource(OverlayWorkspaceReadResult workspace)
    {
        var scope = _sourceScope();
        if (!workspace.SourcePresetsEnabled || _temporarySelection is not { } selected ||
            selected.PresetId != workspace.ActivePresetId || selected.Source.OwnerKey != scope.OwnerKey ||
            selected.Source.Generation != scope.Generation || scope.Generation != _generation())
        {
            _temporarySelection = null;
            return null;
        }
        return selected.Source;
    }

    private async Task<BridgeEnvelope> SelectTemporarySourceAsync(BridgeEnvelope request,
        long revision, CancellationToken cancellation)
    {
        RejectUnknown(request.Payload, "schemaVersion", "action", "expectedRevision", "ownerKey", "sources", "workspace");
        RequireWorkspaceFields(request.Payload, ["ownerKey", "sources"]);
        var workspace = _workspaceStore.Load();
        var scope = _sourceScope();
        if (!workspace.SourcePresetsEnabled || scope.OwnerKey is null || scope.Generation != request.SessionGeneration ||
            OptionalString(request.Payload, "ownerKey") != scope.OwnerKey)
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        if (workspace.Revision != revision)
            throw new OverlaySettingsException("overlay.workspace_revision_conflict", true);
        RequireUsablePreset(workspace);
        // Reuse the strict source codec. A temporary selection is a single choice,
        // never an auto-switch rule or a module-policy mutation.
        var policy = ParseSources(request.Payload.GetProperty("sources"));
        if (policy.AutoSwitch || policy.Modules.Values.Any(source => source.Mode != OverlaySourceMode.None) ||
            policy.Binding.Mode == OverlaySourceMode.Community && policy.Binding.OwnerKey != scope.OwnerKey)
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        if (workspace.Presets.First(p => p.IsActive).Sources?.Binding.Mode == OverlaySourceMode.None)
            throw new OverlaySettingsException("overlay.workspace_invalid_value");
        // Validate a carried draft before changing even session-only intent.
        var runtime = request.Payload.TryGetProperty("workspace", out var draft)
            ? ParseRuntimeDraft(draft, workspace, ResolveLanguage(null))
            : ToRuntimeWorkspace(workspace, ResolveLanguage(null));
        var source = policy.Binding.Mode == OverlaySourceMode.None ? null :
            new OverlayTemporarySource(scope.OwnerKey, scope.Generation, policy.Binding);
        _temporarySelection = source is null ? null : (workspace.ActivePresetId!, source);
        await _runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync,
            runtime with { TemporarySource = source }, cancellation);
        // No persisted revision change: retries cannot create duplicate presets,
        // and a process restart intentionally forgets this choice.
        return WorkspaceResponse(request, workspace);
    }
}
