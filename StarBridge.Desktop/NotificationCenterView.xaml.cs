using StarBridge.Core.TrustSafety;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
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
        _reloadInbox = reloadInbox;
        _markReadAndReload = markReadAndReload;
        _loadReports = loadReports;
        _navigate = navigate;
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
            ReportsListPanel.Children.Add(CreateEmptyState("暂时无法读取举报记录，请稍后重试。"));
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
            NotificationsListPanel.Children.Add(CreateEmptyState("目前没有新的通知。"));
            return;
        }

        foreach (var item in inbox.Items)
        {
            NotificationsListPanel.Children.Add(CreateNotificationCard(item));
        }
    }

    private Border CreateNotificationCard(NotificationItemContract item)
    {
        var accent = ResolveAccent(item);
        var card = new Border
        {
            Margin = new Thickness(0, 0, 0, 9),
            Padding = new Thickness(13, 11, 13, 11),
            Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Opacity = item.ReadAt is null ? 1 : 0.72
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(new Border { Background = accent, CornerRadius = new CornerRadius(2) });

        var content = new StackPanel();
        Grid.SetColumn(content, 2);
        var meta = new StackPanel { Orientation = Orientation.Horizontal };
        meta.Children.Add(CreateLabel(CategoryLabel(item.Category), accent));
        if (item.Priority.Equals(NotificationPriorities.ActionRequired, StringComparison.OrdinalIgnoreCase))
        {
            meta.Children.Add(CreateLabel("需要处理", new SolidColorBrush(Color.FromRgb(255, 181, 79)), new Thickness(6, 0, 0, 0)));
        }
        else if (item.ReadAt is null)
        {
            meta.Children.Add(CreateLabel("未读", new SolidColorBrush(Color.FromRgb(97, 202, 255)), new Thickness(6, 0, 0, 0)));
        }
        if (item.GroupCount > 1)
        {
            meta.Children.Add(CreateLabel($"{item.GroupCount} 条", new SolidColorBrush(Color.FromRgb(145, 167, 181)), new Thickness(6, 0, 0, 0)));
        }
        content.Children.Add(meta);
        content.Children.Add(new TextBlock
        {
            Text = item.Title,
            Margin = new Thickness(0, 7, 0, 0),
            Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = item.Body,
            Margin = new Thickness(0, 5, 0, 0),
            Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = FormatRelativeTime(item.CreatedAt),
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = new SolidColorBrush(Color.FromRgb(91, 121, 139)),
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
            Style = FindResource("SecondaryButton") as Style,
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
            ReportsListPanel.Children.Add(CreateEmptyState("你还没有提交过举报。举报入口位于其他用户的个人资料页。"));
            return;
        }

        foreach (var report in reports.OrderByDescending(item => item.CreatedAt))
        {
            var panel = new StackPanel();
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.Children.Add(new TextBlock
            {
                Text = report.TargetDisplayName,
                Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
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
                Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
                FontSize = 11
            });
            if (!string.IsNullOrWhiteSpace(report.Details))
            {
                panel.Children.Add(new TextBlock
                {
                    Text = report.Details,
                    Margin = new Thickness(0, 5, 0, 0),
                    Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
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
                    Background = new SolidColorBrush(Color.FromRgb(11, 37, 51)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                    BorderThickness = new Thickness(1),
                    Child = new TextBlock
                    {
                        Text = $"处理说明：{report.OutcomeSummary}",
                        Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
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
                Foreground = new SolidColorBrush(Color.FromRgb(91, 121, 139)),
                FontSize = 10
            });

            ReportsListPanel.Children.Add(new Border
            {
                Margin = new Thickness(0, 0, 0, 9),
                Padding = new Thickness(13),
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
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

        if (item.ActionTarget.Equals(NotificationActionTargets.MyReports, StringComparison.OrdinalIgnoreCase))
        {
            await _markReadAndReload([item.NotificationId]);
            await ShowReportsAsync();
            return;
        }

        await _markReadAndReload([item.NotificationId]);
        await _navigate(item);
    }

    private async void MarkAllReadButton_Click(object sender, RoutedEventArgs e)
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
        NotificationsTabButton.Style = FindResource(_showingReports ? "SecondaryButton" : "PrimaryButton") as Style;
        ReportsTabButton.Style = FindResource(_showingReports ? "PrimaryButton" : "SecondaryButton") as Style;
        MarkAllReadButton.Visibility = _showingReports ? Visibility.Collapsed : Visibility.Visible;
        UnreadSummaryText.Visibility = _showingReports ? Visibility.Collapsed : Visibility.Visible;
        ActionSummaryBadge.Visibility = !_showingReports && _inbox is { ActionRequiredCount: > 0 }
            ? Visibility.Visible
            : Visibility.Collapsed;
        StatusText.Text = _showingReports
            ? "这里仅显示你提交的举报及当前处理状态。"
            : "通知只用于提醒和跳转，不会替代原页面的处理功能。";
    }

    private void SetLoading(bool loading, string? copy = null)
    {
        LoadingPanel.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
        NotificationsScrollViewer.IsEnabled = !loading;
        ReportsScrollViewer.IsEnabled = !loading;
        if (!string.IsNullOrWhiteSpace(copy) && LoadingPanel.Children.OfType<TextBlock>().FirstOrDefault() is { } text)
        {
            text.Text = copy;
        }
    }

    private void RenderUnavailable(string copy)
    {
        NotificationsListPanel.Children.Clear();
        NotificationsListPanel.Children.Add(CreateEmptyState(copy));
    }

    private FrameworkElement CreateEmptyState(string copy) => new Border
    {
        Padding = new Thickness(24),
        Child = new TextBlock
        {
            Text = copy,
            Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
            HorizontalAlignment = HorizontalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap
        }
    };

    private Border CreateLabel(string text, Brush brush, Thickness? margin = null) => new()
    {
        Margin = margin ?? new Thickness(0),
        Padding = new Thickness(7, 2, 7, 2),
        BorderBrush = brush,
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(2),
        Child = new TextBlock { Text = text, Foreground = brush, FontSize = 9, FontWeight = FontWeights.SemiBold }
    };

    private static Brush ResolveAccent(NotificationItemContract item) => item.Category switch
    {
        NotificationCategories.Fleet => new SolidColorBrush(Color.FromRgb(120, 102, 255)),
        NotificationCategories.Room => new SolidColorBrush(Color.FromRgb(84, 207, 255)),
        NotificationCategories.Safety => new SolidColorBrush(Color.FromRgb(255, 181, 79)),
        NotificationCategories.System => new SolidColorBrush(Color.FromRgb(145, 167, 181)),
        _ => new SolidColorBrush(Color.FromRgb(97, 202, 255))
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

    private static Brush ReportStatusBrush(string status) => ReportStatuses.Normalize(status) switch
    {
        ReportStatuses.Reviewing => new SolidColorBrush(Color.FromRgb(255, 181, 79)),
        ReportStatuses.Actioned => new SolidColorBrush(Color.FromRgb(64, 218, 146)),
        ReportStatuses.NoViolation => new SolidColorBrush(Color.FromRgb(145, 167, 181)),
        _ => new SolidColorBrush(Color.FromRgb(97, 202, 255))
    };
}
