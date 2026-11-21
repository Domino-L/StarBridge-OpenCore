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
    // Off: every shortcut is read through Raw Input and no hotkey is registered.
    public bool UseRegisteredHotkey { get; init; }
    public bool UsesModuleSources => SourcePresetsEnabled || Sources is not null;
    public bool HasInvalidSourceConfiguration => UsesModuleSources && Sources is null;
    public bool IsPresetCorrupt { get; init; }
    public bool HasInvalidConfiguration => IsPresetCorrupt || HasInvalidSourceConfiguration;
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

/// <summary>Optional push of the same snapshot <c>Sync</c> returns, raised only
/// when it differs from the last one raised. Runs on the runtime's own thread:
/// handlers must return quickly and never call back into the runtime.</summary>
public interface IInformationOverlayRuntimeStateSource
{
    event Action<InformationOverlayRuntimeSnapshot>? StateChanged;
}

/// <summary>Optional declarative presentation forms from installed appearances.
/// Descriptions never grant use, publication or entitlement.</summary>
public interface IInformationOverlayAppearanceConfigurationCatalog
{
    IReadOnlyList<System.Text.Json.JsonElement> GetAppearanceConfigurations();
}

/// <summary>Optional read-only installed collection. A query may refresh account
/// receipts but cannot start usage, equip items, or grant appearance access.</summary>
public interface IInformationOverlayAppearanceProgressCatalog
{
    IReadOnlyList<string> GetAppearanceProgressIds();
    ValueTask<System.Text.Json.JsonElement?> ReadAppearanceProgressAsync(
        string appearanceId, CancellationToken cancellationToken = default);
}

/// <summary>Optional isolated, content-free native preview of an installed appearance.
/// Opening never applies a skin, reads live business sources, or saves a preset.
/// Opaque session IDs make late closes harmless to a replacement preview.</summary>
public interface IInformationOverlayAppearancePreviewRuntime
{
    IReadOnlyList<string> GetLivePreviewAppearanceIds();
    ValueTask<string?> OpenAppearancePreviewAsync(string appearanceId,
        OverlayAppearanceOptions options, bool reduceMotion = false, CancellationToken cancellationToken = default);
    ValueTask CloseAppearancePreviewAsync(string sessionId, CancellationToken cancellationToken = default);
}

/// <summary>
/// Optional: what the visor would show, for the client's layout editor to draw its own simplified panels with (11-12 user:
/// "编辑里还是要用模拟面板，只不过信息都一致", "可以是简化版的面板，只有框和背景那种，其他都按照真实的来"). The given draft
/// workspace with the live sources read the way the overlay reads them: the members (samples when there are none, flagged
/// <see cref="InformationOverlayEditorContent.Sample"/>), the events the overlay shows right now (samples filling the box
/// when there are none), the chat (samples when there is none), and the decoration colour
/// the visor draws with. Nothing shows on screen, nothing is saved, the live overlay's state is untouched, and no image is
/// drawn.
/// </summary>
public interface IInformationOverlayEditorPreviewRuntime
{
    ValueTask<InformationOverlayEditorContent> ReadEditorContentAsync(
        InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default);
}

/// <summary>The visor's content for the editor; <paramref name="Decoration"/> is "#RRGGBB" (the theme or ship colour).</summary>
public sealed record InformationOverlayEditorContent(bool Sample, string Decoration,
    InformationOverlayEditorMembers Members, InformationOverlayEditorEvents Events, InformationOverlayEditorChat Chat);

/// <summary>
/// The members block: its title, "you are at", the counts with their labels (online, in game, same server, in the
/// overlay's language), the page line and the rows shown.
/// </summary>
public sealed record InformationOverlayEditorMembers(string Title, string YouAt, int Online, int InGame, int SameServer,
    string Page, IReadOnlyList<InformationOverlayEditorMember> Rows, IReadOnlyList<string> CountLabels);

/// <summary>
/// One member row: <paramref name="State"/> is InGame, AppOnly, Away or Offline; <paramref name="Vitals"/> is Unknown, Alive,
/// Downed or Dead (only the local player's own row may know it), <paramref name="Health"/> 0..1.
/// </summary>
public sealed record InformationOverlayEditorMember(string Name, string Ship, string Place, string Status, string State,
    bool SameServer, bool Pinned, string Vitals, double Health);

/// <summary>
/// The events block: its title and the events the overlay shows right now, each with its kind's colour name, or sample
/// events (<paramref name="Sample"/>) when it shows none.
/// </summary>
public sealed record InformationOverlayEditorEvents(string Title, bool Sample, IReadOnlyList<InformationOverlayEditorEvent> Rows);

/// <summary>An event: <paramref name="Tone"/> is None, Place, Ship, Server, SameServer, Bad, Good or Reminder.</summary>
public sealed record InformationOverlayEditorEvent(string Title, string Detail, string Time, string Tone);

/// <summary>The chat block: its title and lines; <paramref name="Sample"/> when there is no chat to show.</summary>
public sealed record InformationOverlayEditorChat(string Title, bool Sample, IReadOnlyList<InformationOverlayEditorChatLine> Rows);

public sealed record InformationOverlayEditorChatLine(string Who, string Text);

/// <summary>Host changes schedule a coalesced native refresh; no HWND or render
/// implementation crosses this boundary.</summary>
public interface IInformationOverlayLiveUpdateSink
{
    bool IsVisible { get; }
    // A menu may temporarily hide an enabled HUD. Keep the existing authorized
    // source driver alive without claiming the HWND is visible.
    bool HasDisplayDemand => IsVisible;
    // While the game runs and the HUD is closed, keep its module sources' leases
    // renewed by ordinary fresh reads so reopening has data at once. Not a display
    // demand: no events, prompts or window refreshes follow from it.
    bool HasStandbyDemand => false;
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
