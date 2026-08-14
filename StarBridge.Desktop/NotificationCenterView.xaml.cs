using StarBridge.Core.TrustSafety;
using StarBridge.Desktop.Controls;
using StarBridge.Desktop.Theming;
using System.Windows;
using System.Windows.Controls;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using Orientation = System.Windows.Controls.Orientation;

namespace StarBridge.Desktop;

public partial class NotificationCenterView : System.Windows.Controls.UserControl
{
    private readonly Func<Task<NotificationInboxContract?>> _reloadInbox;
    private readonly Func<string[], Task<NotificationInboxContract?>> _markReadAndReload;
    private readonly Func<Task<MyReportsContract?>> _loadReports;
    private readonly Func<NotificationItemContract, Task> _navigate;
    private NotificationInboxContract? _inbox;
    private bool _showingReports;

    public NotificationCenterView(
        Func<Task<NotificationInboxContract?>> reloadInbox,
        Func<string[], Task<NotificationInboxContract?>> markReadAndReload,
        Func<Task<MyReportsContract?>> loadReports,
        Func<NotificationItemContract, Task> navigate)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.System);
        _reloadInbox = reloadInbox;
        _markReadAndReload = markReadAndReload;
        _loadReports = loadReports;
        _navigate = navigate;
        ApplyTabState();
    }

    public Task ReloadAsync() => _showingReports ? ReloadReportsAsync() : ReloadInboxAsync();

    public async Task ShowReportsAsync()
    {
        _showingReports = true;
        ApplyTabState();
        await ReloadReportsAsync();
    }

    private async Task ReloadInboxAsync()
    {
        SetLoading(true, "正在读取通知…");
        try
        {
            _inbox = await _reloadInbox();
            RenderInbox();
        }
        catch
        {
            RenderUnavailable("暂时无法读取通知，请稍后重试。");
        }
        finally
        {
            SetLoading(false);
        }
    }

    private async Task ReloadReportsAsync()
    {
        SetLoading(true, "正在读取举报记录…");
        try
        {
            var reports = await _loadReports();
            RenderReports(reports);
        }
        catch
        {
            ReportsListPanel.Children.Clear();
            ShowState(
                BridgeStateKind.Error,
                "暂时无法读取举报记录",
                "请检查网络后使用右上角刷新。");
        }
        finally
        {
            SetLoading(false);
        }
    }

    private void RenderInbox()
    {
        NotificationsListPanel.Children.Clear();
        var inbox = _inbox;
        UnreadSummaryText.Text = $"未读 {inbox?.UnreadCount ?? 0}";
        ActionSummaryText.Text = $"待处理 {inbox?.ActionRequiredCount ?? 0}";
        ActionSummaryBadge.Visibility = inbox is { ActionRequiredCount: > 0 }
            ? Visibility.Visible
            : Visibility.Collapsed;
        MarkAllReadButton.IsEnabled = inbox is { UnreadCount: > 0 };

        if (inbox is null || inbox.Items.Length == 0)
        {
            ShowState(
                BridgeStateKind.Empty,
                "目前没有新的通知",
                "需要处理的好友、舰队和房间事项会显示在这里。");
            return;
        }

        HideState();

        foreach (var item in inbox.Items)
        {
            NotificationsListPanel.Children.Add(CreateNotificationCard(item));
        }
    }

    private ChamferBorder CreateNotificationCard(NotificationItemContract item)
    {
        var accent = ResolveAccent(item);
        var card = new ChamferBorder
        {
            Margin = new Thickness(0, 0, 0, 9),
            Padding = new Thickness(13, 11, 13, 11),
            Background = Token(BridgeBrushToken.PanelRaised),
            BorderBrush = Token(BridgeBrushToken.RowHairline),
            BorderThickness = new Thickness(1),
            Chamfer = 7,
            Corners = ChamferCorners.Signature,
            Opacity = item.ReadAt is null ? 1 : 0.72
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(new Border { Background = accent });

        var content = new StackPanel();
        Grid.SetColumn(content, 2);
        var meta = new StackPanel { Orientation = Orientation.Horizontal };
        meta.Children.Add(CreateLabel(CategoryLabel(item.Category), accent));
        if (item.Priority.Equals(NotificationPriorities.ActionRequired, StringComparison.OrdinalIgnoreCase))
        {
            meta.Children.Add(CreateLabel("需要处理", Token(BridgeBrushToken.StatusWarn), new Thickness(6, 0, 0, 0)));
        }
        else if (item.ReadAt is null)
        {
            meta.Children.Add(CreateLabel("未读", Token(BridgeBrushToken.StatusInfo), new Thickness(6, 0, 0, 0)));
        }
        if (item.GroupCount > 1)
        {
            meta.Children.Add(CreateLabel($"{item.GroupCount} 条", Token(BridgeBrushToken.Ink3), new Thickness(6, 0, 0, 0)));
        }
        content.Children.Add(meta);
        content.Children.Add(new TextBlock
        {
            Text = item.Title,
            Margin = new Thickness(0, 7, 0, 0),
            Foreground = Token(BridgeBrushToken.Ink),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = item.Body,
            Margin = new Thickness(0, 5, 0, 0),
            Foreground = Token(BridgeBrushToken.Ink2),
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = FormatRelativeTime(item.CreatedAt),
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = Token(BridgeBrushToken.Ink3),
            FontSize = 10
        });
        grid.Children.Add(content);

        var action = new Button
        {
            Content = item.IsAvailable ? item.ActionLabel : "内容已失效",
            MinWidth = 92,
            Height = 32,
            Margin = new Thickness(14, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            IsEnabled = item.IsAvailable,
            Tag = item
        };
        action.Click += NotificationAction_Click;
        Grid.SetColumn(action, 3);
        grid.Children.Add(action);
        card.Child = grid;
        return card;
    }

    private void RenderReports(MyReportsContract? result)
    {
        ReportsListPanel.Children.Clear();
        var reports = result?.Reports ?? [];
        if (reports.Length == 0)
        {
            ShowState(
                BridgeStateKind.Empty,
                "你还没有提交过举报",
                "举报入口位于其他用户的个人资料页。");
            return;
        }

        HideState();

        foreach (var report in reports.OrderByDescending(item => item.CreatedAt))
        {
            var panel = new StackPanel();
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.Children.Add(new TextBlock
            {
                Text = report.TargetDisplayName,
                Foreground = Token(BridgeBrushToken.Ink),
                FontSize = 14,
                FontWeight = FontWeights.SemiBold
            });
            var status = CreateLabel(ReportStatusLabel(report.Status), ReportStatusBrush(report.Status));
            Grid.SetColumn(status, 1);
            header.Children.Add(status);
            panel.Children.Add(header);
            panel.Children.Add(new TextBlock
            {
                Text = $"原因：{ReportReasonLabel(report.Reason)}",
                Margin = new Thickness(0, 7, 0, 0),
                Foreground = Token(BridgeBrushToken.Ink2),
                FontSize = 11
            });
            if (!string.IsNullOrWhiteSpace(report.Details))
            {
                panel.Children.Add(new TextBlock
                {
                    Text = report.Details,
                    Margin = new Thickness(0, 5, 0, 0),
                    Foreground = Token(BridgeBrushToken.Ink2),
                    FontSize = 11,
                    TextWrapping = TextWrapping.Wrap
                });
            }
            if (!string.IsNullOrWhiteSpace(report.OutcomeSummary))
            {
                panel.Children.Add(new Border
                {
                    Margin = new Thickness(0, 8, 0, 0),
                    Padding = new Thickness(9, 7, 9, 7),
                    Background = Token(BridgeBrushToken.Panel),
                    BorderBrush = Token(BridgeBrushToken.Hairline),
                    BorderThickness = new Thickness(1),
                    Child = new TextBlock
                    {
                        Text = $"处理说明：{report.OutcomeSummary}",
                        Foreground = Token(BridgeBrushToken.Ink),
                        FontSize = 11,
                        TextWrapping = TextWrapping.Wrap
                    }
                });
            }
            panel.Children.Add(new TextBlock
            {
                Text = report.UpdatedAt > report.CreatedAt
                    ? $"提交于 {report.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm} · 更新于 {report.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm}"
                    : $"提交于 {report.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}",
                Margin = new Thickness(0, 7, 0, 0),
                Foreground = Token(BridgeBrushToken.Ink3),
                FontSize = 10
            });

            ReportsListPanel.Children.Add(new ChamferBorder
            {
                Margin = new Thickness(0, 0, 0, 9),
                Padding = new Thickness(13),
                Background = Token(BridgeBrushToken.PanelRaised),
                BorderBrush = Token(BridgeBrushToken.RowHairline),
                BorderThickness = new Thickness(1),
                Chamfer = 7,
                Corners = ChamferCorners.Signature,
                Child = panel
            });
        }
    }

    private async void NotificationAction_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: NotificationItemContract item })
        {
            return;
        }

        await RunNotificationActionAsync(item);
    }

    internal async Task RunNotificationActionAsync(NotificationItemContract item)
    {
        SetLoading(true, "正在打开通知内容…");
        try
        {
            if (item.ActionTarget.Equals(NotificationActionTargets.MyReports, StringComparison.OrdinalIgnoreCase))
            {
                await _markReadAndReload([item.NotificationId]);
                await ShowReportsAsync();
                return;
            }

            await _markReadAndReload([item.NotificationId]);
            await _navigate(item);
        }
        catch
        {
            ShowState(
                BridgeStateKind.Error,
                "暂时无法打开通知内容",
                "操作未完成，请稍后重试或使用原页面入口。");
        }
        finally
        {
            SetLoading(false);
        }
    }

    private async void MarkAllReadButton_Click(object sender, RoutedEventArgs e)
    {
        await RunMarkAllReadAsync();
    }

    internal async Task RunMarkAllReadAsync()
    {
        var unread = _inbox?.Items.Where(item => item.ReadAt is null).Select(item => item.NotificationId).ToArray() ?? [];
        if (unread.Length == 0)
        {
            return;
        }

        SetLoading(true, "正在更新通知…");
        try
        {
            _inbox = await _markReadAndReload(unread);
            RenderInbox();
        }
        catch
        {
            ShowState(
                BridgeStateKind.Error,
                "暂时无法更新通知",
                "未能将通知标为已读，请稍后重试。");
        }
        finally
        {
            SetLoading(false);
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (_showingReports)
        {
            await ReloadReportsAsync();
        }
        else
        {
            await ReloadInboxAsync();
        }
    }

    private async void NotificationsTabButton_Click(object sender, RoutedEventArgs e)
    {
        _showingReports = false;
        ApplyTabState();
        await ReloadInboxAsync();
    }

    private async void ReportsTabButton_Click(object sender, RoutedEventArgs e) => await ShowReportsAsync();

    private void ApplyTabState()
    {
        NotificationsScrollViewer.Visibility = _showingReports ? Visibility.Collapsed : Visibility.Visible;
        ReportsScrollViewer.Visibility = _showingReports ? Visibility.Visible : Visibility.Collapsed;
        NotificationsTabButton.IsChecked = !_showingReports;
        ReportsTabButton.IsChecked = _showingReports;
        MarkAllReadButton.Visibility = _showingReports ? Visibility.Collapsed : Visibility.Visible;
        UnreadSummaryBadge.Visibility = _showingReports ? Visibility.Collapsed : Visibility.Visible;
        ActionSummaryBadge.Visibility = !_showingReports && _inbox is { ActionRequiredCount: > 0 }
            ? Visibility.Visible
            : Visibility.Collapsed;
        StatusText.Text = _showingReports
            ? "这里仅显示你提交的举报及当前处理状态。"
            : "通知只用于提醒和跳转，实际处理仍在原页面完成。";
    }

    private void SetLoading(bool loading, string? copy = null)
    {
        NotificationsScrollViewer.IsEnabled = !loading;
        ReportsScrollViewer.IsEnabled = !loading;
        if (loading)
        {
            ShowState(
                BridgeStateKind.Loading,
                copy ?? (_showingReports ? "正在读取举报记录" : "正在读取通知"),
                "通常只需要几秒。");
        }
        else if (LoadingPanel.State == BridgeStateKind.Loading)
        {
            HideState();
        }
    }

    private void RenderUnavailable(string copy)
    {
        NotificationsListPanel.Children.Clear();
        ShowState(BridgeStateKind.Error, "暂时无法读取通知", copy);
    }

    private void ShowState(BridgeStateKind state, string title, string description)
    {
        LoadingPanel.State = state;
        LoadingPanel.TitleOverride = title;
        LoadingPanel.DescriptionOverride = description;
        LoadingPanel.ActionTextOverride = string.Empty;
        LoadingPanel.Visibility = Visibility.Visible;
    }

    private void HideState() => LoadingPanel.Visibility = Visibility.Collapsed;

    private Border CreateLabel(string text, Brush brush, Thickness? margin = null) => new()
    {
        Margin = margin ?? new Thickness(0),
        Padding = new Thickness(7, 2, 7, 2),
        BorderBrush = brush,
        BorderThickness = new Thickness(1),
        Child = new TextBlock { Text = text, Foreground = brush, FontSize = 9, FontWeight = FontWeights.SemiBold }
    };

    private Brush Token(BridgeBrushToken token) => BridgeTokenBrushes.GetRequired(this, token);

    private Brush ResolveAccent(NotificationItemContract item) => item.Category switch
    {
        NotificationCategories.Fleet => BridgeScenePalette.CreateAccentBrush(BridgeSceneKind.Fleet),
        NotificationCategories.Room => BridgeScenePalette.CreateAccentBrush(BridgeSceneKind.Party),
        NotificationCategories.Safety => Token(BridgeBrushToken.StatusWarn),
        NotificationCategories.System => BridgeScenePalette.CreateAccentBrush(BridgeSceneKind.System),
        _ => BridgeScenePalette.CreateAccentBrush(BridgeSceneKind.Social)
    };

    private static string CategoryLabel(string category) => category switch
    {
        NotificationCategories.Fleet => "舰队",
        NotificationCategories.Room => "房间",
        NotificationCategories.Safety => "安全",
        NotificationCategories.System => "系统",
        _ => "好友"
    };

    private static string FormatRelativeTime(DateTimeOffset createdAt)
    {
        var elapsed = DateTimeOffset.UtcNow - createdAt.ToUniversalTime();
        if (elapsed < TimeSpan.FromMinutes(1)) return "刚刚";
        if (elapsed < TimeSpan.FromHours(1)) return $"{Math.Max(1, (int)elapsed.TotalMinutes)} 分钟前";
        if (elapsed < TimeSpan.FromDays(1)) return $"{Math.Max(1, (int)elapsed.TotalHours)} 小时前";
        if (elapsed < TimeSpan.FromDays(7)) return $"{Math.Max(1, (int)elapsed.TotalDays)} 天前";
        return createdAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
    }

    private static string ReportReasonLabel(string reason) => reason switch
    {
        ReportReasons.Harassment => "骚扰或辱骂",
        ReportReasons.Spam => "垃圾信息",
        ReportReasons.Impersonation => "冒充他人",
        ReportReasons.HateOrThreat => "仇恨或威胁",
        ReportReasons.InappropriateContent => "不当内容",
        ReportReasons.FraudOrScam => "欺诈或诈骗",
        ReportReasons.Privacy => "侵犯隐私",
        _ => "其他问题"
    };

    private static string ReportStatusLabel(string status) => ReportStatuses.Normalize(status) switch
    {
        ReportStatuses.Reviewing => "审核中",
        ReportStatuses.Actioned => "已处理",
        ReportStatuses.NoViolation => "未发现违规",
        _ => "已提交"
    };

    private Brush ReportStatusBrush(string status) => ReportStatuses.Normalize(status) switch
    {
        ReportStatuses.Reviewing => Token(BridgeBrushToken.StatusWarn),
        ReportStatuses.Actioned => Token(BridgeBrushToken.StatusOk),
        ReportStatuses.NoViolation => Token(BridgeBrushToken.StatusOff),
        _ => Token(BridgeBrushToken.StatusInfo)
    };
}
