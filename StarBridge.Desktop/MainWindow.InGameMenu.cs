using StarBridge.Core.Friends;
using StarBridge.Core.PartyRooms;
using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Windows;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private OverlaySettingsArea _overlaySettingsArea =
        OverlaySettingsArea.Information;
    private readonly InGameMenuSettingsStore _inGameMenuSettingsStore =
        InGameMenuSettingsStore.CreateDefault();
    private InGameMenuSettings _inGameMenuSettings =
        InGameMenuSettings.Default;
    private bool _applyingInGameMenuSettings;
    private OverlayHotkeyBindingState _menuHotkeyBindingState =
        OverlayHotkeyBindingState.Disabled;
    private bool _menuHotkeyListenerReady;
    private string _menuOverlaySettingsActiveSection = "overview";
    private InGameBrowserPreferences _inGameBrowserPreferences =
        InGameBrowserPreferences.Load();
    private bool _applyingInGameBrowserPreferences;
    private FriendUserContract[] _inGameFriendSearchResults = [];
    private bool _inGameFriendSearchActive;
    private bool _inGameFriendSearchLoading;
    private InGameFriendDirectoryState _inGameFriendDirectoryState =
        InGameFriendDirectoryState.Loading;
    private string _inGameFriendCollectionStatus = "正在加载好友";
    private string _inGameFriendSearchStatus = "输入呼号或游戏 ID 查找用户";
    private string _inGameDirectMessageKey = "";
    private string _inGameChannelKey = "";
    private Guid _inGameProfileSurfaceRequestId;

    private bool IsInformationOverlayRunning => _overlayWindow?.IsVisible == true;

    private void BeginInGameWorkspaceAccountSession(
        AccountSessionLease accountSession,
        bool signedIn)
    {
        var status = signedIn
            ? "正在加载组织、好友、消息和房间"
            : "登录后即可查看组织、好友、消息和房间。";
        if (!_inGameMenuCoordinator.BeginAccountSession(
                accountSession,
                status,
                isLoading: signedIn))
        {
            return;
        }

        _inGameFriendSearchResults = [];
        _inGameFriendSearchActive = false;
        _inGameFriendSearchLoading = false;
        _inGameFriendSearchStatus = "输入呼号或游戏 ID 查找用户";
        _inGameFriendDirectoryState = signedIn
            ? InGameFriendDirectoryState.Loading
            : InGameFriendDirectoryState.Unavailable;
        _inGameFriendCollectionStatus = signedIn
            ? "正在加载好友"
            : "登录后即可查看好友和申请。";
        _inGameDirectMessageKey = "";
        _inGameChannelKey = "";
    }

    private void InitializeInGameMenuPreferences()
    {
        _inGameMenuSettings = _inGameMenuSettingsStore.Load(
            DesktopAppConfig.Load().EnableOverlayGlobalHotkey,
            _inGameBrowserPreferences.ProviderKey);
        _applyingInGameMenuSettings = true;
        _applyingInGameBrowserPreferences = true;
        try
        {
            MenuOverlayHotkeyEnabledCheck.IsChecked =
                _inGameMenuSettings.EnableHotkey;
            MenuOverlayHotkeyBox.Text = _inGameMenuSettings.Hotkey;
            MenuOverlayRestoreToolsCheck.IsChecked =
                _inGameMenuSettings.RestoreOpenTools;
            InGameBrowserProviderComboBox.ItemsSource = InGameBrowserPreferences.Providers;
            InGameBrowserProviderComboBox.DisplayMemberPath =
                nameof(InGameBrowserProviderOption.DisplayName);
            InGameBrowserProviderComboBox.SelectedItem =
                InGameBrowserPreferences.Providers.First(provider =>
                    provider.Key == _inGameBrowserPreferences.ProviderKey);
        }
        finally
        {
            _applyingInGameMenuSettings = false;
            _applyingInGameBrowserPreferences = false;
        }

        _inGameMenuCoordinator.SetSettings(_inGameMenuSettings);
        _inGameMenuCoordinator.SetBrowserHomePage(
            InGameBrowserPreferences.ResolveHomePage(
                _inGameMenuSettings.BrowserProviderKey));
        MenuOverlaySettingsEditor.LoadSettings(
            _inGameMenuSettings,
            ResolveOverlayTargetSurfaceBounds(),
            BuildInGameMenuSnapshot(),
            IsInformationOverlayRunning);
        if (_inGameMenuSettings.IsSafeModeSession)
        {
            MenuOverlaySettingsEditor.ShowActionStatus(
                "菜单已使用基础显示效果启动，并暂时关闭动画与窗口恢复。");
        }

        UpdateInGameMenuSettingsPresentation();
    }

    private void QueueInGameMenuPreparation()
    {
        Dispatcher.BeginInvoke(
            System.Windows.Threading.DispatcherPriority.ApplicationIdle,
            new Action(() =>
            {
                if (!IsVisible || _inGameMenuCoordinator.IsOpen)
                {
                    return;
                }

                try
                {
                    _inGameMenuCoordinator.Prepare(
                        BuildInGameMenuSnapshot(),
                        ResolveOverlayTargetSurfaceBounds(),
                        IsInformationOverlayRunning);
                }
                catch (Exception exception)
                {
                    App.WriteCrashLog(exception);
                }
            }));
    }

    private void MenuOverlayHotkeyBox_GotKeyboardFocus(
        object sender,
        System.Windows.Input.KeyboardFocusChangedEventArgs e) =>
        MenuOverlayHotkeyBox.SelectAll();

    private void MenuOverlayHotkeyBox_PreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == System.Windows.Input.Key.System
            ? e.SystemKey
            : e.Key;
        if (!OverlayHotkeyBindingPolicy.TryCapture(
                System.Windows.Input.Keyboard.Modifiers,
                key,
                out var captured))
        {
            return;
        }

        MenuOverlayHotkeyBox.Text = captured.StorageText;
        var candidate = _inGameMenuSettings with
        {
            Hotkey = captured.StorageText
        };
        var validation = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            candidate with { EnableHotkey = true });
        if (validation.MenuState != OverlayHotkeyBindingState.Ready)
        {
            MenuOverlayHotkeyBox.Text = _inGameMenuSettings.Hotkey;
            ShowMenuHotkeyValidation(validation.MenuState);
            return;
        }

        TryApplyInGameMenuSettings(candidate);
    }

    private void MenuOverlayHotkeyEnabledCheck_Changed(
        object sender,
        RoutedEventArgs e)
    {
        if (_applyingInGameMenuSettings || _isLoadingSettings)
        {
            return;
        }

        var candidate = _inGameMenuSettings with
        {
            EnableHotkey = MenuOverlayHotkeyEnabledCheck.IsChecked == true
        };
        if (candidate.EnableHotkey)
        {
            var validation = OverlayHotkeyBindingPolicy.Build(
                OverlayHotkeyBox.Text,
                OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
                candidate);
            if (validation.MenuState != OverlayHotkeyBindingState.Ready)
            {
                _applyingInGameMenuSettings = true;
                MenuOverlayHotkeyEnabledCheck.IsChecked =
                    _inGameMenuSettings.EnableHotkey;
                _applyingInGameMenuSettings = false;
                ShowMenuHotkeyValidation(validation.MenuState);
                return;
            }
        }

        TryApplyInGameMenuSettings(candidate);
    }

    private void MenuOverlayRestoreToolsCheck_Changed(
        object sender,
        RoutedEventArgs e)
    {
        if (_applyingInGameMenuSettings || _isLoadingSettings)
        {
            return;
        }

        TryApplyInGameMenuSettings(_inGameMenuSettings with
        {
            RestoreOpenTools =
                MenuOverlayRestoreToolsCheck.IsChecked == true
        });
    }

    private void ResetMenuOverlayHotkey_Click(
        object sender,
        RoutedEventArgs e) =>
        TryApplyInGameMenuSettings(_inGameMenuSettings with
        {
            Hotkey = InGameMenuSettings.Default.Hotkey
        });

    private bool TryApplyInGameMenuSettings(
        InGameMenuSettings candidate)
    {
        var validation = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            candidate);
        if (candidate.EnableHotkey &&
            validation.MenuState != OverlayHotkeyBindingState.Ready)
        {
            ShowMenuHotkeyValidation(validation.MenuState);
            return false;
        }

        var normalized = candidate.Normalize();
        var previous = _inGameMenuSettings;
        var hotkeyRouteChanged =
            previous.EnableHotkey != normalized.EnableHotkey ||
            normalized.EnableHotkey &&
            !previous.Hotkey.Equals(
                normalized.Hotkey,
                StringComparison.OrdinalIgnoreCase);
        if (hotkeyRouteChanged && !_isLoadingSettings)
        {
            _inGameMenuSettings = normalized;
            RegisterOverlayHotkey();
            var menuRouteReady =
                !normalized.EnableHotkey ||
                _menuHotkeyBindingState ==
                    OverlayHotkeyBindingState.Ready &&
                _menuHotkeyListenerReady;
            if (!menuRouteReady)
            {
                _inGameMenuSettings = previous;
                RegisterOverlayHotkey();
                MenuOverlaySettingsEditor.ShowActionStatus(
                    "新热键未能启用，旧热键仍然有效。请换一个组合后再保存。");
                return false;
            }
        }

        if (!_inGameMenuSettingsStore.TrySave(normalized, out var error))
        {
            if (hotkeyRouteChanged && !_isLoadingSettings)
            {
                _inGameMenuSettings = previous;
                RegisterOverlayHotkey();
            }

            MenuOverlaySettingsEditor.ShowActionStatus(
                error ?? "菜单浮层设置未保存，请重试。");
            return false;
        }

        _inGameMenuSettings = normalized;
        ApplyInGameMenuSettingsToControls(_inGameMenuSettings);
        _inGameMenuCoordinator.SetSettings(_inGameMenuSettings);
        RefreshInGameSocialSnapshot();
        _inGameMenuCoordinator.SetBrowserHomePage(
            InGameBrowserPreferences.ResolveHomePage(
                _inGameMenuSettings.BrowserProviderKey));
        _inGameBrowserPreferences = new InGameBrowserPreferences(
            _inGameMenuSettings.BrowserProviderKey,
            _inGameBrowserPreferences.LastPageUrl);
        try
        {
            _inGameBrowserPreferences.Save();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }

        MenuOverlaySettingsEditor.AcceptSavedSettings(_inGameMenuSettings);
        MenuOverlaySettingsEditor.ShowActionStatus("菜单浮层设置已保存。");
        UpdateInGameMenuSettingsPresentation();
        return true;
    }

    private void ApplyInGameMenuSettingsToControls(
        InGameMenuSettings settings)
    {
        _applyingInGameMenuSettings = true;
        try
        {
            MenuOverlayHotkeyEnabledCheck.IsChecked =
                settings.EnableHotkey;
            MenuOverlayHotkeyBox.Text = settings.Hotkey;
            MenuOverlayRestoreToolsCheck.IsChecked =
                settings.RestoreOpenTools;
        }
        finally
        {
            _applyingInGameMenuSettings = false;
        }
    }

    private void InGameMenuSettingsEditor_DraftChanged(
        object sender,
        EventArgs e)
    {
        var draft = MenuOverlaySettingsEditor.DraftSettings;
        var validation = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            draft);
        var listenerReady =
            !MenuOverlaySettingsEditor.IsDirty &&
            _menuHotkeyListenerReady;
        MenuOverlaySettingsEditor.SetHotkeyStatus(
            validation.MenuState,
            listenerReady);
        RefreshInGameMenuDraftPresentation();
    }

    private void SaveInGameMenuSettings_Click(
        object sender,
        RoutedEventArgs e)
    {
        var candidate = MenuOverlaySettingsEditor.DraftSettings;
        var validation = OverlayHotkeyBindingPolicy.Build(
            OverlayHotkeyBox.Text,
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true,
            candidate);
        if (candidate.EnableHotkey &&
            validation.MenuState != OverlayHotkeyBindingState.Ready)
        {
            MenuOverlaySettingsEditor.SetHotkeyStatus(
                validation.MenuState,
                listenerReady: false);
            MenuOverlaySettingsEditor.ShowActionStatus(
                "请先修正热键，再保存菜单设置。");
            return;
        }

        _ = TryApplyInGameMenuSettings(candidate);
    }

    private void DiscardInGameMenuSettings_Click(
        object sender,
        RoutedEventArgs e)
    {
        MenuOverlaySettingsEditor.DiscardChanges();
        RefreshInGameMenuDraftPresentation();
        UpdateMenuHotkeyRegistrationPresentation(
            _menuHotkeyBindingState,
            _menuHotkeyListenerReady);
    }

    private void RefreshInGameMenuDraftPresentation()
    {
        if (MenuOverlaySettingsEditor is null ||
            OverlayHeaderMenuSaveButton is null ||
            OverlayHeaderMenuDiscardButton is null ||
            OverlayHeaderMenuHintText is null)
        {
            return;
        }

        var dirty = MenuOverlaySettingsEditor.IsDirty;
        OverlayHeaderMenuSaveButton.IsEnabled = dirty;
        OverlayHeaderMenuSaveButton.Opacity = dirty ? 1 : 0.52;
        OverlayHeaderMenuDiscardButton.IsEnabled = dirty;
        OverlayHeaderMenuDiscardButton.Opacity = dirty ? 1 : 0.52;
        OverlayHeaderMenuHintText.Text = dirty
            ? "右侧正在预览未保存的更改"
            : "没有未保存的更改";
    }

    private void InGameBrowserProviderComboBox_SelectionChanged(
        object sender,
        System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_applyingInGameBrowserPreferences ||
            InGameBrowserProviderComboBox.SelectedItem is
                not InGameBrowserProviderOption provider)
        {
            return;
        }

        _inGameBrowserPreferences = new InGameBrowserPreferences(provider.Key);
        try
        {
            _inGameBrowserPreferences.Save();
            _inGameMenuCoordinator.SetBrowserHomePage(provider.HomePage);
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void OpenInGameMenu_Click(object sender, RoutedEventArgs e) =>
        ToggleInGameMenu(requireGameForeground: false);

    private void ShowMenuOverlaySettings_Click(object sender, RoutedEventArgs e) =>
        SetOverlaySettingsWorkspace(OverlaySettingsArea.Menu);

    private void ShowInformationOverlaySettings_Click(object sender, RoutedEventArgs e) =>
        SetOverlaySettingsWorkspace(OverlaySettingsArea.Information);

    private void SetOverlaySettingsWorkspace(OverlaySettingsArea area)
    {
        _overlaySettingsArea = area;
        var informationSelected = area == OverlaySettingsArea.Information;
        OverlayEditorWorkspaceGrid.Visibility = informationSelected
            ? Visibility.Visible
            : Visibility.Collapsed;
        MenuOverlaySettingsWorkspace.Visibility = informationSelected
            ? Visibility.Collapsed
            : Visibility.Visible;
        InformationOverlayHeaderActions.Visibility = informationSelected
            ? Visibility.Visible
            : Visibility.Collapsed;
        MenuOverlayHeaderActions.Visibility = informationSelected
            ? Visibility.Collapsed
            : Visibility.Visible;
        if (!informationSelected)
        {
            MenuOverlaySettingsWorkspace.UpdateLayout();
            RefreshActiveMenuOverlaySettingsSectionFromScroll();
        }

        RefreshOverlayLocalModeNoticeVisibility();
        ApplyOverlaySettingsWorkspacePresentation();
    }

    private void ApplyOverlaySettingsWorkspacePresentation()
    {
        if (OverlayHeaderGameMenuButton is null ||
            OverlayHeaderStartOverlayButton is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var informationSelected =
            _overlaySettingsArea == OverlaySettingsArea.Information;

        OverlayHeaderStartOverlayButton.Tag = informationSelected
            ? "Active"
            : "Inactive";
        OverlayHeaderGameMenuButton.Tag = informationSelected
            ? "Inactive"
            : "Active";
        OverlayInformationModeSelectionText.Visibility = informationSelected
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverlayMenuModeSelectionText.Visibility = informationSelected
            ? Visibility.Collapsed
            : Visibility.Visible;

        OverlaySettingsCurrentAreaText.Text = informationSelected
            ? zh ? "当前设置：信息浮层" : "Editing: information overlay"
            : zh ? "当前设置：菜单浮层" : "Editing: game menu";
        OverlayEditHintText.Text = informationSelected
            ? _isOverlayEditorFullScreen
                ? zh
                    ? "全屏编辑按 1:1 对齐真实浮层位置，可直接拖拽调整。"
                    : "Fullscreen editing aligns to the real overlay at 1:1. Drag modules to adjust them."
                : zh
                    ? "持续显示队伍、事件与准星；布局更改由右侧操作区单独保存。"
                    : "Persistent team, event, and crosshair display. Layout changes are saved from the action area."
            : zh
                ? "打开浏览器、参考图和社交工具；工具窗口会保留到本次应用退出。"
                : "Open browser, guide-image, and social tools. Tool windows remain available for this app session.";

        OverlayInformationModeTitleText.Text = zh
            ? "信息浮层"
            : "Information overlay";
        OverlayInformationModeDescriptionText.Text = zh
            ? "持续显示队伍、事件、通讯与虚拟准星"
            : "Persistent team, event, communication, and crosshair display";
        OverlayInformationModeHotkeyText.Text =
            OverlayHotkeyBindingPolicy.TryParse(
                OverlayHotkeyBox.Text,
                out var informationHotkey)
                ? informationHotkey.DisplayText
                : zh ? "未设置" : "Not set";
        OverlayMenuModeTitleText.Text = zh
            ? "菜单浮层"
            : "Game menu";
        OverlayMenuModeDescriptionText.Text = zh
            ? "打开浏览器、图片、组织、通讯与房间工具"
            : "Open browser, image, fleet, communication, and room tools";
        OverlayInformationModeSelectionText.Text = zh
            ? "正在设置"
            : "Editing";
        OverlayMenuModeSelectionText.Text = zh
            ? "正在设置"
            : "Editing";
        UpdateInGameMenuSettingsPresentation();
        RefreshInGameMenuDraftPresentation();
    }

    private void MenuOverlayNavigationButton_Click(
        object sender,
        RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button)
        {
            return;
        }

        ScrollMenuOverlaySettingsToSection(button.Uid);
    }

    private void MenuOverlaySettingsScrollViewer_ScrollChanged(
        object sender,
        System.Windows.Controls.ScrollChangedEventArgs e) =>
        RefreshActiveMenuOverlaySettingsSectionFromScroll();

    private FrameworkElement? ResolveMenuOverlaySettingsSection(
        string? sectionKey) =>
        NormalizeMenuOverlaySettingsSectionKey(sectionKey) switch
        {
            "hotkey" => MenuOverlaySettingsDocumentHotkey,
            "local" => MenuOverlaySettingsDocumentLocalTools,
            "collaboration" => MenuOverlaySettingsDocumentCollaboration,
            "behavior" => MenuOverlaySettingsDocumentBehavior,
            _ => MenuOverlaySettingsDocumentOverview
        };

    private static string NormalizeMenuOverlaySettingsSectionKey(
        string? sectionKey) =>
        sectionKey?.Trim().ToLowerInvariant() switch
        {
            "hotkey" => "hotkey",
            "local" => "local",
            "collaboration" => "collaboration",
            "behavior" => "behavior",
            _ => "overview"
        };

    private IEnumerable<(string Key, FrameworkElement Section)>
        EnumerateMenuOverlaySettingsSections()
    {
        foreach (var key in new[]
                 {
                     "overview",
                     "hotkey",
                     "local",
                     "collaboration",
                     "behavior"
                 })
        {
            var section = ResolveMenuOverlaySettingsSection(key);
            if (section is not null)
            {
                yield return (key, section);
            }
        }
    }

    private void ScrollMenuOverlaySettingsToSection(string? sectionKey)
    {
        var normalizedKey =
            NormalizeMenuOverlaySettingsSectionKey(sectionKey);
        var target = ResolveMenuOverlaySettingsSection(normalizedKey);
        if (target is null || MenuOverlaySettingsScrollViewer is null)
        {
            return;
        }

        SetActiveMenuOverlaySettingsSection(normalizedKey);
        try
        {
            var position = target
                .TransformToAncestor(MenuOverlaySettingsScrollViewer)
                .Transform(new System.Windows.Point(0, 0));
            var targetOffset = Math.Clamp(
                MenuOverlaySettingsScrollViewer.VerticalOffset +
                position.Y -
                14,
                0,
                MenuOverlaySettingsScrollViewer.ScrollableHeight);
            MenuOverlaySettingsScrollViewer.ScrollToVerticalOffset(
                targetOffset);
        }
        catch
        {
            target.BringIntoView();
        }
    }

    private void RefreshActiveMenuOverlaySettingsSectionFromScroll()
    {
        if (MenuOverlaySettingsScrollViewer is null ||
            MenuOverlaySettingsWorkspace.Visibility != Visibility.Visible)
        {
            return;
        }

        try
        {
            if (MenuOverlaySettingsScrollViewer.ScrollableHeight > 0 &&
                MenuOverlaySettingsScrollViewer.VerticalOffset >=
                MenuOverlaySettingsScrollViewer.ScrollableHeight - 0.5)
            {
                SetActiveMenuOverlaySettingsSection("behavior");
                return;
            }

            const double activationLine = 32;
            string? activeKey = null;
            var closestAbove = double.NegativeInfinity;
            var closestDistance = double.PositiveInfinity;
            foreach (var (key, section) in
                     EnumerateMenuOverlaySettingsSections())
            {
                var y = section
                    .TransformToAncestor(MenuOverlaySettingsScrollViewer)
                    .Transform(new System.Windows.Point(0, 0))
                    .Y;
                if (y <= activationLine && y > closestAbove)
                {
                    closestAbove = y;
                    activeKey = key;
                }

                if (activeKey is null)
                {
                    var distance = Math.Abs(y - activationLine);
                    if (distance < closestDistance)
                    {
                        closestDistance = distance;
                        activeKey = key;
                    }
                }
            }

            SetActiveMenuOverlaySettingsSection(activeKey);
        }
        catch
        {
            SetActiveMenuOverlaySettingsSection(
                _menuOverlaySettingsActiveSection);
        }
    }

    private void SetActiveMenuOverlaySettingsSection(string? sectionKey)
    {
        _menuOverlaySettingsActiveSection =
            NormalizeMenuOverlaySettingsSectionKey(sectionKey);
        MenuOverlayOverviewNavigationButton.Tag = "Inactive";
        MenuOverlayHotkeyNavigationButton.Tag = "Inactive";
        MenuOverlayLocalToolsNavigationButton.Tag = "Inactive";
        MenuOverlayCollaborationNavigationButton.Tag = "Inactive";
        MenuOverlayBehaviorNavigationButton.Tag = "Inactive";
        var activeButton = _menuOverlaySettingsActiveSection switch
        {
            "hotkey" => MenuOverlayHotkeyNavigationButton,
            "local" => MenuOverlayLocalToolsNavigationButton,
            "collaboration" => MenuOverlayCollaborationNavigationButton,
            "behavior" => MenuOverlayBehaviorNavigationButton,
            _ => MenuOverlayOverviewNavigationButton
        };
        activeButton.Tag = "Active";
    }

    private void UpdateInGameMenuSettingsPresentation()
    {
        if (OverlayMenuModeHotkeyText is null ||
            MenuOverlayRailHotkeyText is null ||
            MenuOverlayOverviewHotkeyText is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var hasHotkey = OverlayHotkeyBindingPolicy.TryParse(
            _inGameMenuSettings.Hotkey,
            out var hotkey);
        var display = _inGameMenuSettings.EnableHotkey && hasHotkey
            ? hotkey.DisplayText
            : zh ? "热键已关闭" : "Shortcut off";
        OverlayMenuModeHotkeyText.Text = display;
        MenuOverlayRailHotkeyText.Text = display;
        MenuOverlayOverviewHotkeyText.Text = display;
        _inGameMenuCoordinator.SetInformationOverlayHotkey(
            OverlayGlobalHotkeyEnabledCheck.IsChecked == true &&
            OverlayHotkeyBindingPolicy.TryParse(
                OverlayHotkeyBox.Text,
                out var informationHotkey)
                ? informationHotkey.DisplayText
                : "");

        MenuOverlayCurrentLayoutText.Text = zh
            ? "底部工具栏（固定）"
            : "Bottom tool dock (fixed)";
        OverlayHeaderMenuPreviewButton.Content =
            _inGameMenuCoordinator.IsOpen
                ? zh ? "关闭菜单浮层" : "Close menu overlay"
                : zh ? "打开菜单浮层" : "Open menu overlay";
        UpdateMenuHotkeyRegistrationPresentation(
            _menuHotkeyBindingState,
            _menuHotkeyListenerReady);
        RefreshInGameMenuSettingsPreview();
        RefreshInGameMenuDraftPresentation();
    }

    private void RefreshInGameMenuSettingsPreview()
    {
        if (MenuOverlaySettingsEditor is null)
        {
            return;
        }

        var targetBounds = ResolveOverlayTargetSurfaceBounds();
        var snapshot = BuildInGameMenuSnapshot();
        MenuOverlaySettingsEditor.UpdatePreviewState(
            targetBounds,
            snapshot,
            IsInformationOverlayRunning);

        if (InGameMenuPreviewSurface is not null)
        {
            InGameMenuPreviewSurface.ApplyPreview(
                targetBounds,
                snapshot,
                _inGameMenuSettings,
                IsInformationOverlayRunning);
        }

        if (MenuOverlayPreviewResolutionText is null)
        {
            return;
        }

        var width = Math.Max(1, (int)Math.Round(targetBounds.Width));
        var height = Math.Max(1, (int)Math.Round(targetBounds.Height));
        MenuOverlayPreviewResolutionText.Text =
            _language.Equals("zh", StringComparison.OrdinalIgnoreCase)
                ? $"目标画布 {width} × {height} · 自动匹配当前显示器"
                : $"Target canvas {width} × {height} · Matches the active display";
    }

    private void UpdateMenuHotkeyRegistrationPresentation(
        OverlayHotkeyBindingState state,
        bool listenerReady)
    {
        _menuHotkeyBindingState = state;
        _menuHotkeyListenerReady = listenerReady;
        if (MenuOverlayHotkeyStatusBadge is null ||
            MenuOverlayHotkeyStatusIndicator is null ||
            MenuOverlayHotkeyStatusText is null ||
            MenuOverlayHotkeyRegistrationHintText is null)
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var (statusText, hintText, surfaceKey, statusKey) = state switch
        {
            OverlayHotkeyBindingState.Ready when listenerReady => (
                zh ? "游戏内可用" : "In-game ready",
                zh
                    ? $"{_inGameMenuSettings.Hotkey} 已启用，仅在 Star Citizen 位于前台时打开菜单。"
                    : $"{_inGameMenuSettings.Hotkey} is ready and opens the menu only while Star Citizen is foreground.",
                "StatusSuccessSurfaceBrush",
                "StatusSuccessBrush"),
            OverlayHotkeyBindingState.Ready => (
                zh ? "监听未启动" : "Listener unavailable",
                zh
                    ? "菜单热键已保存，但游戏内监听未启动；请重启应用后重试。"
                    : "The menu shortcut is saved, but in-game listening did not start. Restart the app and retry.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyBindingState.Invalid => (
                zh ? "组合键无效" : "Invalid shortcut",
                zh
                    ? "请按下一个有效组合键。"
                    : "Press a valid shortcut combination.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyBindingState.ModifierRequired => (
                zh ? "需要修饰键" : "Modifier required",
                zh
                    ? "字母和数字键需要搭配 Ctrl、Alt、Shift 或 Win。"
                    : "Letters and numbers need Ctrl, Alt, Shift, or Win.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyBindingState.Reserved => (
                zh ? "系统按键不可用" : "Reserved shortcut",
                zh
                    ? "Esc、Alt+Tab、Alt+F4 等系统组合不能用于打开菜单。"
                    : "System shortcuts such as Esc, Alt+Tab, and Alt+F4 cannot open the menu.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            OverlayHotkeyBindingState.ConflictWithInformation => (
                zh ? "与信息浮层重复" : "Matches information overlay",
                zh
                    ? "菜单热键不能与信息浮层热键相同，请设置其他组合。"
                    : "The menu and information overlay must use different shortcuts.",
                "StatusWarningSurfaceBrush",
                "StatusWarningBrush"),
            _ => (
                zh ? "已关闭" : "Disabled",
                zh
                    ? "仍可从应用设置或菜单预览按钮打开。"
                    : "The menu can still be opened from settings or preview controls.",
                "StatusDisabledSurfaceBrush",
                "StatusDisabledBrush")
        };

        var surface = TryFindResource(surfaceKey) as System.Windows.Media.Brush;
        var statusBrush =
            TryFindResource(statusKey) as System.Windows.Media.Brush;
        MenuOverlayHotkeyStatusBadge.Background =
            surface ?? System.Windows.Media.Brushes.Transparent;
        MenuOverlayHotkeyStatusBadge.BorderBrush =
            statusBrush ?? System.Windows.Media.Brushes.Transparent;
        MenuOverlayHotkeyStatusIndicator.Fill =
            statusBrush ?? System.Windows.Media.Brushes.Transparent;
        MenuOverlayHotkeyStatusText.Foreground =
            statusBrush ?? System.Windows.Media.Brushes.Transparent;
        MenuOverlayHotkeyStatusText.Text = statusText;
        MenuOverlayHotkeyRegistrationHintText.Text = hintText;
        MenuOverlaySettingsEditor.SetHotkeyStatus(state, listenerReady);
    }

    private void ShowMenuHotkeyValidation(
        OverlayHotkeyBindingState validationState)
    {
        var activeState = _menuHotkeyBindingState;
        var activeListenerReady = _menuHotkeyListenerReady;
        UpdateMenuHotkeyRegistrationPresentation(
            validationState,
            listenerReady: false);
        _menuHotkeyBindingState = activeState;
        _menuHotkeyListenerReady = activeListenerReady;
    }

    private void RefreshOverlayLocalModeNoticeVisibility()
    {
        if (OverlayLocalModeNotice is null)
        {
            return;
        }

        OverlayLocalModeNotice.Visibility =
            !IsLoggedIn &&
            _overlaySettingsArea == OverlaySettingsArea.Information
                ? Visibility.Visible
                : Visibility.Collapsed;
    }

    private bool EnsureInGameMenuPreviewOpen()
    {
        if (!_inGameMenuCoordinator.IsOpen)
        {
            ToggleInGameMenu(requireGameForeground: false);
        }

        return _inGameMenuCoordinator.IsOpen;
    }

    private void PreviewMenuBrowser_Click(object sender, RoutedEventArgs e)
    {
        if (EnsureInGameMenuPreviewOpen())
        {
            _inGameMenuCoordinator.OpenBrowser();
        }
    }

    private void PreviewMenuImage_Click(object sender, RoutedEventArgs e)
    {
        if (EnsureInGameMenuPreviewOpen())
        {
            _inGameMenuCoordinator.OpenImage();
        }
    }

    private void PreviewMenuFleet_Click(object sender, RoutedEventArgs e)
    {
        if (EnsureInGameMenuPreviewOpen())
        {
            _inGameMenuCoordinator.OpenFleet();
        }
    }

    private void PreviewMenuFriends_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureInGameMenuPreviewOpen())
        {
            return;
        }

        _inGameMenuCoordinator.OpenFriends();
    }

    private void PreviewMenuChat_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureInGameMenuPreviewOpen())
        {
            return;
        }

        _inGameMenuCoordinator.OpenChat();
    }

    private void PreviewMenuRooms_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureInGameMenuPreviewOpen())
        {
            return;
        }

        _inGameMenuCoordinator.OpenRooms();
    }

    private async void InGameMenuSettingsEditor_ActionRequested(
        object? sender,
        InGameMenuSettingsActionEventArgs e)
    {
        try
        {
            switch (e.Action)
            {
                case InGameMenuSettingsAction.OpenBrowser:
                    if (EnsureInGameMenuPreviewOpen())
                    {
                        _inGameMenuCoordinator.OpenBrowser();
                    }

                    break;
                case InGameMenuSettingsAction.OpenImage:
                    if (EnsureInGameMenuPreviewOpen())
                    {
                        _inGameMenuCoordinator.OpenImage();
                    }

                    break;
                case InGameMenuSettingsAction.OpenScreenshotFolder:
                {
                    var directory =
                        InGameScreenshotPathPolicy.ResolveDirectory(
                            MenuOverlaySettingsEditor
                                .DraftSettings
                                .ScreenshotDirectory);
                    Directory.CreateDirectory(directory);
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = directory,
                        UseShellExecute = true
                    });
                    MenuOverlaySettingsEditor.ShowActionStatus(
                        $"已打开截图文件夹：{directory}");
                    break;
                }
                case InGameMenuSettingsAction.ResetWindowPlacements:
                {
                    var count =
                        _inGameMenuCoordinator.ResetToolWindowPlacements();
                    MenuOverlaySettingsEditor.ShowActionStatus(
                        count > 0
                            ? $"已将 {count} 个工具窗口移回当前显示器。"
                            : "当前没有已创建的工具窗口。");
                    break;
                }
                case InGameMenuSettingsAction.ClearBrowserData:
                {
                    var confirmation = System.Windows.MessageBox.Show(
                        this,
                        "将清除游戏内浏览器的缓存、Cookie、历史记录和网站本地数据。此操作无法撤销，是否继续？",
                        "清除浏览数据",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Warning,
                        MessageBoxResult.No);
                    if (confirmation != MessageBoxResult.Yes)
                    {
                        MenuOverlaySettingsEditor.ShowActionStatus(
                            "已取消清除浏览数据。");
                        break;
                    }

                    var cleared =
                        await _inGameMenuCoordinator.ClearBrowserDataAsync();
                    MenuOverlaySettingsEditor.ShowActionStatus(
                        cleared
                            ? "浏览器缓存、Cookie、历史记录和本地数据已清理。"
                            : "浏览器尚未创建；打开浏览器后可清理数据。");
                    break;
                }
                case InGameMenuSettingsAction.ExportDiagnostics:
                {
                    var path = ExportInGameMenuDiagnostics();
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "explorer.exe",
                        Arguments = $"/select,\"{path}\"",
                        UseShellExecute = true
                    });
                    MenuOverlaySettingsEditor.ShowActionStatus(
                        $"问题记录已保存到：{path}");
                    break;
                }
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            MenuOverlaySettingsEditor.ShowActionStatus(
                UserFacingError.Describe(
                    exception,
                    "操作未完成，请稍后重试。"));
        }
    }

    private string ExportInGameMenuDiagnostics()
    {
        var directory = Path.Combine(
            DesktopAppConfig.ConfigDirectory,
            "Diagnostics");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(
            directory,
            $"menu-overlay-{DateTime.Now:yyyyMMdd-HHmmss}.txt");
        var draft = MenuOverlaySettingsEditor.DraftSettings;
        var snapshot = BuildInGameMenuSnapshot();
        var location = draft.EffectiveShowExactLocation
            ? snapshot.Location
            : "已隐藏";
        var content = new StringBuilder()
            .AppendLine("StarBridge 菜单浮层问题记录")
            .AppendLine($"生成时间：{DateTimeOffset.Now:O}")
            .AppendLine($"菜单状态：{(_inGameMenuCoordinator.IsOpen ? "已打开" : "已关闭")}")
            .AppendLine($"信息浮层：{(IsInformationOverlayRunning ? "已打开" : "已关闭")}")
            .AppendLine($"热键状态：{_menuHotkeyBindingState}")
            .AppendLine($"热键监听：{(_menuHotkeyListenerReady ? "可用" : "不可用")}")
            .AppendLine($"目标画布：{ResolveOverlayTargetSurfaceBounds()}")
            .AppendLine($"当前协作：{snapshot.SceneTitle}")
            .AppendLine($"当前位置：{location}")
            .AppendLine($"服务器：{snapshot.Server}")
            .AppendLine()
            .AppendLine("当前未保存设置")
            .AppendLine(draft.Serialize())
            .ToString();
        File.WriteAllText(path, content, Encoding.UTF8);
        return path;
    }

    private void ToggleInGameMenu(bool requireGameForeground)
    {
        if (_inGameMenuCoordinator.IsOpen)
        {
            _inGameMenuCoordinator.Close(InGameMenuExitMode.RestorePreviousOverlay);
            return;
        }

        if (requireGameForeground && !StarCitizenProcessProbe.IsForeground())
        {
            AppendOutput("GAME MENU | ignored because Star Citizen is not the foreground window.");
            return;
        }

        BeginInGameWorkspaceAccountSession(
            _accountSessionCoordinator.Capture(),
            CanSynchronizeUserData);
        var informationOverlayWasVisible = IsInformationOverlayRunning;
        if (informationOverlayWasVisible)
        {
            _overlayWindow?.SetVisible(false);
        }

        try
        {
            _inGameMenuCoordinator.Open(
                BuildInGameMenuSnapshot(),
                ResolveOverlayTargetSurfaceBounds(),
                informationOverlayWasVisible);
            AppendOutput(requireGameForeground
                ? $"GAME MENU | opened from {_inGameMenuSettings.Hotkey}."
                : "GAME MENU | preview opened from overlay settings.");
        }
        catch
        {
            if (informationOverlayWasVisible)
            {
                _overlayWindow?.SetVisible(true);
            }

            throw;
        }
        finally
        {
            RefreshPersonalIdentityConsole();
            RefreshOverlayOverviewSummary();
        }
    }

    private InGameMenuSnapshot BuildInGameMenuSnapshot()
    {
        var scene = ResolveCurrentOverlayScene();
        var context = scene.Context;
        var local = scene.Players.FirstOrDefault(player => player.IsSelf) ??
                    scene.Players.FirstOrDefault(player =>
                        !string.IsNullOrWhiteSpace(_localPlayer) &&
                        player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        var sceneTitle = context.Kind == OverlaySceneKind.PartyRoom
            ? FirstNonEmpty(context.RoomTitle, "当前房间")
            : context.IsLocalOnly || !_hasFleet
                ? "仅自己可见"
                : FirstNonEmpty(_fleetName, "当前组织");
        var sceneDetail = context.Kind == OverlaySceneKind.PartyRoom
            ? FirstNonEmpty(context.RoomGoal, context.RoomActivity, "已加入房间，等待队友更新信息")
            : context.IsLocalOnly
                ? "你暂未加入组织或房间；当前信息只在本机显示。"
                : _hasFleet
                    ? $"已加入 {FirstNonEmpty(_fleetName, "组织")}，可以查看组织消息。"
                    : "加入组织或房间后，这里会显示队友信息。";
        var memberCount = context.Kind == OverlaySceneKind.PartyRoom && context.RoomMemberCount > 0
            ? context.RoomMemberCount
            : scene.Players.Count;
        var server = IsGameServerRegionCurrent()
            ? string.Join(
                " · ",
                new[] { _gameServerRegion, _gameServerShard }
                    .Where(value => !string.IsNullOrWhiteSpace(value)))
            : "";
        var incomingFriendRequests =
            _friendCenterSnapshot?.IncomingRequests.Length ?? 0;
        var messageUnreadCount =
            Math.Max(0, _fleetChatTotalUnread) +
            Math.Max(0, _partyRoomChatUnreadCount) +
            _friendChatConversations.Sum(conversation =>
                Math.Max(0, conversation.Conversation.UnreadCount));
        var roomAlertCount = _receivedPartyRoomInvitations.Length;
        var menuPresence = local?.SharedPresence ?? GetPartyRoomSharedPresence();
        var menuHasServerSession = menuPresence == PlayerPresenceKind.InGame &&
                                   IsGameServerRegionCurrent();

        return new InGameMenuSnapshot(
            GetPersonalDisplayName(),
            PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language),
            sceneTitle,
            sceneDetail,
            context.DisplayName,
            memberCount,
            ShipDisplayNamePresentation.ResolveChinese(
                PlayerSessionStatePresentation.ResolveShip(
                    menuPresence,
                    menuHasServerSession,
                    NormalizeRuntimeMenuValue(local?.SharedShipText)),
                ShipDisplayNamePresentation.UnknownShip),
            PlayerSessionStatePresentation.ResolveLocation(
                menuPresence,
                menuHasServerSession,
                NormalizeRuntimeMenuValue(local?.SharedLocationCompactDisplayText)),
            PlayerSessionStatePresentation.ResolveServer(
                menuPresence,
                menuHasServerSession,
                server),
            incomingFriendRequests,
            messageUnreadCount,
            roomAlertCount);
    }

    private static string NormalizeRuntimeMenuValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            value.Equals("N/A", StringComparison.OrdinalIgnoreCase))
        {
            return "";
        }

        return value.Trim();
    }

    private void RefreshInGameMenu()
    {
        if (_overlaySettingsArea == OverlaySettingsArea.Menu &&
            MenuOverlaySettingsWorkspace is { Visibility: Visibility.Visible })
        {
            RefreshInGameMenuSettingsPreview();
        }

        if (!_inGameMenuCoordinator.IsOpen)
        {
            return;
        }

        _inGameMenuCoordinator.Refresh(
            BuildInGameMenuSnapshot(),
            ResolveOverlayTargetSurfaceBounds());
        RefreshInGameFleetSnapshot();
    }

    private InGameFleetSnapshot BuildInGameFleetSnapshot()
    {
        if (!IsLoggedIn)
        {
            return InGameFleetSnapshot.Unavailable(
                "登录后即可查看你所在组织的详情与当前信息。");
        }

        if (!_hasFleet)
        {
            return InGameFleetSnapshot.Unavailable(
                "加入组织后，这里会显示组织成员与共享舰船。");
        }
        var localServerShard = IsGameServerRegionCurrent()
            ? _gameServerShard.Trim()
            : "";
        var memberRows = _players
            .Select(player =>
            {
                var presence = player.SharedPresence;
                var isInGame = presence == PlayerPresenceKind.InGame;
                var callsign = FirstNonEmpty(player.Callsign, player.Name);
                var accountId = string.IsNullOrWhiteSpace(player.AccountId)
                    ? null
                    : player.AccountId.Trim();
                var relationship = string.IsNullOrWhiteSpace(accountId)
                    ? FriendRelationshipStates.None
                    : ResolveFriendRelationshipState(accountId);
                var serverRegion = player.IsSelf && IsGameServerRegionCurrent()
                    ? _gameServerRegion
                    : player.ServerRegion;
                bool? hasServerSession = !isInGame
                    ? false
                    : player.IsSelf
                        ? IsGameServerRegionCurrent()
                        : PlayerSessionStatePresentation.HasRecognizedValue(player.ServerShard) ||
                          PlayerSessionStatePresentation.HasRecognizedValue(serverRegion)
                            ? true
                            : false;
                var isSameServer =
                    isInGame &&
                    !string.IsNullOrWhiteSpace(localServerShard) &&
                    (player.IsSelf ||
                     string.Equals(
                         player.ServerShard?.Trim(),
                         localServerShard,
                         StringComparison.OrdinalIgnoreCase));
                return new InGameFleetMemberRow(
                    accountId,
                    callsign,
                    player.Name,
                    player.AvatarPath,
                    FirstNonEmpty(player.Initials, GetInitials(callsign)),
                    presence,
                    FirstNonEmpty(
                        GetFleetRole(player.Name, player.Callsign),
                        player.Role,
                        "组织成员"),
                    IsFleetCommander(player.Name, player.Callsign),
                    PlayerSessionStatePresentation.ResolveShip(
                        presence,
                        hasServerSession,
                        NormalizeRuntimeMenuValue(player.SharedShipText)),
                    PlayerSessionStatePresentation.ResolveLocation(
                        presence,
                        hasServerSession,
                        LocationArrivalPresentation.ResolveCompactLocation(
                            presence,
                            hasServerSession,
                            FormatPartyRoomLocation(player.SharedLocationText),
                            player.ArrivalPendingConfirmation)),
                    PlayerSessionStatePresentation.ResolveServer(
                        presence,
                        hasServerSession,
                        string.IsNullOrWhiteSpace(serverRegion)
                            ? null
                            : FormatPartyRoomServer(serverRegion)),
                    player.IsSelf,
                    player.IsSelf || CanSynchronizeUserData &&
                    !string.IsNullOrWhiteSpace(accountId),
                    !player.IsSelf &&
                    CanSynchronizeUserData &&
                    !string.IsNullOrWhiteSpace(accountId) &&
                    relationship != FriendRelationshipStates.Blocked,
                    isSameServer,
                    player.RoleBrush,
                    hasServerSession);
            })
            .ToArray();

        var shipRows = _fleetShipInventory
            .Select(ship => new InGameFleetShipRow(
                ship.Number,
                ship.ShipName,
                ship.ShipCode,
                ship.ShipImagePath,
                FirstNonEmpty(ship.OwnerDisplay, ship.OwnerCallsign, ship.OwnerGameId, "舰长待同步"),
                ship.ShipSpec,
                ship.ShipRole,
                ship.ShipStatus,
                ship.ShipPrice,
                IsFleetShipOwnerOnline(ship),
                ship.CustomImageMediaId,
                ship.ShipInstanceId,
                ship.OwnerAccountId,
                ship.CanReportCustomImage))
            .ToArray();
        var announcement = _fleetCurrentAnnouncement;
        var status = CanSynchronizeUserData
            ? "组织状态将自动更新"
            : "正在显示最近同步信息，连接恢复后将自动更新";

        return InGameFleetProjection.Build(
            true,
            FirstNonEmpty(_fleetName, "未命名组织"),
            FirstNonEmpty(_fleetCode, "识别码未设置"),
            FormatCommanderName(_callsign, _localPlayer, _fleetChiefCommander),
            FirstNonEmpty(_fleetDescription, "暂无组织简介"),
            _fleetLogoPath,
            FirstNonEmpty(announcement?.Title, _fleetNoticeTitle),
            FirstNonEmpty(announcement?.Content, _fleetNoticeContent),
            memberRows,
            shipRows,
            status,
            CanCurrentUserPublishFleetBroadcasts());
    }

    private void RefreshInGameFleetSnapshot()
    {
        if (!_inGameMenuCoordinator.IsFleetVisible)
        {
            return;
        }

        _inGameMenuCoordinator.ApplyFleetSnapshot(
            BuildInGameFleetSnapshot(),
            _accountSessionCoordinator.Capture());
    }

    private void InGameMenuCoordinator_FleetRefreshRequested(
        object? sender,
        EventArgs e) =>
        RefreshInGameFleetSnapshot();

    private void InGameMenuCoordinator_FleetCommunicationRequested(
        object? sender,
        EventArgs e)
    {
        var channel = _fleetChatChannels.FirstOrDefault(row =>
            row.Type == StarBridge.Core.FleetChat.FleetChatChannelTypes.Fleet);
        if (channel is null)
        {
            _inGameMenuCoordinator.ShowNotice(
                "正在同步组织通讯",
                "频道就绪后会显示在通讯窗口的频道列表中。",
                isLoading: true);
            return;
        }

        InGameMenuCoordinator_SocialChannelRequested(
            this,
            new InGameSocialChannelRequestedEventArgs(
                BuildInGameOrganizationChannelRow(channel)));
    }

    private async void InGameMenuCoordinator_FleetMemberActionRequested(
        object? sender,
        InGameFleetMemberActionRequestedEventArgs e)
    {
        if (e.Action != InGameFleetMemberAction.SendMessage ||
            !e.Member.CanMessage ||
            string.IsNullOrWhiteSpace(e.Member.AccountId))
        {
            return;
        }

        var relationship = ResolveFriendRelationshipState(e.Member.AccountId);
        if (relationship == FriendRelationshipStates.Blocked)
        {
            _inGameMenuCoordinator.ShowNotice(
                "暂时无法发起私信",
                "请先在好友模块中解除屏蔽。");
            return;
        }

        var user = new FriendUserContract(
            e.Member.AccountId,
            e.Member.Callsign,
            e.Member.GameId,
            e.Member.AvatarSource,
            PlayerPresence.ToWireValue(e.Member.Presence),
            relationship,
            DateTimeOffset.UtcNow);
        _inGameMenuCoordinator.OpenChat();
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialSelection,
            $"private:{user.AccountId}");
        await SelectInGameSocialConversationAsync(user, request);
    }

    private void InGameMenuCoordinator_ActionRequested(
        object? sender,
        InGameMenuActionRequestedEventArgs e)
    {
        switch (e.Action)
        {
            case InGameMenuAction.OpenFleet:
                _inGameMenuCoordinator.OpenFleet();
                break;
            case InGameMenuAction.OpenFriends:
                _inGameMenuCoordinator.OpenFriends();
                break;
            case InGameMenuAction.OpenChat:
                _inGameMenuCoordinator.OpenChat();
                break;
            case InGameMenuAction.OpenRooms:
                _inGameMenuCoordinator.OpenRooms();
                break;
            case InGameMenuAction.OpenOverlaySettings:
                _inGameMenuCoordinator.Close(InGameMenuExitMode.NavigateToDesktop);
                ShowMainWindowFromInGameMenu(openOverlaySettings: true);
                break;
            case InGameMenuAction.CaptureFullscreen:
                _ = CaptureInGameMenuScreenAsync();
                break;
            case InGameMenuAction.OpenImage:
                _inGameMenuCoordinator.OpenImage();
                _inGameMenuCoordinator.ShowNotice("图片窗口已打开");
                break;
            case InGameMenuAction.OpenBrowser:
                _inGameMenuCoordinator.OpenBrowser();
                _inGameMenuCoordinator.ShowNotice("浏览器已打开");
                break;
        }
    }

    private async Task CaptureInGameMenuScreenAsync()
    {
        try
        {
            if (_inGameMenuSettings.ScreenshotShowNotification)
            {
                _inGameMenuCoordinator.ShowNotice("正在截屏", isLoading: true);
            }

            var gameHandle = StarCitizenProcessProbe.FindMainWindow();
            Func<Task<string>> capture = () =>
                InGameScreenCapture.CaptureAsync(
                    gameHandle,
                    _inGameMenuSettings);
            var path = _inGameMenuSettings.ScreenshotHideMenu
                ? await _inGameMenuCoordinator.RunWithSessionHiddenAsync(capture)
                : await capture();
            var copied =
                _inGameMenuSettings.ScreenshotCopyToClipboard &&
                await TryCopyScreenshotToClipboardAsync(path);
            if (_inGameMenuSettings.ScreenshotShowNotification)
            {
                _inGameMenuCoordinator.ShowNotice(
                    copied ? "截图已复制到剪贴板" : "截图已保存",
                    $"保存至 {Path.GetFullPath(path)}");
            }

            AppendOutput($"GAME MENU | screenshot saved | path={path}");
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            _inGameMenuCoordinator.ShowNotice(
                UserFacingError.Describe(exception, "截图保存失败，请稍后重试。"));
        }
    }

    private static async Task<bool> TryCopyScreenshotToClipboardAsync(string path)
    {
        var image = ImageDecodeCache.Load(path, 0);
        if (image is null)
        {
            return false;
        }

        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                System.Windows.Clipboard.SetImage(image);
                return true;
            }
            catch (Exception exception)
            {
                if (attempt == 2)
                {
                    App.WriteCrashLog(exception);
                    return false;
                }

                await Task.Delay(80);
            }
        }

        return false;
    }

    private void InGameMenuCoordinator_Closed(
        object? sender,
        InGameMenuClosedEventArgs e)
    {
        if (e.Mode == InGameMenuExitMode.ApplicationClosing)
        {
            return;
        }

        var showInformationOverlay =
            e.Mode == InGameMenuExitMode.SwitchToInformationOverlay ||
            e.InformationOverlayWasVisible &&
            e.Mode is InGameMenuExitMode.RestorePreviousOverlay or InGameMenuExitMode.Deactivated;
        if (showInformationOverlay)
        {
            if (_overlayWindow is null)
            {
                OpenOverlayWindow(GetEffectiveOverlaySettings());
            }
            else
            {
                _overlayWindow.SetVisible(true);
                RefreshOverlayWindow();
            }
        }

        if (e.Mode is InGameMenuExitMode.RestorePreviousOverlay or
            InGameMenuExitMode.SwitchToInformationOverlay)
        {
            _ = TryFocusStarCitizenWindow();
        }

        RefreshPersonalIdentityConsole();
        RefreshOverlayOverviewSummary();
    }

    private async void InGameMenuCoordinator_SocialRefreshRequested(
        object? sender,
        EventArgs e)
    {
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialRefresh);
        RefreshInGameSocialSnapshot(request);
        await RefreshInGameSocialAsync(request);
    }

    private void RefreshInGameRoomSnapshot(InGameWorkspaceRequest? request = null)
    {
        var rooms = _partyLobbyRooms.ToArray();
        var status = !CanSynchronizeUserData
            ? "登录后可以浏览、创建和加入房间。"
            : _currentPartyRoom is null
                ? rooms.Length == 0
                    ? "暂时没有可加入的房间。"
                    : "选择一个房间查看详情，或创建自己的房间。"
                : $"当前房间：{_currentPartyRoom.Title}";
        var chatMatchesCurrentRoom =
            _currentPartyRoom is not null &&
            string.Equals(
                _partyRoomChatRoomId,
                _currentPartyRoom.RoomId,
                StringComparison.OrdinalIgnoreCase);
        var chat = new InGameRoomChatSnapshot(
            chatMatchesCurrentRoom
                ? _partyRoomChatMessages.Cast<object>().ToArray()
                : [],
            CanSynchronizeUserData && _currentPartyRoom is not null,
            _currentPartyRoom is null
                ? "加入房间后即可聊天"
                : chatMatchesCurrentRoom
                    ? PartyRoomChatStatusText.Text
                    : "正在同步房间消息",
            IsLoading: _currentPartyRoom is not null && !chatMatchesCurrentRoom);
        var canInviteFriends =
            CanSynchronizeUserData &&
            _currentPartyRoom is { ViewerIsHost: true };
        var invitations = new InGameRoomInvitationSnapshot(
            canInviteFriends,
            canInviteFriends ? BuildPartyRoomFriendInviteRows() : [],
            canInviteFriends
                ? PartyRoomInvitationStatusText.Text
                : "只有房主可以邀请好友加入房间。");

        var snapshot = new InGameRoomSnapshot(
            CanSynchronizeUserData,
            rooms,
            _currentPartyRoom,
            status,
            chat,
            invitations);
        if (request is null)
        {
            _inGameMenuCoordinator.ApplyRoomSnapshot(
                snapshot,
                _accountSessionCoordinator.Capture());
        }
        else
        {
            _inGameMenuCoordinator.ApplyRoomSnapshot(snapshot, request);
        }
    }

    private async void InGameMenuCoordinator_RoomRefreshRequested(
        object? sender,
        EventArgs e)
    {
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.RoomRefresh);
        RefreshInGameRoomSnapshot(request);
        if (!CanSynchronizeUserData)
        {
            return;
        }

        await RefreshPartyRoomsFromServerAsync(showErrors: false);
        if (_currentPartyRoom is { ViewerIsHost: true })
        {
            await RefreshFriendCenterAsync(showErrors: false);
        }
        if (_currentPartyRoom is not null)
        {
            await RefreshPartyRoomChatAsync(showErrors: false);
        }
        RefreshInGameRoomSnapshot(request);
    }

    private async void InGameMenuCoordinator_RoomInvitationActionRequested(
        object? sender,
        InGameRoomInvitationActionRequestedEventArgs e)
    {
        if (!CanSynchronizeUserData ||
            _currentPartyRoom is not { ViewerIsHost: true })
        {
            _inGameMenuCoordinator.ShowRoomInvitationStatus(
                "只有房主可以邀请好友加入房间。");
            return;
        }

        using var operation = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.RoomMutation,
            $"{e.Invitation.RoomId}:{e.Invitation.AccountId}:{e.Action}",
            InGameWorkspaceRequestPolicy.DropIfRunning);
        if (!operation.Started)
        {
            _inGameMenuCoordinator.ShowRoomInvitationStatus(
                "已有房间操作正在进行，请稍候。",
                isLoading: true);
            return;
        }

        if (e.Action == "invite")
        {
            await CreatePartyRoomInvitationAsync(e.Invitation);
        }
        else if (e.Action == "revoke")
        {
            await RevokePartyRoomInvitationAsync(e.Invitation);
        }
        else
        {
            _inGameMenuCoordinator.ShowRoomInvitationStatus("无法识别这项邀请操作。");
            return;
        }

        if (!operation.IsCurrent)
        {
            return;
        }

        _inGameMenuCoordinator.ShowRoomInvitationStatus(
            PartyRoomInvitationStatusText.Text);
        RefreshInGameRoomSnapshot(operation);
    }

    private async void InGameMenuCoordinator_RoomJoinRequested(
        object? sender,
        InGameRoomJoinRequestedEventArgs e)
    {
        if (!CanSynchronizeUserData)
        {
            _inGameMenuCoordinator.ShowRoomStatus("登录后才能加入房间。");
            return;
        }

        if (_currentPartyRoom is not null)
        {
            _inGameMenuCoordinator.ShowRoomStatus("请先退出当前房间，再加入新的房间。");
            return;
        }

        using var operation = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.RoomMutation,
            e.Room?.RoomId ?? e.RoomCode,
            InGameWorkspaceRequestPolicy.DropIfRunning);
        if (!operation.Started)
        {
            _inGameMenuCoordinator.ShowRoomStatus(
                "已有房间操作正在进行，请稍候。",
                isLoading: true);
            return;
        }

        try
        {
            var target = e.Room;
            if (target is null)
            {
                _inGameMenuCoordinator.ShowRoomStatus("正在查找房间", isLoading: true);
                using var resolveResponse = await _relayClient.PostJsonAsync(
                     "api/party-rooms/resolve-code",
                     new PartyRoomResolveCodeRequest(e.RoomCode.Trim()));
                var resolved = await resolveResponse.Content
                    .ReadFromJsonAsync<PartyRoomMutationResponse>();
                if (!operation.IsCurrent)
                {
                    return;
                }

                if (!resolveResponse.IsSuccessStatusCode || resolved?.Room is null)
                {
                    if (HandleAuthorizationFailure(resolveResponse.StatusCode, "查找房间"))
                    {
                        return;
                    }

                    _inGameMenuCoordinator.ShowRoomStatus(
                        resolved?.Error ?? "没有找到这个房间，房间可能已经解散。");
                    return;
                }

                target = ToPartyLobbyRoomCard(resolved.Room);
            }

            _inGameMenuCoordinator.ShowRoomStatus("正在确认是否可以加入", isLoading: true);
            await PublishCurrentPresenceBeforePartyRoomMutationAsync();
            if (!operation.IsCurrent)
            {
                return;
            }

            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/join",
                new PartyRoomJoinRequest(
                    target.RoomId,
                    e.Password,
                     BuildCurrentPartyRoomMemberState()));
            var mutation = await response.Content
                .ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!operation.IsCurrent)
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "加入房间"))
                {
                    return;
                }

                _inGameMenuCoordinator.ShowRoomStatus(
                    mutation?.Error ?? DescribeResponseFailure(response.StatusCode));
                return;
            }

            if (string.Equals(
                    mutation?.Status,
                    "pending",
                    StringComparison.OrdinalIgnoreCase))
            {
                _inGameMenuCoordinator.ShowRoomStatus(
                    "加入申请已提交，房主批准后会自动进入房间。");
                await RefreshPartyRoomsFromServerAsync(showErrors: false);
                if (operation.IsCurrent)
                {
                    RefreshInGameRoomSnapshot(operation);
                }

                return;
            }

            if (mutation?.Room is null)
            {
                _inGameMenuCoordinator.ShowRoomStatus(
                    "没有收到加入结果，请刷新房间列表后重试。");
                return;
            }

            ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            if (!operation.IsCurrent)
            {
                return;
            }

            RefreshInGameRoomSnapshot(operation);
            RefreshInGameSocialSnapshot(operation);
        }
        catch (TaskCanceledException)
        {
            if (operation.IsCurrent)
            {
                _inGameMenuCoordinator.ShowRoomStatus("等待时间过长，请检查网络后重试。");
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            if (operation.IsCurrent)
            {
                _inGameMenuCoordinator.ShowRoomStatus("暂时无法加入房间，请稍后重试。");
            }
        }
    }

    private async void InGameMenuCoordinator_RoomCreateRequested(
        object? sender,
        InGameRoomCreateRequestedEventArgs e)
    {
        if (!CanSynchronizeUserData)
        {
            _inGameMenuCoordinator.ShowRoomStatus("登录后才能创建房间。");
            return;
        }

        if (_currentPartyRoom is not null)
        {
            _inGameMenuCoordinator.ShowRoomStatus("请先退出当前房间，再创建新的房间。");
            return;
        }

        var draft = e.Draft;
        var callsign = !string.IsNullOrWhiteSpace(_callsign)
            ? _callsign.Trim()
            : GetPersonalDisplayName();
        var gameId = !string.IsNullOrWhiteSpace(_localPlayer)
            ? _localPlayer.Trim()
            : _localPlayerId ?? "";
        var validation = PartyRoomCreation.Create(
            draft,
            new PartyLobbyMemberPreview(
                callsign,
                gameId,
                _avatarPath,
                true,
                _accountId)
            {
                PresenceText = PlayerPresencePresentation.Format(
                    GetPartyRoomSharedPresence(),
                    _language),
                PresenceBrush = GetPartyPresenceBrush(GetPartyRoomSharedPresence())
            },
            DateTimeOffset.UtcNow);
        if (!validation.IsSuccess || validation.Room is null)
        {
            _inGameMenuCoordinator.ShowRoomStatus(
                string.Join(" ", validation.Errors));
            return;
        }

        var localHost = validation.Room.Members[0];
        var localMemberState = BuildCurrentPartyRoomMemberState();
        var createRequest = new PartyRoomCreateRequest(
            draft.Title,
            draft.Goal,
            draft.GameplayTagNodeIds.ToArray(),
            draft.ContextTagIds.ToArray(),
            draft.Capacity,
            draft.IsPublic,
            "everyone",
            draft.AdmissionMode == PartyLobbyAdmissionMode.Direct
                ? "direct"
                : "approval",
            draft.PasswordEnabled,
            draft.Password,
            draft.VoiceRequirement switch
            {
                PartyLobbyVoiceRequirement.Required => "required",
                PartyLobbyVoiceRequirement.Recommended => "recommended",
                _ => "none"
            },
            "zh",
            draft.RecruitmentDurationMinutes,
            draft.AutoDisbandHours,
            localMemberState with { PresenceText = localHost.PresenceText })
        {
            TagCatalogVersion = PartyRoomTagCatalog.Version
        };
        using var operation = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.RoomMutation,
            $"create:{draft.Title}",
            InGameWorkspaceRequestPolicy.DropIfRunning);
        if (!operation.Started)
        {
            _inGameMenuCoordinator.ShowRoomStatus(
                "已有房间操作正在进行，请稍候。",
                isLoading: true);
            return;
        }

        try
        {
            _inGameMenuCoordinator.ShowRoomStatus("正在创建房间", isLoading: true);
            await PublishCurrentPresenceBeforePartyRoomMutationAsync();
            if (!operation.IsCurrent)
            {
                return;
            }

            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms",
                createRequest);
            var mutation = await response.Content
                .ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!operation.IsCurrent)
            {
                return;
            }

            if (response.StatusCode == HttpStatusCode.Conflict &&
                mutation?.Room is not null)
            {
                ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            }
            else if (!response.IsSuccessStatusCode || mutation?.Room is null)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "创建房间"))
                {
                    return;
                }

                _inGameMenuCoordinator.ShowRoomStatus(
                    mutation?.Error ?? DescribeResponseFailure(response.StatusCode));
                return;
            }
            else
            {
                ApplyCurrentPartyRoom(ToPartyLobbyRoomCard(mutation.Room));
            }

            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            if (!operation.IsCurrent)
            {
                return;
            }

            RefreshInGameRoomSnapshot(operation);
            RefreshInGameSocialSnapshot(operation);
            _inGameMenuCoordinator.ShowRoomStatus("房间已创建，你已进入房间。");
        }
        catch (TaskCanceledException)
        {
            if (operation.IsCurrent)
            {
                _inGameMenuCoordinator.ShowRoomStatus("等待时间过长，请检查网络后重试。");
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            if (operation.IsCurrent)
            {
                _inGameMenuCoordinator.ShowRoomStatus("暂时无法创建房间，请稍后重试。");
            }
        }
    }

    private async void InGameMenuCoordinator_RoomLeaveRequested(
        object? sender,
        EventArgs e)
    {
        var room = _currentPartyRoom;
        if (room is null)
        {
            _inGameMenuCoordinator.ShowRoomStatus("当前没有加入房间。");
            return;
        }

        using var operation = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.RoomMutation,
            room.RoomId,
            InGameWorkspaceRequestPolicy.DropIfRunning);
        if (!operation.Started)
        {
            _inGameMenuCoordinator.ShowRoomStatus(
                "已有房间操作正在进行，请稍候。",
                isLoading: true);
            return;
        }

        try
        {
            _inGameMenuCoordinator.ShowRoomStatus("正在退出房间", isLoading: true);
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/leave",
                     new PartyRoomLeaveRequest(room.RoomId));
            var mutation = await response.Content
                .ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!operation.IsCurrent)
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, "退出房间"))
                {
                    return;
                }

                _inGameMenuCoordinator.ShowRoomStatus(
                    mutation?.Error ?? "暂时无法退出房间，请稍后重试。");
                return;
            }

            ClearCurrentPartyRoom();
            await RefreshPartyRoomsFromServerAsync(showErrors: false);
            if (!operation.IsCurrent)
            {
                return;
            }

            RefreshInGameRoomSnapshot(operation);
            RefreshInGameSocialSnapshot(operation);
            _inGameMenuCoordinator.ShowRoomStatus("已退出房间。");
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            if (operation.IsCurrent)
            {
                _inGameMenuCoordinator.ShowRoomStatus("网络连接失败，你仍在当前房间中。请稍后重试。");
            }
        }
    }

    private async void InGameMenuCoordinator_RoomMessageRequested(
        object? sender,
        InGameRoomMessageRequestedEventArgs e)
    {
        var room = _currentPartyRoom;
        if (room is null)
        {
            _inGameMenuCoordinator.ShowRoomStatus("加入房间后即可使用房间聊天。");
            return;
        }

        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialSend,
            $"room:{room.RoomId}");
        await SendPartyRoomChatMessageAsync(e.Text, null);
        if (request.IsCurrent)
        {
            RefreshInGameRoomSnapshot(request);
        }
    }

    private void InGameMenuCoordinator_RoomAttachmentRequested(
        object? sender,
        InGameRoomAttachmentRequestedEventArgs e) =>
        OpenChatAttachmentMenu(new ChatAttachmentDestination(
            e.Anchor,
            ChatAttachmentTarget.PartyRoom));

    private void InGameMenuCoordinator_SocialAttachmentRequested(
        object? sender,
        InGameSocialAttachmentRequestedEventArgs e)
    {
        var selectedKey = e.ChannelKind == InGameChatChannelKind.Private
            ? _inGameDirectMessageKey
            : _inGameChannelKey;
        if (!e.ChannelKey.Equals(selectedKey, StringComparison.OrdinalIgnoreCase))
        {
            RefreshInGameSocialSnapshot();
            return;
        }

        var target = e.ChannelKind switch
        {
            InGameChatChannelKind.Private => ChatAttachmentTarget.DirectMessage,
            InGameChatChannelKind.Room => ChatAttachmentTarget.PartyRoom,
            _ => ChatAttachmentTarget.FleetChannel
        };
        OpenChatAttachmentMenu(new ChatAttachmentDestination(e.Anchor, target));
    }

    private async void InGameMenuCoordinator_ChatAttachmentActionRequested(
        object? sender,
        InGameChatAttachmentActionRequestedEventArgs e)
    {
        try
        {
            await HandleChatAttachmentActionAsync(e.Attachment);
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            _inGameMenuCoordinator.ShowNotice(
                "附件操作失败",
                UserFacingError.Describe(exception, "无法处理这个聊天附件，请稍后重试。"));
        }
    }

    private void InGameMenuCoordinator_FleetBroadcastRequested(object? sender, EventArgs e)
    {
        if (!CanCurrentUserPublishFleetBroadcasts())
        {
            _inGameMenuCoordinator.ShowNotice(
                "无法发送舰队广播",
                "当前身份没有发送广播权限。请联系舰队负责人调整身份权限。");
            return;
        }

        FleetSubTabs.SelectedItem = FleetBroadcastTab;
        RefreshFleetRailHeaders();
        RefreshFleetMainContentView();
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
        FleetBroadcastMessageBox.Focus();
    }

    private async void InGameMenuCoordinator_ProfileRequested(
        object? sender,
        InGameProfileRequestedEventArgs e)
    {
        var target = e.Target;
        var surfaceRequestId = Guid.NewGuid();
        _inGameProfileSurfaceRequestId = surfaceRequestId;
        try
        {
            if (PersonalTab.Content is not UIElement)
            {
                return;
            }

            if (target.IsOwner)
            {
                if (_isPersonalProfileVisitorMode)
                {
                    ExitPersonalProfileVisitorMode(restoreReturnTab: false);
                }

                RefreshPersonalProfileContent();
                MainTabs.SelectedItem = PersonalTab;
                SetActiveNav(PersonalNavButton);
                _inGameMenuCoordinator.AttachProfileSurface(
                    target.Key,
                    PersonalTab,
                    [
                        PersonalProfileRoleSelectorOverlay,
                        PersonalProfileFavoriteShipSelectorOverlay
                    ],
                    released: null);
                return;
            }

            var accountId = target.User?.AccountId ?? target.Key;
            if (string.IsNullOrWhiteSpace(accountId))
            {
                return;
            }

            var visitor = new PlayerRow(
                Name: target.GameId,
                Status: target.PresenceText,
                Ship: "Unknown",
                ShipInfo: "飞船：未知",
                Location: "地点：未知星域",
                Callsign: target.Callsign,
                AvatarPath: target.AvatarSource,
                Initials: target.AvatarFallbackText,
                IsSelf: false,
                ShowMemberActions: false,
                LiveStatus: target.User?.Presence,
                AccountId: accountId);

            var loadTask = OpenPersonalProfileVisitorAsync(visitor);
            if (!_isPersonalProfileVisitorMode)
            {
                await loadTask;
                return;
            }

            var attached = _inGameMenuCoordinator.AttachProfileSurface(
                target.Key,
                PersonalTab,
                [
                    PersonalProfileRoleSelectorOverlay,
                    PersonalProfileFavoriteShipSelectorOverlay
                ],
                () =>
                {
                    if (_isPersonalProfileVisitorMode &&
                        _inGameProfileSurfaceRequestId == surfaceRequestId)
                    {
                        ExitPersonalProfileVisitorMode(restoreReturnTab: true);
                    }
                });
            if (!attached && _isPersonalProfileVisitorMode)
            {
                ExitPersonalProfileVisitorMode(restoreReturnTab: true);
            }

            await loadTask;
        }
        catch (OperationCanceledException)
        {
            // A newer profile request superseded this load.
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            if (_isPersonalProfileVisitorMode)
            {
                ExitPersonalProfileVisitorMode(restoreReturnTab: true);
            }
        }
    }

    private async void InGameMenuCoordinator_ProfileOwnerSaveRequested(
        object? sender,
        InGameProfileOwnerSaveRequestedEventArgs e)
    {
        var callsign = LimitCallsign(e.Draft.Callsign).Trim();
        if (string.IsNullOrWhiteSpace(callsign))
        {
            _inGameMenuCoordinator.SetProfileSaveState(
                e.ProfileKey,
                "呼号不能为空。",
                false,
                false);
            return;
        }

        var introduction = e.Draft.Introduction.Trim();
        if (introduction.Length > PersonalProfileContractPolicy.MaximumIntroductionLength)
        {
            introduction = introduction[..PersonalProfileContractPolicy.MaximumIntroductionLength];
        }

        var candidate = _personalProfileSettings with
        {
            Introduction = introduction,
            ActivityRhythm = e.Draft.ActivityRhythm,
            PresenceIntent = PersonalProfilePresenceIntentCatalog.Normalize(e.Draft.PresenceIntent),
            IsProfilePublic = e.Draft.IsPublic
        };
        var accountIdentity = GetPersonalProfileAccountIdentity();
        _inGameMenuCoordinator.SetProfileSaveState(
            e.ProfileKey,
            "正在保存个人资料",
            true,
            false);
        try
        {
            if (!CanSynchronizeUserData ||
                string.IsNullOrWhiteSpace(accountIdentity) ||
                _personalProfileRepository is null)
            {
                candidate.Save(accountIdentity);
                _personalProfileSettings = candidate;
                _personalProfileSavedSettings = candidate.Copy();
                CommitInGameProfileIdentity(callsign);
                CompleteInGameOwnerProfileSave(
                    e.ProfileKey,
                    "资料已保存到本机。",
                    isWarning: false);
                return;
            }

            var expectedRevision = _personalProfileSyncCoordinator.Snapshot?.Revision ?? 0;
            var result = await SavePersonalProfileRemoteAsync(
                candidate,
                expectedRevision,
                accountIdentity,
                CancellationToken.None);
            switch (result.Status)
            {
                case PersonalProfileSaveStatus.Saved when result.Document is not null:
                    AcceptSavedPersonalProfile(result.Document, accountIdentity, applyToEditor: true);
                    CommitInGameProfileIdentity(callsign);
                    CompleteInGameOwnerProfileSave(
                        e.ProfileKey,
                        "个人资料已保存并同步。",
                        isWarning: false);
                    break;
                case PersonalProfileSaveStatus.QueuedOffline:
                case PersonalProfileSaveStatus.Unauthorized:
                    candidate.Save(accountIdentity);
                    _personalProfileSettings = candidate;
                    _personalProfileSavedSettings = candidate.Copy();
                    CommitInGameProfileIdentity(callsign);
                    CompleteInGameOwnerProfileSave(
                        e.ProfileKey,
                        "资料已保存到本机，恢复连接后会自动同步。",
                        isWarning: true);
                    break;
                case PersonalProfileSaveStatus.Conflict:
                    if (result.Document is not null)
                    {
                        _personalProfileSyncCoordinator.AcceptSaved(result.Document);
                    }

                    _inGameMenuCoordinator.SetProfileSaveState(
                        e.ProfileKey,
                        "资料已在其他设备更新。你的编辑仍保留，请检查后再次保存。",
                        false,
                        false);
                    break;
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            _inGameMenuCoordinator.SetProfileSaveState(
                e.ProfileKey,
                "保存失败，请检查连接后重试。",
                false,
                false);
        }
    }

    private async void InGameMenuCoordinator_ProfileAvatarChangeRequested(
        object? sender,
        InGameProfileAvatarChangeRequestedEventArgs e)
    {
        var croppedPath = ChooseAndCropImage(
            "选择个人头像",
            $"player-avatar-profile-{Guid.NewGuid():N}.png",
            LocalImageStorage.UserAsset);
        if (croppedPath is null)
        {
            return;
        }

        _avatarPath = croppedPath;
        _cachedAvatarImagePath = null;
        _cachedAvatarImageData = null;
        SaveCurrentConfig();
        LoadAvatarPreview();
        RenderState();
        await UpdateProfileAsync(includeAvatarImage: true);
        await PushLocalSnapshotAsync(silent: true);
        var fallback = GetInitials(GetPersonalDisplayName());
        _inGameMenuCoordinator.UpdateProfileAvatar(e.ProfileKey, _avatarPath, fallback);
        RefreshInGameSocialSnapshot();
    }

    private void InGameMenuCoordinator_ProfileScanHangarRequested(
        object? sender,
        InGameProfileScanHangarRequestedEventArgs e) =>
        OpenHangarReaderButton_Click(this, new RoutedEventArgs());

    private async void InGameMenuCoordinator_ProfileVisibilityModeChanged(
        object? sender,
        InGameProfileVisibilityModeChangedEventArgs e)
    {
        await ApplyPresenceVisibilityModeAsync(e.Mode);
        _inGameMenuCoordinator.ApplyProfileSnapshot(
            BuildOwnerInGameProfileSnapshot(e.ProfileKey),
            _accountSessionCoordinator.Capture());
    }

    private InGameProfileSnapshot BuildOwnerInGameProfileSnapshot(string profileKey)
    {
        var target = new InGameProfileTarget(
            profileKey,
            true,
            GetPersonalDisplayName(),
            !string.IsNullOrWhiteSpace(_localPlayer)
                ? _localPlayer.Trim()
                : _localPlayerId ?? "",
            _avatarPath,
            GetInitials(GetPersonalDisplayName()),
            PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language),
            PlayerPresencePresentation.LocalBrush(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode),
            VisibilityMode: _syncPrivacySettings.PresenceVisibilityMode);
        var ships = _ownedShips
            .Select(BuildInGameProfileShipRow)
            .ToArray();
        var favoriteShips = (_personalProfileSettings.FavoriteShipCodes ?? [])
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Select(code => _ownedShips.FirstOrDefault(ship =>
                ship.Code.Equals(code, StringComparison.OrdinalIgnoreCase)))
            .Where(ship => ship is not null)
            .Take(3)
            .Select(ship => BuildInGameProfileShipRow(ship!))
            .ToArray();
        var hangarSummary = FormatInGameProfileHangarComposition(_ownedShips);
        var recentOwnedShip = _ownedShips
            .OrderByDescending(ship => ship.ImportedAt)
            .FirstOrDefault();
        var recentShipBase = recentOwnedShip is null
            ? null
            : BuildInGameProfileShipRow(recentOwnedShip);
        var recentShip = recentShipBase is null
            ? null
            : recentShipBase with
            {
                ImportedText = recentOwnedShip!.ImportedAt == DateTimeOffset.MinValue
                    ? "入库时间待同步"
                    : $"入库 {recentOwnedShip.ImportedAt.ToLocalTime():yyyy-MM-dd}"
            };
        return new InGameProfileSnapshot(
            target,
            false,
            true,
            _personalProfileSettings.Introduction,
            PersonalProfileAvailabilityPresentation.FormatSummary(
                _personalProfileSettings,
                PersonalProfileViewerMode.Owner),
            FormatPersonalProfileAvailabilityTimeZone(_personalProfileSettings.AvailabilityTimeZoneId),
            FormatGameplayStatisticsDuration(
                _gameplayStatisticsRecorder.Snapshot.PlayTimeSeconds),
            _gameplayStatisticsRecorder.Consent.ShareOnProfile
                ? "对访客公开"
                : "仅自己可见",
            _personalProfileSettings.ActivityRhythm,
            _personalProfileSettings.PresenceIntent,
            _personalProfileSettings.IsProfilePublic,
            PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileSettings.SkilledRoles),
            FormatInGameProfileRoles(_personalProfileSettings.SkilledRoles),
            _personalProfileSettings.SupportCapabilities ?? [],
            _personalProfileSettings.ParticipationInterests ?? [],
            _hasFleet ? _fleetName : "",
            _hasFleet ? _fleetCode : "",
            _hasFleet ? GetFleetRole(_localPlayer ?? "", _callsign) : "",
            _hasFleet ? _fleetLogoPath : null,
            ships,
            BuildInGameProfileHangarSegments(_ownedShips),
            _personalProfileSettings.IsProfilePublic
                ? "你的个人资料当前对其他用户公开。"
                : "你的个人资料当前仅自己可见。",
            favoriteShips,
            FormatPersonalProfileHangarTotalValue(_ownedShips),
            FormatInGameProfileHangarCategorySummary(_ownedShips),
            hangarSummary.PrimaryType,
            hangarSummary.Composition,
            hangarSummary.PrimaryShare,
            recentShip);
    }

    private InGameProfileSnapshot BuildVisitorInGameProfileSnapshot(
        InGameProfileTarget target,
        PersonalProfileDocumentContract document)
    {
        var identity = document.Identity;
        var resolvedTarget = target with
        {
            Callsign = string.IsNullOrWhiteSpace(identity.Callsign)
                ? target.Callsign
                : identity.Callsign,
            GameId = string.IsNullOrWhiteSpace(identity.GameId)
                ? target.GameId
                : identity.GameId
        };
        var affiliation = document.FleetAffiliation;
        var hangarShips = document.Hangar?.Ships ?? [];
        var ships = hangarShips
            .Select(BuildInGameProfileShipRow)
            .ToArray();
        var favoriteShips = (document.Content.FavoriteShipCodes ?? [])
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Select(code => hangarShips.FirstOrDefault(ship =>
                ship.Code.Equals(code, StringComparison.OrdinalIgnoreCase)))
            .Where(ship => ship is not null)
            .Take(3)
            .Select(ship => BuildInGameProfileShipRow(ship!))
            .ToArray();
        var visitorOwnedShips = hangarShips
            .Select(ship => new OwnedShipRecord(
                ship.Code,
                ship.DisplayName,
                "PublicProfile",
                ship.ImportedAt,
                ship.ImportedAt,
                ship.SyncedAt,
                CustomImageMediaId: ship.CustomImageMediaId,
                CustomImageCropFocusX: ship.CustomImageCropFocusX,
                CustomImageCropFocusY: ship.CustomImageCropFocusY,
                CustomImageCropZoom: ship.CustomImageCropZoom))
            .ToArray();
        var hangarSummary = FormatInGameProfileHangarComposition(visitorOwnedShips);
        var recentVisitorShip = hangarShips
            .OrderByDescending(ship => ship.ImportedAt)
            .FirstOrDefault();
        var recentShipBase = recentVisitorShip is null
            ? null
            : BuildInGameProfileShipRow(recentVisitorShip);
        var recentShip = recentShipBase is null
            ? null
            : recentShipBase with
            {
                ImportedText = recentVisitorShip!.ImportedAt == DateTimeOffset.MinValue
                    ? "入库时间待同步"
                    : $"入库 {recentVisitorShip.ImportedAt.ToLocalTime():yyyy-MM-dd}"
            };
        var visitorSettings = PersonalProfileContractMapper.ToSettings(
            document,
            PersonalProfileSettings.CreateDefault());
        var gameplayDuration = document.IsGameplayStatisticsPublic &&
                               document.GameplayStatistics is not null
            ? FormatGameplayStatisticsDuration(document.GameplayStatistics.PlayTimeSeconds)
            : "未公开";
        return new InGameProfileSnapshot(
            resolvedTarget,
            false,
            true,
            document.Content.Introduction,
            PersonalProfileAvailabilityPresentation.FormatSummary(
                visitorSettings,
                PersonalProfileViewerMode.Visitor),
            string.IsNullOrWhiteSpace(visitorSettings.AvailabilityTimeZoneId)
                ? "未公开"
                : FormatPersonalProfileAvailabilityTimeZone(visitorSettings.AvailabilityTimeZoneId),
            gameplayDuration,
            document.IsGameplayStatisticsPublic
                ? "对访客公开"
                : "未公开",
            document.Content.ActivityRhythm,
            document.Content.PresenceIntent,
            document.IsPublic,
            PersonalProfileRoleCatalog.NormalizeRoleIds(document.Content.SkilledRoles),
            FormatInGameProfileRoles(document.Content.SkilledRoles),
            document.Content.SupportCapabilities ?? [],
            document.Content.ParticipationInterests ?? [],
            affiliation?.FleetName ?? "",
            affiliation?.FleetCode ?? "",
            affiliation?.PositionTitle ?? "",
            affiliation is not null &&
            affiliation.FleetCode.Equals(_fleetCode, StringComparison.OrdinalIgnoreCase)
                ? _fleetLogoPath
                : null,
            ships,
            BuildInGameProfileHangarSegments(visitorOwnedShips),
            $"公开资料 · 更新于 {document.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm}",
            favoriteShips,
            FormatPersonalProfileHangarTotalValue(visitorOwnedShips),
            FormatInGameProfileHangarCategorySummary(visitorOwnedShips),
            hangarSummary.PrimaryType,
            hangarSummary.Composition,
            hangarSummary.PrimaryShare,
            recentShip);
    }

    private static InGameProfileSnapshot BuildUnavailableInGameProfileSnapshot(
        InGameProfileTarget target,
        string statusText) =>
        new(
            target,
            false,
            false,
            "",
            "",
            "",
            "未公开",
            "未公开",
            "休闲",
            null,
            false,
            [],
            [],
            [],
            [],
            "",
            "",
            "",
            null,
            [],
            [],
            statusText);

    private static string[] FormatInGameProfileRoles(IEnumerable<string>? roles) =>
        (roles ?? [])
        .Select(role => PersonalProfileRoleCatalog.FindRole(role)?.Name ?? role)
        .Where(role => !string.IsNullOrWhiteSpace(role))
        .Distinct(StringComparer.CurrentCultureIgnoreCase)
        .ToArray();

    private InGameProfileShipRow BuildInGameProfileShipRow(OwnedShipRecord ship)
    {
        var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
        return new InGameProfileShipRow(
            catalog?.DisplayName(_language) ?? ship.DisplayName,
            catalog?.EnglishName ?? ship.Code,
            ResolveShipDisplayImagePath(
                ship.CustomImageMediaId,
                ShipCatalog.ResolveImagePath(catalog, ship.Code, ship.DisplayName)),
            catalog?.PriceDisplay ?? "未公布",
            catalog?.RoleDisplay(_language),
            catalog?.Spec);
    }

    private InGameProfileShipRow BuildInGameProfileShipRow(
        PersonalProfileHangarShipContract ship)
    {
        var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
        return new InGameProfileShipRow(
            catalog?.DisplayName(_language) ?? ship.DisplayName,
            catalog?.EnglishName ?? ship.Code,
            ResolveShipDisplayImagePath(
                ship.CustomImageMediaId,
                ShipCatalog.ResolveImagePath(catalog, ship.Code, ship.DisplayName)),
            catalog?.PriceDisplay ?? "未公布",
            catalog?.RoleDisplay(_language),
            catalog?.Spec);
    }

    private InGameProfileHangarSegment[] BuildInGameProfileHangarSegments(
        IReadOnlyCollection<OwnedShipRecord> ships) =>
        FleetShipRoleVisuals
            .Select(item => new InGameProfileHangarSegment(
                item.DisplayName,
                ships.Count(ship => GetOwnedShipRoleCategory(ship) == item.Category),
                item.ColorHex))
            .Where(segment => segment.Count > 0)
            .ToArray();

    private static string FormatInGameProfileHangarCategorySummary(
        IEnumerable<OwnedShipRecord> ships)
    {
        var categoryCount = ships
            .Select(ship => ShipCatalog.Find(ship.Code, ship.DisplayName)?.Role)
            .Where(role => !string.IsNullOrWhiteSpace(role))
            .Distinct(StringComparer.CurrentCultureIgnoreCase)
            .Count();
        return categoryCount == 0 ? "未公开舰船分类" : $"{categoryCount} 类";
    }

    private static (string PrimaryType, string Composition, double PrimaryShare)
        FormatInGameProfileHangarComposition(IEnumerable<OwnedShipRecord> ships)
    {
        var groups = ships
            .Select(ship => ShipCatalog.Find(ship.Code, ship.DisplayName)?.Role)
            .Where(role => !string.IsNullOrWhiteSpace(role))
            .GroupBy(role => role!, StringComparer.CurrentCultureIgnoreCase)
            .Select(group => (
                Name: ShipRoleLocalizer.DisplayName(group.Key),
                Count: group.Count()))
            .OrderByDescending(group => group.Count)
            .ThenBy(group => group.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        if (groups.Length == 0)
        {
            return ("未公开", "暂无舰船构成", 0.5d);
        }

        var total = groups.Sum(group => group.Count);
        return (
            groups[0].Name,
            string.Join(" · ", groups.Take(3).Select(group => $"{group.Name} {group.Count}")),
            (double)groups[0].Count / total);
    }

    private void CommitInGameProfileIdentity(string callsign)
    {
        var changed = !string.Equals(_callsign, callsign, StringComparison.Ordinal);
        _callsign = callsign;
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            CallsignBox.Text = callsign;
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        SaveCurrentConfig();
        RefreshAccountPanel();
        RenderState();
        if (changed)
        {
            StartProfileSyncDebounce();
            _ = PushLocalSnapshotAsync(silent: true);
        }

        _personalProfileSavedCallsign = callsign;
        _personalProfileSavedAvatarPath = _avatarPath;
        _personalProfileDraftAvatarPath = _avatarPath;
    }

    private void CompleteInGameOwnerProfileSave(
        string profileKey,
        string statusText,
        bool isWarning)
    {
        RefreshPersonalProfileContent();
        RefreshInGameSocialSnapshot();
        _inGameMenuCoordinator.ApplyProfileSnapshot(
            BuildOwnerInGameProfileSnapshot(profileKey),
            _accountSessionCoordinator.Capture());
        _inGameMenuCoordinator.SetProfileSaveState(
            profileKey,
            statusText,
            false,
            true);
        RefreshPersonalProfileOnlineTimeEditorState(statusText, isWarning);
    }

    private async void InGameMenuCoordinator_SocialConversationRequested(
        object? sender,
        InGameSocialConversationRequestedEventArgs e)
    {
        _inGameMenuCoordinator.OpenChat();
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialSelection,
            $"private:{e.User.AccountId}");
        await SelectInGameSocialConversationAsync(e.User, request);
    }

    private async void InGameMenuCoordinator_SocialChannelRequested(
        object? sender,
        InGameSocialChannelRequestedEventArgs e)
    {
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialSelection,
            e.Channel.Key);
        if (e.Channel.Kind == InGameChatChannelKind.Private)
        {
            _inGameDirectMessageKey = e.Channel.Key;
        }
        else
        {
            _inGameChannelKey = e.Channel.Key;
        }

        switch (e.Channel.Kind)
        {
            case InGameChatChannelKind.Private when e.Channel.User is not null:
                await SelectInGameSocialConversationAsync(e.Channel.User, request);
                break;
            case InGameChatChannelKind.Fleet:
            {
                var selected = _fleetChatChannels.FirstOrDefault(channel =>
                    channel.ChannelId.Equals(
                        e.Channel.Key,
                        StringComparison.OrdinalIgnoreCase));
                if (selected is null)
                {
                    RefreshInGameSocialSnapshot(request);
                    return;
                }

                if (!request.IsCurrent)
                {
                    return;
                }

                if (_activeFleetChatChannel is null ||
                    !_activeFleetChatChannel.ChannelId.Equals(
                        selected.ChannelId,
                        StringComparison.OrdinalIgnoreCase))
                {
                    _activeFleetChatChannel = selected;
                    _fleetChatLatestSequence = 0;
                    _fleetChatMessages.Clear();
                    ResetFleetChatPagingState();
                    RenderFleetChat();
                }

                await RefreshFleetChatMessagesAsync(showErrors: true);
                if (request.IsCurrent)
                {
                    RefreshInGameSocialSnapshot(request);
                }

                break;
            }
            case InGameChatChannelKind.Room:
                await RefreshPartyRoomChatAsync(showErrors: true);
                if (request.IsCurrent)
                {
                    RefreshInGameSocialSnapshot(request);
                }

                break;
        }
    }

    private async void InGameMenuCoordinator_SocialMessageRequested(
        object? sender,
        InGameSocialMessageRequestedEventArgs e)
    {
        var channelKind = e.ChannelKind;
        var channelKey = e.ChannelKey;
        var selectedKey = channelKind == InGameChatChannelKind.Private
            ? _inGameDirectMessageKey
            : _inGameChannelKey;
        if (!channelKey.Equals(selectedKey, StringComparison.OrdinalIgnoreCase))
        {
            RefreshInGameSocialSnapshot();
            return;
        }

        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.SocialSend,
            channelKey);
        switch (channelKind)
        {
            case InGameChatChannelKind.Fleet:
                await SendFleetChatMessageAsync(e.Text, null);
                break;
            case InGameChatChannelKind.Room:
                await SendPartyRoomChatMessageAsync(e.Text, null);
                break;
            case InGameChatChannelKind.Private:
                await SendFriendChatMessageAsync(e.Text, null);
                break;
            default:
                RefreshInGameSocialSnapshot(request);
                return;
        }

        if (request.IsCurrent)
        {
            RefreshInGameSocialSnapshot(request);
        }
    }

    private async void InGameMenuCoordinator_FriendSearchRequested(
        object? sender,
        InGameSocialFriendSearchRequestedEventArgs e)
    {
        var query = e.Query.Trim();
        using var request = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.FriendSearch,
            query);
        if (query.Length == 0)
        {
            _inGameFriendSearchResults = [];
            _inGameFriendSearchActive = false;
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = "输入呼号或游戏 ID 查找用户";
            RefreshInGameSocialSnapshot(request);
            return;
        }

        if (query.Length < 2)
        {
            _inGameFriendSearchResults = [];
            _inGameFriendSearchActive = true;
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = "请输入至少 2 个字符";
            RefreshInGameSocialSnapshot(request);
            return;
        }

        if (!CanSynchronizeUserData)
        {
            _inGameFriendSearchResults = [];
            _inGameFriendSearchActive = true;
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = "登录后即可查找用户";
            RefreshInGameSocialSnapshot(request);
            return;
        }

        try
        {
            _inGameFriendSearchActive = true;
            _inGameFriendSearchLoading = true;
            _inGameFriendSearchStatus = "正在查找用户";
            RefreshInGameSocialSnapshot(request);
            var includePresence = GetPresenceSharingDecision()
                .CanReceiveRealtime.ToString().ToLowerInvariant();
            var response = await _relayClient.GetFromJsonAsync<FriendSearchResponseContract>(
                $"api/friends/search?q={Uri.EscapeDataString(query)}&includePresence={includePresence}");
            if (!request.IsCurrent)
            {
                return;
            }

            _inGameFriendSearchResults = response?.Results ?? [];
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = _inGameFriendSearchResults.Length == 0
                ? "没有找到匹配用户"
                : $"找到 {_inGameFriendSearchResults.Length} 位用户";
        }
        catch (Exception exception)
        {
            if (!request.IsCurrent)
            {
                return;
            }

            _inGameFriendSearchResults = [];
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = UserFacingError.Describe(
                exception,
                "暂时无法查找用户，请稍后重试。");
            }

        RefreshInGameSocialSnapshot(request);
    }

    private async void InGameMenuCoordinator_FriendActionRequested(
        object? sender,
        InGameSocialFriendActionRequestedEventArgs e)
    {
        if (e.Action == "profile")
        {
            var row = e.Row;
            _inGameMenuCoordinator.OpenProfileWindow(new InGameProfileTarget(
                row.AccountId,
                false,
                string.IsNullOrWhiteSpace(row.Callsign) ? row.GameId : row.Callsign,
                row.GameId,
                row.AvatarSource,
                row.Initials,
                row.PresenceText,
                row.PresenceBrush,
                row.User));
            InGameMenuCoordinator_ProfileRequested(
                this,
                new InGameProfileRequestedEventArgs(new InGameProfileTarget(
                    row.AccountId,
                    false,
                    string.IsNullOrWhiteSpace(row.Callsign) ? row.GameId : row.Callsign,
                    row.GameId,
                    row.AvatarSource,
                    row.Initials,
                    row.PresenceText,
                    row.PresenceBrush,
                    row.User)));
            return;
        }

        if (e.Action == "chat")
        {
            _inGameMenuCoordinator.OpenChat();
            using var selection = _inGameMenuCoordinator.BeginDataRequest(
                _accountSessionCoordinator.Capture(),
                InGameWorkspaceRequestLane.SocialSelection,
                $"private:{e.Row.AccountId}");
            await SelectInGameSocialConversationAsync(e.Row.User, selection);
            return;
        }

        using var operation = _inGameMenuCoordinator.BeginDataRequest(
            _accountSessionCoordinator.Capture(),
            InGameWorkspaceRequestLane.FriendAction,
            $"{e.Action}:{e.Row.AccountId}",
            InGameWorkspaceRequestPolicy.DropIfRunning);
        if (!operation.Started)
        {
            return;
        }

        var succeeded = await MutateFriendRelationshipAsync(e.Row.AccountId, e.Action);
        if (!operation.IsCurrent)
        {
            return;
        }

        if (succeeded)
        {
            _inGameFriendSearchResults = [];
            _inGameFriendSearchActive = false;
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = "输入呼号或游戏 ID 查找用户";
        }
        else
        {
            _inGameFriendSearchActive = true;
            _inGameFriendSearchLoading = false;
            _inGameFriendSearchStatus = FriendCenterStatusText.Text;
        }
        RefreshInGameSocialSnapshot(operation);
    }

    private async void InGameMenuCoordinator_FriendPresenceChanged(
        object? sender,
        InGameFriendPresenceChangedEventArgs e)
    {
        await ApplyPresenceVisibilityModeAsync(e.Mode);
        RefreshInGameSocialSnapshot();
    }

    private async Task RefreshInGameSocialAsync(InGameWorkspaceRequest request)
    {
        if (!request.IsCurrent)
        {
            return;
        }

        if (!CanSynchronizeUserData)
        {
            RefreshInGameSocialSnapshot(request);
            return;
        }

        await RefreshFriendCenterAsync(showErrors: false);
        if (!request.IsCurrent)
        {
            return;
        }

        await RefreshFriendChatAsync(showErrors: false);
        if (!request.IsCurrent)
        {
            return;
        }

        if (CanUseFleetChat)
        {
            await RefreshFleetChatChannelsAsync(showErrors: false);
            if (!request.IsCurrent)
            {
                return;
            }

            await RefreshFleetChatMessagesAsync(showErrors: false);
            if (!request.IsCurrent)
            {
                return;
            }
        }

        if (_currentPartyRoom is not null)
        {
            await RefreshPartyRoomChatAsync(showErrors: false);
            if (!request.IsCurrent)
            {
                return;
            }
        }

        RefreshInGameSocialSnapshot(request);
    }

    private async Task SelectInGameSocialConversationAsync(
        FriendUserContract user,
        InGameWorkspaceRequest request)
    {
        if (!request.IsCurrent)
        {
            return;
        }

        _inGameDirectMessageKey = $"private:{user.AccountId}";
        _activeFriendChatUser = FriendCenterUserResolver.Resolve(user, _networkSnapshots.Values);
        _activeFriendChatOrigin = DirectMessageOrigins.FriendCenter;
        _activeFriendChatConversation = _friendChatConversations
            .FirstOrDefault(row => row.AccountId.Equals(
                user.AccountId,
                StringComparison.OrdinalIgnoreCase))
            ?.Conversation ??
            new FriendChatConversationContract(
                _activeFriendChatUser,
                "",
                default,
                "",
                0,
                0,
                user.RelationshipState == FriendRelationshipStates.Friend
                    ? DirectMessageConversationStates.Friend
                    : DirectMessageConversationStates.None,
                new DirectMessageContextContract(DirectMessageOrigins.FriendCenter));
        _activeFriendChatOrigin = DirectMessageOrigins.Normalize(
            _activeFriendChatConversation.Context?.Origin);
        _friendChatLatestSequence = 0;
        _friendChatMessages.Clear();
        ResetFriendChatPagingState();
        RenderActiveFriendChat();
        EnsureActiveFriendChatConversationRow();
        SelectActiveFriendChatConversation();
        RefreshInGameSocialSnapshot(request);
        await RefreshFriendChatMessagesAsync(showErrors: true);
        if (request.IsCurrent)
        {
            RefreshInGameSocialSnapshot(request);
        }
    }

    private InGameChatChannelRow BuildInGameOrganizationChannelRow(
        FleetChatChannelRow row)
    {
        return new InGameChatChannelRow(
            InGameChatChannelKind.Fleet,
            row.ChannelId,
            row.DisplayName,
            row.PreviewText,
            "组织频道",
            _fleetLogoPath,
            GetInitials(FirstNonEmpty(_fleetName, _fleetCode, row.DisplayName)),
            row.AccentBrush,
            row.Channel.LastMessageAt is { } lastMessageAt
                ? CommunicationTimeFormatter.Format(lastMessageAt)
                : "",
            "组织",
            Visibility.Visible,
            row.UnreadText,
            row.UnreadVisibility);
    }

    private void RefreshInGameSocialSnapshot(InGameWorkspaceRequest? request = null)
    {
        var friends = (_friendCenterSnapshot?.Friends ?? [])
            .Select(entry => new FriendCenterRow(
                ResolveInGameFriendUser(entry.User),
                entry.RelationshipUpdatedAt))
            .ToArray();
        var incomingRequests = (_friendCenterSnapshot?.IncomingRequests ?? [])
            .Select(entry => new FriendCenterRow(
                ResolveInGameFriendUser(entry.User),
                entry.RelationshipUpdatedAt))
            .ToArray();
        var searchResults = _inGameFriendSearchResults
            .Select(user => new FriendCenterRow(
                ResolveInGameFriendUser(user),
                user.LastUpdated))
            .ToArray();

        var directMessages = _friendChatConversations.Select(row =>
            new InGameChatChannelRow(
                InGameChatChannelKind.Private,
                $"private:{row.AccountId}",
                row.Callsign,
                row.Preview,
                row.ContextText,
                _inGameMenuSettings.LoadNetworkAvatars
                    ? row.AvatarSource
                    : null,
                GetInitials(row.Callsign),
                row.PresenceBrush,
                row.UpdatedAtText,
                row.ConversationStateText,
                row.RequestBadgeVisibility,
                row.UnreadText,
                row.UnreadVisibility,
                row.User))
            .ToArray();

        var channels = _fleetChatChannels
            .Select(BuildInGameOrganizationChannelRow)
            .ToList();

        if (_currentPartyRoom is { } room)
        {
            var latestRoomMessage = _partyRoomChatMessages.LastOrDefault();
            channels.Add(new InGameChatChannelRow(
                InGameChatChannelKind.Room,
                $"room:{room.RoomId}",
                room.Title,
                latestRoomMessage?.Text is { Length: > 0 } preview
                    ? preview
                    : "还没有房间消息",
                $"房间聊天 · {room.MemberCount}/{room.Capacity} 人",
                null,
                GetInitials(room.Title),
                new System.Windows.Media.SolidColorBrush(
                    System.Windows.Media.Color.FromRgb(61, 218, 146)),
                latestRoomMessage?.TimeText ?? "",
                "房间",
                Visibility.Visible,
                "",
                Visibility.Collapsed));
        }

        var activeDirectMessage = directMessages.FirstOrDefault(conversation =>
            conversation.Key.Equals(
                _inGameDirectMessageKey,
                StringComparison.OrdinalIgnoreCase));
        var activeChannel = channels.FirstOrDefault(channel =>
            channel.Key.Equals(_inGameChannelKey, StringComparison.OrdinalIgnoreCase));

        object[] directMessageHistory =
            activeDirectMessage?.User is not null &&
            _activeFriendChatUser is not null &&
            activeDirectMessage.User.AccountId.Equals(
                _activeFriendChatUser.AccountId,
                StringComparison.OrdinalIgnoreCase)
                ? _friendChatMessages.Cast<object>().ToArray()
                : [];
        object[] channelHistory = activeChannel?.Kind switch
        {
            InGameChatChannelKind.Fleet
                when _activeFleetChatChannel is not null &&
                     _activeFleetChatChannel.ChannelId.Equals(
                         activeChannel.Key,
                         StringComparison.OrdinalIgnoreCase) =>
                _fleetChatMessages.Cast<object>().ToArray(),
            InGameChatChannelKind.Room
                when _currentPartyRoom is not null &&
                     $"room:{_currentPartyRoom.RoomId}".Equals(
                         activeChannel.Key,
                         StringComparison.OrdinalIgnoreCase) =>
                _partyRoomChatMessages.Cast<object>().ToArray(),
            _ => []
        };
        var canSendDirectMessage =
            CanSynchronizeUserData &&
            activeDirectMessage?.User is not null &&
            _activeFriendChatUser is not null &&
            activeDirectMessage.User.AccountId.Equals(
                _activeFriendChatUser.AccountId,
                StringComparison.OrdinalIgnoreCase) &&
            FriendChatInputBox.IsEnabled &&
            !_isSendingFriendChatMessage;
        var canSendChannel =
            CanSynchronizeUserData &&
            (activeChannel?.Kind switch
            {
                InGameChatChannelKind.Fleet =>
                    _activeFleetChatChannel?.ChannelId.Equals(
                        activeChannel.Key,
                        StringComparison.OrdinalIgnoreCase) == true &&
                    _activeFleetChatChannel.CanSend &&
                    !_isSendingFleetChatMessage,
                InGameChatChannelKind.Room =>
                    _currentPartyRoom is not null &&
                    $"room:{_currentPartyRoom.RoomId}".Equals(
                        activeChannel.Key,
                        StringComparison.OrdinalIgnoreCase),
                _ => false
            });
        var directMessageStatus = !CanSynchronizeUserData
            ? "登录后即可查看好友和消息"
            : activeDirectMessage is null
                ? "选择一位好友开始私聊"
                : FriendChatStatusText.Text;
        var channelStatus = !CanSynchronizeUserData
            ? "登录后即可查看聊天频道"
            : activeChannel?.Kind switch
            {
                InGameChatChannelKind.Fleet =>
                    FleetChatStatusText.Text,
                InGameChatChannelKind.Room => PartyRoomChatStatusText.Text,
                _ => "选择一个频道后即可发送消息"
            };
        var snapshot = new InGameSocialSnapshot(
            CanSynchronizeUserData,
            friends,
            incomingRequests,
            searchResults,
            new InGameConversationPaneSnapshot(
                directMessages,
                directMessageHistory,
                activeDirectMessage,
                activeDirectMessage?.User,
                canSendDirectMessage,
                directMessageStatus),
            new InGameConversationPaneSnapshot(
                channels.ToArray(),
                channelHistory,
                activeChannel,
                null,
                canSendChannel,
                channelStatus),
            _inGameFriendDirectoryState,
            _inGameFriendCollectionStatus,
            _inGameFriendSearchStatus,
            _inGameFriendSearchActive,
            _inGameFriendSearchLoading,
            GetPersonalDisplayName(),
            !string.IsNullOrWhiteSpace(_localPlayer)
                ? _localPlayer.Trim()
                : _localPlayerId ?? "",
            _avatarPath,
            GetInitials(GetPersonalDisplayName()),
            _syncPrivacySettings.PresenceVisibilityMode,
            PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language),
            PlayerPresencePresentation.LocalBrush(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode));
        if (request is null)
        {
            _inGameMenuCoordinator.ApplySocialSnapshot(
                snapshot,
                _accountSessionCoordinator.Capture());
        }
        else
        {
            _inGameMenuCoordinator.ApplySocialSnapshot(snapshot, request);
        }
    }

    private FriendUserContract ResolveInGameFriendUser(
        FriendUserContract user)
    {
        var resolved = FriendCenterUserResolver.Resolve(
            user,
            _networkSnapshots.Values);
        return _inGameMenuSettings.LoadNetworkAvatars
            ? resolved
            : resolved with { AvatarImageData = null };
    }

    private void ShowMainWindowFromInGameMenu(bool openOverlaySettings)
    {
        if (!IsVisible)
        {
            Show();
        }

        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Activate();
        if (openOverlaySettings)
        {
            OverlayNav_Click(this, new RoutedEventArgs());
            SetOverlaySettingsWorkspace(OverlaySettingsArea.Menu);
        }
    }

}
