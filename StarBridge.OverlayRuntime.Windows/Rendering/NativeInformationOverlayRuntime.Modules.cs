using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime
{
    private readonly Func<InformationOverlayRuntimeWorkspace, InformationOverlayModuleReadResult>? _moduleProvider;
    private OverlayModulePresentation? _lastRenderedModules;
    private string? _moduleFailure;
    private bool ModuleFailureRetryable => _moduleFailure is not null and not ("overlay.sources_limit_exceeded" or "overlay.workspace_invalid_preset");
    private DispatcherTimer? _moduleExpiryTimer;
    // Sources are re-read on open after their authorization lapsed while closed.
    internal static readonly TimeSpan ModuleSyncWindow = TimeSpan.FromSeconds(15);
    private DateTimeOffset? _moduleSyncStartedAt;
    // Modules that have shown data since this window opened. A later lapse is a
    // real "unavailable", never "syncing".
    private readonly HashSet<string> _modulesShownSinceOpen = new(StringComparer.Ordinal);

    private bool ModuleSyncing(DateTimeOffset now) =>
        _moduleSyncStartedAt is { } started && now - started < ModuleSyncWindow;

    private void StartModuleSync(DateTimeOffset? at)
    {
        _moduleSyncStartedAt = at;
        _modulesShownSinceOpen.Clear();
    }

    // Test observations run on the same STA and after the real window's model
    // has been updated. They neither provide content nor bypass authorization.
    internal Action<OverlayModulePresentation, OverlayModuleWindowObservation>? ModulesPresented;
    internal Action<DateTimeOffset>? ModuleValidationScheduled;

    internal Task PausePeriodicRefreshForTestAsync()
    {
        if (TestSurfaceBounds is null || _dispatcher is null)
            throw new InvalidOperationException("Periodic refresh control requires an isolated native test surface.");
        return _dispatcher.InvokeAsync(() => _gameWindowTimer?.Stop(), DispatcherPriority.Send).Task;
    }

    private OverlayModulePresentation? ReadModules(InformationOverlayRuntimeWorkspace workspace,
        GameLogSessionSnapshot session, PlayerPresenceKind? presence)
    {
        _moduleFailure = null;
        if (!workspace.UsesModuleSources) return null;
        try
        {
            var local = ReadLocalSource();
            var result = workspace.HasInvalidConfiguration
                ? new InformationOverlayModuleReadResult(null, "overlay.workspace_invalid_preset")
                : local is not null ? local.ReadModules(workspace) : _moduleProvider?.Invoke(workspace);
            var now = DateTimeOffset.UtcNow;
            if (result is { Frame: { } frame, FailureCode: null })
                return ExplainModules(ApplyModuleSync(ProjectModules(frame, workspace.Language, now, session, presence, local?.Read()),
                    workspace.Language, now), workspace);
            _moduleFailure = result?.FailureCode ?? "overlay.source_unavailable";
        }
        catch
        {
            // Never render the old single-source data after a v2 read fails.
            _moduleFailure = "overlay.source_unavailable";
        }
        var empty = new OverlayModuleScene(new([], false, OverlaySceneContext.Local(OverlayScenePreference.Auto)),
            BuildCommandState(workspace.Language) with { NoticeTitle = "", NoticeText = "" }, [], null, false, null)
        { EmptyMessage = OverlayModuleSourceCopy.Generic(workspace.Language) };
        return ApplyModuleSync(new(empty, empty, empty, empty, empty, "unavailable"), workspace.Language, DateTimeOffset.UtcNow);
    }

    // The in-game menu hint names the hotkey that actually opens it.
    private OverlayModulePresentation ExplainModules(OverlayModulePresentation modules, InformationOverlayRuntimeWorkspace workspace) =>
        OverlayModuleSourceCopy.ExplainOnce(modules,
            chatIsPanel: workspace.Settings.ChatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage,
            OverlayModuleSourceCopy.SwitchHint(_menuHotkey is { Enabled: false } ? null : _menuHotkey?.Binding ?? "Alt+M",
                workspace.Language));

    private OverlayModulePresentation ApplyModuleSync(OverlayModulePresentation modules, string language, DateTimeOffset now)
    {
        var syncing = false;
        OverlayModuleScene Mark(string key, OverlayModuleScene scene)
        {
            if (scene.Available) { _modulesShownSinceOpen.Add(key); return scene; }
            if (!ModuleSyncing(now) || _modulesShownSinceOpen.Contains(key) || scene.EmptyMessage is null) return scene;
            syncing = true;
            // Name what is being read, never a generic or a different source.
            return scene with { EmptyMessage = OverlayModuleSourceCopy.Syncing(scene.SourceLabel, language) };
        }
        var next = modules with
        {
            Notice = Mark("Notice", modules.Notice), Overview = Mark("Overview", modules.Overview),
            Members = Mark("Members", modules.Members), Chat = Mark("Chat", modules.Chat), Events = Mark("Events", modules.Events)
        };
        if (!syncing) return next;
        // Re-check when the window ends so "syncing" moves on to the real state.
        var end = _moduleSyncStartedAt!.Value + ModuleSyncWindow;
        return next with { NextValidationAt = next.NextValidationAt is { } at && at < end ? at : end };
    }

    private void ScheduleModuleValidation(OverlayModulePresentation? modules)
    {
        _moduleExpiryTimer?.Stop();
        _moduleExpiryTimer = null;
        if (modules?.NextValidationAt is not { } deadline || _dispatcher is null) return;
        var delay = deadline - DateTimeOffset.UtcNow;
        var timer = new DispatcherTimer(DispatcherPriority.Send, _dispatcher)
        {
            Interval = delay > TimeSpan.Zero ? delay : TimeSpan.FromMilliseconds(1)
        };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_moduleExpiryTimer, timer)) return;
            _moduleExpiryTimer = null;
            if (!_disposed && HasDisplayDemand)
            {
                try { if (!ValidateMenuInformationLayer()) RefreshWindow(); }
                catch (Exception error)
                {
                    TryCloseWindow();
                    _snapshot = FailedSnapshot(_workspace!, ResolveFailureCode(error), retryable: true);
                }
            }
        };
        _moduleExpiryTimer = timer;
        timer.Start();
        ModuleValidationScheduled?.Invoke(deadline);
    }
}

internal sealed record OverlayModuleWindowObservation(string Notice, string OverviewTitle, string MembersTitle,
    IReadOnlyList<string> Members, IReadOnlyList<string> Chat, int ChatPulse, string OverviewPrimary)
{
    internal OverlayModuleSourceLabels SourceLabels { get; init; } = OverlayModuleSourceLabels.Empty;
    internal OverlayModuleEmptyStates EmptyStates { get; init; } = OverlayModuleEmptyStates.Empty;
    internal InformationOverlayVisibility Visibility { get; init; }
}
