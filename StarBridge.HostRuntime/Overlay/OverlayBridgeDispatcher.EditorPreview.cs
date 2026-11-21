namespace StarBridge.HostRuntime.Overlay;

using StarBridge.NativeBridge;

/// <summary>
/// What the visor would show, for the client's layout editor to draw its own simplified panels with (11-12 user: "编辑里
/// 还是要用模拟面板，只不过信息都一致"). Only the draft is read under the workspace gate; the content is read outside it, so
/// a save never waits on it. The draft is checked exactly as the runtime requests check it (ParseRuntimeDraft). The reply
/// is text only (members, sample events, chat, the decoration colour): no image, so it is small and quick.
/// </summary>
public sealed partial class OverlayBridgeDispatcher
{
    internal const string EditorPreviewCapability = "overlay.editorPreview";

    private async ValueTask<BridgeDispatchBatch> DispatchEditorPreviewAsync(
        BridgeEnvelope request, CancellationToken cancellationToken)
    {
        InformationOverlayRuntimeWorkspace workspace;
        IInformationOverlayEditorPreviewRuntime preview;
        try
        {
            await _gate.WaitAsync(cancellationToken);
            try
            {
                Validate(request);
                RejectUnknown(request.Payload, "schemaVersion", "language", "workspace");
                if (_runtime is not IInformationOverlayEditorPreviewRuntime runtime)
                    throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Overlay editor preview is unavailable.");
                preview = runtime;
                var language = ResolveLanguage(OptionalString(request.Payload, "language"));
                // read only: Load() may finish a migration and write files; the preview saves nothing
                if (_workspaceStore is not IOverlayWorkspaceInspector inspector)
                    throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Overlay editor preview is unavailable.");
                var saved = inspector.Inspect();
                workspace = request.Payload.TryGetProperty("workspace", out var draft)
                    ? ParseRuntimeDraft(draft, saved, language)
                    : ToRuntimeWorkspace(saved, language);
            }
            finally { _gate.Release(); }
            var content = await preview.ReadEditorContentAsync(workspace, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation())
                throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
            return new(BridgeEnvelope.Response(request, EditorContentPayload(content), preserveRequestAccountContext: false), []);
        }
        catch (OverlaySettingsException error) { return Error(request, error.Code, error.Retryable); }
        catch (BridgeProtocolException error) { return Error(request, error.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Error(request, "overlay.editor_preview_unavailable", true); }
    }

    internal static object EditorContentPayload(InformationOverlayEditorContent content) => new
    {
        schemaVersion = 1,
        sample = content.Sample,
        decoration = content.Decoration,
        members = new
        {
            title = content.Members.Title,
            youAt = content.Members.YouAt,
            online = content.Members.Online,
            inGame = content.Members.InGame,
            sameServer = content.Members.SameServer,
            page = content.Members.Page,
            counts = content.Members.CountLabels.ToArray(),
            rows = content.Members.Rows.Select(row => new
            {
                name = row.Name,
                ship = row.Ship,
                place = row.Place,
                status = row.Status,
                state = row.State,
                sameServer = row.SameServer,
                pinned = row.Pinned,
                vitals = row.Vitals,
                health = Math.Clamp(double.IsFinite(row.Health) ? row.Health : 0, 0, 1),
            }).ToArray(),
        },
        events = new
        {
            title = content.Events.Title,
            sample = content.Events.Sample,
            rows = content.Events.Rows.Select(row => new { title = row.Title, detail = row.Detail, time = row.Time, tone = row.Tone }).ToArray(),
        },
        chat = new
        {
            title = content.Chat.Title,
            sample = content.Chat.Sample,
            rows = content.Chat.Rows.Select(row => new { who = row.Who, text = row.Text }).ToArray(),
        },
    };
}
