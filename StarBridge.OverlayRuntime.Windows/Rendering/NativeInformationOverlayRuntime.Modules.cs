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
            var result = workspace.HasInvalidSourceConfiguration
                ? new InformationOverlayModuleReadResult(null, "overlay.workspace_invalid_preset")
                : _moduleProvider?.Invoke(workspace);
            if (result is { Frame: { } frame, FailureCode: null })
                return ProjectModules(frame, workspace.Language, DateTimeOffset.UtcNow, session, presence);
            _moduleFailure = result?.FailureCode ?? "overlay.source_unavailable";
        }
        catch
        {
            // Never render the old single-source data after a v2 read fails.
            _moduleFailure = "overlay.source_unavailable";
        }
        var empty = new OverlayModuleScene(new([], false, OverlaySceneContext.Local(OverlayScenePreference.Auto)),
            BuildCommandState(workspace.Language) with { NoticeTitle = "", NoticeText = "" }, [], null, false, null)
        { EmptyMessage = OverlayModuleEmptyStates.Message(new(OverlaySourceMode.None, null, false), workspace.Language) };
        return new(empty, empty, empty, empty, empty, "unavailable");
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
            if (!_disposed && IsVisible)
            {
                try { RefreshWindow(); }
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
