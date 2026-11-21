namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    /// <summary>
    /// The visor scene for the client's layout editor (NativeInformationOverlayRuntime.EditorPreview): what this window
    /// would draw now, settled (no opening or closing). The window is never shown for it.
    /// </summary>
    internal OverlayVisorScene EditorPreviewScene() =>
        BuildVisorScene(BuildFrameState()) with { OpenAt = double.NegativeInfinity, CloseAt = double.NegativeInfinity };

    /// <summary>
    /// The events this (live) window shows right now, settled, each with its kind's colour, for the editor (11-12: the
    /// editor shows the real events when there are any). Leaving ones are left out.
    /// </summary>
    internal IReadOnlyList<OverlayVisorEvent> EditorLiveEvents() =>
        _viewModel.EventNotifications.Where(row => !row.IsExiting)
            .Select(row => new OverlayVisorEvent(row.Title, row.Detail, row.Timestamp, 1, 1, Tone: EventTone(row.EventType, row.Negative)))
            .ToArray();
}
