using StarBridge.Core.TrustSafety;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class ReportModerationView : System.Windows.Controls.UserControl
{
    private readonly Func<string?, Task<AdminReportQueueContract?>> _loadQueue;
    private readonly Func<string, Task<AdminReportDetailContract?>> _loadDetail;
    private readonly Func<string, ReviewReportRequestContract, Task<AdminReportDetailContract?>> _review;
    private readonly string _reviewer;
    private string? _selectedReportId;
    private bool _loading;

    public ReportModerationView(
        Func<string?, Task<AdminReportQueueContract?>> loadQueue,
        Func<string, Task<AdminReportDetailContract?>> loadDetail,
        Func<string, ReviewReportRequestContract, Task<AdminReportDetailContract?>> review,
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
        QueueLoadingPanel.Visibility = Visibility.Visible;
        StatusText.Text = "正在读取举报记录…";
        try
        {
            var filter = (QueueFilterComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
            var queue = await _loadQueue(string.IsNullOrWhiteSpace(filter) ? null : filter);
            RenderQueue(queue?.Reports ?? []);
            StatusText.Text = "处理结果会记录时间与审核人，保存前请再次确认。";
        }
        catch (Exception ex)
        {
            QueueListPanel.Children.Clear();
            QueueListPanel.Children.Add(CreateMessage("暂时无法读取举报记录，请稍后重试。"));
            StatusText.Text = $"读取失败：{ex.Message}";
        }
        finally
        {
            QueueLoadingPanel.Visibility = Visibility.Collapsed;
            _loading = false;
        }
    }

    private void RenderQueue(AdminReportSummaryContract[] reports)
    {
        QueueListPanel.Children.Clear();
        QueueCountText.Text = $"{reports.Length} 条";
        if (reports.Length == 0)
        {
            QueueListPanel.Children.Add(CreateMessage("当前筛选条件下没有举报。"));
            return;
        }

        foreach (var item in reports)
        {
            var button = new Button
            {
                Style = FindResource("ReportModerationQueueItemButton") as Style,
                Margin = new Thickness(0, 0, 0, 8),
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = item.Report.ReportId.Equals(_selectedReportId, StringComparison.OrdinalIgnoreCase)
                    ? new SolidColorBrush(Color.FromRgb(97, 202, 255))
                    : new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                Tag = item.Report.ReportId,
                Content = BuildQueueCard(item)
            };
            button.Click += QueueItem_Click;
            QueueListPanel.Children.Add(button);
        }
    }

    private FrameworkElement BuildQueueCard(AdminReportSummaryContract item)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock
        {
            Text = item.Report.TargetDisplayName,
            Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        panel.Children.Add(new TextBlock
        {
            Text = $"{ReasonLabel(item.Report.Reason)} · {StatusLabel(item.Report.Status)}",
            Margin = new Thickness(0, 5, 0, 0),
            Foreground = StatusBrush(item.Report.Status),
            FontSize = 10
        });
        panel.Children.Add(new TextBlock
        {
            Text = $"提交于 {item.Report.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm} · 记录 {item.AuditEntryCount} 条",
            Margin = new Thickness(0, 5, 0, 0),
            Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
            FontSize = 9
        });
        return panel;
    }

    private async void QueueItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string reportId })
        {
            return;
        }

        _selectedReportId = reportId;
        await LoadSelectedDetailAsync();
        await RefreshAsync();
    }

    private async Task LoadSelectedDetailAsync()
    {
        if (string.IsNullOrWhiteSpace(_selectedReportId))
        {
            return;
        }

        StatusText.Text = "正在读取举报详情…";
        try
        {
            var detail = await _loadDetail(_selectedReportId);
            if (detail is null)
            {
                throw new InvalidOperationException("这条举报记录已不存在。");
            }

            RenderDetail(detail);
            StatusText.Text = "举报详情已更新。";
        }
        catch (Exception ex)
        {
            StatusText.Text = $"读取失败：{ex.Message}";
        }
    }

    private void RenderDetail(AdminReportDetailContract detail)
    {
        EmptyDetailText.Visibility = Visibility.Collapsed;
        DetailScrollViewer.Visibility = Visibility.Visible;
        DetailTargetText.Text = detail.Report.TargetDisplayName;
        DetailMetaText.Text = $"举报人账号：{detail.ReporterAccountId} · 来源：{ContextLabel(detail.Report.ContextType)} · 提交于 {detail.Report.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm}";
        DetailStatusText.Text = StatusLabel(detail.Report.Status);
        DetailStatusText.Foreground = StatusBrush(detail.Report.Status);
        DetailStatusBadge.BorderBrush = StatusBrush(detail.Report.Status);
        DetailReasonText.Text = $"原因：{ReasonLabel(detail.Report.Reason)}";
        DetailBodyText.Text = string.IsNullOrWhiteSpace(detail.Report.Details) ? "举报人没有填写补充说明。" : detail.Report.Details;
        DetailSnapshotText.Text = $"显示名称：{detail.TargetSnapshot.DisplayName}\n游戏账号：{DisplayOrFallback(detail.TargetSnapshot.GameName)}\n呼号：{DisplayOrFallback(detail.TargetSnapshot.Callsign)}\n记录时间：{detail.TargetSnapshot.CapturedAt.ToLocalTime():yyyy-MM-dd HH:mm}";
        RenderEvidence(detail.Evidence);
        OutcomeSummaryTextBox.Text = detail.Report.OutcomeSummary ?? "";
        InternalNoteTextBox.Clear();
        SanctionTypeComboBox.SelectedIndex = 0;
        SanctionDurationTextBox.Text = "24";
        SelectReviewStatus(detail.Report.Status);

        AuditListPanel.Children.Clear();
        foreach (var entry in detail.AuditTrail.OrderByDescending(item => item.CreatedAt))
        {
            var text = new TextBlock
            {
                Text = $"{entry.CreatedAt.ToLocalTime():yyyy-MM-dd HH:mm} · {ActorLabel(entry.Actor)}\n{StatusLabel(entry.FromStatus)} → {StatusLabel(entry.ToStatus)}" +
                       (string.IsNullOrWhiteSpace(entry.InternalNote) ? "" : $"\n{entry.InternalNote}"),
                Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
                FontSize = 10,
                TextWrapping = TextWrapping.Wrap
            };
            AuditListPanel.Children.Add(new Border
            {
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(10),
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                Child = text
            });
        }

        SanctionListPanel.Children.Clear();
        var sanctions = detail.Sanctions ?? [];
        if (sanctions.Length == 0)
        {
            SanctionListPanel.Children.Add(CreateMessage("尚未应用账号处理。"));
        }
        else
        {
            foreach (var sanction in sanctions.OrderByDescending(item => item.IssuedAt))
            {
                SanctionListPanel.Children.Add(new Border
                {
                    Margin = new Thickness(0, 0, 0, 7),
                    Padding = new Thickness(10),
                    Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                    BorderThickness = new Thickness(1),
                    Child = new TextBlock
                    {
                        Text = $"{AccountSafetyView.SanctionLabel(sanction.Type)} · {sanction.IssuedAt.ToLocalTime():yyyy-MM-dd HH:mm}\n{sanction.Summary}\n{SanctionExpiryLabel(sanction)}",
                        Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
                        FontSize = 10,
                        TextWrapping = TextWrapping.Wrap
                    }
                });
            }
        }
    }

    private void RenderEvidence(ReportEvidenceSnapshotContract? evidence)
    {
        EvidenceListPanel.Children.Clear();
        if (evidence is null)
        {
            EvidenceScopeText.Text = "这条记录创建时尚未启用证据快照。请根据举报说明和账号快照谨慎判断。";
            EvidenceListPanel.Children.Add(CreateMessage("没有随举报保存的附加证据。"));
            return;
        }

        EvidenceScopeText.Text = $"{evidence.ScopeExplanation} 保存于 {evidence.CapturedAt.ToLocalTime():yyyy-MM-dd HH:mm}。";
        if (evidence.Items.Length == 0)
        {
            EvidenceListPanel.Children.Add(CreateMessage("当时没有可随举报保存的相关文字内容。"));
            return;
        }

        foreach (var item in evidence.Items.OrderByDescending(item => item.CapturedAt))
        {
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition());
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.Children.Add(new TextBlock
            {
                Text = $"{EvidenceCategoryLabel(item.Category)} · {item.Label}",
                Foreground = new SolidColorBrush(Color.FromRgb(97, 202, 255)),
                FontSize = 10,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
            var time = new TextBlock
            {
                Text = item.CapturedAt.ToLocalTime().ToString("MM-dd HH:mm"),
                Margin = new Thickness(10, 0, 0, 0),
                Foreground = FindResource("MutedTextBrush") as Brush ?? Brushes.LightGray,
                FontSize = 9
            };
            Grid.SetColumn(time, 1);
            header.Children.Add(time);

            var content = new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(item.Content) ? "仅包含附件或非文字内容。" : item.Content,
                Margin = new Thickness(0, 7, 0, 0),
                Foreground = FindResource("PrimaryTextBrush") as Brush ?? Brushes.White,
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap
            };
            var panel = new StackPanel();
            panel.Children.Add(header);
            panel.Children.Add(content);
            EvidenceListPanel.Children.Add(new Border
            {
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(10),
                Background = new SolidColorBrush(Color.FromRgb(9, 27, 39)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(35, 77, 99)),
                BorderThickness = new Thickness(1),
                Child = panel
            });
        }
    }

    private async void SaveReviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_selectedReportId) ||
            ReviewStatusComboBox.SelectedItem is not ComboBoxItem selected)
        {
            return;
        }

        var status = selected.Tag?.ToString() ?? ReportStatuses.Reviewing;
        var sanctionType = (SanctionTypeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
        int? sanctionDurationHours = null;
        if (!string.IsNullOrWhiteSpace(sanctionType) &&
            sanctionType != AccountSanctionTypes.Warning &&
            !string.IsNullOrWhiteSpace(SanctionDurationTextBox.Text))
        {
            if (!int.TryParse(SanctionDurationTextBox.Text.Trim(), out var duration) ||
                duration is < 1 or > 87_600)
            {
                StatusText.Text = "持续时间应在 1 小时到 10 年之间。";
                return;
            }

            sanctionDurationHours = duration;
        }

        SaveReviewButton.IsEnabled = false;
        StatusText.Text = "正在保存处理结果…";
        try
        {
            var updated = await _review(
                _selectedReportId,
                new ReviewReportRequestContract(
                    status,
                    _reviewer,
                    InternalNoteTextBox.Text,
                    OutcomeSummaryTextBox.Text,
                    string.IsNullOrWhiteSpace(sanctionType) ? null : sanctionType,
                    sanctionDurationHours,
                    Guid.NewGuid().ToString("N")));
            if (updated is null)
            {
                throw new InvalidOperationException("服务没有返回更新后的举报记录。");
            }

            RenderDetail(updated);
            await RefreshAsync();
            StatusText.Text = "处理结果已保存，相关用户会在“我的举报”中看到最新状态。";
        }
        catch (Exception ex)
        {
            StatusText.Text = $"保存失败：{ex.Message}";
        }
        finally
        {
            SaveReviewButton.IsEnabled = true;
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

    private void SanctionTypeComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SanctionDurationPanel is null)
        {
            return;
        }

        var type = (SanctionTypeComboBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
        SanctionDurationPanel.Visibility = !string.IsNullOrWhiteSpace(type) &&
                                           type != AccountSanctionTypes.Warning
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void SelectReviewStatus(string currentStatus)
    {
        var normalized = ReportStatuses.Normalize(currentStatus);
        var preferred = normalized is ReportStatuses.Actioned or ReportStatuses.NoViolation
            ? ReportStatuses.Reviewing
            : normalized;
        foreach (var item in ReviewStatusComboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag?.ToString(), preferred, StringComparison.OrdinalIgnoreCase))
            {
                ReviewStatusComboBox.SelectedItem = item;
                break;
            }
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

    private static string StatusLabel(string? status) => string.IsNullOrWhiteSpace(status)
        ? "初始记录"
        : ReportStatuses.Normalize(status) switch
        {
            ReportStatuses.Reviewing => "审核中",
            ReportStatuses.Actioned => "已处理",
            ReportStatuses.NoViolation => "未发现违规",
            _ => "待审核"
        };

    private static Brush StatusBrush(string status) => ReportStatuses.Normalize(status) switch
    {
        ReportStatuses.Reviewing => new SolidColorBrush(Color.FromRgb(255, 181, 79)),
        ReportStatuses.Actioned => new SolidColorBrush(Color.FromRgb(64, 218, 146)),
        ReportStatuses.NoViolation => new SolidColorBrush(Color.FromRgb(145, 167, 181)),
        _ => new SolidColorBrush(Color.FromRgb(97, 202, 255))
    };

    private static string ReasonLabel(string reason) => reason switch
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

    private static string ContextLabel(string context) => context switch
    {
        "personal_profile" => "个人资料",
        "friend_chat" => "好友私信",
        "fleet_chat" => "舰队通讯",
        "party_room" => "组队房间",
        _ => "应用内入口"
    };

    private static string EvidenceCategoryLabel(string category) => category switch
    {
        ReportEvidenceCategories.Profile => "公开资料",
        ReportEvidenceCategories.DirectMessage => "双方私信",
        ReportEvidenceCategories.FleetChat => "舰队通讯",
        ReportEvidenceCategories.RoomChat => "房间聊天",
        ReportEvidenceCategories.RoomContent => "房间资料",
        _ => "相关内容"
    };

    private static string DisplayOrFallback(string? value) => string.IsNullOrWhiteSpace(value) ? "未提供" : value;

    private static string SanctionExpiryLabel(AccountSanctionContract sanction) => sanction.RevokedAt is { } revokedAt
        ? $"已于 {revokedAt.ToLocalTime():yyyy-MM-dd HH:mm} 撤销"
        : sanction.ExpiresAt is { } expiresAt
            ? $"预计于 {expiresAt.ToLocalTime():yyyy-MM-dd HH:mm} 恢复"
            : sanction.Type == AccountSanctionTypes.Warning
                ? "此记录不限制账号功能"
                : "等待复核恢复";

    private static string ActorLabel(string actor) => actor.Equals("reporter", StringComparison.OrdinalIgnoreCase)
        ? "举报人提交"
        : actor;
}
