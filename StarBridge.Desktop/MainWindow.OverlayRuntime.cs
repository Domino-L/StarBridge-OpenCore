using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private enum OverlayHotkeyRegistrationState
    {
        Disabled,
        Registered,
        GameCompatibleOnly,
        DesktopOnly,
        Conflict,
        ConflictWithMenu,
        Invalid,
        Failed
    }

    private const int ErrorHotkeyAlreadyRegistered = 1409;
    private OverlayHotkeyRegistrationState _overlayHotkeyRegistrationState = OverlayHotkeyRegistrationState.Disabled;
    private bool _applyingOverlayHotkeySettings;

    private async void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        var app = System.Windows.Application.Current as App;
        if (app is not null &&
            app.BehaviorSettings.ShouldPromptForCloseBehavior(
                app.ExitRequested,
                app.IsUpdateRestartRequested))
        {
            var keepRunning = StarBridgeMessageBox.ShowAction(
                this,
                ApplicationClosePromptCopy.Build(_gameplayStatisticsRecorder.IsRecordingAllowed),
                "关闭窗口后如何运行？",
                "保持后台运行",
                "完全退出",
                MessageBoxImage.Question);
            var result = app.TryApplyBehaviorSettings(app.BehaviorSettings with
            {
                KeepRunningInBackground = keepRunning,
                CloseBehaviorChoiceMade = true
            });
            if (!result.Succeeded)
            {
                e.Cancel = true;
                StarBridgeMessageBox.Show(
                    this,
                    $"关闭行为未保存：{result.Error ?? "无法写入应用设置。"}\n\n请重试，或前往应用设置手动选择关闭行为。",
                    "设置未保存",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            _applicationBehaviorSettings = result.Settings;
            if (keepRunning)
            {
                e.Cancel = true;
                app.HideMainWindowToBackground();
                return;
            }
        }

        if (app?.ShouldKeepRunningInBackground == true)
        {
            e.Cancel = true;
            app.HideMainWindowToBackground();
            return;
        }

        if (!TryResolveOverlayEditorUnsavedChanges("关闭星海舰桥"))
        {
            e.Cancel = true;
            app?.CancelExitRequest();
            return;
        }

        if (_isOverlayEditorFullScreen)
        {
            ExitOverlayEditorFullScreen();
        }

        _gameplayStatisticsRecorder.Stop(DateTimeOffset.UtcNow);
        SaveCurrentConfig();
        if (!_isClosingAfterOfflineUpload && IsLoggedIn && !string.IsNullOrWhiteSpace(_localPlayer))
        {
            if (app?.IsUpdateRestartRequested == true)
            {
                // An update restart is a continuation of the same session. Avoid publishing a
                // false offline transition and keep the file replacement path deterministic.
                _isClosingAfterOfflineUpload = true;
                _gameProcessTimer.Stop();
                StopNetworkSyncTimers();
                CloseOverlayWindow();
                return;
            }

            e.Cancel = true;
            _isClosingAfterOfflineUpload = true;
            _gameProcessTimer.Stop();
            StopNetworkSyncTimers();
            await PushOfflineSnapshotOnShutdownAsync();
            _ = Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(Close));
            return;
        }

        CloseOverlayWindow();
    }

    private void MainWindow_StateChanged(object? sender, EventArgs e)
    {
        UpdateMaximizeButtonText();
        UpdateOverlayVisibilityForMainWindowState();
    }

    private void UpdateOverlayVisibilityForMainWindowState()
    {
        if (WindowState == WindowState.Minimized)
        {
            if (!_overlaySettings.EnableTrayMode && IsOverlayRunning && _overlayWindow is not null)
            {
                _overlayHiddenForMainWindowMinimize = true;
                _overlayWindow.SetVisible(false);
                RefreshPersonalIdentityConsole();
                RefreshOverlayOverviewSummary();
            }

            return;
        }

        if (!_overlayHiddenForMainWindowMinimize)
        {
            return;
        }

        _overlayHiddenForMainWindowMinimize = false;
        _overlayWindow?.SetVisible(true);
        RefreshOverlayWindow();
        RefreshPersonalIdentityConsole();
        RefreshOverlayOverviewSummary();
    }

    private void LanguageBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (LanguageBox.SelectedItem is ComboBoxItem { Tag: string language })
        {
            _language = NormalizeLanguage(language);
            ApplyLanguageToControls();
            RenderState();
            RefreshOverlayWindow();
            if (!_isLoadingSettings)
            {
                SaveCurrentConfig();
            }
        }
    }

    private void OverlayHotkeyBox_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        OverlayHotkeyBox.SelectAll();
    }

    private void OverlayHotkeyBox_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (!OverlayHotkeyBindingPolicy.TryCapture(
                Keyboard.Modifiers,
                key,
                out var captured))
        {
            return;
        }

        var previousHotkey = OverlayHotkeyBox.Text;
        OverlayHotkeyBox.Text = captured.StorageText;
        var plan = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            _inGameMenuSettings);
        if (plan.MenuState ==
            OverlayHotkeyBindingState.ConflictWithInformation)
        {
            OverlayHotkeyBox.Text = previousHotkey;
            ShowInformationHotkeyValidation(
                OverlayHotkeyRegistrationState.ConflictWithMenu);
            return;
        }

        if (!_isLoadingSettings)
        {
            RegisterOverlayHotkey();
            if (!RequestedHotkeyRoutesAreReady(
                    OverlayGlobalHotkeyEnabledCheck.IsChecked == true))
            {
                RestoreInformationHotkeyRoute(
                    previousHotkey,
                    OverlayGlobalHotkeyEnabledCheck.IsChecked == true);
                return;
            }

            SaveCurrentConfig();
            UpdateInGameMenuSettingsPresentation();
        }
    }

    private void OverlayGlobalHotkeyEnabledCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _applyingOverlayHotkeySettings)
        {
            return;
        }

        var requestedEnabled =
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true;
        if (requestedEnabled)
        {
            var plan = OverlayHotkeyBindingPolicy.Build(
                OverlayHotkeyBox.Text,
                informationEnabled: true,
                _inGameMenuSettings);
            if (plan.MenuState ==
                OverlayHotkeyBindingState.ConflictWithInformation)
            {
                _applyingOverlayHotkeySettings = true;
                OverlayGlobalHotkeyEnabledCheck.IsChecked = false;
                _applyingOverlayHotkeySettings = false;
                ShowInformationHotkeyValidation(
                    OverlayHotkeyRegistrationState.ConflictWithMenu);
                return;
            }
        }

        RegisterOverlayHotkey();
        if (!RequestedHotkeyRoutesAreReady(requestedEnabled))
        {
            _applyingOverlayHotkeySettings = true;
            OverlayGlobalHotkeyEnabledCheck.IsChecked =
                !requestedEnabled;
            _applyingOverlayHotkeySettings = false;
            RegisterOverlayHotkey();
            OverlayHotkeyRegistrationHintText.Text =
                "新的信息浮层热键设置未能启用，已恢复原设置。";
            return;
        }

        SaveCurrentConfig();
        UpdateInGameMenuSettingsPresentation();
        RefreshPersonalIdentityConsole();
    }

    private void OpenOverlay_Click(object sender, RoutedEventArgs e)
    {
        ToggleOverlayWindow();
    }

    private void ToggleOverlayWindow(bool focusGameWindow = true)
    {
        if (_inGameMenuCoordinator.IsOpen)
        {
            _inGameMenuCoordinator.Close(InGameMenuExitMode.SwitchToInformationOverlay);
            return;
        }

        if (_overlayHiddenForMainWindowMinimize && _overlayWindow is not null)
        {
            CloseOverlayWindow();
            RefreshPersonalIdentityConsole();
            RefreshOverlayOverviewSummary();
            return;
        }

        if (_overlayWindow is { IsVisible: true })
        {
            CloseOverlayWindow();
            RefreshPersonalIdentityConsole();
            RefreshOverlayOverviewSummary();
            return;
        }

        var overlaySettings = OverlayStartupTransitionPolicy.ResolveForOpen(
            GetEffectiveOverlaySettings(),
            StarCitizenProcessProbe.IsForeground());
        var opened = OpenOverlayWindow(overlaySettings);
        if (opened && focusGameWindow && overlaySettings.AutoFocusGameWindowOnOpen)
        {
            ScheduleGameFocusAfterOverlayStartup(overlaySettings);
        }

        RefreshPersonalIdentityConsole();
        RefreshOverlayOverviewSummary();
    }

    private void ScheduleGameFocusAfterOverlayStartup(OverlayDisplaySettings overlaySettings)
    {
        CancelPendingOverlayGameFocus();
        var nightShadowFlowHandoff = false;
        var flowFieldMidTransitionHandoff = false;
        var deferredNightShadowStart = false;
        var nightShadowSettleMs = 0;
        if (StarCitizenProcessProbe.IsForeground())
        {
            if (deferredNightShadowStart)
            {
                _overlayWindow?.BeginStartupTransition(nightShadowSettleMs);
                AppendOutput("OVERLAY | game window active; deferred Night Shadow transition armed after focus settle.");
            }
            else
            {
                AppendOutput("OVERLAY | game window already active; post-transition focus skipped.");
            }

            return;
        }

        var delayMs = ResolveOverlayGameFocusDelayMs(overlaySettings);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(delayMs) };
        var focusAttempts = 0;
        _overlayGameFocusDelayTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_overlayGameFocusDelayTimer, timer))
            {
                return;
            }

            if (_overlayWindow is not { IsVisible: true })
            {
                _overlayGameFocusDelayTimer = null;
                return;
            }

            var focusStopwatch = Stopwatch.StartNew();
            TryFocusStarCitizenWindow();
            LogOverlayPerformance("game-focus-timer", focusStopwatch, force: true);
            focusAttempts++;
            if (nightShadowFlowHandoff && !StarCitizenProcessProbe.IsForeground() && focusAttempts < 5)
            {
                timer.Interval = TimeSpan.FromMilliseconds(20);
                timer.Start();
                return;
            }

            _overlayGameFocusDelayTimer = null;
            if (deferredNightShadowStart)
            {
                _overlayWindow.BeginStartupTransition(nightShadowSettleMs);
                AppendOutput(StarCitizenProcessProbe.IsForeground()
                    ? "OVERLAY | deferred Night Shadow transition started after foreground confirmation."
                    : "OVERLAY | foreground confirmation timed out; deferred Night Shadow transition released safely.");
            }
        };

        AppendOutput(flowFieldMidTransitionHandoff
            ? $"OVERLAY | game window focus scheduled behind the closed Night Shadow shutter ({delayMs}ms)."
            : $"OVERLAY | game window focus scheduled at overlay handoff ({delayMs}ms).");
        timer.Start();
    }

    private void CancelPendingOverlayGameFocus()
    {
        _overlayGameFocusDelayTimer?.Stop();
        _overlayGameFocusDelayTimer = null;
    }

    private static bool ShouldPlayOverlayStartupTransition(OverlayDisplaySettings settings)
    {
        return settings.EnableStartupTransition &&
               settings.StartupTransitionStyle == OverlayStartupTransitionStyle.BridgeTerminal;
    }

    private int ResolveOverlayGameFocusDelayMs(OverlayDisplaySettings settings)
    {
        if (settings.EnableStartupTransition &&
            settings.StartupTransitionStyle == OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium)
        {
            return (int)Math.Ceiling(LagrangeWeaveTimeline.FocusHandoffMs);
        }


        if (!ShouldPlayOverlayStartupTransition(settings))
        {
            return OverlayGameFocusWithoutTransitionDelayMs;
        }

        return (int)Math.Ceiling(OverlayCompositionStartupTransitionWindow.PreferredGameFocusDelayMs);
    }

    private bool OpenOverlayWindow(OverlayDisplaySettings overlaySettings)
    {
        _overlayHiddenForMainWindowMinimize = false;
        var stopwatch = Stopwatch.StartNew();
        var commandState = BuildOverlayCommandState();
        var localShard = IsGameServerRegionCurrent() ? _gameServerShard : "";
        var surfaceBounds = ResolveOverlayTargetSurfaceBounds();
        var transitionContext = BuildOverlayStartupTransitionContext(overlaySettings);
        var overlayHost = CreateOverlayHost(
            overlaySettings,
            commandState,
            _localPresence,
            localShard,
            surfaceBounds,
            transitionContext);
        _overlayWindow = overlayHost;
        overlayHost.Closed += (_, _) =>
        {
            if (ReferenceEquals(_overlayWindow, overlayHost))
            {
                _overlayWindow = null;
            }

            RefreshPersonalIdentityConsole();
            RefreshOverlayOverviewSummary();
        };
        try
        {
            var opened = OverlayStartupBoundary.TryShow(
                overlayHost.Show,
                overlayHost.Close,
                exception =>
                {
                    App.WriteDiagnosticLog($"overlay-startup-contained | {exception}");
                    AppendOutput($"OVERLAY | startup failed={exception.GetBaseException().Message}");
                    _ = ShowAppNoticeAsync(
                        "信息浮层未能启动",
                        "图形渲染初始化没有及时完成，主应用仍可继续使用。",
                        "请稍后重试；如果问题再次发生，可在“帮助与反馈”中提交诊断记录。");
                });
            if (!opened && ReferenceEquals(_overlayWindow, overlayHost))
            {
                _overlayWindow = null;
            }

            return opened;
        }
        finally
        {
            LogOverlayPerformance("open-overlay mode=DirectComposition", stopwatch);
        }
    }


    private IOverlayHost CreateOverlayHost(
        OverlayDisplaySettings overlaySettings,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        Rect surfaceBounds,
        OverlayStartupTransitionContext transitionContext)
    {
        var projection = BuildOverlayAccessProjection(overlaySettings, commandState);
        AppendOutput("OVERLAY | render-mode=DirectComposition | DC HUD");
        var roster = ResolveOverlayAuthorizedRoster(projection.Scene);
        var rosterSettings = GetOverlayRosterSelectionSettings();
        return new OverlayCompositionHudWindow(
            roster,
            projection.ChatMessages,
            _overlayLayout,
            projection.Settings,
            rosterSettings,
            _language,
            projection.Scene.HasContent,
            projection.CommandState,
            localPresence,
            localShard,
            surfaceBounds,
            transitionContext,
            projection.Scene.Context);
    }

    private OverlayAccessProjection BuildOverlayAccessProjection(
        OverlayDisplaySettings overlaySettings,
        OverlayCommandState commandState)
    {
        var scene = ResolveCurrentOverlayScene(overlaySettings);
        commandState = scene.ApplySceneCommandState(
            commandState,
            _language.Equals("zh", StringComparison.OrdinalIgnoreCase));
        return OverlayAccessPolicy.Apply(
            IsLoggedIn && !_isAccountTransition,
            scene,
            overlaySettings,
            commandState,
            ResolveCurrentOverlayChatMessages(scene.Context));
    }

    private OverlaySceneSnapshot ResolveCurrentOverlayScene(OverlayDisplaySettings? settings = null)
    {
        var effectiveSettings = settings ?? _overlaySettings;
        var scene = OverlaySceneResolver.Resolve(
            effectiveSettings.ScenePreference,
            _players,
            _hasFleet,
            _currentPartyRoom,
            _localPlayer,
            _callsign);
        var context = scene.Context.Kind == OverlaySceneKind.PartyRoom
            ? scene.Context with
            {
                ChatChannelId = scene.Context.RoomId,
                ChatChannelTitle = scene.Context.RoomTitle
            }
            : scene.Context with
            {
                ChatChannelId = ResolveFleetOverlayChatProjectionId(),
                ChatChannelTitle = ResolveFleetOverlayChatTitle()
            };
        return OverlayAccessPolicy.Apply(
            IsLoggedIn && !_isAccountTransition,
            scene with { Context = context },
            effectiveSettings,
            new OverlayCommandState(null, null, null, null, null, null),
            []).Scene;
    }

    internal TrayQuickPanelState BuildTrayQuickPanelState()
    {
        var sharing = GetPresenceSharingDecision();
        var scene = ResolveCurrentOverlayScene().Context;
        var preferenceText = _overlaySettings.ScenePreference switch
        {
            OverlayScenePreference.Fleet => "舰队",
            OverlayScenePreference.PartyRoom => "组队房间",
            _ => "自动"
        };
        var resolvedSceneText = scene.IsLocalOnly
            ? "本地模式"
            : scene.Kind == OverlaySceneKind.PartyRoom
                ? "组队房间"
                : "舰队";
        var sceneText = scene.IsLocalOnly
            ? resolvedSceneText
            : $"{preferenceText} · {resolvedSceneText}";
        if (scene.IsFallback)
        {
            sceneText += "（回退）";
        }

        return new TrayQuickPanelState(
            $"V{GetAppVersion()}",
            PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language),
            sharing.PublicPresence,
            _isGameProcessRunning,
            IsOverlayRunning,
            IsOverlayRunning ? "已开启" : "未开启",
                IsOverlayRunning ? "关闭浮层" : "开启浮层",
            sceneText,
            AvatarImage.Source,
            TrayQuickPanelIdentity.ResolveAvatarInitial(GetPersonalDisplayName()));
    }

    internal void ToggleOverlayFromTray()
    {
        ToggleOverlayWindow(focusGameWindow: false);
    }

    internal void OpenOverlaySettingsFromTray()
    {
        OverlayNav_Click(this, new RoutedEventArgs());
    }

    private void OpenOverlayAppearanceSettings()
    {
        OpenOverlaySettingsFromTray();
        SetOverlaySettingsWorkspace(OverlaySettingsArea.Information);
        Dispatcher.BeginInvoke(
            new Action(() =>
            {
                var target = ResolveOverlaySettingsSection("appearance");
                if (target is null)
                {
                    return;
                }

                _overlaySettingsProgrammaticTargetKey = "appearance";
                SetActiveOverlaySettingsSection("appearance");
                ScrollOverlaySettingsToSection(target);
            }),
            System.Windows.Threading.DispatcherPriority.Loaded);
    }

    private IntPtr MainWindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmGetMinMaxInfo)
        {
            AdjustMaximizedWindowBounds(hwnd, lParam);
            handled = true;
            return IntPtr.Zero;
        }

        if (msg == WmHotkey && wParam.ToInt32() == OverlayHotkeyId)
        {
            handled = true;
            HandleOverlayHotkeyTrigger("windows");
        }

        if (msg == WmGameCompatibleHotkey)
        {
            handled = true;
            var commandId = wParam.ToInt32();
            if (commandId == InGameMenuHotkeyCommand)
            {
                HandleInGameMenuHotkeyTrigger("game-compatible");
            }
            else if (StarCitizenProcessProbe.IsForeground())
            {
                HandleOverlayHotkeyTrigger("game-compatible");
            }
        }

        return IntPtr.Zero;
    }

    private void HandleOverlayHotkeyTrigger(string source)
    {
        if (OverlayGlobalHotkeyEnabledCheck.IsChecked != true)
        {
            return;
        }

        var messageTimestamp = unchecked((uint)GetMessageTime());
        if (!_overlayHotkeyTriggerGate.TryAccept(messageTimestamp))
        {
            AppendOutput($"HOTKEY | duplicate suppressed | source={source}");
            return;
        }

        AppendOutput($"HOTKEY | triggered | source={source}");
        ToggleOverlayWindow();
    }

    private void HandleInGameMenuHotkeyTrigger(string source)
    {
        if (!_inGameMenuSettings.EnableHotkey ||
            !_inGameMenuCoordinator.IsOpen &&
            !StarCitizenProcessProbe.IsForeground())
        {
            return;
        }

        if (_inGameMenuCoordinator.IsOpen &&
            !_inGameMenuSettings.CloseWithHotkey)
        {
            _inGameMenuCoordinator.ShowNotice(
                "菜单热键仅用于打开",
                "按 Esc 返回游戏。可在菜单浮层设置中改为再次按热键关闭。");
            return;
        }

        var messageTimestamp = unchecked((uint)GetMessageTime());
        if (!_inGameMenuHotkeyTriggerGate.TryAccept(messageTimestamp))
        {
            AppendOutput($"GAME MENU HOTKEY | duplicate suppressed | source={source}");
            return;
        }

        AppendOutput($"GAME MENU HOTKEY | triggered | source={source}");
        ToggleInGameMenu(requireGameForeground: !_inGameMenuCoordinator.IsOpen);
    }

    private void AdjustMaximizedWindowBounds(IntPtr hwnd, IntPtr lParam)
    {
        var monitor = MonitorFromWindow(hwnd, MonitorDefaultToNearest);
        if (monitor == IntPtr.Zero)
        {
            return;
        }

        var monitorInfo = new MonitorInfo();
        monitorInfo.Size = Marshal.SizeOf<MonitorInfo>();
        if (!GetMonitorInfo(monitor, ref monitorInfo))
        {
            return;
        }

        var minMaxInfo = Marshal.PtrToStructure<MinMaxInfo>(lParam);
        var monitorArea = monitorInfo.MonitorArea;
        var targetArea = _isOverlayEditorFullScreen
            ? monitorArea
            : monitorInfo.WorkArea;

        minMaxInfo.MaxPosition.X = targetArea.Left - monitorArea.Left;
        minMaxInfo.MaxPosition.Y = targetArea.Top - monitorArea.Top;
        minMaxInfo.MaxSize.X = Math.Abs(targetArea.Right - targetArea.Left);
        minMaxInfo.MaxSize.Y = Math.Abs(targetArea.Bottom - targetArea.Top);
        minMaxInfo.MaxTrackSize.X = minMaxInfo.MaxSize.X;
        minMaxInfo.MaxTrackSize.Y = minMaxInfo.MaxSize.Y;

        Marshal.StructureToPtr(minMaxInfo, lParam, false);
    }

    private void RegisterOverlayHotkey()
    {
        UnregisterOverlayHotkey();
        var plan = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            _inGameMenuSettings);
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero)
        {
            SetOverlayHotkeyRegistrationState(
                plan.InformationState switch
                {
                    OverlayHotkeyBindingState.Disabled =>
                        OverlayHotkeyRegistrationState.Disabled,
                    OverlayHotkeyBindingState.Invalid =>
                        OverlayHotkeyRegistrationState.Invalid,
                    _ => OverlayHotkeyRegistrationState.Failed
                });
            UpdateMenuHotkeyRegistrationPresentation(
                plan.MenuState,
                listenerReady: false);
            return;
        }

        var compatibleRoutes = plan.CreateGameCompatibleRoutes(
            InformationOverlayHotkeyCommand,
            InGameMenuHotkeyCommand);
        var compatibleRegistered =
            compatibleRoutes.Count > 0 &&
            _gameCompatibleHotkeyListener.Start(
                handle,
                WmGameCompatibleHotkey,
                compatibleRoutes);
        var compatibleError = _gameCompatibleHotkeyListener.LastError;
        UpdateMenuHotkeyRegistrationPresentation(
            plan.MenuState,
            listenerReady:
                plan.MenuState == OverlayHotkeyBindingState.Ready &&
                compatibleRegistered);
        AppendOutput(
            $"GAME MENU HOTKEY | state={plan.MenuState} | binding={_inGameMenuSettings.Hotkey} | listener={compatibleRegistered}");

        if (plan.InformationState == OverlayHotkeyBindingState.Disabled)
        {
            SetOverlayHotkeyRegistrationState(
                OverlayHotkeyRegistrationState.Disabled);
            AppendOutput("HOTKEY | information disabled");
            return;
        }

        if (plan.InformationState != OverlayHotkeyBindingState.Ready ||
            plan.InformationHotkey is not { } informationHotkey)
        {
            SetOverlayHotkeyRegistrationState(
                OverlayHotkeyRegistrationState.Invalid);
            AppendOutput($"HOTKEY | information invalid={OverlayHotkeyBox.Text}");
            return;
        }

        _hotkeyRegistered = RegisterHotKey(
            handle,
            OverlayHotkeyId,
            informationHotkey.Modifiers | ModNoRepeat,
            informationHotkey.VirtualKey);
        var windowsError = _hotkeyRegistered ? 0 : Marshal.GetLastWin32Error();
        if (_hotkeyRegistered && compatibleRegistered)
        {
            SetOverlayHotkeyRegistrationState(OverlayHotkeyRegistrationState.Registered);
            AppendOutput($"HOTKEY | registered={OverlayHotkeyBox.Text} | game-compatible=ready");
            return;
        }

        if (compatibleRegistered)
        {
            SetOverlayHotkeyRegistrationState(OverlayHotkeyRegistrationState.GameCompatibleOnly);
            AppendOutput(
                $"HOTKEY | game-compatible ready={OverlayHotkeyBox.Text} | windows-error={windowsError}");
            return;
        }

        if (_hotkeyRegistered)
        {
            SetOverlayHotkeyRegistrationState(OverlayHotkeyRegistrationState.DesktopOnly);
            AppendOutput(
                $"HOTKEY | windows registered={OverlayHotkeyBox.Text} | game-compatible-error={compatibleError}");
            return;
        }

        SetOverlayHotkeyRegistrationState(windowsError == ErrorHotkeyAlreadyRegistered
            ? OverlayHotkeyRegistrationState.Conflict
            : OverlayHotkeyRegistrationState.Failed);
        AppendOutput(
            $"HOTKEY | register failed={OverlayHotkeyBox.Text} | windows-error={windowsError} | game-compatible-error={compatibleError}");
    }

    private void SetOverlayHotkeyRegistrationState(OverlayHotkeyRegistrationState state)
    {
        _overlayHotkeyRegistrationState = state;
        if (OverlayHotkeyStatusBadge is null ||
            OverlayHotkeyStatusIndicator is null ||
            OverlayHotkeyStatusText is null ||
            OverlayHotkeyRegistrationHintText is null)
        {
            return;
        }

        var zh = _language == "zh";
        var (statusText, hintText, surfaceKey, statusKey) = state switch
        {
            OverlayHotkeyRegistrationState.Registered => (
                zh ? "已启用" : "Enabled",
                zh
                    ? $"{OverlayHotkeyBox.Text} 已启用，支持在游戏内切换浮层。"
                    : $"{OverlayHotkeyBox.Text} is ready for desktop and in-game use.",
                "StatusSuccessSurfaceBrush",
                "StatusSuccessBrush"),
            OverlayHotkeyRegistrationState.GameCompatibleOnly => (
                zh ? "游戏内可用" : "In-game ready",
                zh
                    ? $"{OverlayHotkeyBox.Text} 可在游戏内使用；该组合键的桌面注册被其他应用占用。"
                    : $"{OverlayHotkeyBox.Text} works in game, but another app owns the desktop shortcut.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyRegistrationState.DesktopOnly => (
                zh ? "部分可用" : "Limited",
                zh
                    ? $"{OverlayHotkeyBox.Text} 可在桌面使用，游戏兼容监听未启动；请重启应用后重试。"
                    : $"{OverlayHotkeyBox.Text} works on desktop, but in-game listening did not start. Restart the app and retry.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyRegistrationState.Conflict => (
                zh ? "按键被占用" : "In use",
                zh ? "该组合键已被其他应用占用，请设置其他组合键。" : "Another app is using this shortcut. Choose a different combination.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyRegistrationState.ConflictWithMenu => (
                zh ? "与菜单热键重复" : "Matches menu shortcut",
                zh
                    ? "信息浮层与菜单浮层不能使用同一组合键，请先更改其中一个。"
                    : "Information and menu overlays cannot use the same shortcut. Change either shortcut first.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyRegistrationState.Invalid => (
                zh ? "按键无效" : "Invalid",
                zh ? "请按下包含一个非修饰键的有效组合。" : "Press a valid combination containing a non-modifier key.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyRegistrationState.Failed => (
                zh ? "注册失败" : "Failed",
                zh ? "Windows 未能注册该组合键，请重试或更换组合键。" : "Windows could not register this shortcut. Retry or choose another one.",
                "StatusDangerSurfaceBrush",
                "StatusDangerBrush"),
            _ => (
                zh ? "已关闭" : "Disabled",
                zh ? "全局监听已关闭，仍可从应用或托盘控制浮层。" : "Global listening is off. The app and tray controls still work.",
                "StatusDisabledSurfaceBrush",
                "StatusDisabledBrush")
        };

        var surface = TryFindResource(surfaceKey) as System.Windows.Media.Brush;
        var statusBrush = TryFindResource(statusKey) as System.Windows.Media.Brush;
        OverlayHotkeyStatusBadge.Background = surface ?? System.Windows.Media.Brushes.Transparent;
        OverlayHotkeyStatusBadge.BorderBrush = statusBrush ?? System.Windows.Media.Brushes.Transparent;
        OverlayHotkeyStatusIndicator.Fill = statusBrush ?? System.Windows.Media.Brushes.Transparent;
        OverlayHotkeyStatusText.Foreground = statusBrush ?? System.Windows.Media.Brushes.Transparent;
        OverlayHotkeyStatusText.Text = statusText;
        OverlayHotkeyRegistrationHintText.Text = hintText;
    }

    private void ShowInformationHotkeyValidation(
        OverlayHotkeyRegistrationState validationState)
    {
        var activeState = _overlayHotkeyRegistrationState;
        SetOverlayHotkeyRegistrationState(validationState);
        _overlayHotkeyRegistrationState = activeState;
    }

    private bool RequestedHotkeyRoutesAreReady(
        bool informationEnabled)
    {
        var informationReady =
            !informationEnabled ||
            _overlayHotkeyRegistrationState is
                OverlayHotkeyRegistrationState.Registered or
                OverlayHotkeyRegistrationState.GameCompatibleOnly or
                OverlayHotkeyRegistrationState.DesktopOnly;
        var menuReady =
            !_inGameMenuSettings.EnableHotkey ||
            _menuHotkeyBindingState ==
                OverlayHotkeyBindingState.Ready &&
            _menuHotkeyListenerReady;
        return informationReady && menuReady;
    }

    private void RestoreInformationHotkeyRoute(
        string previousHotkey,
        bool informationEnabled)
    {
        OverlayHotkeyBox.Text = previousHotkey;
        RegisterOverlayHotkey();
        OverlayHotkeyRegistrationHintText.Text =
            informationEnabled
                ? "新的信息浮层热键未能启用，已恢复原设置。"
                : "信息浮层热键保持关闭，未更改当前菜单热键。";
    }

    private void UnregisterOverlayHotkey()
    {
        _gameCompatibleHotkeyListener.Stop();
        _overlayHotkeyTriggerGate.Reset();
        _inGameMenuHotkeyTriggerGate.Reset();

        var handle = new WindowInteropHelper(this).Handle;
        if (_hotkeyRegistered && handle != IntPtr.Zero)
        {
            UnregisterHotKey(handle, OverlayHotkeyId);
        }

        _hotkeyRegistered = false;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr handle, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr handle, int id);

    [DllImport("user32.dll")]
    private static extern int GetMessageTime();

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr handle, int flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo monitorInfo);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    private struct PointInfo
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public PointInfo Reserved;
        public PointInfo MaxSize;
        public PointInfo MaxPosition;
        public PointInfo MinTrackSize;
        public PointInfo MaxTrackSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RectInfo
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MonitorInfo
    {
        public int Size;
        public RectInfo MonitorArea;
        public RectInfo WorkArea;
        public uint Flags;
    }

    private void CloseOverlayWindow()
    {
        CancelPendingOverlayGameFocus();
        _overlayHiddenForMainWindowMinimize = false;
        var overlayWindow = _overlayWindow;
        if (overlayWindow is null)
        {
            return;
        }

        _overlayWindow = null;
        try
        {
            overlayWindow.Close();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void RefreshOverlayWindow()
    {
        RefreshInGameMenu();
        if (_overlayWindow is not { IsVisible: true })
        {
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            var projection = BuildOverlayAccessProjection(
                GetEffectiveOverlaySettings(),
                BuildOverlayCommandState());
            var roster = ResolveOverlayAuthorizedRoster(projection.Scene);
            _overlayWindow.Refresh(
                roster,
                projection.ChatMessages,
                _overlayLayout,
                projection.Settings,
                GetOverlayRosterSelectionSettings(),
                _language,
                projection.Scene.HasContent,
                projection.CommandState,
                _localPresence,
                IsGameServerRegionCurrent() ? _gameServerShard : "",
                ResolveOverlayTargetSurfaceBounds(),
                BuildOverlayStartupTransitionContext(projection.Settings),
                projection.Scene.Context);
        }
        finally
        {
            LogOverlayPerformance("refresh-overlay", stopwatch);
        }
    }

    private Rect ResolveOverlayTargetSurfaceBounds()
    {
        var gameHandle = StarCitizenProcessProbe.FindMainWindow();
        if (TryResolveOverlayScreenBounds(gameHandle, out var gameBounds))
        {
            return gameBounds;
        }

        var appHandle = new WindowInteropHelper(this).Handle;
        if (TryResolveOverlayScreenBounds(appHandle, out var appBounds))
        {
            return appBounds;
        }

        return new Rect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            Math.Max(1, SystemParameters.VirtualScreenWidth),
            Math.Max(1, SystemParameters.VirtualScreenHeight));
    }

    private bool TryResolveOverlayScreenBounds(IntPtr handle, out Rect bounds)
    {
        bounds = default;
        if (handle == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            var screen = WinForms.Screen.FromHandle(handle);
            if (screen.Bounds.Width <= 0 || screen.Bounds.Height <= 0)
            {
                return false;
            }

            var targetDpi = GetDpiForWindow(handle);
            var fallbackDpi = VisualTreeHelper.GetDpi(this);
            var scaleX = targetDpi > 0
                ? targetDpi / 96d
                : fallbackDpi.DpiScaleX > 0 ? fallbackDpi.DpiScaleX : 1;
            var scaleY = targetDpi > 0
                ? targetDpi / 96d
                : fallbackDpi.DpiScaleY > 0 ? fallbackDpi.DpiScaleY : 1;
            bounds = new Rect(
                screen.Bounds.Left / scaleX,
                screen.Bounds.Top / scaleY,
                screen.Bounds.Width / scaleX,
                screen.Bounds.Height / scaleY);
            return bounds.Width > 1 && bounds.Height > 1;
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            return false;
        }
    }

    private OverlayStartupTransitionContext BuildOverlayStartupTransitionContext(OverlayDisplaySettings settings)
    {
        var traditional = _language.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase) ||
                          _language.Equals("zh-TW", StringComparison.OrdinalIgnoreCase) ||
                          _language.Equals("zh-HK", StringComparison.OrdinalIgnoreCase);
        var zh = traditional || _language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        string Localize(string simplified, string traditionalText, string english) =>
            traditional ? traditionalText : zh ? simplified : english;

        var localized = OverlayStartupTransitionContext.ForLanguage(_language);
        var hasCollaborativeFleet = IsLoggedIn && _hasFleet;
        var logSelected = !string.IsNullOrWhiteSpace(_logPath);
        var logExists = logSelected && File.Exists(_logPath!);
        var logLabel = logExists
            ? Path.GetFileName(_logPath!)
            : logSelected
                ? Localize("Game.log 路径待检查", "Game.log 路徑待檢查", "Game.log path check")
                : Localize("尚未选择 Game.log", "尚未選擇 Game.log", "Game.log not selected");
        var identityLabel = !string.IsNullOrWhiteSpace(_localPlayer)
            ? DisplayCallsign(_callsign, _localPlayer)
            : IsLoggedIn
                ? (_callsign ?? Localize("账号身份", "帳號身份", "account identity"))
                : Localize("访客身份", "訪客身份", "guest identity");
        var fleetLabel = hasCollaborativeFleet
            ? $"{_fleetName} [{_fleetCode}]"
            : Localize("本地指挥模式", "本機指揮模式", "local command mode");
        var relayHost = BuildOverlayRelayHostLabel();
        var hudModuleCount = CountOverlayHudModules(settings);
        var hudModuleLabel = Localize(
            $"已启用 {hudModuleCount} 个模块",
            $"已啟用 {hudModuleCount} 個模組",
            $"{hudModuleCount} modules active");
        var logStateLabel = !logSelected
            ? Localize("未选择", "未選擇", "NOT SELECTED")
            : logExists
                ? Localize("就绪", "就緒", "READY")
                : Localize("检查路径", "檢查路徑", "CHECK PATH");
        var sessionId = Math.Abs(HashCode.Combine(_localPlayer ?? "", _fleetCode ?? "", _logPath ?? "")).ToString("X", CultureInfo.InvariantCulture);
        if (sessionId.Length > 6)
        {
            sessionId = sessionId[..6];
        }

        var statusSteps = new OverlayStartupStatusStep[]
        {
            new(
                localized.StatusSteps[0].Label,
                _isGameProcessRunning
                    ? "StarCitizen.exe"
                    : Localize("等待 StarCitizen.exe", "等待 StarCitizen.exe", "waiting for StarCitizen.exe"),
                Localize("扫描", "掃描", "SCAN"),
                _isGameProcessRunning
                    ? Localize("已找到", "已找到", "FOUND")
                    : Localize("等待中", "等待中", "WAITING")),
            new(
                localized.StatusSteps[1].Label,
                CompactOverlayTransitionText(logLabel, 34),
                Localize("等待", "等待", "WAIT"),
                logExists
                    ? _watcher is null
                        ? Localize("就绪", "就緒", "READY")
                        : Localize("同步", "同步", "SYNC")
                    : Localize("检查", "檢查", "CHECK")),
            new(
                localized.StatusSteps[2].Label,
                CompactOverlayTransitionText(identityLabel, 34),
                Localize("待命", "待命", "STANDBY"),
                !string.IsNullOrWhiteSpace(_localPlayer)
                    ? Localize("已绑定", "已綁定", "BOUND")
                    : IsLoggedIn
                        ? Localize("账号", "帳號", "ACCOUNT")
                        : Localize("访客", "訪客", "GUEST")),
            new(
                localized.StatusSteps[3].Label,
                CompactOverlayTransitionText(hasCollaborativeFleet ? $"{_fleetCode} via {relayHost}" : relayHost, 34),
                Localize("待命", "待命", "STANDBY"),
                hasCollaborativeFleet
                    ? Localize("就绪", "就緒", "READY")
                    : Localize("已旁路", "已旁路", "BYPASS")),
            new(
                localized.StatusSteps[4].Label,
                hudModuleLabel,
                Localize("等待", "等待", "WAIT"),
                hudModuleCount > 0
                    ? Localize("正常", "正常", "OK")
                    : Localize("空", "空", "EMPTY")),
            new(
                localized.StatusSteps[5].Label,
                localized.StatusSteps[5].Value,
                localized.StatusSteps[5].PendingState,
                localized.StatusSteps[5].DoneState),
            new(
                localized.StatusSteps[6].Label,
                CompactOverlayTransitionText(
                    hasCollaborativeFleet
                        ? fleetLabel
                        : Localize("本地浮层界面", "本機浮層介面", "local overlay surface"),
                    34),
                localized.StatusSteps[6].PendingState,
                localized.StatusSteps[6].DoneState)
        };

        var terminalLines = new List<string>
        {
            localized.TerminalLines[0],
            _isGameProcessRunning
                ? Localize("> 已找到游戏窗口：StarCitizen.exe", "> 已找到遊戲視窗：StarCitizen.exe", "> locate active game window: StarCitizen.exe")
                : Localize("> 等待游戏窗口：待命", "> 等待遊戲視窗：待命", "> wait for active game window: standby"),
            logExists
                ? Localize(
                    $"> 读取 {Path.GetFileName(_logPath!)} 通道：{(_watcher is null ? "就绪" : "同步")}",
                    $"> 讀取 {Path.GetFileName(_logPath!)} 通道：{(_watcher is null ? "就緒" : "同步")}",
                    $"> read {Path.GetFileName(_logPath!)} channel: {(_watcher is null ? "ready" : "sync")}")
                : Localize("> 读取 Game.log 通道：检查路径", "> 讀取 Game.log 通道：檢查路徑", "> read Game.log channel: path check"),
            Localize(
                $"> 绑定身份：{CompactOverlayTransitionText(identityLabel, 28)}",
                $"> 綁定身份：{CompactOverlayTransitionText(identityLabel, 28)}",
                $"> bind identity: {CompactOverlayTransitionText(identityLabel, 28)}"),
            hasCollaborativeFleet
                ? Localize(
                    $"> 同步舰队中继：{CompactOverlayTransitionText(_fleetCode, 18)}",
                    $"> 同步艦隊中繼：{CompactOverlayTransitionText(_fleetCode, 18)}",
                    $"> sync fleet relay: {CompactOverlayTransitionText(_fleetCode, 18)}")
                : Localize("> 载入本地指挥界面", "> 載入本機指揮介面", "> load local command surface"),
            localized.TerminalLines[4],
            Localize(
                $"> 校准战术浮层模块：{hudModuleCount}",
                $"> 校準戰術浮層模組：{hudModuleCount}",
                $"> calibrate tactical HUD modules: {hudModuleCount}"),
            localized.TerminalLines[6]
        };

        return new OverlayStartupTransitionContext(
            statusSteps,
            terminalLines,
            HeaderTargetLabel: _isGameProcessRunning
                ? Localize("StarCitizen.exe // 已锁定", "StarCitizen.exe // 已鎖定", "StarCitizen.exe // LOCK")
                : Localize("本地浮层 // 待命", "本機浮層 // 待命", "LOCAL OVERLAY // STANDBY"),
            SurfaceTitle: localized.SurfaceTitle,
            MountingStateLabel: localized.MountingStateLabel,
            CheckingStateLabel: localized.CheckingStateLabel,
            OnlineStateLabel: localized.OnlineStateLabel,
            BootStateLabel: localized.BootStateLabel,
            BottomLeftDiagnostic: Localize(
                $"会话 {sessionId} / {(hasCollaborativeFleet ? "舰队" : "本地")}界面",
                $"工作階段 {sessionId} / {(hasCollaborativeFleet ? "艦隊" : "本機")}介面",
                $"SESSION {sessionId} / {(hasCollaborativeFleet ? "FLEET" : "LOCAL")} SURFACE"),
            BottomRightDiagnostic: Localize(
                $"日志 {logStateLabel} / 鼠标穿透",
                $"日誌 {logStateLabel} / 滑鼠穿透",
                $"LOG {logStateLabel} / INPUT CLICK-THROUGH"),
            CompletionLabel: localized.CompletionLabel,
            CompletionSubLabel: hasCollaborativeFleet
                ? Localize(
                    $"舰桥链路已建立 / {_fleetCode}",
                    $"艦橋鏈路已建立 / {_fleetCode}",
                    $"BRIDGE LINK ESTABLISHED / {_fleetCode}")
                : Localize("本地战术界面已上线", "本機戰術介面已上線", "LOCAL TACTICAL SURFACE ONLINE"));
    }

    private int CountOverlayHudModules(OverlayDisplaySettings settings)
    {
        var count = 0;
        if (settings.ShowNotice)
        {
            count++;
        }

        if (settings.ShowSquads)
        {
            count++;
        }

        if (settings.ShowMembers)
        {
            count++;
        }

        if (settings.ShowEventNotifications)
        {
            count++;
        }

        if (settings.ShowCrosshair)
        {
            count++;
        }

        return count;
    }

    private string BuildOverlayRelayHostLabel()
    {
        var serverText = NetworkServerUrlBox?.Text?.Trim();
        if (string.IsNullOrWhiteSpace(serverText))
        {
            serverText = DefaultRelayUrl;
        }

        if (Uri.TryCreate(serverText, UriKind.Absolute, out var uri) &&
            !string.IsNullOrWhiteSpace(uri.Host))
        {
            return uri.Host;
        }

        return CompactOverlayTransitionText(serverText, 32);
    }

    private static string CompactOverlayTransitionText(string? value, int maxLength)
    {
        var text = string.IsNullOrWhiteSpace(value)
            ? "-"
            : value.ReplaceLineEndings(" ").Trim();
        if (text.Length <= maxLength)
        {
            return text;
        }

        return maxLength <= 1
            ? text[..maxLength]
            : $"{text[..(maxLength - 1)]}…";
    }

    private OverlayDisplaySettings GetEffectiveOverlaySettings()
    {
        var settings = ApplyOverlayFeatureLocks(_overlaySettings);
        if (!settings.AutoThemeByShip)
        {
            return settings;
        }

        var localShip = _players.FirstOrDefault(player =>
            player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase))?.RawShip;
        var shipTheme = GetOverlayThemeForShip(localShip);
        return settings with { Theme = shipTheme };
    }

    private static bool IsOverlaySkinThemeLocked(OverlaySkin skin)
    {
        return OverlaySkinCatalog.Get(skin).LocksTheme;
    }

    private static OverlayDisplaySettings ApplyOverlaySkinLocks(OverlayDisplaySettings settings)
    {
        return OverlaySkinCatalog.ApplyLocks(settings, settings.Skin);
    }

    private OverlayDisplaySettings ApplyOverlayFeatureLocks(OverlayDisplaySettings settings)
    {
        var resolution = OverlaySkinCatalog.Resolve(
            settings,
            IsLoggedIn ? EnumerateActiveOverlayEntitlements() : []);
        if (!resolution.IsAvailable)
        {
            _overlaySkinRequestedWhileLocked = resolution.RequestedSkin;
        }

        settings = resolution.Settings;

        return settings with
        {
            HideMissionWhenIdle = false,
            ShowMission = false
        };
    }

    private void ApplyOverlayEntitlementState()
    {
        if (_overlaySkinRequestedWhileLocked is { } requestedSkin &&
            CanUseOverlaySkin(requestedSkin))
        {
            _overlaySettings = OverlaySkinCatalog.ApplyLocks(
                _overlaySettings with
                {
                    Skin = requestedSkin,
                    RequestedSkin = requestedSkin
                },
                requestedSkin);
            _overlaySkinRequestedWhileLocked = null;
        }

        _overlaySettings = ApplyOverlayFeatureLocks(_overlaySettings);
        if (OverlaySkinBox is null)
        {
            return;
        }

        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            ApplyOverlaySettingsToControls();
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        RenderOverlayEditor();
        RefreshOverlayWindow();
    }

    private void ScheduleTemporaryEntitlementRefresh()
    {
        _temporaryEntitlementTimer.Stop();
        var nextExpiry = _temporaryEntitlements.Values
            .Where(expiresAt => expiresAt > DateTimeOffset.UtcNow)
            .OrderBy(expiresAt => expiresAt)
            .FirstOrDefault();
        if (nextExpiry == default)
        {
            return;
        }

        var delay = nextExpiry - DateTimeOffset.UtcNow;
        _temporaryEntitlementTimer.Interval = delay <= TimeSpan.FromSeconds(1)
            ? TimeSpan.FromSeconds(1)
            : delay;
        _temporaryEntitlementTimer.Start();
    }

    private void TemporaryEntitlementTimer_Tick(object? sender, EventArgs e)
    {
        _temporaryEntitlementTimer.Stop();
        var now = DateTimeOffset.UtcNow;
        foreach (var entitlement in _temporaryEntitlements
                     .Where(pair => pair.Value <= now)
                     .Select(pair => pair.Key)
                     .ToArray())
        {
            _temporaryEntitlements.Remove(entitlement);
        }

        ApplyOverlayEntitlementState();
        RefreshPersonalApplicationSettings();
        ScheduleTemporaryEntitlementRefresh();
    }
}
