using System.Windows;
using System.Windows.Input;

namespace StarBridge.Desktop;

public partial class OverlaySettingsGuideWindow : Window
{
    private sealed record GuidePage(
        string Key,
        string Title,
        string Summary,
        string Detail);

    private sealed record GuideStepRow(string Number, string Title);

    private static readonly GuidePage[] Pages =
    [
        new("overview", "总览", "先确认当前预设、模块和启动状态。",
            "总览用于快速检查这套浮层是否符合预期。建议先查看当前预设、模块数量和显示状态，再进入具体设置。右侧屏幕布局始终是最终游戏画面的编辑参考。"),
        new("preset", "预设与布局", "保存不同用途的整套配置。",
            "预设会组合布局与显示设置。可以为舰队行动、临时组队或简洁模式保存不同方案。切换后先预览，再保存更改；恢复默认布局只影响当前编辑内容。"),
        new("modules", "模块", "决定画面中显示哪些信息；位置与顺序在画布编辑中调整。",
            "选择模块后，可以调整显示、尺寸、图层顺序和锁定状态。减少低价值模块能让战斗画面更清晰；事件、成员和通讯模块应按实际使用优先级排列。"),
        new("placement", "画布编辑", "在屏幕比例画布中拖动、缩放和吸附模块。",
            "画布编辑提供网格、吸附、边缘对齐和布局锁定。右侧的全屏预览可以进入接近真实屏幕尺寸的编辑模式：拖动模块改变位置，拖动右下角缩放，使用工具面板精确调整锚点和尺寸。退出全屏预览前仍需保存更改。"),
        new("events", "事件通知", "选择哪些即时事件进入游戏浮层。",
            "在这里管理成员进出服务器、倒地与死亡、量子航行、通讯和连续游玩提醒等事件。只保留行动中真正需要的信息，避免事件栏持续占据注意力。"),
        new("appearance", "外观风格", "统一浮层的主题、色彩、透明度与泛光。",
            "外观风格控制整体视觉语言。主题色可以使用应用色板精确设置；透明度和泛光应优先保证游戏画面可读性。部分高级外观可能需要对应权限。"),
        new("motion", "转场与动效", "让出现、切换和隐藏反馈与当前风格一致。",
            "每种外观只保留与其匹配的转场。动效用于说明状态变化，不应遮挡操作；如果设备性能有限，可以优先降低动态表现，同时保留必要反馈。"),
        new("crosshair", "虚拟准星", "选择准星类型并调整可读性。",
            "支持十字、点、圆形和 T 形等常用准星。可调整尺寸、粗细、间距、中心标记、描边、颜色和透明度。建议先在全屏预览中确认，再进入游戏。"),
        new("startup", "启动与热键", "控制全局热键及游戏窗口联动。",
            "启用全局热键后，可以在游戏中切换浮层。这里会显示热键注册状态；若发生冲突，请更换组合。启动联动决定进入或返回游戏窗口时是否自动调整浮层状态。"),
        new("background", "显示行为", "决定不同场景、主窗口状态与游戏状态下显示什么。",
            "显示行为负责场景来源、游戏窗口联动和主窗口最小化时的表现。使用自动场景时，舰队与房间上下文会决定内容；手动场景适合固定演示或排查布局。")
    ];

    private readonly Action<string> _navigateToSection;
    private int _pageIndex;

    public OverlaySettingsGuideWindow(Action<string> navigateToSection)
    {
        InitializeComponent();
        _navigateToSection = navigateToSection;
        GuideStepsList.ItemsSource = Pages
            .Select((page, index) => new GuideStepRow($"{index + 1:00}", page.Title))
            .ToArray();
        ShowPage(0);
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        MainWindowPlacementService.FitInitialWindow(this);
    }

    private void ShowPage(int index)
    {
        _pageIndex = Math.Clamp(index, 0, Pages.Length - 1);
        var page = Pages[_pageIndex];
        GuideStepsList.SelectedIndex = _pageIndex;
        GuideStepsList.ScrollIntoView(GuideStepsList.SelectedItem);
        GuideStepCounterText.Text = $"{_pageIndex + 1:00} / {Pages.Length:00}";
        GuidePageTitleText.Text = page.Title;
        GuidePageSummaryText.Text = page.Summary;
        GuidePageDetailText.Text = page.Detail;
        GuideFooterText.Text = $"{_pageIndex + 1} / {Pages.Length}";
        PreviousButton.IsEnabled = _pageIndex > 0;
        NextButton.Content = _pageIndex == Pages.Length - 1 ? "完成引导" : "下一项";
        _navigateToSection(page.Key);
    }

    private void PreviousButton_Click(object sender, RoutedEventArgs e) => ShowPage(_pageIndex - 1);

    private void NextButton_Click(object sender, RoutedEventArgs e)
    {
        if (_pageIndex >= Pages.Length - 1)
        {
            DialogResult = true;
            return;
        }

        ShowPage(_pageIndex + 1);
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }
}
