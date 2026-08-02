using StarBridge.Core.TrustSafety;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class AppealModerationView : System.Windows.Controls.UserControl
{
    private readonly Func<string?, Task<AdminSanctionAppealQueueContract?>> _loadQueue;
    private readonly Func<string, Task<AdminSanctionAppealDetailContract?>> _loadDetail;
    private readonly Func<string, ReviewSanctionAppealRequestContract, Task<AdminSanctionAppealDetailContract?>> _review;
    private readonly string _reviewer;
    private string? _selectedAppealId;
    private bool _selectedAppealTerminal;
    private bool _loading;

    public AppealModerationView(
        Func<string?, Task<AdminSanctionAppealQueueContract?>> loadQueue,
        Func<string, Task<AdminSanctionAppealDetailContract?>> loadDetail,
        Func<string, ReviewSanctionAppealRequestContract, Task<AdminSanctionAppealDetailContract?>> review,
        string reviewer)
    {
        InitializeComponent();
        _loadQueue = loadQueue;
        _loadDetail = loadDetail;
        _review = review;
        _reviewer = reviewer;
    }

    public async Task RefreshAsync()
    {
        if (_loading)
        {
            return;
        }

        _loading = true;
        try
        {
            var filter = (QueueFilterComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
            var queue = await _loadQueue(string.IsNullOrWhiteSpace(filter) ? null : filter);
            RenderQueue(queue?.Appeals ?? []);
            StatusText.Text = "通过申诉会立即撤销原处理，请在保存前核对完整记录。";
        }
        catch
        {
            QueueListPanel.Children.Clear();
            QueueListPanel.Children.Add(CreateMessage("暂时无法读取申诉记录，请稍后重试。"));
            StatusText.Text = "读取失败，请稍后重试。";
        }
        finally
        {
            _loading = false;
        }
    }

    private void RenderQueue(AdminSanctionAppealSummaryContract[] appeals)
    {
        QueueListPanel.Children.Clear();
        if (appeals.Length == 0)
        {
            QueueListPanel.Children.Add(CreateMessage("当前筛选条件下没有申诉。"));
            return;
        }

        foreach (var item in appeals)
        {
            var button = new Button
            {
                Margin = new Thickness(0, 0, 0, 8),
                Padding = new Thickness(12),
                HorizontalContentAlignment = System.Windows.HorizontalAlignment.Stretch,
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = item.Appeal.AppealId.Equals(_selectedAppealId, StringComparison.OrdinalIgnoreCase)
                    ? new SolidColorBrush(Color.FromRgb(97, 202, 255))
                    : new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                Tag = item.Appeal.AppealId,
                Content = new TextBlock
                {
                    Text = $"{AccountSafetyView.SanctionLabel(item.Appeal.SanctionType)} · {AccountSafetyView.AppealStatusLabel(item.Appeal.Status)}\n账号：{item.AccountId}\n提交于 {item.Appeal.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}",
                    Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
                    FontSize = 11,
                    TextWrapping = TextWrapping.Wrap
                }
            };
            button.Click += QueueItem_Click;
            QueueListPanel.Children.Add(button);
        }
    }

    private async void QueueItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string appealId })
        {
            return;
        }

        _selectedAppealId = appealId;
        await LoadSelectedDetailAsync();
        await RefreshAsync();
    }

    private async Task LoadSelectedDetailAsync()
    {
        if (string.IsNullOrWhiteSpace(_selectedAppealId))
        {
            return;
        }

        try
        {
            var detail = await _loadDetail(_selectedAppealId) ??
                         throw new InvalidOperationException();
            RenderDetail(detail);
            StatusText.Text = "申诉详情已更新。";
        }
        catch
        {
            StatusText.Text = "暂时无法读取这条申诉，请稍后重试。";
        }
    }

    private void RenderDetail(AdminSanctionAppealDetailContract detail)
    {
        EmptyDetailText.Visibility = Visibility.Collapsed;
        DetailScrollViewer.Visibility = Visibility.Visible;
        DetailTitleText.Text = $"{AccountSafetyView.SanctionLabel(detail.Appeal.SanctionType)} · {AccountSafetyView.AppealStatusLabel(detail.Appeal.Status)}";
        DetailMetaText.Text = $"账号：{detail.AccountId} · 提交于 {detail.Appeal.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}";
        AppealDetailsText.Text = detail.Appeal.Details;
        SanctionDetailsText.Text = $"{detail.Sanction.Summary}\n应用于 {detail.Sanction.IssuedAt.ToLocalTime():yyyy-MM-dd HH:mm}" +
                                   (detail.Sanction.ExpiresAt is { } expiresAt ? $" · 原定恢复 {expiresAt.ToLocalTime():yyyy-MM-dd HH:mm}" : "");
        OutcomeSummaryTextBox.Text = detail.Appeal.OutcomeSummary ?? "";
        InternalNoteTextBox.Clear();
        _selectedAppealTerminal = detail.Appeal.Status is SanctionAppealStatuses.Accepted or SanctionAppealStatuses.Denied;
        SaveReviewButton.IsEnabled = !_selectedAppealTerminal;
        AuditListPanel.Children.Clear();
        foreach (var entry in detail.AuditTrail.OrderByDescending(item => item.CreatedAt))
        {
            AuditListPanel.Children.Add(new Border
            {
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(10),
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                Child = new TextBlock
                {
                    Text = $"{entry.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm} · {ActorLabel(entry.Actor)}\n{AccountSafetyView.AppealStatusLabel(entry.ToStatus)}" +
                           (string.IsNullOrWhiteSpace(entry.InternalNote) ? "" : $"\n{entry.InternalNote}"),
                    Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
                    FontSize = 10,
                    TextWrapping = TextWrapping.Wrap
                }
            });
        }
    }

    private async void SaveReviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_selectedAppealId) ||
            ReviewStatusComboBox.SelectedItem is not ComboBoxItem selected)
        {
            return;
        }

        SaveReviewButton.IsEnabled = false;
        StatusText.Text = "正在保存申诉结果…";
        try
        {
            var updated = await _review(
                _selectedAppealId,
                new ReviewSanctionAppealRequestContract(
                    selected.Tag?.ToString() ?? SanctionAppealStatuses.Reviewing,
                    _reviewer,
                    InternalNoteTextBox.Text,
                    OutcomeSummaryTextBox.Text,
                    Guid.NewGuid().ToString("N"))) ?? throw new InvalidOperationException();
            RenderDetail(updated);
            await RefreshAsync();
            StatusText.Text = updated.Appeal.Status == SanctionAppealStatuses.Accepted
                ? "申诉已通过，原处理已撤销。"
                : "申诉结果已保存。";
        }
        catch
        {
            StatusText.Text = "申诉结果暂未保存，请检查填写内容后重试。";
        }
        finally
        {
            SaveReviewButton.IsEnabled = !_selectedAppealTerminal;
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void QueueFilterComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IsLoaded)
        {
            await RefreshAsync();
        }
    }

    private FrameworkElement CreateMessage(string text) => new TextBlock
    {
        Text = text,
        Margin = new Thickness(12),
        Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
        TextAlignment = TextAlignment.Center,
        TextWrapping = TextWrapping.Wrap
    };

    private static string ActorLabel(string actor) => actor.Equals("appellant", StringComparison.OrdinalIgnoreCase)
        ? "用户提交"
        : actor;
}
