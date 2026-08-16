using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private enum GuideMode
    {
        None,
        Initial,
        IdentityBinding,
        OverlaySettings
    }

    private enum GuideStep
    {
        None,
        LoginFirst,
        AccountOverview,
        SettingsOverview,
        ProfileHangarOverview,
        FriendsOverview,
        FleetOverview,
        RoomsOverview,
        OverlayOverview,
        SupportOverview,
        Complete,
        Introduction,
        OpenAccountMenu,
        OpenIdentitySettings,
        SelectLog,
        BindIdentity
    }

    private sealed record OverlayGuidePage(
        FrameworkElement Target,
        string Title,
        string Body,
        string SectionKey,
        bool RequiresTargetAction = true,
        bool IsNavigationTarget = true,
        FrameworkElement? ExplanationTarget = null,
        string? InspectorModuleKey = null,
        bool ExpandGeometry = false);

    private GuideMode _guideMode;
    private GuideStep _guideStep;
    private FrameworkElement? _guidedTourTarget;
    private TaskCompletionSource<bool>? _initialGuideCompletionSource;
    private IReadOnlyList<OverlayGuidePage> _overlayGuidePages = Array.Empty<OverlayGuidePage>();
    private int _overlayGuidePageIndex;
    private bool _guidedTourLayoutScheduled;
    private FrameworkElement? _lastGuidedTourLayoutTarget;
    private OnboardingJourneyStage _onboardingJourneyStage;

    private async Task<bool> StartInitialGuidedTourAsync()
    {
        if (!IsLoggedIn)
        {
            return false;
        }

        await WaitForVisibleDialogsToCloseAsync();
        if (Dispatcher.HasShutdownStarted || !IsLoaded)
        {
            return false;
        }

        var shouldStart = StarBridgeMessageBox.ShowAction(
            this,
            "是否开始应用引导流程？\n\n引导会先帮助你连接 Game.log，再带你完成登录、身份绑定并认识主要功能。你也可以暂不开始，之后从“信息与支持”重新打开。",
            "开始应用引导流程",
            "开始引导",
            "暂不开始",
            MessageBoxImage.Question);
        if (!shouldStart)
        {
            OnboardingState.MarkDeferred();
            return false;
        }

        _initialGuideCompletionSource = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        _guideMode = GuideMode.Initial;
        OnboardingState.ClearDeferred();
        _onboardingJourneyStage = OnboardingJourney.Resume(
            isLoggedIn: true,
            OnboardingState.GetFeatureTourStep());
        if (_identityBindingSupported && !IsIdentityBindingVerified)
        {
            ShowMandatoryIdentityBindingGuide();
        }
        else
        {
            ShowJourneyStage(_onboardingJourneyStage);
        }

        return await _initialGuideCompletionSource.Task;
    }

    private async Task WaitForVisibleDialogsToCloseAsync()
    {
        await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
        while (!Dispatcher.HasShutdownStarted)
        {
            var hasVisibleDialog = false;
            foreach (Window ownedWindow in OwnedWindows)
            {
                if (ownedWindow.IsVisible)
                {
                    hasVisibleDialog = true;
                    break;
                }
            }

            if (!hasVisibleDialog)
            {
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                return;
            }

            await Task.Delay(100);
        }
    }

    private void ShowJourneyStage(OnboardingJourneyStage stage)
    {
        _onboardingJourneyStage = stage;
        var step = stage.Chapter switch
        {
            OnboardingJourneyChapter.Login => GuideStep.LoginFirst,
            OnboardingJourneyChapter.Account => GuideStep.AccountOverview,
            OnboardingJourneyChapter.Settings => GuideStep.SettingsOverview,
            OnboardingJourneyChapter.ProfileAndHangar => GuideStep.ProfileHangarOverview,
            OnboardingJourneyChapter.Friends => GuideStep.FriendsOverview,
            OnboardingJourneyChapter.Fleet => GuideStep.FleetOverview,
            OnboardingJourneyChapter.Rooms => GuideStep.RoomsOverview,
            OnboardingJourneyChapter.Overlay => GuideStep.OverlayOverview,
            OnboardingJourneyChapter.Support => GuideStep.SupportOverview,
            _ => GuideStep.Complete
        };
        if (step == GuideStep.LoginFirst && !HasConnectedGameLog())
        {
            step = GuideStep.SelectLog;
        }

        ShowInitialGuideStep(step);
    }

    private void ShowInitialGuideStep(GuideStep step)
    {
        _guideMode = GuideMode.Initial;
        _guideStep = step;
        GuidedTourInteractionBlocker.Visibility = Visibility.Collapsed;
        GuidedTourOverlay.Visibility = Visibility.Visible;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourBodyText.Visibility = Visibility.Visible;
        GuidedTourSecondaryButton.Content = "暂时收起";
        GuidedTourSecondaryButton.Visibility = Visibility.Visible;
        GuidedTourBackButton.Visibility = Visibility.Collapsed;
        GuidedTourPrimaryButton.Visibility = Visibility.Collapsed;
        GuidedTourEyebrowText.Text = step is GuideStep.LoginFirst or GuideStep.SelectLog ? "首次启航" : "启航航线";

        if (IsBridgeShellEnabled && TryConfigureBridgeFeatureTourStep(step))
        {
            ScheduleGuidedTourLayout();
            return;
        }

        switch (step)
        {
            case GuideStep.Introduction:
                _guidedTourTarget = null;
                GuidedTourTitleText.Text = "开始前，请阅读使用说明";
                GuidedTourBodyText.Text = "阅读到说明底部后才能继续。接下来会带你完成必要设置，并依次认识主要功能。";
                GuidedTourIntroductionScrollViewer.Visibility = Visibility.Visible;
                GuidedTourPrimaryButton.Content = "已阅读，开始设置";
                GuidedTourPrimaryButton.IsEnabled = false;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                GuidedTourProgressText.Text = "说明 · 1 / 3";
                break;
            case GuideStep.SelectLog:
                OpenPersonalIdentitySettings_Click(this, new RoutedEventArgs());
                RefreshBridgeShellForSelectedTab();
                ConfigureClickStep(
                    PersonalQuickScanLogButton,
                    "先连接 Game.log",
                    "无需登录即可扫描游戏日志。连接后，应用才能识别你的 Star Citizen 游戏 ID，并在注册后用一个明确步骤请你确认绑定。",
                    "首次启航 · 游戏日志");
                GuidedTourPrimaryButton.Content = "扫描日志";
                GuidedTourPrimaryButton.IsEnabled = true;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                break;
            case GuideStep.LoginFirst:
                ConfigureClickStep(
                    IsBridgeShellEnabled ? BridgeAuthenticationButton : HeaderAuthenticationButton,
                    "先登录你的账号",
                    "完整引导会在登录后开始。在此之前只介绍登录入口；如果现在不登录，后续章节不会出现。",
                    "首次启航 · 登录");
                GuidedTourPrimaryButton.Content = "登录 / 注册";
                GuidedTourPrimaryButton.IsEnabled = true;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                break;
            case GuideStep.Complete:
                _guidedTourTarget = null;
                GuidedTourTitleText.Text = "启航航线已完成";
                GuidedTourBodyText.Text = "你已经走过自己的账号、设置与资料，也知道了好友、组织、房间、浮层和帮助入口。之后仍可在帮助中心重新查看。";
                GuidedTourProgressText.Text = "启航航线 · 完成";
                GuidedTourBackButton.Visibility = Visibility.Visible;
                GuidedTourPrimaryButton.Content = "完成引导";
                GuidedTourPrimaryButton.IsEnabled = true;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                break;
        }

        ScheduleGuidedTourLayout();
    }

    private bool TryConfigureBridgeFeatureTourStep(GuideStep step)
    {
        switch (step)
        {
            case GuideStep.AccountOverview:
                OpenPersonalIdentitySettings_Click(this, new RoutedEventArgs());
                RefreshBridgeShellForSelectedTab();
                ConfigureOverviewStep(
                    PersonalDashboardIdentityButton,
                    "我的账号",
                    "先认识和自己有关的内容：登录状态、头像、呼号、游戏 ID 与 Game.log 都在这里。你可以现在设置，也可以只查看后继续。",
                    chapterIndex: 0);
                return true;
            case GuideStep.SettingsOverview:
                HeaderSettingsButton_Click(this, new RoutedEventArgs());
                RefreshBridgeShellForSelectedTab();
                ConfigureOverviewStep(
                    PersonalDashboardAppSettingsButton,
                    "我的设置",
                    "同步与隐私、提醒方式和应用选项都在设置中。你可以按自己的习惯调整；引导不会要求你必须改成某个值。",
                    chapterIndex: 1);
                return true;
            case GuideStep.ProfileHangarOverview:
                PersonalNav_Click(BridgePersonalNavButton, new RoutedEventArgs());
                RefreshBridgeShellForSelectedTab();
                ConfigureOverviewStep(
                    BridgePersonalNavButton,
                    "我的资料与机库",
                    "个人主页展示你的公开资料、游戏定位与舰船概况。右上角头像菜单还可以进入“我的机库”管理舰船和专属图片。",
                    chapterIndex: 2);
                return true;
            case GuideStep.FriendsOverview:
                BridgeSocialNav_Click(BridgeSocialNavButton, new RoutedEventArgs());
                ConfigureOverviewStep(
                    BridgeSocialNavButton,
                    "好友",
                    "这里可以查看好友、处理申请和打开私信。先自由看看，不需要为了完成引导而添加任何人。",
                    chapterIndex: 3);
                return true;
            case GuideStep.FleetOverview:
                BridgeFleetNav_Click(BridgeFleetNavButton, new RoutedEventArgs());
                ConfigureOverviewStep(
                    BridgeFleetNavButton,
                    "组织",
                    "没有组织时可以浏览并申请加入；加入后，这里会成为成员、舰船、聊天和管理的长期协作空间。",
                    chapterIndex: 4);
                return true;
            case GuideStep.RoomsOverview:
                BridgePartyNav_Click(BridgePartyNavButton, new RoutedEventArgs());
                ConfigureOverviewStep(
                    BridgePartyNavButton,
                    "房间",
                    "房间用于临时组队。你可以浏览已有房间或创建自己的房间；引导不会代替你提交或创建。",
                    chapterIndex: 5);
                return true;
            case GuideStep.OverlayOverview:
                var previousTab = MainTabs.SelectedItem;
                MainTabs.SelectedItem = OverlayEditTab;
                SetActiveNav(OverlayNavButton);
                QueueMainPageReveal(previousTab);
                RenderOverlayEditor();
                OnboardingState.MarkHintCompleted(OverlayInitialTourVisitedHintId);
                RefreshBridgeShellForSelectedTab();
                ConfigureOverviewStep(
                    BridgeOverlayNavButton,
                    "游戏浮层",
                    "在这里配置信息浮层、菜单浮层与参考图。详细编辑有自己的设置引导，本次只带你认识入口。",
                    chapterIndex: 6);
                return true;
            case GuideStep.SupportOverview:
                BridgeInfoNav_Click(BridgeInfoNavButton, new RoutedEventArgs());
                ConfigureOverviewStep(
                    BridgeInfoNavButton,
                    "信息与支持",
                    "游戏日志识别、说明与声明、版本更新记录和问题反馈都在这里；以后也能从这里重新打开启航航线。",
                    chapterIndex: 7);
                return true;
            default:
                return false;
        }
    }

    private void ConfigureOverviewStep(
        FrameworkElement target,
        string title,
        string body,
        int chapterIndex)
    {
        _guidedTourTarget = target;
        GuidedTourTitleText.Text = title;
        GuidedTourBodyText.Text = body + "\n\n你可以继续操作当前页面；准备好后再点“我了解了”。";
        GuidedTourProgressText.Text = $"启航航线 · {chapterIndex + 1} / {OnboardingJourney.AuthenticatedChapterCount}";
        GuidedTourBackButton.Visibility = chapterIndex > 0 ? Visibility.Visible : Visibility.Collapsed;
        GuidedTourPrimaryButton.Content = "我了解了";
        GuidedTourPrimaryButton.IsEnabled = true;
        GuidedTourPrimaryButton.Visibility = Visibility.Visible;
    }

    private void ConfigureClickStep(
        FrameworkElement target,
        string title,
        string body,
        string progress)
    {
        _guidedTourTarget = target;
        GuidedTourTitleText.Text = title;
        GuidedTourBodyText.Text = body;
        GuidedTourProgressText.Text = progress;
        GuidedTourPrimaryButton.Visibility = Visibility.Visible;
    }

    private void ShowFeatureTourStep(int step)
    {
        ShowJourneyStage(OnboardingJourney.Resume(isLoggedIn: true, savedChapterIndex: step));
    }

    private void NotifyGuidedTourAction(GuideStep action)
    {
        if (_guideMode != GuideMode.Initial)
        {
            return;
        }

        if (_guideStep == GuideStep.SelectLog && action == GuideStep.SelectLog)
        {
            ShowInitialGuideStep(GuideStep.LoginFirst);
            return;
        }

        if (_guideStep == GuideStep.LoginFirst && action == GuideStep.LoginFirst)
        {
            if (!IsLoggedIn)
            {
                return;
            }

            OnboardingState.MarkIntroductionRead();
            OnboardingState.MarkPreparationCompleted();
            OnboardingState.SetFeatureTourStep(0);
            ShowJourneyStage(OnboardingJourney.Next(_onboardingJourneyStage, isLoggedIn: true));
        }
    }

    private async void GuidedTourPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode == GuideMode.OverlaySettings)
        {
            ContinueOverlayGuideAfterExplanation();
            return;
        }

        if (_guideMode == GuideMode.IdentityBinding)
        {
            await ContinueMandatoryIdentityBindingGuideAsync();
            return;
        }

        switch (_guideStep)
        {
            case GuideStep.SelectLog:
                if (QuickScanLogAndStart())
                {
                    ShowInitialGuideStep(GuideStep.LoginFirst);
                }
                break;
            case GuideStep.LoginFirst:
                await HandleOnboardingActionAsync(OnboardingNextAction.Login);
                if (IsLoggedIn && _identityBindingSupported && !IsIdentityBindingVerified)
                {
                    ShowMandatoryIdentityBindingGuide();
                }
                else
                {
                    NotifyGuidedTourAction(GuideStep.LoginFirst);
                }
                break;
            case GuideStep.Complete:
                OnboardingState.MarkCompleted();
                HideGuidedTour();
                RefreshOnboardingSupportPanel();
                _initialGuideCompletionSource?.TrySetResult(true);
                break;
            default:
                var next = OnboardingJourney.Next(_onboardingJourneyStage, IsLoggedIn);
                OnboardingState.SetFeatureTourStep(next.AuthenticatedIndex);
                ShowJourneyStage(next);
                break;
        }
    }

    private void GuidedTourBackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode != GuideMode.Initial || !IsLoggedIn)
        {
            return;
        }

        var previous = OnboardingJourney.Previous(_onboardingJourneyStage);
        OnboardingState.SetFeatureTourStep(previous.AuthenticatedIndex);
        ShowJourneyStage(previous);
    }

    private void GuidedTourSecondaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode == GuideMode.OverlaySettings)
        {
            FinishOverlaySettingsSpotlightGuide();
            return;
        }

        if (_guideMode == GuideMode.IdentityBinding)
        {
            SelectLog_Click(this, new RoutedEventArgs());
            ShowMandatoryIdentityBindingGuide();
            return;
        }

        OnboardingState.MarkDeferred();
        HideGuidedTour();
        _initialGuideCompletionSource?.TrySetResult(false);
    }

    private void GuidedTourIntroductionScrollViewer_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (_guideStep != GuideStep.Introduction ||
            GuidedTourIntroductionScrollViewer.ScrollableHeight <= 0 ||
            GuidedTourIntroductionScrollViewer.VerticalOffset <
            GuidedTourIntroductionScrollViewer.ScrollableHeight - 2)
        {
            return;
        }

        GuidedTourPrimaryButton.IsEnabled = true;
        GuidedTourProgressText.Text = "说明已阅读";
    }

    private void HideGuidedTour()
    {
        GuidedTourOverlay.Visibility = Visibility.Collapsed;
        GuidedTourInteractionBlocker.Visibility = Visibility.Collapsed;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourTargetFrame.Visibility = Visibility.Collapsed;
        _guidedTourTarget = null;
        _lastGuidedTourLayoutTarget = null;
        _guideMode = GuideMode.None;
        _guideStep = GuideStep.None;
    }

    private void GuidedTourOverlay_SizeChanged(object sender, SizeChangedEventArgs e) =>
        ScheduleGuidedTourLayout();

    private void ScheduleGuidedTourLayout()
    {
        if (GuidedTourOverlay.Visibility != Visibility.Visible)
        {
            return;
        }

        if (_guidedTourLayoutScheduled)
        {
            return;
        }

        _guidedTourLayoutScheduled = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            _guidedTourLayoutScheduled = false;
            UpdateGuidedTourLayout();
        }));
    }

    private void UpdateGuidedTourLayout()
    {
        if (GuidedTourOverlay.Visibility != Visibility.Visible ||
            GuidedTourOverlay.ActualWidth <= 0 ||
            GuidedTourOverlay.ActualHeight <= 0)
        {
            return;
        }

        var overlayWidth = GuidedTourOverlay.ActualWidth;
        var overlayHeight = GuidedTourOverlay.ActualHeight;
        var targetChanged = !ReferenceEquals(_lastGuidedTourLayoutTarget, _guidedTourTarget);
        Rect targetRect;
        if (_guidedTourTarget is { IsVisible: true, ActualWidth: > 0, ActualHeight: > 0 } target)
        {
            try
            {
                var origin = target.TransformToAncestor(MainWindowRootGrid).Transform(new System.Windows.Point(0, 0));
                targetRect = ClipGuidedTourTargetToVisibleRegion(
                    target,
                    new Rect(
                        origin.X - 6,
                        origin.Y - 6,
                        target.ActualWidth + 12,
                        target.ActualHeight + 12),
                    overlayWidth,
                    overlayHeight);
            }
            catch (InvalidOperationException)
            {
                targetRect = Rect.Empty;
            }
        }
        else
        {
            targetRect = Rect.Empty;
        }

        ArrangeGuidedTourMasks(targetRect, overlayWidth, overlayHeight);
        GuidedTourCoachCard.Measure(new System.Windows.Size(Math.Min(420, overlayWidth - 32), overlayHeight - 32));
        var cardWidth = Math.Min(400, Math.Max(280, overlayWidth - 32));
        var cardHeight = Math.Min(GuidedTourCoachCard.DesiredSize.Height, overlayHeight - 32);
        GuidedTourCoachCard.Width = cardWidth;

        var cardPoint = CalculateGuideCardPosition(
            targetRect,
            cardWidth,
            cardHeight,
            overlayWidth,
            overlayHeight);
        cardPoint = SnapPointToDevicePixels(cardPoint, GuidedTourOverlay);
        MoveGuideElement(GuidedTourCoachCard, GuidedTourCardTransform, cardPoint.X, cardPoint.Y, animate: targetChanged);

        if (!targetRect.IsEmpty)
        {
            GuidedTourTargetFrame.Visibility = Visibility.Visible;
            GuidedTourTargetFrame.Width = targetRect.Width;
            GuidedTourTargetFrame.Height = targetRect.Height;
            MoveGuideElement(GuidedTourTargetFrame, GuidedTourTargetTransform, targetRect.X, targetRect.Y, animate: targetChanged);
        }

        _lastGuidedTourLayoutTarget = _guidedTourTarget;
    }

    private Rect ClipGuidedTourTargetToVisibleRegion(
        FrameworkElement target,
        Rect targetRect,
        double overlayWidth,
        double overlayHeight)
    {
        targetRect.Intersect(new Rect(
            6,
            6,
            Math.Max(0, overlayWidth - 12),
            Math.Max(0, overlayHeight - 12)));
        if (targetRect.IsEmpty || FindGuidedTourScrollViewport(target) is not { IsVisible: true } viewport)
        {
            return targetRect;
        }

        try
        {
            var viewportOrigin = viewport
                .TransformToAncestor(MainWindowRootGrid)
                .Transform(new System.Windows.Point(0, 0));
            targetRect.Intersect(new Rect(
                viewportOrigin.X,
                viewportOrigin.Y,
                viewport.ActualWidth,
                viewport.ActualHeight));
        }
        catch (InvalidOperationException)
        {
            return Rect.Empty;
        }

        return targetRect;
    }

    private static ScrollViewer? FindGuidedTourScrollViewport(DependencyObject target)
    {
        for (DependencyObject? current = target; current is not null;)
        {
            if (current is ScrollViewer viewer)
            {
                return viewer;
            }

            try
            {
                current = VisualTreeHelper.GetParent(current) ?? LogicalTreeHelper.GetParent(current);
            }
            catch (InvalidOperationException)
            {
                current = LogicalTreeHelper.GetParent(current);
            }
        }

        return null;
    }

    private void ArrangeGuidedTourMasks(Rect target, double width, double height)
    {
        if (target.IsEmpty)
        {
            SetCanvasRect(GuidedTourMaskTop, 0, 0, width, height);
            GuidedTourMaskLeft.Visibility = Visibility.Collapsed;
            GuidedTourMaskRight.Visibility = Visibility.Collapsed;
            GuidedTourMaskBottom.Visibility = Visibility.Collapsed;
            GuidedTourTargetFrame.Visibility = Visibility.Collapsed;
            return;
        }

        GuidedTourMaskLeft.Visibility = Visibility.Visible;
        GuidedTourMaskRight.Visibility = Visibility.Visible;
        GuidedTourMaskBottom.Visibility = Visibility.Visible;
        SetCanvasRect(GuidedTourMaskTop, 0, 0, width, target.Top);
        SetCanvasRect(GuidedTourMaskBottom, 0, target.Bottom, width, Math.Max(0, height - target.Bottom));
        SetCanvasRect(GuidedTourMaskLeft, 0, target.Top, target.Left, target.Height);
        SetCanvasRect(GuidedTourMaskRight, target.Right, target.Top, Math.Max(0, width - target.Right), target.Height);
    }

    private static void SetCanvasRect(FrameworkElement element, double x, double y, double width, double height)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        element.Width = Math.Max(0, width);
        element.Height = Math.Max(0, height);
        element.Visibility = Visibility.Visible;
    }

    private static System.Windows.Point CalculateGuideCardPosition(
        Rect target,
        double cardWidth,
        double cardHeight,
        double width,
        double height)
    {
        const double margin = 18;
        if (target.IsEmpty)
        {
            return new System.Windows.Point(
                Math.Max(16, (width - cardWidth) / 2),
                Math.Max(16, (height - cardHeight) / 2));
        }

        var x = Math.Clamp(target.Left, 16, Math.Max(16, width - cardWidth - 16));
        var below = target.Bottom + margin;
        if (below + cardHeight <= height - 16)
        {
            return new System.Windows.Point(x, below);
        }

        var above = target.Top - cardHeight - margin;
        if (above >= 16)
        {
            return new System.Windows.Point(x, above);
        }

        var sideX = target.Right + margin;
        if (sideX + cardWidth > width - 16)
        {
            sideX = target.Left - cardWidth - margin;
        }

        return new System.Windows.Point(
            Math.Clamp(sideX, 16, Math.Max(16, width - cardWidth - 16)),
            Math.Clamp(target.Top, 16, Math.Max(16, height - cardHeight - 16)));
    }

    private static System.Windows.Point CalculateAccountMenuSafeCardPosition(
        Rect target,
        double cardWidth,
        double cardHeight,
        double width,
        double height)
    {
        if (target.IsEmpty)
        {
            return CalculateGuideCardPosition(target, cardWidth, cardHeight, width, height);
        }

        const double popupClearance = 188;
        var x = target.Left - cardWidth - popupClearance;
        var y = target.Bottom + 14;
        return new System.Windows.Point(
            Math.Clamp(x, 16, Math.Max(16, width - cardWidth - 16)),
            Math.Clamp(y, 16, Math.Max(16, height - cardHeight - 16)));
    }

    private static System.Windows.Point SnapPointToDevicePixels(System.Windows.Point point, Visual visual)
    {
        var dpi = VisualTreeHelper.GetDpi(visual);
        return new System.Windows.Point(
            Math.Round(point.X * dpi.DpiScaleX) / dpi.DpiScaleX,
            Math.Round(point.Y * dpi.DpiScaleY) / dpi.DpiScaleY);
    }

    private static void MoveGuideElement(
        FrameworkElement element,
        TranslateTransform transform,
        double x,
        double y,
        bool animate)
    {
        var previousLeft = Canvas.GetLeft(element);
        var previousTop = Canvas.GetTop(element);
        if (!animate ||
            double.IsNaN(previousLeft) ||
            double.IsNaN(previousTop) ||
            !UiMotion.IsEnabled)
        {
            transform.BeginAnimation(TranslateTransform.XProperty, null);
            transform.BeginAnimation(TranslateTransform.YProperty, null);
            transform.X = 0;
            transform.Y = 0;
            Canvas.SetLeft(element, x);
            Canvas.SetTop(element, y);
            return;
        }

        var currentX = previousLeft + transform.X;
        var currentY = previousTop + transform.Y;
        transform.BeginAnimation(TranslateTransform.XProperty, null);
        transform.BeginAnimation(TranslateTransform.YProperty, null);
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        transform.X = currentX - x;
        transform.Y = currentY - y;

        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
        var duration = TimeSpan.FromMilliseconds(180);
        var xAnimation = new DoubleAnimation(0, duration) { EasingFunction = easing };
        var yAnimation = new DoubleAnimation(0, duration) { EasingFunction = easing };
        yAnimation.Completed += (_, _) =>
        {
            transform.BeginAnimation(TranslateTransform.XProperty, null);
            transform.BeginAnimation(TranslateTransform.YProperty, null);
            transform.X = 0;
            transform.Y = 0;
        };
        transform.BeginAnimation(TranslateTransform.XProperty, xAnimation, HandoffBehavior.SnapshotAndReplace);
        transform.BeginAnimation(TranslateTransform.YProperty, yAnimation, HandoffBehavior.SnapshotAndReplace);
    }
}
