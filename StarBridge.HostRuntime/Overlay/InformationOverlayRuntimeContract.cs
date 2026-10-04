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
    string Language,
    // Null preserves the v1 runtime until the versioned preset store is enabled.
    // These are display choices only; all authority comes from the Host reader.
    OverlayPresetSources? Sources = null,
    // Retained even when a damaged v2 document cannot provide source choices.
    // Missing v2 data must never opt the runtime back into the legacy reader.
    bool SourcePresetsEnabled = false,
    OverlayTemporarySource? TemporarySource = null)
{
    public bool UsesModuleSources => SourcePresetsEnabled || Sources is not null;
    public bool HasInvalidSourceConfiguration => UsesModuleSources && Sources is null;
}

/// <summary>Process-local display choice, scoped to the exact signed-in session.
/// Never serialized with a preset or used as authorization evidence.</summary>
public sealed record OverlayTemporarySource(string OwnerKey, long Generation, OverlaySourceBinding Choice)
{
    public OverlaySourceBinding? ForScope(string ownerKey, long generation) =>
        OwnerKey == ownerKey && Generation == generation ? Choice : null;
}

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

/// <summary>Host changes schedule a coalesced native refresh; no HWND or render
/// implementation crosses this boundary.</summary>
public interface IInformationOverlayLiveUpdateSink
{
    bool IsVisible { get; }
    // A menu may temporarily hide an enabled HUD. Keep the existing authorized
    // source driver alive without claiming the HWND is visible.
    bool HasDisplayDemand => IsVisible;
    // Null means legacy single-source mode, not a missing v2 source grant.
    InformationOverlayModuleDemand? ModuleDemand => null;
    void RequestContentRefresh();
}

/// <summary>Immutable display intent for the existing shared refresh drivers.
/// It contains no content, lease or authority, and remains present when content expires.</summary>
public sealed class InformationOverlayModuleDemand
{
    public OverlayPresetSources? Sources { get; }
    public IReadOnlyCollection<OverlaySourceModule> ActiveModules { get; }
    public OverlayTemporarySource? TemporarySource { get; }
    internal string RefreshIdentity { get; }

    public InformationOverlayModuleDemand(OverlayPresetSources? sources,
        IReadOnlyCollection<OverlaySourceModule> activeModules, OverlayTemporarySource? temporarySource = null)
    {
        ArgumentNullException.ThrowIfNull(activeModules);
        if (activeModules.Any(module => !Enum.IsDefined(module)))
            throw new ArgumentException("Invalid overlay module demand.", nameof(activeModules));
        Sources = sources;
        TemporarySource = temporarySource;
        ActiveModules = Array.AsReadOnly(activeModules.Distinct().ToArray());
        RefreshIdentity = (sources is null ? "invalid" : OverlayPresetSourcesCodec.Serialize(new(sources.Binding, modules: sources.Modules, chatSources: sources.ChatSources))) +
            "|" + string.Join(",", ActiveModules.Order()) + "|" +
            (temporarySource is null ? "" : System.Text.Json.JsonSerializer.Serialize(temporarySource));
    }
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
