using StarBridge.Core.TrustSafety;
using StarBridge.Desktop.Controls;
using StarBridge.Desktop.Theming;
using System.Windows;
using System.Windows.Controls;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class AppealModerationView : System.Windows.Controls.UserControl
{
    private readonly Func<string?, Task<AdminSanctionAppealQueueContract?>> _loadQueue;
    private readonly Func<string, Task<AdminSanctionAppealDetailContract?>> _loadDetail;
    private readonly Func<string, ReviewSanctionAppealRequestContract, Task<AdminSanctionAppealDetailContract?>> _review;
    private readonly string _reviewer;
    private string? _selectedAppealId;
    private bool _selectedAppealTerminal;
    private bool _saving;
    private long _detailRequestGeneration;
    private long _queueRequestGeneration;

    public AppealModerationView(
        Func<string?, Task<AdminSanctionAppealQueueContract?>> loadQueue,
        Func<string, Task<AdminSanctionAppealDetailContract?>> loadDetail,
        Func<string, ReviewSanctionAppealRequestContract, Task<AdminSanctionAppealDetailContract?>> review,
        string reviewer)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Review);
        _loadQueue = loadQueue;
        _loadDetail = loadDetail;
        _review = review;
        _reviewer = reviewer;
    }

    public async Task RefreshAsync()
    {
        var filter = (QueueFilterComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
        var generation = ++_queueRequestGeneration;
        ShowQueueState(
            BridgeStateKind.Loading,
            "正在读取申诉记录",
            "正在获取最新审核队列。");
        try
        {
            var queue = await _loadQueue(string.IsNullOrWhiteSpace(filter) ? null : filter);
            if (generation != _queueRequestGeneration)
            {
                return;
            }

            var appeals = queue?.Appeals ?? [];
            ReconcileSelectedAppeal(appeals);
            RenderQueue(appeals);
            if (appeals.Length == 0)
            {
                ShowQueueState(
                    BridgeStateKind.Empty,
                    "当前没有申诉记录",
                    "当前筛选条件下没有待显示的申诉。");
            }
            else
            {
                ShowQueueContent();
            }
            StatusText.Text = "通过申诉会立即撤销原处理，请在保存前核对完整记录。";
        }
        catch
        {
            if (generation != _queueRequestGeneration)
            {
                return;
            }

            ShowQueueState(
                BridgeStateKind.Error,
                "暂时无法读取申诉记录",
                "请稍后重试。");
            StatusText.Text = "读取失败，请稍后重试。";
        }
    }

    private void ShowQueueState(BridgeStateKind state, string title, string description)
    {
        QueueListPanel.Children.Clear();
        QueueScrollViewer.Visibility = Visibility.Collapsed;
        QueueStatePanel.State = state;
        QueueStatePanel.TitleOverride = title;
        QueueStatePanel.DescriptionOverride = description;
        QueueStatePanel.ActionTextOverride = "";
        QueueStatePanel.Visibility = Visibility.Visible;
    }

    private void ShowQueueContent()
    {
        QueueStatePanel.Visibility = Visibility.Collapsed;
        QueueScrollViewer.Visibility = Visibility.Visible;
    }

    private void ShowDetailState(BridgeStateKind state, string title, string description)
    {
        DetailScrollViewer.Visibility = Visibility.Collapsed;
        DetailStatePanel.State = state;
        DetailStatePanel.TitleOverride = title;
        DetailStatePanel.DescriptionOverride = description;
        DetailStatePanel.ActionTextOverride = "";
        DetailStatePanel.Visibility = Visibility.Visible;
    }

    private void ShowDetailContent()
    {
        DetailStatePanel.Visibility = Visibility.Collapsed;
        DetailScrollViewer.Visibility = Visibility.Visible;
    }

    private void ReconcileSelectedAppeal(AdminSanctionAppealSummaryContract[] appeals)
    {
        if (string.IsNullOrWhiteSpace(_selectedAppealId) ||
            appeals.Any(item => item.Appeal.AppealId.Equals(_selectedAppealId, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        _selectedAppealId = null;
        _selectedAppealTerminal = false;
        _detailRequestGeneration++;
        SaveReviewButton.IsEnabled = false;
        ShowDetailState(
            BridgeStateKind.Empty,
            "选择一条申诉查看详情",
            "审核内容会显示在这里。");
    }

    private void RenderQueue(AdminSanctionAppealSummaryContract[] appeals)
    {
        QueueListPanel.Children.Clear();

        foreach (var item in appeals)
        {
            var button = new Button
            {
                Margin = new Thickness(0, 0, 0, 8),
                Padding = new Thickness(12),
                HorizontalContentAlignment = System.Windows.HorizontalAlignment.Stretch,
                Background = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.PanelRaised),
                BorderBrush = item.Appeal.AppealId.Equals(_selectedAppealId, StringComparison.OrdinalIgnoreCase)
                    ? Theming.BridgeSceneContext.GetRequiredAccentBrush(this)
                    : Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Hairline),
                BorderThickness = new Thickness(1),
                Tag = item.Appeal.AppealId,
                Content = new TextBlock
                {
                    Text = $"{AccountSafetyView.SanctionLabel(item.Appeal.SanctionType)} · {AccountSafetyView.AppealStatusLabel(item.Appeal.Status)}\n账号：{item.AccountId}\n提交于 {item.Appeal.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}",
                    Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink),
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
        var generation = ++_detailRequestGeneration;
        await LoadSelectedDetailAsync(appealId, generation);
        if (IsCurrentDetailRequest(appealId, generation))
        {
            await RefreshAsync();
        }
    }

    private async Task LoadSelectedDetailAsync(string appealId, long generation)
    {
        if (!IsCurrentDetailRequest(appealId, generation))
        {
            return;
        }

        ShowDetailState(
            BridgeStateKind.Loading,
            "正在读取申诉详情",
            "正在核对最新记录。");
        try
        {
            var detail = await _loadDetail(appealId) ??
                         throw new InvalidOperationException();
            if (!IsCurrentDetailRequest(appealId, generation))
            {
                return;
            }

            RenderDetail(detail);
            StatusText.Text = "申诉详情已更新。";
        }
        catch
        {
            if (!IsCurrentDetailRequest(appealId, generation))
            {
                return;
            }

            ShowDetailState(
                BridgeStateKind.Error,
                "暂时无法读取这条申诉",
                "请稍后重试，旧详情已隐藏。");
            StatusText.Text = "暂时无法读取这条申诉，请稍后重试。";
        }
    }

    private bool IsCurrentDetailRequest(string appealId, long generation) =>
        generation == _detailRequestGeneration &&
        string.Equals(appealId, _selectedAppealId, StringComparison.OrdinalIgnoreCase);

    private void RenderDetail(AdminSanctionAppealDetailContract detail)
    {
        ShowDetailContent();
        DetailTitleText.Text = $"{AccountSafetyView.SanctionLabel(detail.Appeal.SanctionType)} · {AccountSafetyView.AppealStatusLabel(detail.Appeal.Status)}";
        DetailMetaText.Text = $"账号：{detail.AccountId} · 提交于 {detail.Appeal.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}";
        AppealDetailsText.Text = detail.Appeal.Details;
        SanctionDetailsText.Text = $"{detail.Sanction.Summary}\n应用于 {detail.Sanction.IssuedAt.ToLocalTime():yyyy-MM-dd HH:mm}" +
                                   (detail.Sanction.ExpiresAt is { } expiresAt ? $" · 原定恢复 {expiresAt.ToLocalTime():yyyy-MM-dd HH:mm}" : "");
        OutcomeSummaryTextBox.Text = detail.Appeal.OutcomeSummary ?? "";
        InternalNoteTextBox.Clear();
        _selectedAppealTerminal = detail.Appeal.Status is SanctionAppealStatuses.Accepted or SanctionAppealStatuses.Denied;
        SaveReviewButton.IsEnabled = !_saving && !_selectedAppealTerminal;
        AuditListPanel.Children.Clear();
        foreach (var entry in detail.AuditTrail.OrderByDescending(item => item.CreatedAt))
        {
            AuditListPanel.Children.Add(new Border
            {
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(10),
                Background = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.PanelRaised),
                BorderBrush = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Hairline),
                BorderThickness = new Thickness(1),
                Child = new TextBlock
                {
                    Text = $"{entry.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm} · {ActorLabel(entry.Actor)}\n{AccountSafetyView.AppealStatusLabel(entry.ToStatus)}" +
                           (string.IsNullOrWhiteSpace(entry.InternalNote) ? "" : $"\n{entry.InternalNote}"),
                    Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink2),
                    FontSize = 10,
                    TextWrapping = TextWrapping.Wrap
                }
            });
        }
    }

    private async void SaveReviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (_saving ||
            string.IsNullOrWhiteSpace(_selectedAppealId) ||
            ReviewStatusComboBox.SelectedItem is not ComboBoxItem selected)
        {
            return;
        }

        var appealId = _selectedAppealId;
        var detailGeneration = _detailRequestGeneration;
        _saving = true;
        SaveReviewButton.IsEnabled = false;
        OperationLoadingIndicator.IsActive = true;
        OperationLoadingIndicator.Visibility = Visibility.Visible;
        StatusText.Text = "正在保存申诉结果…";
        try
        {
            var updated = await _review(
                appealId,
                new ReviewSanctionAppealRequestContract(
                    selected.Tag?.ToString() ?? SanctionAppealStatuses.Reviewing,
                    _reviewer,
                    InternalNoteTextBox.Text,
                    OutcomeSummaryTextBox.Text,
                    Guid.NewGuid().ToString("N"))) ?? throw new InvalidOperationException();
            if (!IsCurrentDetailRequest(appealId, detailGeneration))
            {
                return;
            }

            RenderDetail(updated);
            await RefreshAsync();
            if (!IsCurrentDetailRequest(appealId, detailGeneration))
            {
                return;
            }

            StatusText.Text = updated.Appeal.Status == SanctionAppealStatuses.Accepted
                ? "申诉已通过，原处理已撤销。"
                : "申诉结果已保存。";
        }
        catch
        {
            if (!IsCurrentDetailRequest(appealId, detailGeneration))
            {
                return;
            }

            StatusText.Text = "申诉结果暂未保存，请检查填写内容后重试。";
        }
        finally
        {
            _saving = false;
            OperationLoadingIndicator.IsActive = false;
            OperationLoadingIndicator.Visibility = Visibility.Collapsed;
            SaveReviewButton.IsEnabled = !string.IsNullOrWhiteSpace(_selectedAppealId) &&
                                         DetailScrollViewer.Visibility == Visibility.Visible &&
                                         !_selectedAppealTerminal;
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

    private static string ActorLabel(string actor) => actor.Equals("appellant", StringComparison.OrdinalIgnoreCase)
        ? "用户提交"
        : actor;
}
