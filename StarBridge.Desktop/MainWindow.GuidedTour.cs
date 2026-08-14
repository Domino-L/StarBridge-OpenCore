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
        OverlaySettings
    }

    private enum GuideStep
    {
        None,
        Introduction,
        LoginFirst,
        OpenAccountMenu,
        OpenIdentitySettings,
        SelectLog,
        HomeOverview,
        FindFleetOverview,
        MyFleetOverview,
        MySquadOverview,
        OverlayOverview,
        Complete
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
    private bool _introductionReadToEnd;
    private bool _guidedTourLayoutScheduled;
    private FrameworkElement? _lastGuidedTourLayoutTarget;

    private Task<bool> StartInitialGuidedTourAsync()
    {
        _initialGuideCompletionSource = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        _guideMode = GuideMode.Initial;

        if (!OnboardingState.HasReadIntroduction())
        {
            ShowInitialGuideStep(GuideStep.Introduction);
        }
        else if (!OnboardingState.HasCompletedPreparation())
        {
            ShowInitialGuideStep(IsLoggedIn ? GuideStep.OpenAccountMenu : GuideStep.LoginFirst);
        }
        else
        {
            ShowFeatureTourStep(OnboardingState.GetFeatureTourStep());
        }

        return _initialGuideCompletionSource.Task;
    }

    private void ShowInitialGuideStep(GuideStep step)
    {
        _guideMode = GuideMode.Initial;
        _guideStep = step;
        GuidedTourOverlay.Visibility = Visibility.Visible;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourBodyText.Visibility = Visibility.Visible;
        GuidedTourSecondaryButton.Content = "稍后继续";
        GuidedTourSecondaryButton.Visibility = Visibility.Visible;
        GuidedTourPrimaryButton.Visibility = Visibility.Collapsed;
        GuidedTourEyebrowText.Text = "首次启航";

        if (IsBridgeShellEnabled && TryConfigureBridgeFeatureTourStep(step))
        {
            ScheduleGuidedTourLayout();
            return;
        }

        switch (step)
        {
            case GuideStep.Introduction:
                _guidedTourTarget = null;
                _introductionReadToEnd = false;
                GuidedTourTitleText.Text = "开始前，请阅读使用说明";
                GuidedTourBodyText.Text = "阅读到说明底部后才能继续。接下来会带你完成必要设置，并依次认识主要功能。";
                GuidedTourIntroductionScrollViewer.Visibility = Visibility.Visible;
                GuidedTourPrimaryButton.Content = "已阅读，开始设置";
                GuidedTourPrimaryButton.IsEnabled = false;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                GuidedTourProgressText.Text = "说明 · 1 / 3";
                break;
            case GuideStep.LoginFirst:
                ConfigureClickStep(
                    HeaderAuthenticationButton,
                    "登录账号（可选）",
                    "登录后可以使用好友、舰队、房间和资料同步。你也可以先浏览应用，需要在线功能时再登录。",
                    "准备 · 登录入口");
                GuidedTourPrimaryButton.Content = "暂不登录，继续";
                GuidedTourPrimaryButton.IsEnabled = true;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                break;
            case GuideStep.OpenAccountMenu:
                ConfigureClickStep(
                    IsBridgeShellEnabled ? BridgeSettingsButton : HeaderSettingsButton,
                    "打开设置",
                    "点击右上角的设置按钮，进入应用设置。",
                    "准备 · 设置入口");
                break;
            case GuideStep.OpenIdentitySettings:
                ConfigureClickStep(
                    PersonalDashboardIdentityButton,
                    "进入账号与识别",
                    "点击左侧的“账号与识别”。这里集中管理登录、头像、Game.log 与游戏身份。",
                    "准备 · 账号与识别");
                break;
            case GuideStep.SelectLog:
                ConfigureClickStep(
                    PersonalIdentityLogActionPanel,
                    "连接 Game.log",
                    "点击“重新扫描”自动查找，或点击“选择日志”手动选择 StarCitizen\\LIVE\\Game.log。连接后可以识别游戏身份、舰船、地点和游戏状态，也可以稍后再设置。",
                    "准备 · 游戏日志");
                GuidedTourPrimaryButton.Content = "稍后连接，继续导览";
                GuidedTourPrimaryButton.IsEnabled = true;
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                break;
            case GuideStep.HomeOverview:
                ConfigureOverviewStep(
                    BrandHomeButton,
                    "首页",
                    "左上角的星海舰桥标志是首页入口，可查看使用帮助、版本说明和问题反馈。",
                    "顶部导航 · 1 / 5");
                break;
            case GuideStep.FindFleetOverview:
                ConfigureOverviewStep(
                    FindFleetNavButton,
                    "寻找舰队",
                    "浏览公开舰队、筛选招募条件，并在了解详情后提交加入申请。",
                    "顶部导航 · 2 / 5");
                break;
            case GuideStep.MyFleetOverview:
                ConfigureOverviewStep(
                    MyFleetNavButton,
                    "我的舰队",
                    "查看舰队成员、聊天、公告、事件与舰船。尚未加入舰队时，也可以从这里创建舰队。",
                    "顶部导航 · 3 / 5");
                break;
            case GuideStep.MySquadOverview:
                ConfigureOverviewStep(
                    MySquadNavButton,
                    "组队大厅与当前房间",
                    "寻找或创建临时组队房间。加入房间后，这个入口会显示为“当前房间”，方便快速返回。",
                    "顶部导航 · 4 / 5");
                break;
            case GuideStep.OverlayOverview:
                OnboardingState.MarkHintCompleted(OverlayInitialTourVisitedHintId);
                ConfigureOverviewStep(
                    OverlayNavButton,
                    "游戏浮层",
                    "管理游戏内浮层的模块、布局、外观、准星、事件提醒和显示行为。首次进入时还可以选择查看详细设置引导。",
                    "顶部导航 · 5 / 5");
                break;
            case GuideStep.Complete:
                _guidedTourTarget = null;
                GuidedTourTitleText.Text = "初步引导已完成";
                GuidedTourBodyText.Text = "你已经了解账号与识别及顶部主要入口。现在可以按自己的节奏浏览和使用星海舰桥。";
                GuidedTourProgressText.Text = "可以开始使用";
                GuidedTourPrimaryButton.Content = "完成初步引导";
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
            case GuideStep.HomeOverview:
                ConfigureOverviewStep(
                    BridgeFleetNavButton,
                    "舰队",
                    "寻找或管理舰队，并在舰队内查看成员、舰船和舰队聊天。",
                    "模块导航 · 1 / 5");
                return true;
            case GuideStep.FindFleetOverview:
                ConfigureOverviewStep(
                    BridgePartyNavButton,
                    "房间",
                    "寻找或创建临时房间；房间成员与房间聊天都留在当前房间中。",
                    "模块导航 · 2 / 5");
                return true;
            case GuideStep.MyFleetOverview:
                ConfigureOverviewStep(
                    BridgePersonalNavButton,
                    "我的",
                    "从头像菜单进入个人资料、我的机库、账号识别与安全记录。",
                    "模块导航 · 3 / 5");
                return true;
            case GuideStep.MySquadOverview:
                ConfigureOverviewStep(
                    BridgeSocialNavButton,
                    "好友",
                    "处理好友申请、查看好友状态，并单独进行好友私信。",
                    "模块导航 · 4 / 5");
                return true;
            case GuideStep.OverlayOverview:
                ConfigureOverviewStep(
                    BridgeOverlayNavButton,
                    "游戏浮层",
                    "管理信息浮层、菜单浮层、游戏内工具及其显示方式。",
                    "模块导航 · 5 / 5");
                return true;
            default:
                return false;
        }
    }

    private void ConfigureOverviewStep(
        FrameworkElement target,
        string title,
        string body,
        string progress)
    {
        _guidedTourTarget = target;
        GuidedTourTitleText.Text = title;
        GuidedTourBodyText.Text = body;
        GuidedTourProgressText.Text = progress;
        GuidedTourPrimaryButton.Content = "下一项";
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
        GuidedTourBodyText.Text = body + "\n\n请点击高亮区域继续。";
        GuidedTourProgressText.Text = progress;
        GuidedTourPrimaryButton.Visibility = Visibility.Collapsed;
    }

    private void ShowFeatureTourStep(int step)
    {
        switch (Math.Clamp(step, 0, 5))
        {
            case 0: ShowInitialGuideStep(GuideStep.HomeOverview); break;
            case 1: ShowInitialGuideStep(GuideStep.FindFleetOverview); break;
            case 2: ShowInitialGuideStep(GuideStep.MyFleetOverview); break;
            case 3: ShowInitialGuideStep(GuideStep.MySquadOverview); break;
            case 4: ShowInitialGuideStep(GuideStep.OverlayOverview); break;
            default: ShowInitialGuideStep(GuideStep.Complete); break;
        }
    }

    private void ContinueAfterPreparationAction()
    {
        OnboardingState.MarkPreparationCompleted();
        OnboardingState.SetFeatureTourStep(0);
        ShowFeatureTourStep(0);
    }

    private void NotifyGuidedTourAction(GuideStep action)
    {
        if (_guideMode != GuideMode.Initial)
        {
            return;
        }

        if (_guideStep == GuideStep.LoginFirst && action == GuideStep.LoginFirst)
        {
            ShowInitialGuideStep(GuideStep.OpenAccountMenu);
        }
        else if (_guideStep == GuideStep.OpenAccountMenu && action == GuideStep.OpenAccountMenu)
        {
            ShowInitialGuideStep(GuideStep.OpenIdentitySettings);
        }
        else if (_guideStep == GuideStep.OpenIdentitySettings && action == GuideStep.OpenIdentitySettings)
        {
            ShowInitialGuideStep(GuideStep.SelectLog);
        }
        else if (_guideStep == GuideStep.SelectLog && action == GuideStep.SelectLog)
        {
            ContinueAfterPreparationAction();
        }
    }

    private void GuidedTourPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode == GuideMode.OverlaySettings)
        {
            ContinueOverlayGuideAfterExplanation();
            return;
        }

        switch (_guideStep)
        {
            case GuideStep.Introduction when _introductionReadToEnd:
                OnboardingState.MarkIntroductionRead();
                ShowInitialGuideStep(IsLoggedIn ? GuideStep.OpenAccountMenu : GuideStep.LoginFirst);
                break;
            case GuideStep.LoginFirst:
                ShowInitialGuideStep(GuideStep.OpenAccountMenu);
                break;
            case GuideStep.SelectLog:
                ContinueAfterPreparationAction();
                break;
            case GuideStep.HomeOverview:
                OnboardingState.SetFeatureTourStep(1);
                ShowFeatureTourStep(1);
                break;
            case GuideStep.FindFleetOverview:
                OnboardingState.SetFeatureTourStep(2);
                ShowFeatureTourStep(2);
                break;
            case GuideStep.MyFleetOverview:
                OnboardingState.SetFeatureTourStep(3);
                ShowFeatureTourStep(3);
                break;
            case GuideStep.MySquadOverview:
                OnboardingState.SetFeatureTourStep(4);
                ShowFeatureTourStep(4);
                break;
            case GuideStep.OverlayOverview:
                OnboardingState.SetFeatureTourStep(5);
                ShowFeatureTourStep(5);
                break;
            case GuideStep.Complete:
                OnboardingState.MarkCompleted();
                HideGuidedTour();
                RefreshOnboardingSupportPanel();
                _initialGuideCompletionSource?.TrySetResult(true);
                break;
        }
    }

    private void GuidedTourSecondaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode == GuideMode.OverlaySettings)
        {
            FinishOverlaySettingsSpotlightGuide();
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

        _introductionReadToEnd = true;
        GuidedTourPrimaryButton.IsEnabled = true;
        GuidedTourProgressText.Text = "说明已阅读";
    }

    private void HideGuidedTour()
    {
        GuidedTourOverlay.Visibility = Visibility.Collapsed;
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
