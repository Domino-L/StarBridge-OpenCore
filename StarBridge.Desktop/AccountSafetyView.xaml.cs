using StarBridge.Core.TrustSafety;
using StarBridge.Desktop.Controls;
using StarBridge.Desktop.Theming;
using System.Windows;
using System.Windows.Controls;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class AccountSafetyView : System.Windows.Controls.UserControl
{
    private readonly Func<Task<TrustSafetyAccountStatusContract?>> _loadStatus;
    private readonly Func<Task<MySanctionAppealsContract?>> _loadAppeals;
    private readonly Func<CreateSanctionAppealRequestContract, Task<SanctionAppealRecordContract?>> _submitAppeal;
    private readonly Func<string, Task<string?>> _requestAppealDetails;
    private TrustSafetyAccountStatusContract? _accountStatus;
    private MySanctionAppealsContract? _appeals;
    private bool _loading;

    public AccountSafetyView(
        Func<Task<TrustSafetyAccountStatusContract?>> loadStatus,
        Func<Task<MySanctionAppealsContract?>> loadAppeals,
        Func<CreateSanctionAppealRequestContract, Task<SanctionAppealRecordContract?>> submitAppeal,
        Func<string, Task<string?>> requestAppealDetails)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Review);
        _loadStatus = loadStatus;
        _loadAppeals = loadAppeals;
        _submitAppeal = submitAppeal;
        _requestAppealDetails = requestAppealDetails;
    }

    public async Task RefreshAsync()
    {
        if (_loading)
        {
            return;
        }

        _loading = true;
        ShowPageState(
            BridgeStateKind.Loading,
            "正在读取账号状态",
            "正在同步生效记录与申诉进度。",
            actionTextOverride: string.Empty);
        OperationLoadingIndicator.IsActive = true;
        OperationLoadingIndicator.Visibility = Visibility.Visible;
        StatusText.Text = "正在更新账号状态…";
        try
        {
            var statusTask = _loadStatus();
            var appealsTask = _loadAppeals();
            await Task.WhenAll(statusTask, appealsTask);
            _accountStatus = await statusTask;
            _appeals = await appealsTask;
            Render();
            StatusText.Text = "账号状态已更新。申诉提交后会进入人工审核，请勿重复提交。";
        }
        catch
        {
            ShowPageState(
                BridgeStateKind.Error,
                "暂时无法读取账号状态",
                "请检查网络后使用右上角刷新。",
                actionTextOverride: null);
            StatusText.Text = "暂时无法读取账号状态，请稍后重试。";
        }
        finally
        {
            OperationLoadingIndicator.IsActive = false;
            OperationLoadingIndicator.Visibility = Visibility.Collapsed;
            _loading = false;
        }
    }

    private void Render()
    {
        var sanctions = _accountStatus?.ActiveSanctions ?? [];
        var appeals = _appeals?.Appeals ?? [];
        if (sanctions.Length == 0 && appeals.Length == 0)
        {
            SanctionListPanel.Children.Clear();
            AppealListPanel.Children.Clear();
            ShowPageState(
                BridgeStateKind.Empty,
                "账号状态正常",
                "当前没有生效中的警告、功能限制或申诉记录。",
                actionTextOverride: string.Empty);
            return;
        }

        ShowContent();
        AccountStateSummaryText.Text = sanctions.Length == 0 ? "账号状态正常" : "账号存在需要留意的记录";
        AccountStateSummaryText.Foreground = sanctions.Length == 0
            ? Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.StatusOk)
            : Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.StatusWarn);
        AccountStateDetailText.Text = sanctions.Length == 0
            ? "当前没有生效中的警告或功能限制。"
            : "你仍可以查看账号状态和提交申诉。具体影响与恢复时间请查看下方记录。";

        SanctionListPanel.Children.Clear();
        if (sanctions.Length == 0)
        {
            SanctionListPanel.Children.Add(CreateEmptyMessage("当前没有生效中的记录。"));
        }
        else
        {
            foreach (var sanction in sanctions.OrderByDescending(item => item.IssuedAt))
            {
                SanctionListPanel.Children.Add(CreateSanctionCard(sanction));
            }
        }

        AppealListPanel.Children.Clear();
        if (appeals.Length == 0)
        {
            AppealListPanel.Children.Add(CreateEmptyMessage("你还没有提交过申诉。"));
        }
        else
        {
            foreach (var appeal in appeals.OrderByDescending(item => item.CreatedAt))
            {
                AppealListPanel.Children.Add(CreateAppealCard(appeal));
            }
        }
    }

    private FrameworkElement CreateSanctionCard(AccountSanctionContract sanction)
    {
        var existingAppeal = _appeals?.Appeals.FirstOrDefault(appeal =>
            appeal.SanctionId.Equals(sanction.SanctionId, StringComparison.OrdinalIgnoreCase));
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel();
        text.Children.Add(new TextBlock
        {
            Text = SanctionLabel(sanction.Type),
            Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold
        });
        text.Children.Add(new TextBlock
        {
            Text = sanction.Summary,
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink2),
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        text.Children.Add(new TextBlock
        {
            Text = sanction.ExpiresAt is { } expiresAt
                ? $"恢复时间：{expiresAt.ToLocalTime():yyyy-MM-dd HH:mm}"
                : sanction.Type == AccountSanctionTypes.Warning ? "此记录不会限制功能。" : "恢复时间以审核结果为准。",
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = Theming.BridgeSceneContext.GetRequiredAccentBrush(this),
            FontSize = 10
        });
        grid.Children.Add(text);

        var appealButton = new Button
        {
            Width = 96,
            Height = 32,
            Margin = new Thickness(14, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Content = existingAppeal is null ? "提交申诉" : "已提交申诉",
            IsEnabled = existingAppeal is null,
            Tag = sanction
        };
        appealButton.SetResourceReference(StyleProperty, "BridgeDirectorySecondaryButtonStyle");
        appealButton.Click += AppealButton_Click;
        Grid.SetColumn(appealButton, 1);
        grid.Children.Add(appealButton);
        return WrapCard(grid);
    }

    private FrameworkElement CreateAppealCard(SanctionAppealRecordContract appeal)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock
        {
            Text = $"{SanctionLabel(appeal.SanctionType)} · {AppealStatusLabel(appeal.Status)}",
            Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink),
            FontSize = 13,
            FontWeight = FontWeights.SemiBold
        });
        panel.Children.Add(new TextBlock
        {
            Text = appeal.Details,
            Margin = new Thickness(0, 6, 0, 0),
            Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink2),
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap
        });
        if (!string.IsNullOrWhiteSpace(appeal.OutcomeSummary))
        {
            panel.Children.Add(new TextBlock
            {
                Text = $"审核结果：{appeal.OutcomeSummary}",
                Margin = new Thickness(0, 7, 0, 0),
                Foreground = Theming.BridgeSceneContext.GetRequiredAccentBrush(this),
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap
            });
        }

        return WrapCard(panel);
    }

    private async void AppealButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not AccountSanctionContract sanction)
        {
            return;
        }

        var details = await _requestAppealDetails(SanctionLabel(sanction.Type));
        if (string.IsNullOrWhiteSpace(details))
        {
            return;
        }

        button.IsEnabled = false;
        OperationLoadingIndicator.IsActive = true;
        OperationLoadingIndicator.Visibility = Visibility.Visible;
        StatusText.Text = "正在提交申诉…";
        try
        {
            var submitted = await _submitAppeal(new CreateSanctionAppealRequestContract(
                sanction.SanctionId,
                details,
                Guid.NewGuid().ToString("N")));
            if (submitted is null)
            {
                throw new InvalidOperationException();
            }

            await RefreshAsync();
            StatusText.Text = "申诉已提交，可以在这里查看审核进度。";
        }
        catch
        {
            button.IsEnabled = true;
            StatusText.Text = "申诉暂未提交，请稍后重试。";
        }
        finally
        {
            OperationLoadingIndicator.IsActive = false;
            OperationLoadingIndicator.Visibility = Visibility.Collapsed;
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void PageStatePresenter_ActionInvoked(object sender, RoutedEventArgs e) => await RefreshAsync();

    private void ShowPageState(
        BridgeStateKind state,
        string title,
        string description,
        string? actionTextOverride)
    {
        ContentScrollViewer.Visibility = Visibility.Collapsed;
        PageStatePresenter.State = state;
        PageStatePresenter.TitleOverride = title;
        PageStatePresenter.DescriptionOverride = description;
        PageStatePresenter.ActionTextOverride = actionTextOverride;
        PageStatePresenter.Visibility = Visibility.Visible;
    }

    private void ShowContent()
    {
        PageStatePresenter.Visibility = Visibility.Collapsed;
        ContentScrollViewer.Visibility = Visibility.Visible;
    }

    private FrameworkElement WrapCard(FrameworkElement child) => new Border
    {
        Margin = new Thickness(0, 0, 0, 8),
        Padding = new Thickness(13),
        Background = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.PanelRaised),
        BorderBrush = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Hairline),
        BorderThickness = new Thickness(1),
        Child = child
    };

    private FrameworkElement CreateEmptyMessage(string text) => new TextBlock
    {
        Text = text,
        Margin = new Thickness(10),
        Foreground = Theming.BridgeTokenBrushes.GetRequired(this, Theming.BridgeBrushToken.Ink2),
        TextAlignment = TextAlignment.Center
    };

    internal static string SanctionLabel(string type) => type switch
    {
        AccountSanctionTypes.Warning => "账号警告",
        AccountSanctionTypes.ChatMute => "消息发送限制",
        AccountSanctionTypes.ProfileRestriction => "公开个人资料暂停",
        AccountSanctionTypes.RoomCreationRestriction => "创建房间限制",
        AccountSanctionTypes.RoomParticipationRestriction => "房间加入与邀请限制",
        AccountSanctionTypes.FleetParticipationRestriction => "组织创建、加入与邀请限制",
        AccountSanctionTypes.ShipMediaUploadRestriction => "舰船图片上传限制",
        AccountSanctionTypes.SocialRestriction => "社交功能限制",
        AccountSanctionTypes.AccountRestriction => "账号功能限制",
        _ => "账号记录"
    };

    internal static string AppealStatusLabel(string status) => SanctionAppealStatuses.Normalize(status) switch
    {
        SanctionAppealStatuses.Reviewing => "审核中",
        SanctionAppealStatuses.Accepted => "已通过",
        SanctionAppealStatuses.Denied => "审核完成",
        _ => "已提交"
    };
}
