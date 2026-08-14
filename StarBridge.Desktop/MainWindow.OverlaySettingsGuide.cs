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
                "引导将依次介绍设置分组、模块设置和全屏预览编辑。它不会自动修改或保存任何设置。",
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

        SetOverlaySettingsWorkspace(OverlaySettingsArea.Information);
        var pages = new List<OverlayGuidePage>
        {
            new OverlayGuidePage(OverlayOverviewCategoryButton, "总览", "查看当前预设、启用状态和保存情况。", "overview"),
            new OverlayGuidePage(OverlayStartupCategoryButton, "打开方式", "管理浮层热键，并检查热键是否可用。", "startup"),
            new OverlayGuidePage(OverlayDisplayBehaviorCategoryButton, "跟随游戏", "决定浮层如何跟随游戏窗口和当前协作场景。", "background"),
            new OverlayGuidePage(
                OverlayModulesCategoryButton,
                "模块与内容",
                "这里统一管理通讯提醒、舰队总览、成员信息、场景通讯和事件通知。关闭模块会让它从画面和工作台中隐藏；模块要显示什么、停留多久以及如何排列，则在模块工作台中调整。",
                "modules"),
            new OverlayGuidePage(
                OverlayOpenModuleWorkbenchButton,
                "打开模块工作台",
                "工作台顶部用于切换当前模块。选择后，下方只显示这个模块自己的内容、显示规则和停留时间，右侧画布会同步预览结果。",
                "",
                IsNavigationTarget: false,
                ExplanationTarget: OverlayInspectorModulePickerExpander),
        };

        if (_overlaySettings.ShowEventNotifications)
        {
            pages.Add(new OverlayGuidePage(
                OverlayEventNotificationSettingsPanel,
                "调整事件通知",
                "事件通知的播报类型、同时显示数量、重要事件常驻、弹出速度和各类事件停留时间都集中在这里。关闭某类播报只影响事件通知，不会关闭其他模块。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false,
                InspectorModuleKey: "EventNotifications"));
        }

        if (_overlaySettings.ShowNotice)
        {
            pages.Add(new OverlayGuidePage(
                OverlayNoticeInspectorPanel,
                "调整通讯提醒",
                "通讯提醒可选择是否显示好友事件、是否预览私信正文，并可设置吸附位置和停留时间。这些选项只属于通讯提醒模块。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false,
                InspectorModuleKey: "Notice"));
        }

        var adjustableModuleKey = _overlayLayout
            .Where(IsOverlayEditorItemVisible)
            .OrderBy(item => GetOverlayInspectorModulePickerOrder(item.Key))
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .Select(item => item.Key)
            .FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(adjustableModuleKey))
        {
            pages.Add(new OverlayGuidePage(
                OverlayInspectorModuleAppearancePanel,
                "调整当前模块的显示",
                "每个常驻模块都有自己的锁定、文字不透明度和背景不透明度。你调整的是当前选中的模块，不会连带改变其他模块。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false,
                InspectorModuleKey: adjustableModuleKey));
            pages.Add(new OverlayGuidePage(
                OverlayInspectorGeometryExpander,
                "调整位置与尺寸",
                "展开“位置与尺寸”后，可以精确设置锚点、坐标、宽度和高度；更直观的方式是在右侧画布中直接拖动和缩放模块。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false,
                InspectorModuleKey: adjustableModuleKey,
                ExpandGeometry: true));
        }

        pages.AddRange(new[]
        {
            new OverlayGuidePage(OverlayPlacementCategoryButton, "屏幕布局", "在画布中调整模块位置、尺寸与吸附方式。直接点击画布中的模块，也可以快速回到它的工作台设置。", "placement"),
            new OverlayGuidePage(OverlayCrosshairCategoryButton, "虚拟准星", "选择准星类型，并调整大小、间距、线宽与颜色。", "crosshair"),
            new OverlayGuidePage(OverlayAppearanceCategoryButton, "外观", "统一主题、颜色、泛光和其他视觉表现。", "appearance"),
            new OverlayGuidePage(OverlayMotionCategoryButton, "动画与性能", "选择体验方案，或分别调整转场和常驻动画。", "motion"),
            new OverlayGuidePage(OverlayPresetCategoryButton, "预设与恢复", "管理当前预设，并在需要时恢复默认布局。", "preset"),
            new OverlayGuidePage(
                SaveLayoutButton,
                "保存设置",
                "右侧预览会即时显示调整效果；确认无误后点击“保存更改”。如果不想保留本次调整，可以选择“放弃更改”。",
                "",
                RequiresTargetAction: false,
                IsNavigationTarget: false),
            new OverlayGuidePage(
                OverlayEditorFullScreenButton,
                "全屏预览编辑",
                "点击高亮按钮进入全屏编辑；在接近实际游戏画面比例的画布中检查布局，完成后可按 Esc 返回。",
                "placement",
                IsNavigationTarget: false)
        });
        _overlayGuidePages = pages;
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
        PrepareOverlayGuidePage(page);
        CaptureOverlayGuideLockedScrollOffset();
        _guidedTourTarget = page.Target;
        GuidedTourOverlay.Visibility = Visibility.Visible;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourEyebrowText.Text = "游戏浮层设置引导";
        GuidedTourTitleText.Text = $"打开{page.Title}";
        GuidedTourBodyText.Text = page.Target switch
        {
            var target when ReferenceEquals(target, OverlayEditorFullScreenButton) =>
                "点击高亮按钮进入全屏预览编辑。",
            var target when ReferenceEquals(target, OverlayOpenModuleWorkbenchButton) =>
                "点击高亮的“打开工作台”，开始调整各个模块。",
            _ => $"点击左侧高亮的“{page.Title}”。"
        };
        GuidedTourProgressText.Text = $"{_overlayGuidePageIndex + 1} / {_overlayGuidePages.Count}";
        GuidedTourPrimaryButton.Visibility = Visibility.Collapsed;
        GuidedTourSecondaryButton.Content = "结束引导";
        GuidedTourSecondaryButton.Visibility = Visibility.Visible;
        EnsureOverlayGuideTargetVisible(page);

        if (!page.RequiresTargetAction)
        {
            _overlayGuideShowingExplanation = true;
            ShowOverlayGuideExplanation();
            return;
        }

        ScheduleGuidedTourLayout();
    }

    private void PrepareOverlayGuidePage(OverlayGuidePage page)
    {
        if (string.IsNullOrWhiteSpace(page.InspectorModuleKey))
        {
            return;
        }

        SelectOverlayLayerEntry(page.InspectorModuleKey);
        SetOverlayInspectorOpen(true);
        RefreshOverlayInspector();
        OverlayInspectorModulePickerExpander.IsExpanded = false;
        OverlayInspectorGeometryExpander.IsExpanded = page.ExpandGeometry;
        SmoothWheelScrollBehavior.CancelPendingMotion(OverlayInspectorScrollViewer);
        OverlayInspectorScrollViewer.ScrollToTop();
    }

    private void EnsureOverlayGuideTargetVisible(OverlayGuidePage page)
    {
        if (page.IsNavigationTarget && OverlaySettingsNavigationScrollViewer is null)
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
            OverlaySettingsNavigationScrollViewer?.UpdateLayout();
            OverlayInspectorScrollViewer?.UpdateLayout();
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
            : page.ExplanationTarget ?? ResolveOverlaySettingsSection(page.SectionKey) ?? page.Target;
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
