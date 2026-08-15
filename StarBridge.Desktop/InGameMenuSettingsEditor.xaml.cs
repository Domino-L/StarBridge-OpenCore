using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using WpfBrush = System.Windows.Media.Brush;
using WpfButton = System.Windows.Controls.Button;
using WpfColor = System.Windows.Media.Color;
using WpfComboBox = System.Windows.Controls.ComboBox;
using WpfPoint = System.Windows.Point;
using WpfUserControl = System.Windows.Controls.UserControl;

namespace StarBridge.Desktop;

internal enum InGameMenuSettingsAction
{
    OpenBrowser,
    OpenImage,
    OpenScreenshotFolder,
    ResetWindowPlacements,
    ClearBrowserData,
    ExportDiagnostics
}

internal sealed class InGameMenuSettingsActionEventArgs(
    InGameMenuSettingsAction action) : EventArgs
{
    internal InGameMenuSettingsAction Action { get; } = action;
}

public sealed class InGameMenuToolSettingItem : INotifyPropertyChanged
{
    private bool _isVisible;

    internal InGameMenuToolSettingItem(
        InGameMenuTool tool,
        string displayName,
        bool isVisible,
        bool canHide)
    {
        Tool = tool;
        DisplayName = displayName;
        _isVisible = isVisible;
        CanHide = canHide;
    }

    internal InGameMenuTool Tool { get; }
    public string ToolKey => Tool.ToString();
    public string DisplayName { get; }
    public bool CanHide { get; }

    public bool IsVisible
    {
        get => _isVisible;
        set
        {
            if (_isVisible == value)
            {
                return;
            }

            _isVisible = value;
            PropertyChanged?.Invoke(
                this,
                new PropertyChangedEventArgs(nameof(IsVisible)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

public partial class InGameMenuSettingsEditor : WpfUserControl
{
    private sealed record Choice<T>(string DisplayName, T Value)
    {
        public override string ToString() => DisplayName;
    }

    private enum MenuEditorCompactDrawer
    {
        None,
        Navigation,
        Settings
    }

    private static readonly IReadOnlyDictionary<InGameMenuTool, string>
        ToolDisplayNames = new Dictionary<InGameMenuTool, string>
        {
            [InGameMenuTool.InformationOverlay] = "信息浮层（始终保留）",
            [InGameMenuTool.Fleet] = "组织",
            [InGameMenuTool.Friends] = "好友",
            [InGameMenuTool.Chat] = "通讯",
            [InGameMenuTool.Rooms] = "组队房间",
            [InGameMenuTool.Screenshot] = "全屏截图",
            [InGameMenuTool.Image] = "参考图",
            [InGameMenuTool.Browser] = "浏览器"
        };

    private InGameMenuSettings _savedSettings =
        InGameMenuSettings.Default;
    private InGameMenuSettings _draftSettings =
        InGameMenuSettings.Default;
    private InGameMenuSnapshot? _snapshot;
    private Rect _targetBounds = new(0, 0, 1920, 1080);
    private bool _informationOverlayVisible;
    private bool _applying = true;
    private string _activeSection = "overview";
    private DispatcherTimer? _navigationSmoothScrollTimer;
    private double _navigationSmoothScrollTarget;
    private string? _programmaticNavigationTargetKey;
    private bool _navigationWheelInterruptionAttached;
    private bool _navigationActiveRailInitialized;
    private string _screenshotDirectory = "";
    private bool _isMenuEditorCompact;
    private MenuEditorCompactDrawer _menuEditorCompactDrawer;

    public ObservableCollection<InGameMenuToolSettingItem> ToolItems
    {
        get;
    } = [];

    internal InGameMenuSettings DraftSettings => _draftSettings;
    internal bool IsDirty => _draftSettings != _savedSettings;

    internal event EventHandler? DraftChanged;
    internal event EventHandler<InGameMenuSettingsActionEventArgs>?
        ActionRequested;

    public InGameMenuSettingsEditor()
    {
        InitializeComponent();
        InitializeChoices();
        _applying = false;
    }

    internal void LoadSettings(
        InGameMenuSettings settings,
        Rect targetBounds,
        InGameMenuSnapshot snapshot,
        bool informationOverlayVisible)
    {
        _savedSettings = settings.Normalize();
        _draftSettings = _savedSettings;
        _targetBounds = targetBounds;
        _snapshot = snapshot;
        _informationOverlayVisible = informationOverlayVisible;
        ApplySettingsToControls(_draftSettings);
        RefreshPreview();
        RefreshDirtyPresentation();
    }

    internal void UpdatePreviewState(
        Rect targetBounds,
        InGameMenuSnapshot snapshot,
        bool informationOverlayVisible)
    {
        _targetBounds = targetBounds;
        _snapshot = snapshot;
        _informationOverlayVisible = informationOverlayVisible;
        RefreshPreview();
    }

    internal void AcceptSavedSettings(InGameMenuSettings settings)
    {
        _savedSettings = settings.Normalize();
        _draftSettings = _savedSettings;
        ApplySettingsToControls(_draftSettings);
        RefreshPreview();
        RefreshDirtyPresentation();
    }

    internal void DiscardChanges()
    {
        _draftSettings = _savedSettings;
        ApplySettingsToControls(_draftSettings);
        RefreshPreview();
        RefreshDirtyPresentation();
        DraftChanged?.Invoke(this, EventArgs.Empty);
        ShowActionStatus("已放弃尚未保存的菜单设置。");
    }

    internal void ShowActionStatus(string message) =>
        ActionStatusText.Text = message;

    internal void SetHotkeyStatus(
        OverlayHotkeyBindingState state,
        bool listenerReady)
    {
        var (status, hint, color) = state switch
        {
            OverlayHotkeyBindingState.Ready when listenerReady => (
                "游戏内可用",
                $"{_draftSettings.Hotkey} 仅在 Star Citizen 位于前台时响应。",
                WpfColor.FromRgb(69, 223, 154)),
            OverlayHotkeyBindingState.Ready => (
                "保存后启用",
                "保存后将改用新组合键；如果无法使用，会继续保留原热键。",
                WpfColor.FromRgb(244, 196, 94)),
            OverlayHotkeyBindingState.Invalid => (
                "组合键无效",
                "请按下一个有效组合键。",
                WpfColor.FromRgb(244, 196, 94)),
            OverlayHotkeyBindingState.ModifierRequired => (
                "需要修饰键",
                "字母和数字键需要搭配 Ctrl、Alt、Shift 或 Win。",
                WpfColor.FromRgb(244, 196, 94)),
            OverlayHotkeyBindingState.Reserved => (
                "系统按键不可用",
                "Esc、Alt+Tab、Alt+F4 等系统组合不能用于打开菜单。",
                WpfColor.FromRgb(244, 196, 94)),
            OverlayHotkeyBindingState.ConflictWithInformation => (
                "与信息浮层重复",
                "菜单与信息浮层必须使用不同热键。",
                WpfColor.FromRgb(244, 196, 94)),
            _ => (
                "热键已关闭",
                "仍可从此设置页打开菜单浮层。",
                WpfColor.FromRgb(114, 147, 168))
        };
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        HotkeyStatusBadge.BorderBrush = brush;
        Controls.InGameLoadingPresentation.Apply(HotkeyLoadingIndicator, false);
        HotkeyStatusIndicator.Visibility = Visibility.Visible;
        HotkeyStatusIndicator.Fill = brush;
        HotkeyStatusText.Foreground = brush;
        HotkeyStatusText.Text = status;
        HotkeyStatusHintText.Text = hint;
    }

    private void InitializeChoices()
    {
        SetChoices(
            ToolbarDensityCombo,
            new Choice<InGameMenuToolbarDensity>("紧凑", InGameMenuToolbarDensity.Compact),
            new Choice<InGameMenuToolbarDensity>("标准", InGameMenuToolbarDensity.Standard),
            new Choice<InGameMenuToolbarDensity>("宽松", InGameMenuToolbarDensity.Comfortable));
        SetChoices(
            ToolLabelModeCombo,
            new Choice<InGameMenuToolLabelMode>("自动（空间不足时隐藏）", InGameMenuToolLabelMode.Auto),
            new Choice<InGameMenuToolLabelMode>("始终显示", InGameMenuToolLabelMode.Always),
            new Choice<InGameMenuToolLabelMode>("仅图标", InGameMenuToolLabelMode.IconsOnly));
        SetChoices(
            ClockFormatCombo,
            new Choice<InGameMenuClockFormat>("跟随系统", InGameMenuClockFormat.System),
            new Choice<InGameMenuClockFormat>("24 小时制", InGameMenuClockFormat.TwentyFourHour),
            new Choice<InGameMenuClockFormat>("12 小时制", InGameMenuClockFormat.TwelveHour));
        SetChoices(
            ImageOpenModeCombo,
            new Choice<InGameMenuImageOpenMode>("编辑模式", InGameMenuImageOpenMode.Edit),
            new Choice<InGameMenuImageOpenMode>("纯图片模式", InGameMenuImageOpenMode.ImageOnly));
        SetChoices(
            ImageScaleModeCombo,
            new Choice<InGameMenuImageScaleMode>("适应窗口", InGameMenuImageScaleMode.Fit),
            new Choice<InGameMenuImageScaleMode>("实际大小", InGameMenuImageScaleMode.ActualSize));
        SetChoices(
            ScreenshotFormatCombo,
            new Choice<InGameMenuScreenshotFormat>("PNG（无损）", InGameMenuScreenshotFormat.Png),
            new Choice<InGameMenuScreenshotFormat>("JPEG（较小文件）", InGameMenuScreenshotFormat.Jpeg));
        SetChoices(
            CommunicationLandingCombo,
            new Choice<InGameMenuCommunicationLanding>("上次使用", InGameMenuCommunicationLanding.LastUsed),
            new Choice<InGameMenuCommunicationLanding>("好友私信", InGameMenuCommunicationLanding.DirectMessages),
            new Choice<InGameMenuCommunicationLanding>("频道", InGameMenuCommunicationLanding.Channels));
        SetChoices(
            FriendSortCombo,
            new Choice<InGameMenuFriendSortMode>("在线优先", InGameMenuFriendSortMode.OnlineFirst),
            new Choice<InGameMenuFriendSortMode>("按名称", InGameMenuFriendSortMode.Alphabetical));
        SetChoices(
            InvitationPreviewCombo,
            new Choice<InGameMenuInvitationPreviewMode>("显示邀请内容", InGameMenuInvitationPreviewMode.Full),
            new Choice<InGameMenuInvitationPreviewMode>("仅显示发送者", InGameMenuInvitationPreviewMode.SenderOnly),
            new Choice<InGameMenuInvitationPreviewMode>("隐藏内容", InGameMenuInvitationPreviewMode.Hidden));
        SetChoices(
            CrashRecoveryCombo,
            new Choice<InGameMenuCrashRecoveryMode>("每次询问", InGameMenuCrashRecoveryMode.Ask),
            new Choice<InGameMenuCrashRecoveryMode>("自动恢复", InGameMenuCrashRecoveryMode.Restore),
            new Choice<InGameMenuCrashRecoveryMode>("从空白状态开始", InGameMenuCrashRecoveryMode.StartClean));
        SetChoices(
            InterfaceScaleCombo,
            new Choice<int>("自动匹配屏幕", 0),
            new Choice<int>("85%", 85),
            new Choice<int>("100%", 100),
            new Choice<int>("115%", 115),
            new Choice<int>("125%", 125));
        SetChoices(
            TextScaleCombo,
            new Choice<int>("标准 100%", 100),
            new Choice<int>("较大 110%", 110),
            new Choice<int>("最大 125%", 125));
        SetChoices(
            MotionModeCombo,
            new Choice<InGameMenuMotionMode>("跟随系统", InGameMenuMotionMode.System),
            new Choice<InGameMenuMotionMode>("减少动画", InGameMenuMotionMode.Reduced),
            new Choice<InGameMenuMotionMode>("关闭动画", InGameMenuMotionMode.Off));
        SetChoices(
            PerformanceModeCombo,
            new Choice<InGameMenuPerformanceMode>("自动平衡", InGameMenuPerformanceMode.Auto),
            new Choice<InGameMenuPerformanceMode>("优先流畅", InGameMenuPerformanceMode.Smooth),
            new Choice<InGameMenuPerformanceMode>("节省资源", InGameMenuPerformanceMode.ResourceSaving));
        SetChoices(
            CompatibilityModeCombo,
            new Choice<InGameMenuCompatibilityMode>("自动（推荐）", InGameMenuCompatibilityMode.Auto),
            new Choice<InGameMenuCompatibilityMode>("优先画面效果", InGameMenuCompatibilityMode.Hardware),
            new Choice<InGameMenuCompatibilityMode>("基础显示（画面异常时使用）", InGameMenuCompatibilityMode.Software));

        BrowserProviderCombo.ItemsSource = InGameBrowserPreferences.Providers;
    }

    private static void SetChoices<T>(
        WpfComboBox comboBox,
        params Choice<T>[] choices)
    {
        comboBox.DisplayMemberPath = nameof(Choice<T>.DisplayName);
        comboBox.ItemsSource = choices;
    }

    private void ApplySettingsToControls(InGameMenuSettings settings)
    {
        _applying = true;
        try
        {
            EnableHotkeyCheck.IsChecked = settings.EnableHotkey;
            HotkeyBox.Text = settings.Hotkey;
            CloseWithHotkeyCheck.IsChecked = settings.CloseWithHotkey;
            RailHotkeyText.Text = settings.EnableHotkey
                ? settings.Hotkey.Replace("+", " + ", StringComparison.Ordinal)
                : "热键已关闭";

            ToolItems.Clear();
            foreach (var tool in settings.ResolveToolOrder())
            {
                ToolItems.Add(new InGameMenuToolSettingItem(
                    tool,
                    ToolDisplayNames[tool],
                    settings.IsToolVisible(tool),
                    tool != InGameMenuTool.InformationOverlay));
            }

            SelectChoice(ToolbarDensityCombo, settings.ToolbarDensity);
            SelectChoice(ToolLabelModeCombo, settings.ToolLabelMode);
            ShowUnreadBadgesCheck.IsChecked = settings.ShowUnreadBadges;
            ShowContextBarCheck.IsChecked = settings.ShowContextBar;
            ShowSceneCheck.IsChecked = settings.ShowScene;
            ShowMemberCountCheck.IsChecked = settings.ShowMemberCount;
            ShowShipCheck.IsChecked = settings.ShowShip;
            ShowLocationCheck.IsChecked = settings.ShowLocation;
            ShowServerCheck.IsChecked = settings.ShowServer;
            ShowClockCheck.IsChecked = settings.ShowClock;
            ShowDateCheck.IsChecked = settings.ShowDate;
            ShowPresenceCheck.IsChecked = settings.ShowPresence;
            SelectChoice(ClockFormatCombo, settings.ClockFormat);

            BrowserProviderCombo.SelectedValue = settings.BrowserProviderKey;
            BrowserRestorePageCheck.IsChecked = settings.BrowserRestorePreviousPage;
            BrowserNewTabCheck.IsChecked = settings.BrowserOpenLinksInNewTab;
            BrowserPauseHiddenCheck.IsChecked = settings.BrowserPauseWhenHidden;
            BrowserTabLimitSlider.Value = settings.BrowserTabLimit;

            SelectChoice(ImageOpenModeCombo, settings.ImageOpenMode);
            SelectChoice(ImageScaleModeCombo, settings.ImageScaleMode);
            ImageOpacitySlider.Value = settings.ImageDefaultOpacity;
            RememberImageAdjustmentsCheck.IsChecked = settings.RememberImageAdjustments;
            ImageDefaultPinnedCheck.IsChecked = settings.ImageDefaultPinned;
            PauseAnimatedImagesCheck.IsChecked = settings.PauseHiddenAnimatedImages;

            _screenshotDirectory = settings.ScreenshotDirectory;
            RefreshScreenshotDirectoryPresentation();
            SelectChoice(ScreenshotFormatCombo, settings.ScreenshotFormat);
            ScreenshotQualitySlider.Value = settings.ScreenshotJpegQuality;
            ScreenshotClipboardCheck.IsChecked = settings.ScreenshotCopyToClipboard;
            ScreenshotHideMenuCheck.IsChecked = settings.ScreenshotHideMenu;
            ScreenshotNotificationCheck.IsChecked = settings.ScreenshotShowNotification;

            SelectChoice(CommunicationLandingCombo, settings.CommunicationLanding);
            SelectChoice(FriendSortCombo, settings.FriendSortMode);
            SocialNotificationsCheck.IsChecked = settings.ShowSocialNotifications;
            SocialSoundCheck.IsChecked = settings.SocialNotificationSound;
            SelectChoice(InvitationPreviewCombo, settings.InvitationPreviewMode);
            LoadNetworkAvatarsCheck.IsChecked = settings.LoadNetworkAvatars;

            RestoreOpenToolsCheck.IsChecked = settings.RestoreOpenTools;
            RestoreLastFocusedToolCheck.IsChecked = settings.RestoreLastFocusedTool;
            RememberWindowPlacementCheck.IsChecked = settings.RememberWindowPlacement;
            FitToolsToDisplayCheck.IsChecked = settings.FitToolsToGameDisplay;
            SnapToolWindowsCheck.IsChecked = settings.SnapToolWindows;
            SnapDistanceSlider.Value = settings.SnapDistance;
            RestoreAcrossRestartsCheck.IsChecked = settings.RestoreToolsAcrossRestarts;
            SelectChoice(CrashRecoveryCombo, settings.CrashRecoveryMode);

            SelectChoice(InterfaceScaleCombo, settings.InterfaceScalePercent);
            SelectChoice(TextScaleCombo, settings.TextScalePercent);
            BackgroundDimSlider.Value = settings.BackgroundDimPercent;
            SelectChoice(MotionModeCombo, settings.MotionMode);
            HighContrastCheck.IsChecked = settings.HighContrast;
            ToolTipDelaySlider.Value = settings.ToolTipDelayMilliseconds;
            SelectChoice(PerformanceModeCombo, settings.PerformanceMode);
            PauseUpdatesWhileDraggingCheck.IsChecked = settings.PauseUpdatesWhileDragging;
            AutoReduceEffectsCheck.IsChecked = settings.AutoReduceEffects;
            SelectChoice(CompatibilityModeCombo, settings.CompatibilityMode);

            StreamerPrivacyCheck.IsChecked = settings.StreamerPrivacyMode;
            ShowExactLocationCheck.IsChecked = settings.ShowExactLocation;
            ShowRoomCodeCheck.IsChecked = settings.ShowRoomCode;
            ConfirmExternalLinksCheck.IsChecked = settings.ConfirmExternalLinks;
            SafeModeNextLaunchCheck.IsChecked = settings.SafeModeNextLaunch;
            RefreshValueLabels();
            RefreshDependencies();
        }
        finally
        {
            _applying = false;
        }
    }

    private static void SelectChoice<T>(WpfComboBox comboBox, T value)
    {
        comboBox.SelectedItem = comboBox.Items
            .OfType<Choice<T>>()
            .FirstOrDefault(choice =>
                EqualityComparer<T>.Default.Equals(choice.Value, value));
    }

    private static T ChoiceValue<T>(WpfComboBox comboBox, T fallback) =>
        comboBox.SelectedItem is Choice<T> choice
            ? choice.Value
            : fallback;

    private InGameMenuSettings ReadSettingsFromControls()
    {
        var current = _draftSettings;
        var toolOrder = string.Join(
            ',',
            ToolItems.Select(item => item.Tool.ToString()));
        return (current with
        {
            Hotkey = HotkeyBox.Text,
            EnableHotkey = EnableHotkeyCheck.IsChecked == true,
            CloseWithHotkey = CloseWithHotkeyCheck.IsChecked == true,
            ShowFleetTool = ToolIsVisible(InGameMenuTool.Fleet),
            ShowFriendsTool = ToolIsVisible(InGameMenuTool.Friends),
            ShowChatTool = ToolIsVisible(InGameMenuTool.Chat),
            ShowRoomsTool = ToolIsVisible(InGameMenuTool.Rooms),
            ShowScreenshotTool = ToolIsVisible(InGameMenuTool.Screenshot),
            ShowImageTool = ToolIsVisible(InGameMenuTool.Image),
            ShowBrowserTool = ToolIsVisible(InGameMenuTool.Browser),
            ToolOrder = toolOrder,
            ToolbarDensity = ChoiceValue(ToolbarDensityCombo, current.ToolbarDensity),
            ToolLabelMode = ChoiceValue(ToolLabelModeCombo, current.ToolLabelMode),
            ShowUnreadBadges = ShowUnreadBadgesCheck.IsChecked == true,
            ShowContextBar = ShowContextBarCheck.IsChecked == true,
            ShowScene = ShowSceneCheck.IsChecked == true,
            ShowMemberCount = ShowMemberCountCheck.IsChecked == true,
            ShowShip = ShowShipCheck.IsChecked == true,
            ShowLocation = ShowLocationCheck.IsChecked == true,
            ShowServer = ShowServerCheck.IsChecked == true,
            ShowClock = ShowClockCheck.IsChecked == true,
            ShowDate = ShowDateCheck.IsChecked == true,
            ShowPresence = ShowPresenceCheck.IsChecked == true,
            ClockFormat = ChoiceValue(ClockFormatCombo, current.ClockFormat),
            BrowserProviderKey =
                BrowserProviderCombo.SelectedValue as string ??
                current.BrowserProviderKey,
            BrowserRestorePreviousPage = BrowserRestorePageCheck.IsChecked == true,
            BrowserOpenLinksInNewTab = BrowserNewTabCheck.IsChecked == true,
            BrowserPauseWhenHidden = BrowserPauseHiddenCheck.IsChecked == true,
            BrowserTabLimit = (int)Math.Round(BrowserTabLimitSlider.Value),
            ImageOpenMode = ChoiceValue(ImageOpenModeCombo, current.ImageOpenMode),
            ImageScaleMode = ChoiceValue(ImageScaleModeCombo, current.ImageScaleMode),
            ImageDefaultOpacity = (int)Math.Round(ImageOpacitySlider.Value),
            RememberImageAdjustments = RememberImageAdjustmentsCheck.IsChecked == true,
            ImageDefaultPinned = ImageDefaultPinnedCheck.IsChecked == true,
            ImageWindowLimit = 1,
            PauseHiddenAnimatedImages = PauseAnimatedImagesCheck.IsChecked == true,
            ScreenshotDirectory = _screenshotDirectory,
            ScreenshotFormat = ChoiceValue(ScreenshotFormatCombo, current.ScreenshotFormat),
            ScreenshotJpegQuality = (int)Math.Round(ScreenshotQualitySlider.Value),
            ScreenshotCopyToClipboard = ScreenshotClipboardCheck.IsChecked == true,
            ScreenshotHideMenu = ScreenshotHideMenuCheck.IsChecked == true,
            ScreenshotShowNotification = ScreenshotNotificationCheck.IsChecked == true,
            CommunicationLanding =
                ChoiceValue(CommunicationLandingCombo, current.CommunicationLanding),
            FriendSortMode = ChoiceValue(FriendSortCombo, current.FriendSortMode),
            ShowSocialNotifications = SocialNotificationsCheck.IsChecked == true,
            SocialNotificationSound = SocialSoundCheck.IsChecked == true,
            InvitationPreviewMode =
                ChoiceValue(InvitationPreviewCombo, current.InvitationPreviewMode),
            LoadNetworkAvatars = LoadNetworkAvatarsCheck.IsChecked == true,
            RestoreOpenTools = RestoreOpenToolsCheck.IsChecked == true,
            RestoreLastFocusedTool = RestoreLastFocusedToolCheck.IsChecked == true,
            RememberWindowPlacement = RememberWindowPlacementCheck.IsChecked == true,
            FitToolsToGameDisplay = FitToolsToDisplayCheck.IsChecked == true,
            SnapToolWindows = SnapToolWindowsCheck.IsChecked == true,
            SnapDistance = (int)Math.Round(SnapDistanceSlider.Value),
            RestoreToolsAcrossRestarts = RestoreAcrossRestartsCheck.IsChecked == true,
            CrashRecoveryMode = ChoiceValue(CrashRecoveryCombo, current.CrashRecoveryMode),
            InterfaceScalePercent = ChoiceValue(
                InterfaceScaleCombo,
                current.InterfaceScalePercent),
            TextScalePercent = ChoiceValue(TextScaleCombo, current.TextScalePercent),
            BackgroundDimPercent = (int)Math.Round(BackgroundDimSlider.Value),
            MotionMode = ChoiceValue(MotionModeCombo, current.MotionMode),
            HighContrast = HighContrastCheck.IsChecked == true,
            ToolTipDelayMilliseconds = (int)Math.Round(ToolTipDelaySlider.Value),
            PerformanceMode = ChoiceValue(PerformanceModeCombo, current.PerformanceMode),
            PauseUpdatesWhileDragging =
                PauseUpdatesWhileDraggingCheck.IsChecked == true,
            AutoReduceEffects = AutoReduceEffectsCheck.IsChecked == true,
            CompatibilityMode =
                ChoiceValue(CompatibilityModeCombo, current.CompatibilityMode),
            StreamerPrivacyMode = StreamerPrivacyCheck.IsChecked == true,
            ShowExactLocation = ShowExactLocationCheck.IsChecked == true,
            ShowRoomCode = ShowRoomCodeCheck.IsChecked == true,
            ConfirmExternalLinks = ConfirmExternalLinksCheck.IsChecked == true,
            SafeModeNextLaunch = SafeModeNextLaunchCheck.IsChecked == true
        }).Normalize();
    }

    private bool ToolIsVisible(InGameMenuTool tool) =>
        ToolItems.FirstOrDefault(item => item.Tool == tool)?.IsVisible ??
        tool == InGameMenuTool.InformationOverlay;

    private void SettingsControl_Changed(object sender, RoutedEventArgs e) =>
        ApplyDraftFromControls();

    private void SettingsTextBox_Changed(
        object sender,
        TextChangedEventArgs e) =>
        ApplyDraftFromControls();

    private void SelectScreenshotDirectory_Click(
        object sender,
        RoutedEventArgs e)
    {
        var preferredDirectory = string.IsNullOrWhiteSpace(_screenshotDirectory)
            ? InGameScreenshotPathPolicy.ResolveDirectory()
            : _screenshotDirectory;
        var initialDirectory = Directory.Exists(preferredDirectory)
            ? preferredDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        var dialog = new OpenFolderDialog
        {
            Title = "选择截图保存文件夹",
            Multiselect = false,
            InitialDirectory = initialDirectory
        };
        var owner = Window.GetWindow(this);
        var accepted = owner is null
            ? dialog.ShowDialog()
            : dialog.ShowDialog(owner);
        if (accepted != true)
        {
            return;
        }

        _screenshotDirectory = dialog.FolderName;
        RefreshScreenshotDirectoryPresentation();
        ApplyDraftFromControls();
    }

    private void UseDefaultScreenshotDirectory_Click(
        object sender,
        RoutedEventArgs e)
    {
        _screenshotDirectory = "";
        RefreshScreenshotDirectoryPresentation();
        ApplyDraftFromControls();
    }

    private void RefreshScreenshotDirectoryPresentation()
    {
        var usesDefault = string.IsNullOrWhiteSpace(_screenshotDirectory);
        ScreenshotDirectoryText.Text = usesDefault
            ? InGameScreenshotPathPolicy.ResolveDirectory()
            : _screenshotDirectory;
        ScreenshotDirectoryText.ToolTip = ScreenshotDirectoryText.Text;
        ScreenshotDirectoryModeText.Text = usesDefault
            ? "当前使用系统图片文件夹中的 StarBridge\\Screenshots。"
            : "当前使用自定义保存位置。";
    }

    private void ToolVisibility_Changed(object sender, RoutedEventArgs e) =>
        ApplyDraftFromControls();

    private void ApplyDraftFromControls()
    {
        if (_applying)
        {
            return;
        }

        _draftSettings = ReadSettingsFromControls();
        RefreshValueLabels();
        RefreshDependencies();
        RefreshPreview();
        RefreshDirtyPresentation();
        DraftChanged?.Invoke(this, EventArgs.Empty);
    }

    private void RefreshDependencies()
    {
        HotkeyBox.IsEnabled = EnableHotkeyCheck.IsChecked == true;
        CloseWithHotkeyCheck.IsEnabled = EnableHotkeyCheck.IsChecked == true;
        ContextFieldPanel.IsEnabled = ShowContextBarCheck.IsChecked == true;
        ShowDateCheck.IsEnabled = ShowClockCheck.IsChecked == true;
        ClockFormatCombo.IsEnabled = ShowClockCheck.IsChecked == true;
        ScreenshotQualitySlider.IsEnabled =
            ChoiceValue(
                ScreenshotFormatCombo,
                InGameMenuScreenshotFormat.Png) ==
            InGameMenuScreenshotFormat.Jpeg;
        SocialSoundCheck.IsEnabled =
            SocialNotificationsCheck.IsChecked == true;
        ShowExactLocationCheck.IsEnabled =
            StreamerPrivacyCheck.IsChecked != true;
        ShowRoomCodeCheck.IsEnabled =
            StreamerPrivacyCheck.IsChecked != true;
        RestoreLastFocusedToolCheck.IsEnabled =
            RestoreOpenToolsCheck.IsChecked == true ||
            RestoreAcrossRestartsCheck.IsChecked == true;
        FitToolsToDisplayCheck.IsEnabled =
            RememberWindowPlacementCheck.IsChecked == true;
        SnapToolWindowsCheck.IsEnabled =
            RememberWindowPlacementCheck.IsChecked == true;
        SnapDistanceSlider.IsEnabled =
            RememberWindowPlacementCheck.IsChecked == true &&
            SnapToolWindowsCheck.IsChecked == true;
        CrashRecoveryCombo.IsEnabled =
            RestoreAcrossRestartsCheck.IsChecked == true;
    }

    private void RefreshValueLabels()
    {
        BrowserTabLimitText.Text =
            $"标签页上限：{(int)Math.Round(BrowserTabLimitSlider.Value)}";
        ImageOpacityText.Text =
            $"默认透明度：{(int)Math.Round(ImageOpacitySlider.Value)}%";
        ScreenshotQualityText.Text =
            $"JPEG 质量：{(int)Math.Round(ScreenshotQualitySlider.Value)}%";
        SnapDistanceText.Text =
            $"吸附距离：{(int)Math.Round(SnapDistanceSlider.Value)} 像素";
        BackgroundDimText.Text =
            $"游戏背景压暗：{(int)Math.Round(BackgroundDimSlider.Value)}%";
        ToolTipDelayText.Text =
            $"按钮提示延迟：{(int)Math.Round(ToolTipDelaySlider.Value)} 毫秒";
        RailHotkeyText.Text = EnableHotkeyCheck.IsChecked == true
            ? HotkeyBox.Text.Replace("+", " + ", StringComparison.Ordinal)
            : "热键已关闭";
    }

    private void RefreshDirtyPresentation()
    {
        if (IsDirty)
        {
            OverviewDirtyText.Text = "有未保存的更改";
            OverviewDirtyText.Foreground =
                (WpfBrush)FindResource("StatusWarningBrush");
        }
        else
        {
            OverviewDirtyText.Text = "没有未保存的更改";
            OverviewDirtyText.Foreground =
                (WpfBrush)FindResource("StatusSuccessBrush");
        }
    }

    private void RefreshPreview()
    {
        if (_snapshot is null)
        {
            return;
        }

        PreviewSurface.ApplyPreview(
            _targetBounds,
            _snapshot,
            _draftSettings,
            _informationOverlayVisible);
        var width = Math.Max(1, (int)Math.Round(_targetBounds.Width));
        var height = Math.Max(1, (int)Math.Round(_targetBounds.Height));
        PreviewResolutionText.Text =
            $"目标画布 {width} × {height} · 自动匹配当前游戏显示器";
    }

    private void HotkeyBox_GotKeyboardFocus(
        object sender,
        KeyboardFocusChangedEventArgs e) =>
        HotkeyBox.SelectAll();

    private void HotkeyBox_PreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
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

        HotkeyBox.Text = captured.StorageText;
        ApplyDraftFromControls();
    }

    private void ResetHotkey_Click(object sender, RoutedEventArgs e)
    {
        HotkeyBox.Text = InGameMenuSettings.Default.Hotkey;
        ApplyDraftFromControls();
    }

    private void MoveToolUp_Click(object sender, RoutedEventArgs e) =>
        MoveTool(sender, -1);

    private void MoveToolDown_Click(object sender, RoutedEventArgs e) =>
        MoveTool(sender, 1);

    private void MoveTool(object sender, int delta)
    {
        if (sender is not WpfButton { Tag: string toolKey } ||
            !Enum.TryParse<InGameMenuTool>(
                toolKey,
                ignoreCase: true,
                out var tool))
        {
            return;
        }

        var index = ToolItems
            .Select((item, position) => (item, position))
            .FirstOrDefault(entry => entry.item.Tool == tool)
            .position;
        var target = index + delta;
        if (index < 0 || target < 0 || target >= ToolItems.Count)
        {
            return;
        }

        ToolItems.Move(index, target);
        ApplyDraftFromControls();
    }

    private void ActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton { Tag: string actionName } ||
            !Enum.TryParse<InGameMenuSettingsAction>(
                actionName,
                ignoreCase: true,
                out var action))
        {
            return;
        }

        ActionRequested?.Invoke(
            this,
            new InGameMenuSettingsActionEventArgs(action));
    }

    private void MenuEditorWorkspaceGrid_SizeChanged(
        object sender,
        SizeChangedEventArgs e) => ApplyMenuEditorResponsiveState();

    private void MenuEditorCompactNavigationButton_Click(
        object sender,
        RoutedEventArgs e) => SetMenuEditorCompactDrawer(
            _menuEditorCompactDrawer == MenuEditorCompactDrawer.Navigation
                ? MenuEditorCompactDrawer.None
                : MenuEditorCompactDrawer.Navigation);

    private void MenuEditorCompactSettingsButton_Click(
        object sender,
        RoutedEventArgs e) => SetMenuEditorCompactDrawer(
            _menuEditorCompactDrawer == MenuEditorCompactDrawer.Settings
                ? MenuEditorCompactDrawer.None
                : MenuEditorCompactDrawer.Settings);

    private void SetMenuEditorCompactDrawer(MenuEditorCompactDrawer drawer)
    {
        _menuEditorCompactDrawer = _isMenuEditorCompact
            ? drawer
            : MenuEditorCompactDrawer.None;
        ApplyMenuEditorResponsiveState();
    }

    private void ApplyMenuEditorResponsiveState()
    {
        if (MenuEditorWorkspaceGrid is null ||
            MenuEditorNavigationPanel is null ||
            MenuEditorSettingsPanel is null ||
            MenuEditorPreviewPanel is null ||
            MenuEditorNavigationColumn is null ||
            MenuEditorNavigationGapColumn is null ||
            MenuEditorSettingsColumn is null ||
            MenuEditorSettingsGapColumn is null ||
            MenuEditorPreviewColumn is null)
        {
            return;
        }

        var layout = MenuOverlaySettingsResponsiveLayout.Resolve(
            MenuEditorWorkspaceGrid.ActualWidth);
        _isMenuEditorCompact = layout.UsesCompactDrawers;

        if (_isMenuEditorCompact)
        {
            MenuEditorNavigationColumn.Width = new GridLength(0);
            MenuEditorNavigationGapColumn.Width = new GridLength(0);
            MenuEditorSettingsColumn.Width = new GridLength(0);
            MenuEditorSettingsGapColumn.Width = new GridLength(0);
            MenuEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);

            Grid.SetColumn(MenuEditorPreviewPanel, 0);
            Grid.SetColumnSpan(MenuEditorPreviewPanel, 5);
            ConfigureMenuEditorDrawer(
                MenuEditorNavigationPanel,
                Math.Min(300, Math.Max(280, MenuEditorWorkspaceGrid.ActualWidth - 12)));
            ConfigureMenuEditorDrawer(
                MenuEditorSettingsPanel,
                Math.Min(
                    MenuOverlaySettingsResponsiveLayout.SettingsWidth,
                    Math.Max(320, MenuEditorWorkspaceGrid.ActualWidth - 12)));
            MenuEditorNavigationPanel.Visibility =
                _menuEditorCompactDrawer == MenuEditorCompactDrawer.Navigation
                    ? Visibility.Visible
                    : Visibility.Collapsed;
            MenuEditorSettingsPanel.Visibility =
                _menuEditorCompactDrawer == MenuEditorCompactDrawer.Settings
                    ? Visibility.Visible
                    : Visibility.Collapsed;
        }
        else
        {
            _menuEditorCompactDrawer = MenuEditorCompactDrawer.None;
            MenuEditorNavigationColumn.Width = new GridLength(layout.NavigationColumnWidth);
            MenuEditorNavigationGapColumn.Width = new GridLength(
                MenuOverlaySettingsResponsiveLayout.InterColumnGap);
            MenuEditorSettingsColumn.Width = new GridLength(layout.SettingsColumnWidth);
            MenuEditorSettingsGapColumn.Width = new GridLength(
                MenuOverlaySettingsResponsiveLayout.InterColumnGap);
            MenuEditorPreviewColumn.Width = new GridLength(1, GridUnitType.Star);

            RestoreMenuEditorRail(MenuEditorNavigationPanel, 0);
            RestoreMenuEditorRail(MenuEditorSettingsPanel, 2);
            MenuEditorNavigationPanel.Visibility = Visibility.Visible;
            MenuEditorSettingsPanel.Visibility = Visibility.Visible;
            Grid.SetColumn(MenuEditorPreviewPanel, 4);
            Grid.SetColumnSpan(MenuEditorPreviewPanel, 1);
            System.Windows.Controls.Panel.SetZIndex(MenuEditorPreviewPanel, 0);
        }

        MenuEditorCompactNavigationButton.Visibility = _isMenuEditorCompact
            ? Visibility.Visible
            : Visibility.Collapsed;
        MenuEditorCompactSettingsButton.Visibility = _isMenuEditorCompact
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private static void ConfigureMenuEditorDrawer(
        FrameworkElement panel,
        double width)
    {
        Grid.SetColumn(panel, 0);
        Grid.SetColumnSpan(panel, 5);
        panel.Width = width;
        panel.HorizontalAlignment = System.Windows.HorizontalAlignment.Left;
        panel.Margin = new Thickness(0, 0, 10, 0);
        System.Windows.Controls.Panel.SetZIndex(panel, 40);
    }

    private static void RestoreMenuEditorRail(
        FrameworkElement panel,
        int column)
    {
        Grid.SetColumn(panel, column);
        Grid.SetColumnSpan(panel, 1);
        panel.Width = double.NaN;
        panel.HorizontalAlignment = System.Windows.HorizontalAlignment.Stretch;
        panel.Margin = new Thickness(0);
        System.Windows.Controls.Panel.SetZIndex(panel, 0);
    }

    private void NavigationButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is WpfButton button)
        {
            if (_isMenuEditorCompact)
            {
                SetMenuEditorCompactDrawer(MenuEditorCompactDrawer.Settings);
                Dispatcher.BeginInvoke(
                    () => ScrollToSection(button.Uid),
                    DispatcherPriority.Loaded);
            }
            else
            {
                ScrollToSection(button.Uid);
            }
        }
    }

    private void SettingsScrollViewer_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not ScrollViewer viewer)
        {
            return;
        }

        if (!_navigationWheelInterruptionAttached)
        {
            viewer.AddHandler(
                Mouse.PreviewMouseWheelEvent,
                new MouseWheelEventHandler(
                    SettingsScrollViewer_PreviewMouseWheel),
                handledEventsToo: true);
            _navigationWheelInterruptionAttached = true;
        }
    }

    private void Editor_IsVisibleChanged(
        object sender,
        DependencyPropertyChangedEventArgs e)
    {
        if (!IsVisible)
        {
            _navigationSmoothScrollTimer?.Stop();
            _programmaticNavigationTargetKey = null;
            if (SettingsNavigationActiveRail is not null)
            {
                SettingsNavigationActiveRail.Opacity = 0;
            }

            return;
        }

        Dispatcher.BeginInvoke(
            () =>
            {
                ApplyMenuEditorResponsiveState();
                SetActiveSection(_activeSection);
            },
            DispatcherPriority.Loaded);
    }

    private void SettingsNavigationContentGrid_SizeChanged(
        object sender,
        SizeChangedEventArgs e)
    {
        if (!IsVisible || e.NewSize.Height <= 0)
        {
            return;
        }

        SetActiveSection(_activeSection);
    }

    private void SettingsScrollViewer_PreviewMouseWheel(
        object sender,
        MouseWheelEventArgs e)
    {
        CancelProgrammaticNavigationScroll();
    }

    private void CancelProgrammaticNavigationScroll()
    {
        if (_navigationSmoothScrollTimer?.IsEnabled != true &&
            string.IsNullOrWhiteSpace(_programmaticNavigationTargetKey))
        {
            return;
        }

        _navigationSmoothScrollTimer?.Stop();
        _programmaticNavigationTargetKey = null;
        _navigationSmoothScrollTarget = SettingsScrollViewer.VerticalOffset;
    }

    private FrameworkElement ResolveSection(string key) =>
        key switch
        {
            "hotkey" => HotkeySection,
            "toolbar" => ToolbarSection,
            "local" => LocalToolsSection,
            "social" => SocialSection,
            "window" => WindowSection,
            "appearance" => AppearanceSection,
            "advanced" => AdvancedSection,
            _ => OverviewSection
        };

    private IEnumerable<(string Key, FrameworkElement Section)>
        EnumerateSections()
    {
        yield return ("overview", OverviewSection);
        yield return ("hotkey", HotkeySection);
        yield return ("toolbar", ToolbarSection);
        yield return ("local", LocalToolsSection);
        yield return ("social", SocialSection);
        yield return ("window", WindowSection);
        yield return ("appearance", AppearanceSection);
        yield return ("advanced", AdvancedSection);
    }

    private void ScrollToSection(string? key)
    {
        var normalized = EnumerateSections()
            .Select(entry => entry.Key)
            .Contains(key)
            ? key!
            : "overview";
        _programmaticNavigationTargetKey = normalized;
        SetActiveSection(normalized);
        var target = ResolveSection(normalized);
        try
        {
            var position = target
                .TransformToAncestor(SettingsScrollViewer)
                .Transform(new WpfPoint(0, 0));
            var targetOffset = Math.Clamp(
                SettingsScrollViewer.VerticalOffset + position.Y - 12,
                0,
                SettingsScrollViewer.ScrollableHeight);
            StartNavigationSmoothScroll(targetOffset);
        }
        catch
        {
            target.BringIntoView();
            _programmaticNavigationTargetKey = null;
            SetActiveSection(normalized);
        }
    }

    private void StartNavigationSmoothScroll(double targetOffset)
    {
        SmoothWheelScrollBehavior.CancelPendingMotion(SettingsScrollViewer);
        _navigationSmoothScrollTarget = Math.Clamp(
            targetOffset,
            0,
            SettingsScrollViewer.ScrollableHeight);
        _navigationSmoothScrollTimer ??=
            new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(12)
            };
        _navigationSmoothScrollTimer.Tick -=
            SettingsNavigationSmoothScrollTimer_Tick;
        _navigationSmoothScrollTimer.Tick +=
            SettingsNavigationSmoothScrollTimer_Tick;
        _navigationSmoothScrollTimer.Start();
    }

    private void SettingsNavigationSmoothScrollTimer_Tick(
        object? sender,
        EventArgs e)
    {
        if (_navigationSmoothScrollTimer is null)
        {
            return;
        }

        var currentOffset = SettingsScrollViewer.VerticalOffset;
        var delta = _navigationSmoothScrollTarget - currentOffset;
        if (Math.Abs(delta) < 0.5)
        {
            SettingsScrollViewer.ScrollToVerticalOffset(
                _navigationSmoothScrollTarget);
            _navigationSmoothScrollTimer.Stop();
            var targetKey = _programmaticNavigationTargetKey;
            _programmaticNavigationTargetKey = null;
            if (!string.IsNullOrWhiteSpace(targetKey))
            {
                SetActiveSection(targetKey);
            }
            else
            {
                RefreshActiveSectionFromScroll();
            }

            return;
        }

        SettingsScrollViewer.ScrollToVerticalOffset(
            currentOffset + delta * 0.28);
    }

    private void SettingsScrollViewer_ScrollChanged(
        object sender,
        ScrollChangedEventArgs e)
    {
        if (_applying ||
            !IsVisible ||
            !string.IsNullOrWhiteSpace(_programmaticNavigationTargetKey))
        {
            return;
        }

        RefreshActiveSectionFromScroll();
    }

    private void RefreshActiveSectionFromScroll()
    {
        try
        {
            if (SettingsScrollViewer.ScrollableHeight > 0 &&
                SettingsScrollViewer.VerticalOffset >=
                SettingsScrollViewer.ScrollableHeight - 0.5)
            {
                SetActiveSection("advanced");
                return;
            }

            const double activationLine = 30;
            var active = "overview";
            var closest = double.NegativeInfinity;
            foreach (var (key, section) in EnumerateSections())
            {
                var y = section
                    .TransformToAncestor(SettingsScrollViewer)
                    .Transform(new WpfPoint(0, 0))
                    .Y;
                if (y <= activationLine && y > closest)
                {
                    closest = y;
                    active = key;
                }
            }

            SetActiveSection(active);
        }
        catch
        {
            SetActiveSection(_activeSection);
        }
    }

    private void SetActiveSection(string key)
    {
        WpfButton? activeButton = null;
        var shouldAnimate =
            _navigationActiveRailInitialized &&
            !string.Equals(
                _activeSection,
                key,
                StringComparison.OrdinalIgnoreCase);
        _activeSection = key;
        foreach (var button in new[]
                 {
                     OverviewNavigationButton,
                     HotkeyNavigationButton,
                     ToolbarNavigationButton,
                     LocalToolsNavigationButton,
                     SocialNavigationButton,
                     WindowNavigationButton,
                     AppearanceNavigationButton,
                     AdvancedNavigationButton
                 })
        {
            button.Tag = button.Uid == key ? "Active" : "Inactive";
            if (button.Uid == key)
            {
                activeButton = button;
            }
        }

        if (activeButton is not null)
        {
            activeButton.BringIntoView();
            MoveSettingsNavigationActiveRail(
                activeButton,
                shouldAnimate);
        }
    }

    private void MoveSettingsNavigationActiveRail(
        WpfButton activeButton,
        bool animate)
    {
        if (!IsVisible ||
            !SettingsNavigationContentGrid.IsLoaded ||
            !activeButton.IsLoaded ||
            activeButton.ActualHeight <= 0)
        {
            SettingsNavigationActiveRail.Opacity = 0;
            return;
        }

        try
        {
            var targetPosition = activeButton
                .TransformToAncestor(SettingsNavigationContentGrid)
                .Transform(new WpfPoint(0, 0));
            var targetY = targetPosition.Y + 2;
            SettingsNavigationActiveRail.Height = Math.Max(
                0,
                activeButton.ActualHeight - 4);
            SettingsNavigationActiveRail.Opacity = 1;

            var currentY = SettingsNavigationActiveRailTransform.Y;
            SettingsNavigationActiveRailTransform.BeginAnimation(
                TranslateTransform.YProperty,
                null);
            SettingsNavigationActiveRailTransform.Y = targetY;

            if (!animate ||
                !UiMotion.IsEnabled ||
                Math.Abs(targetY - currentY) < 0.5)
            {
                _navigationActiveRailInitialized = true;
                return;
            }

            var animation = new DoubleAnimationUsingKeyFrames
            {
                FillBehavior = FillBehavior.Stop
            };
            animation.KeyFrames.Add(
                new DiscreteDoubleKeyFrame(
                    currentY,
                    KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(
                new SplineDoubleKeyFrame(
                    targetY,
                    KeyTime.FromTimeSpan(
                        TimeSpan.FromMilliseconds(180)),
                    new KeySpline(0.22, 1.0, 0.36, 1.0)));
            SettingsNavigationActiveRailTransform.BeginAnimation(
                TranslateTransform.YProperty,
                animation,
                HandoffBehavior.SnapshotAndReplace);
            _navigationActiveRailInitialized = true;
        }
        catch
        {
            SettingsNavigationActiveRailTransform.BeginAnimation(
                TranslateTransform.YProperty,
                null);
            _navigationActiveRailInitialized = true;
        }
    }
}
