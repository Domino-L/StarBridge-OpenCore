using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace StarBridge.Desktop;

internal enum OnboardingFlowStage
{
    Introduction,
    Preparation,
    FeatureTour
}

internal enum OnboardingNextAction
{
    None,
    ReadIntroduction,
    Login,
    OpenIdentitySettings,
    SelectLog,
    QuickScanLog,
    BindIdentity,
    BeginFeatureTour,
    FindFleet,
    MyFleet,
    CreateFleet,
    MySquad,
    Overlay,
    Profile,
    Complete,
    ExitApplication
}

public partial class OnboardingWindow : Window
{
    private sealed record FeatureTourPage(
        string Title,
        string Route,
        string Summary,
        string Detail,
        string ActionText,
        OnboardingNextAction Action);

    private static readonly FeatureTourPage[] FeatureTourPages =
    [
        new(
            "寻找组织",
            "顶部导航  /  寻找组织",
            "浏览公开组织，按玩法、语言、加入方式和活跃时间筛选。",
            "这里是加入长期组织的入口。你可以查看组织介绍、公开公告、规模、标签和申请条件，再提交加入申请。",
            "打开寻找组织",
            OnboardingNextAction.FindFleet),
        new(
            "我的组织",
            "顶部导航  /  我的组织",
            "查看组织成员、聊天、事件、指挥与舰船信息。",
            "加入组织后，这里会成为主要协作空间。不同权限的成员会看到对应的管理入口；尚未加入时则会显示申请与创建引导。",
            "打开我的组织",
            OnboardingNextAction.MyFleet),
        new(
            "组队大厅",
            "顶部导航  /  组队大厅",
            "寻找临时队友或创建房间，不会改变你的组织成员关系。",
            "房间适合一次性的游戏活动。可以设置目标、玩法、语言和加入条件，并邀请好友进入；房间关闭后临时上下文随之结束。",
            "打开组队大厅",
            OnboardingNextAction.MySquad),
        new(
            "游戏浮层",
            "顶部导航  /  游戏浮层",
            "配置游戏内成员状态、通讯事件、布局与虚拟准星。",
            "首次这里只介绍入口。完成初步引导后，当你再次进入游戏浮层时，应用会询问是否查看详细设置引导。",
            "打开游戏浮层",
            OnboardingNextAction.Overlay),
        new(
            "个人资料",
            "右上角头像  /  查看个人资料",
            "维护公开身份、简介、可游玩时间、游戏定位和个人机库展示。",
            "你的头像同时也是账号菜单入口。可以从这里查看个人资料、返回账号与识别、切换账号或退出登录。资料公开范围仍由你控制。",
            "打开个人资料",
            OnboardingNextAction.Profile)
    ];

    private readonly OnboardingFlowStage _stage;
    private readonly int _featureTourStep;
    private bool _allowClose;

    internal OnboardingNextAction NextAction { get; private set; } = OnboardingNextAction.None;

    internal OnboardingWindow(
        OnboardingFlowStage stage,
        bool isLoggedIn,
        bool hasLog,
        bool identityVerified,
        string? detectedGameId,
        int featureTourStep)
    {
        InitializeComponent();
        _stage = stage;
        _featureTourStep = Math.Clamp(featureTourStep, 0, FeatureTourPages.Length);
        var preparationReady = isLoggedIn && hasLog && identityVerified;

        AccountPreparationStatusText.Text = isLoggedIn
            ? "已登录 · 多人同步账号已就绪"
            : "未登录 · 先登录或注册以启用多人同步";
        PreparationLoginButton.Content = isLoggedIn ? "已登录" : "登录 / 注册";
        PreparationLoginButton.IsEnabled = !isLoggedIn;

        LogPreparationStatusText.Text = hasLog
            ? "已选择 Game.log · 应用会持续监控新的游戏事件"
            : "尚未选择 · 文件通常位于 StarCitizen\\LIVE\\Game.log";

        IdentityPreparationStatusText.Text = identityVerified
            ? $"已验证{FormatGameId(detectedGameId)}"
            : !isLoggedIn
                ? "登录后可以绑定日志识别到的游戏 ID"
                : !hasLog
                    ? "选择 Game.log 后开始识别游戏 ID"
                    : string.IsNullOrWhiteSpace(detectedGameId)
                        ? "等待日志识别游戏 ID · 可以先启动一次 Star Citizen"
                        : $"待绑定{FormatGameId(detectedGameId)}";
        BindIdentityButton.Content = identityVerified ? "已完成" : "绑定身份";
        BindIdentityButton.IsEnabled = isLoggedIn && hasLog && !identityVerified &&
                                               !string.IsNullOrWhiteSpace(detectedGameId);

        PreparationGateText.Text = preparationReady
            ? "账号、日志与身份均已就绪。可以进入功能导览。"
            : BuildPreparationGateText(isLoggedIn, hasLog, identityVerified);
        PreparationGateText.Foreground = preparationReady
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusWarningBrush", Brushes.Goldenrod);
        PreparationGateBanner.BorderBrush = preparationReady
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : new SolidColorBrush(Color.FromRgb(107, 84, 32));

        ApplyStage(preparationReady);
        Loaded += (_, _) =>
        {
            if (_stage == OnboardingFlowStage.Introduction)
            {
                Dispatcher.BeginInvoke(DispatcherPriority.Loaded, UpdateIntroductionReadState);
            }
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        MainWindowPlacementService.FitInitialWindow(this);
    }

    private void ApplyStage(bool preparationReady)
    {
        IntroductionPanel.Visibility = _stage == OnboardingFlowStage.Introduction
            ? Visibility.Visible
            : Visibility.Collapsed;
        PreparationPanel.Visibility = _stage == OnboardingFlowStage.Preparation
            ? Visibility.Visible
            : Visibility.Collapsed;
        FeatureTourPanel.Visibility = _stage == OnboardingFlowStage.FeatureTour
            ? Visibility.Visible
            : Visibility.Collapsed;

        ApplyRailState(IntroductionStageRail, _stage == OnboardingFlowStage.Introduction);
        ApplyRailState(PreparationStageRail, _stage == OnboardingFlowStage.Preparation);
        ApplyRailState(FeatureTourStageRail, _stage == OnboardingFlowStage.FeatureTour);

        switch (_stage)
        {
            case OnboardingFlowStage.Introduction:
                StageHeaderText.Text = "01 · 阅读使用说明";
                FooterStatusText.Text = "阅读到底后才能继续";
                FooterPrimaryButton.Content = "已阅读，继续";
                FooterPrimaryButton.IsEnabled = false;
                break;
            case OnboardingFlowStage.Preparation:
                StageHeaderText.Text = "02 · 建立账号与游戏身份链路";
                FooterStatusText.Text = preparationReady
                    ? "准备完成"
                    : "完成登录、日志选择与身份绑定后继续";
                FooterPrimaryButton.Content = "进入功能导览";
                FooterPrimaryButton.IsEnabled = preparationReady;
                break;
            default:
                StageHeaderText.Text = "03 · 浏览主要功能";
                ApplyFeatureTourPage();
                break;
        }
    }

    private void ApplyFeatureTourPage()
    {
        if (_featureTourStep >= FeatureTourPages.Length)
        {
            FeatureTourEyebrowText.Text = "READY / 5 OF 5";
            FeatureTourTitleText.Text = "初步引导已完成";
            FeatureTourSummaryText.Text = "你已经了解账号身份链路和主要功能入口。";
            FeatureTourRouteText.Text = "下一步  /  隐私与数据授权";
            FeatureTourDetailText.Text =
                "完成后，应用才会分别询问是否允许记录游玩时长、是否参与地点代码采集。每一项都可以独立选择，未允许的采集不会启动。";
            FooterStatusText.Text = "完成后进入应用";
            FooterPrimaryButton.Content = "完成初步引导";
            FooterPrimaryButton.IsEnabled = true;
            return;
        }

        var page = FeatureTourPages[_featureTourStep];
        FeatureTourEyebrowText.Text = $"功能导览 {_featureTourStep + 1} / {FeatureTourPages.Length}";
        FeatureTourTitleText.Text = page.Title;
        FeatureTourSummaryText.Text = page.Summary;
        FeatureTourRouteText.Text = page.Route;
        FeatureTourDetailText.Text = page.Detail;
        FooterStatusText.Text = $"第 {_featureTourStep + 1} 项，共 {FeatureTourPages.Length} 项";
        FooterPrimaryButton.Content = page.ActionText;
        FooterPrimaryButton.IsEnabled = true;
    }

    private void IntroductionScrollViewer_ScrollChanged(object sender, System.Windows.Controls.ScrollChangedEventArgs e) =>
        UpdateIntroductionReadState();

    private void UpdateIntroductionReadState()
    {
        if (_stage != OnboardingFlowStage.Introduction)
        {
            return;
        }

        var hasReachedBottom = IntroductionScrollViewer.ScrollableHeight <= 1 ||
                               IntroductionScrollViewer.VerticalOffset >=
                               IntroductionScrollViewer.ScrollableHeight - 1;
        FooterPrimaryButton.IsEnabled = hasReachedBottom;
        IntroductionReadHintText.Text = hasReachedBottom
            ? "已阅读到末尾，可以继续"
            : "继续向下阅读以解锁下一步";
        IntroductionReadHintText.Foreground = hasReachedBottom
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusWarningBrush", Brushes.Goldenrod);
    }

    private void FooterPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        var action = _stage switch
        {
            OnboardingFlowStage.Introduction => OnboardingNextAction.ReadIntroduction,
            OnboardingFlowStage.Preparation => OnboardingNextAction.BeginFeatureTour,
            _ when _featureTourStep >= FeatureTourPages.Length => OnboardingNextAction.Complete,
            _ => FeatureTourPages[_featureTourStep].Action
        };
        CompleteWithAction(action);
    }

    private void PreparationLoginButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.Login);

    private void OpenIdentitySettingsButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.OpenIdentitySettings);

    private void SelectLogButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.SelectLog);

    private void QuickScanLogButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.QuickScanLog);

    private void BindIdentityButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.BindIdentity);

    private void ExitApplicationButton_Click(object sender, RoutedEventArgs e) =>
        CompleteWithAction(OnboardingNextAction.ExitApplication);

    private void CompleteWithAction(OnboardingNextAction action)
    {
        NextAction = action;
        _allowClose = true;
        DialogResult = true;
    }

    private void OnboardingWindow_Closing(object? sender, CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
        }
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void ApplyRailState(FrameworkElement rail, bool isActive)
    {
        if (rail is not System.Windows.Controls.Border border)
        {
            return;
        }

        border.Background = isActive
            ? new SolidColorBrush(Color.FromRgb(19, 46, 64))
            : new SolidColorBrush(Color.FromRgb(8, 23, 34));
        border.BorderBrush = isActive
            ? FindBrush("AccentBrush", Brushes.DeepSkyBlue)
            : new SolidColorBrush(Color.FromRgb(36, 71, 92));
    }

    private Brush FindBrush(string key, Brush fallback) => FindResource(key) as Brush ?? fallback;

    private static string BuildPreparationGateText(bool isLoggedIn, bool hasLog, bool identityVerified)
    {
        var pending = new List<string>();
        if (!isLoggedIn)
        {
            pending.Add("登录账号");
        }

        if (!hasLog)
        {
            pending.Add("选择 Game.log");
        }

        if (!identityVerified)
        {
            pending.Add("绑定游戏身份");
        }

        return $"还需完成：{string.Join("、", pending)}。";
    }

    private static string FormatGameId(string? gameId) =>
        string.IsNullOrWhiteSpace(gameId) ? "" : $" · {gameId.Trim()}";
}
