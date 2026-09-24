namespace StarBridge.HostRuntime.Overlay;

using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Presence;

public enum InformationOverlayRuntimeCommand
{
    Sync,
    Open,
    Close,
    Retry
}

public sealed record InformationOverlayRuntimeWorkspace(
    long Revision,
    OverlayDisplaySettings Settings,
    IReadOnlyList<InformationOverlayLayoutItem> Layout,
    string HotkeyBinding,
    bool HotkeyEnabled,
    GameLogSessionSnapshot Session,
    string Language);

public sealed record InformationOverlayRuntimeSnapshot(
    string WindowState,
    bool IsVisible,
    long AppliedRevision,
    string HotkeyState,
    string FollowGameState,
    string RequestedSkin,
    string EffectiveSkin,
    bool UsedFallbackSkin,
    string? FailureCode = null,
    bool Retryable = false)
{
    public static InformationOverlayRuntimeSnapshot Unavailable { get; } = new(
        "unavailable",
        IsVisible: false,
        AppliedRevision: 0,
        HotkeyState: "unavailable",
        FollowGameState: "unavailable",
        RequestedSkin: "Default",
        EffectiveSkin: "Default",
        UsedFallbackSkin: false,
        FailureCode: "overlay.runtime_unavailable",
        Retryable: true);
}

public sealed record InformationOverlayAppearanceProfile(
    string Id,
    string DisplayNameZh,
    string DisplayNameEn,
    string SummaryZh,
    string SummaryEn,
    IReadOnlyList<string> TraitsZh,
    IReadOnlyList<string> TraitsEn,
    string PreviewSurface,
    string PreviewPrimary,
    string PreviewSecondary,
    bool LocksTheme,
    bool SupportsBloom,
    string StartupTransition,
    bool RequiresEntitlement,
    bool IsReleased,
    bool IsAvailable,
    bool? IsPreviewAvailable = null);

/// <summary>
/// Projects listed appearance metadata, explicit preview visibility, and the
/// server-authoritative use decision. Preview visibility cannot grant or persist an entitlement.
/// </summary>
public interface IInformationOverlayAppearanceCatalog
{
    IReadOnlyList<InformationOverlayAppearanceProfile> GetAppearances();
}

/// <summary>
/// Owns the complete native overlay lifecycle behind one command interface.
/// Callers provide saved workspace state; HWND, STA, rendering, hotkey, and
/// game-window tracking remain implementation details.
/// </summary>
public interface IInformationOverlayRuntime : IDisposable
{
    ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(
        InformationOverlayRuntimeCommand command,
        InformationOverlayRuntimeWorkspace workspace,
        CancellationToken cancellationToken = default);
}

internal sealed class UnavailableInformationOverlayRuntime : IInformationOverlayRuntime
{
    public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(
        InformationOverlayRuntimeCommand command,
        InformationOverlayRuntimeWorkspace workspace,
        CancellationToken cancellationToken = default)
    {
        _ = command;
        _ = workspace;
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable);
    }

    public void Dispose()
    {
    }
}
