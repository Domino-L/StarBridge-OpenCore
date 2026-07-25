using System.Windows;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    internal const string OverlayInitialTourVisitedHintId = "overlay-initial-tour-visited-v1";
    private const string OverlayGuideOfferHintId = "overlay-settings-guide-offer-v1";
    private const string OverlayGuideCompletedHintId = "overlay-settings-guide-complete-v1";
    private bool _overlayGuideOfferOpen;
    private bool _overlayGuideShowingExplanation;
    private double _overlayGuideLockedScrollOffset;

    private async Task OfferOverlaySettingsGuideAsync()
    {
        if (_overlayGuideOfferOpen ||
            OnboardingState.GetCompletionStatus() != OnboardingCompletionStatus.Current ||
            !OnboardingState.IsHintCompleted(OverlayInitialTourVisitedHintId) ||
            OnboardingState.IsHintCompleted(OverlayGuideOfferHintId) ||
            OnboardingState.IsHintCompleted(OverlayGuideCompletedHintId))
        {
            return;
        }

        _overlayGuideOfferOpen = true;
        OnboardingState.MarkHintCompleted(OverlayGuideOfferHintId);
        try
        {
            var showGuide = await ShowAppConfirmationAsync(
                "游戏浮层",
                "是否查看浮层设置引导？",
                "引导将依次介绍设置分组、模块控制台和全屏预览编辑。它不会自动修改或保存任何设置。",
                "查看详细引导",
                "暂时不用",
                danger: false,
                showCancel: true,
                footerText: "以后仍可在浮层设置左侧点击“查看设置引导”。");
            if (showGuide)
            {
                ShowOverlaySettingsGuide();
            }
        }
        finally
        {
            _overlayGuideOfferOpen = false;
        }
    }

    private void ShowOverlaySettingsGuide()
    {
        if (_guideMode == GuideMode.Initial)
        {
            return;
        }

        _overlayGuidePages = new[]
        {
            new OverlayGuidePage(OverlayOverviewCategoryButton, "总览", "查看当前预设、启用状态和保存情况。", "overview"),
            new OverlayGuidePage(OverlayPresetCategoryButton, "预设与布局", "切换预设，并管理当前屏幕布局。", "preset"),
            new OverlayGuidePage(OverlayPlacementCategoryButton, "画布编辑", "在画布中调整模块位置、尺寸与吸附方式。", "placement"),
            new OverlayGuidePage(OverlayModulesCategoryButton, "模块", "决定哪些信息进入浮层；具体显示顺序在画布编辑中调整。", "modules"),
            new OverlayGuidePage(
                OverlayInspectorPanel,
                "模块控制台",
                "先在预览画布中选择一个模块，再从这里调整位置、尺寸、显示方式和图层顺序；也可以锁定模块，避免编辑布局时误移动。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false),
            new OverlayGuidePage(OverlayEventsCategoryButton, "事件通知", "选择要在游戏内事件栏显示的即时消息。", "events"),
            new OverlayGuidePage(OverlayCrosshairCategoryButton, "虚拟准星", "选择准星类型，并调整大小、间距、线宽与颜色。", "crosshair"),
            new OverlayGuidePage(OverlayAppearanceCategoryButton, "外观风格", "统一主题、颜色、泛光和其他视觉表现。", "appearance"),
            new OverlayGuidePage(OverlayMotionCategoryButton, "转场与动效", "设置与当前外观风格配套的转场和反馈效果。", "motion"),
            new OverlayGuidePage(OverlayStartupCategoryButton, "启动与热键", "管理浮层启动方式和全局热键，并检查热键是否可用。", "startup"),
            new OverlayGuidePage(OverlayDisplayBehaviorCategoryButton, "显示行为", "决定浮层在游戏窗口、主窗口和不同场景中的显示方式。", "background"),
            new OverlayGuidePage(
                OverlayEditorFullScreenButton,
                "全屏预览编辑",
                "点击高亮按钮进入全屏编辑；在接近实际游戏画面比例的画布中检查布局，完成后可按 Esc 返回。",
                "placement",
                IsNavigationTarget: false)
        };
        _overlayGuidePageIndex = 0;
        _overlayGuideShowingExplanation = false;
        _guideMode = GuideMode.OverlaySettings;
        ShowOverlayGuidePage();
    }

    private void ShowOverlayGuidePage()
    {
        if (_overlayGuidePageIndex < 0 || _overlayGuidePageIndex >= _overlayGuidePages.Count)
        {
            FinishOverlaySettingsSpotlightGuide();
            return;
        }

        var page = _overlayGuidePages[_overlayGuidePageIndex];
        CaptureOverlayGuideLockedScrollOffset();
        _guidedTourTarget = page.Target;
        GuidedTourOverlay.Visibility = Visibility.Visible;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourEyebrowText.Text = "游戏浮层设置引导";
        GuidedTourTitleText.Text = $"打开{page.Title}";
        GuidedTourBodyText.Text = page.Target == OverlayEditorFullScreenButton
            ? "点击高亮按钮进入全屏预览编辑。"
            : $"点击左侧高亮的“{page.Title}”。";
        GuidedTourProgressText.Text = $"{_overlayGuidePageIndex + 1} / {_overlayGuidePages.Count}";
        GuidedTourPrimaryButton.Visibility = Visibility.Collapsed;
        GuidedTourSecondaryButton.Content = "结束引导";
        GuidedTourSecondaryButton.Visibility = Visibility.Visible;
        EnsureOverlayGuideNavigationTargetVisible(page);

        if (!page.RequiresTargetAction)
        {
            _overlayGuideShowingExplanation = true;
            ShowOverlayGuideExplanation();
            return;
        }

        ScheduleGuidedTourLayout();
    }

    private void EnsureOverlayGuideNavigationTargetVisible(OverlayGuidePage page)
    {
        if (!page.IsNavigationTarget || OverlaySettingsNavigationScrollViewer is null)
        {
            return;
        }

        page.Target.BringIntoView();
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            if (_guideMode != GuideMode.OverlaySettings ||
                _overlayGuideShowingExplanation ||
                _overlayGuidePageIndex < 0 ||
                _overlayGuidePageIndex >= _overlayGuidePages.Count ||
                !ReferenceEquals(_overlayGuidePages[_overlayGuidePageIndex], page))
            {
                return;
            }

            page.Target.BringIntoView();
            OverlaySettingsNavigationScrollViewer.UpdateLayout();
            ScheduleGuidedTourLayout();
        }));
    }

    private void ShowOverlayGuideExplanation()
    {
        var page = _overlayGuidePages[_overlayGuidePageIndex];
        GuidedTourOverlay.Visibility = Visibility.Visible;
        System.Windows.Controls.Panel.SetZIndex(GuidedTourOverlay, 1000);
        _guidedTourTarget = page.Target == OverlayEditorFullScreenButton
            ? OverlayPreviewCanvasHost
            : ResolveOverlaySettingsSection(page.SectionKey) ?? page.Target;
        GuidedTourTitleText.Text = page.Title;
        GuidedTourBodyText.Text = page.Body;
        GuidedTourProgressText.Text = $"{_overlayGuidePageIndex + 1} / {_overlayGuidePages.Count} · 已打开";
        GuidedTourPrimaryButton.Content = _overlayGuidePageIndex == _overlayGuidePages.Count - 1
            ? "完成设置引导"
            : "了解，下一项";
        GuidedTourPrimaryButton.IsEnabled = true;
        GuidedTourPrimaryButton.Visibility = Visibility.Visible;
        ApplyOverlayGuideScrollRange();
        ScheduleGuidedTourLayout();
    }

    private void NotifyOverlaySettingsGuideTarget(FrameworkElement target)
    {
        if (_guideMode != GuideMode.OverlaySettings ||
            _overlayGuidePageIndex < 0 ||
            _overlayGuidePageIndex >= _overlayGuidePages.Count ||
            !ReferenceEquals(_overlayGuidePages[_overlayGuidePageIndex].Target, target))
        {
            return;
        }

        _overlayGuideShowingExplanation = true;
        if (ReferenceEquals(target, OverlayEditorFullScreenButton))
        {
            GuidedTourOverlay.Visibility = Visibility.Visible;
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
            {
                if (_guideMode == GuideMode.OverlaySettings &&
                    _overlayGuideShowingExplanation &&
                    _overlayGuidePageIndex >= 0 &&
                    _overlayGuidePageIndex < _overlayGuidePages.Count &&
                    ReferenceEquals(_overlayGuidePages[_overlayGuidePageIndex].Target, OverlayEditorFullScreenButton))
                {
                    ShowOverlayGuideExplanation();
                }
            }));
            return;
        }

        ShowOverlayGuideExplanation();
    }

    private void ContinueOverlayGuideAfterExplanation()
    {
        if (!_overlayGuideShowingExplanation)
        {
            return;
        }

        _overlayGuidePageIndex++;
        _overlayGuideShowingExplanation = false;
        ShowOverlayGuidePage();
    }

    private void FinishOverlaySettingsSpotlightGuide()
    {
        OnboardingState.MarkHintCompleted(OverlayGuideCompletedHintId);
        _overlayGuidePages = Array.Empty<OverlayGuidePage>();
        _overlayGuidePageIndex = 0;
        _overlayGuideShowingExplanation = false;
        ReleaseOverlayGuideScrollRange();
        HideGuidedTour();

        if (_isOverlayEditorFullScreen)
        {
            ExitOverlayEditorFullScreen();
            ApplyOverlayEditorChromeState();
            RenderOverlayEditor();
        }
    }

    private void CaptureOverlayGuideLockedScrollOffset()
    {
        if (OverlaySettingsScrollViewer is not null)
        {
            _overlayGuideLockedScrollOffset = OverlaySettingsScrollViewer.VerticalOffset;
            ApplyOverlayGuideScrollRange();
        }
    }

    private void OverlaySettingsGuideButton_Click(object sender, RoutedEventArgs e)
    {
        ShowOverlaySettingsGuide();
    }
}
