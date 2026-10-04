namespace StarBridge.HostRuntime.Overlay;

/// <summary>Build-time rollout only. A request or saved file cannot enable migration.</summary>
internal static class OverlaySourcePresetBuild
{
#if STARBRIDGE_OVERLAY_SOURCE_PRESETS
    internal const bool Enabled = true;
#else
    internal const bool Enabled = false;
#endif
}
