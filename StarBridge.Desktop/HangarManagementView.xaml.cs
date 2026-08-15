using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using StarBridge.Desktop.Controls;
using StarBridge.Desktop.Theming;
using Brush = System.Windows.Media.Brush;

namespace StarBridge.Desktop;

public sealed record HangarManagementShipRow(
    string InstanceId,
    string Code,
    string DisplayName,
    string EnglishName,
    string Source,
    string ImagePath,
    string? CustomImageMediaId,
    bool CanUpload,
    string Spec,
    string Role,
    string Status,
    string PriceDisplay,
    decimal PriceValue,
    string ImportedAtText,
    string SyncedAtText,
    DateTimeOffset SortTimestamp,
    string CategoryKey,
    string CategoryName,
    int CategoryOrder,
    Brush CategoryBrush,
    Brush StatusBrush,
    bool IsFlyable,
    bool IsConcept,
    bool IsFavorite,
    bool IsSynced,
    double CustomImageCropFocusX = 0.5,
    double CustomImageCropFocusY = 0.5,
    double CustomImageCropZoom = 1.0)
{
    public bool HasCustomImage => !string.IsNullOrWhiteSpace(CustomImageMediaId);
    public string UploadActionText => HasCustomImage ? "更新图片" : "设置图片";
    public string SyncStateText => IsSynced ? SyncedAtText : "等待同步";
    public Visibility CustomBadgeVisibility => HasCustomImage ? Visibility.Visible : Visibility.Collapsed;
    public Visibility FavoriteBadgeVisibility => IsFavorite ? Visibility.Visible : Visibility.Collapsed;
    public Visibility RemoveVisibility => HasCustomImage ? Visibility.Visible : Visibility.Collapsed;
}

public sealed record HangarManagementSnapshot(
    IReadOnlyList<HangarManagementShipRow> Ships,
    string LastReadText,
    string LastSyncText,
    bool SyncEnabled,
    bool SharingEnabled,
    int FavoriteCount);

public partial class HangarManagementView : System.Windows.Controls.UserControl
{
    private sealed record DistributionItem(
        string Key,
        string Name,
        string CountText,
        int Count,
        int Order,
        Brush Brush);

    private readonly Func<Task<HangarManagementSnapshot>> _reload;
    private readonly Func<Task> _scan;
    private readonly Func<HangarManagementShipRow, Task<bool>> _upload;
    private readonly Func<HangarManagementShipRow, Task<bool>> _remove;
    private readonly Action<HangarManagementShipRow> _preview;
    private readonly Action _openPrivacySettings;
    private readonly ObservableCollection<HangarManagementShipRow> _rows = [];
    private readonly ICollectionView _view;
    private bool _busy;

    public HangarManagementView(
        Func<Task<HangarManagementSnapshot>> reload,
        Func<Task> scan,
        Func<HangarManagementShipRow, Task<bool>> upload,
        Func<HangarManagementShipRow, Task<bool>> remove,
        Action<HangarManagementShipRow> preview,
        Action openPrivacySettings)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Hangar);
        _reload = reload;
        _scan = scan;
        _upload = upload;
        _remove = remove;
        _preview = preview;
        _openPrivacySettings = openPrivacySettings;
        ShipsListBox.ItemsSource = _rows;
        _view = CollectionViewSource.GetDefaultView(_rows);
        _view.Filter = MatchesFilter;
        ApplySorting();
    }

    public async Task RefreshAsync(string? status = null)
    {
        if (_busy)
        {
            return;
        }

        SetBusyState(true);
        ShowOperationalState(
            BridgeStateKind.Loading,
            "正在读取机库",
            "正在同步舰船资料与机库状态。",
            string.Empty);
        StatusText.Text = status ?? "正在读取机库…";
        try
        {
            var snapshot = await _reload();
            _rows.Clear();
            foreach (var row in snapshot.Ships)
            {
                _rows.Add(row);
            }

            if (_rows.Count == 0)
            {
                ShowOperationalState(
                    BridgeStateKind.Empty,
                    "机库中还没有舰船",
                    "扫描官网机库后，已同步的舰船会显示在这里。",
                    string.Empty);
                StatusText.Text = status ?? "机库已同步，目前没有可显示的舰船。";
            }
            else
            {
                RefreshSummary(snapshot);
                ShowDataSurface();
                StatusText.Text = status ?? "机库已更新。你可以查看舰船资料、调整主页展示或管理专属图片。";
            }
        }
        catch (Exception ex)
        {
            var description = UserFacingError.Describe(ex, "暂时无法读取机库，请稍后重试。");
            ShowOperationalState(
                BridgeStateKind.Error,
                "暂时无法读取机库",
                description,
                "重试");
            StatusText.Text = description;
        }
        finally
        {
            SetBusyState(false);
        }
    }

    private bool MatchesFilter(object value)
    {
        if (value is not HangarManagementShipRow row)
        {
            return false;
        }

        var query = SearchBox?.Text.Trim() ?? "";
        if (query.Length > 0 &&
            !row.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase) &&
            !row.EnglishName.Contains(query, StringComparison.OrdinalIgnoreCase) &&
            !row.Code.Contains(query, StringComparison.OrdinalIgnoreCase) &&
            !row.Role.Contains(query, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var filter = (FilterComboBox?.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "all";
        var statusMatches = filter switch
        {
            "flyable" => row.IsFlyable,
            "concept" => row.IsConcept,
            "custom" => row.HasCustomImage,
            "missing" => row.CanUpload && !row.HasCustomImage,
            "unbound" => !row.CanUpload,
            _ => true
        };
        if (!statusMatches)
        {
            return false;
        }

        var role = (RoleFilterComboBox?.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "all";
        return role.Equals("all", StringComparison.OrdinalIgnoreCase) ||
               row.CategoryKey.Equals(role, StringComparison.OrdinalIgnoreCase);
    }

    private void ApplySorting()
    {
        if (_view is null)
        {
            return;
        }

        _view.SortDescriptions.Clear();
        var sort = (SortComboBox?.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "name";
        switch (sort)
        {
            case "recent":
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.SortTimestamp), ListSortDirection.Descending));
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.DisplayName), ListSortDirection.Ascending));
                break;
            case "value":
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.PriceValue), ListSortDirection.Descending));
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.DisplayName), ListSortDirection.Ascending));
                break;
            case "role":
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.CategoryOrder), ListSortDirection.Ascending));
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.Role), ListSortDirection.Ascending));
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.DisplayName), ListSortDirection.Ascending));
                break;
            default:
                _view.SortDescriptions.Add(new SortDescription(nameof(HangarManagementShipRow.DisplayName), ListSortDirection.Ascending));
                break;
        }
    }

    private void RefreshSummary(HangarManagementSnapshot snapshot)
    {
        var flyableCount = _rows.Count(row => row.IsFlyable);
        var conceptCount = _rows.Count(row => row.IsConcept);
        var customCount = _rows.Count(row => row.HasCustomImage);
        var missingCount = _rows.Count(row => row.CanUpload && !row.HasCustomImage);
        var totalValue = _rows.Sum(row => row.PriceValue);

        TotalCountText.Text = $"{_rows.Count} 艘";
        ManageableCountText.Text = $"{_rows.Count(row => row.CanUpload)} 艘可管理";
        TotalValueText.Text = totalValue <= 0
            ? "未公布"
            : $"${totalValue.ToString("N0", CultureInfo.InvariantCulture)}";
        DeliverySummaryText.Text = $"{flyableCount} 可飞 · {conceptCount} 概念";
        CustomCountText.Text = $"{customCount} / {_rows.Count}";
        MissingCountText.Text = $"尚有 {missingCount} 艘待设置";
        MissingCountText.Foreground = BridgeTokenBrushes.GetRequired(
            this,
            missingCount > 0 ? BridgeBrushToken.StatusWarn : BridgeBrushToken.Ink2);
        var syncedCount = _rows.Count(row => row.IsSynced);
        SyncCoverageText.Text = $"{syncedCount} / {_rows.Count}";
        SyncCoverageStatusText.Text = syncedCount == 0
            ? "等待首次同步"
            : syncedCount == _rows.Count
                ? "全部舰船已同步"
                : $"尚有 {_rows.Count - syncedCount} 艘待同步";
        LastReadText.Text = snapshot.LastReadText;
        LastSyncText.Text = snapshot.LastSyncText;
        ShareStatusText.Text = !snapshot.SyncEnabled
            ? "同步已关闭"
            : snapshot.SharingEnabled ? "已向组织公开摘要" : "仅自己可见";
        ShareStatusText.Foreground = BridgeTokenBrushes.GetRequired(
            this,
            snapshot.SharingEnabled
                ? BridgeBrushToken.StatusOk
                : BridgeBrushToken.StatusWarn);
        RenderDistribution();
        RefreshViewState();
    }

    private void RenderDistribution()
    {
        var items = _rows
            .GroupBy(row => new { row.CategoryKey, row.CategoryName, row.CategoryOrder })
            .Select(group => new DistributionItem(
                group.Key.CategoryKey,
                group.Key.CategoryName,
                $"{group.Count()} 艘",
                group.Count(),
                group.Key.CategoryOrder,
                group.First().CategoryBrush))
            .OrderBy(item => item.Order)
            .ToArray();

        DistributionBar.Children.Clear();
        DistributionBar.ColumnDefinitions.Clear();
        if (items.Length == 0)
        {
            DistributionBar.ColumnDefinitions.Add(new ColumnDefinition());
            DistributionBar.Children.Add(new Border
            {
                Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Hairline)
            });
        }
        else
        {
            for (var index = 0; index < items.Length; index++)
            {
                var item = items[index];
                DistributionBar.ColumnDefinitions.Add(new ColumnDefinition
                {
                    Width = new GridLength(Math.Max(1, item.Count), GridUnitType.Star)
                });
                var segment = new Border
                {
                    Background = item.Brush,
                    Opacity = 0.82,
                    Margin = index == 0 ? new Thickness(0) : new Thickness(3, 0, 0, 0)
                };
                Grid.SetColumn(segment, index);
                DistributionBar.Children.Add(segment);
            }
        }

        DistributionLegend.ItemsSource = items;
    }

    private void RefreshViewState()
    {
        _view.Refresh();
        var visibleCount = _view.Cast<object>().Count();
        VisibleCountText.Text = $"{visibleCount} 艘";
        EmptyPanel.Visibility = _rows.Count > 0 && visibleCount == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void Filter_Changed(object sender, RoutedEventArgs e)
    {
        if (_view is null)
        {
            return;
        }

        ApplySorting();
        RefreshViewState();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void ScanButton_Click(object sender, RoutedEventArgs e) => await ScanAsync();

    internal async Task ScanAsync()
    {
        if (_busy)
        {
            return;
        }

        SetBusyState(true);
        ShowOperationalState(
            BridgeStateKind.Loading,
            "正在扫描官网机库",
            "扫描完成后会重新读取舰船资料。",
            string.Empty);
        StatusText.Text = "正在扫描官网机库…";
        var completed = false;
        try
        {
            await _scan();
            completed = true;
        }
        catch (Exception ex)
        {
            var description = UserFacingError.Describe(ex, "官网机库扫描未完成，请稍后重试。");
            ShowOperationalState(
                BridgeStateKind.Error,
                "扫描未完成",
                description,
                string.Empty);
            StatusText.Text = description;
        }
        finally
        {
            SetBusyState(false);
        }

        if (completed)
        {
            await RefreshAsync("官网机库扫描结果已更新。");
        }
    }

    private async void OperationalStatePanel_ActionInvoked(object sender, RoutedEventArgs e) =>
        await RefreshAsync();

    private void ShowOperationalState(
        BridgeStateKind state,
        string title,
        string description,
        string actionText)
    {
        SummaryPanel.Visibility = Visibility.Collapsed;
        FilterPanel.Visibility = Visibility.Collapsed;
        ContentPanel.Visibility = Visibility.Collapsed;
        OperationalStatePanel.State = state;
        OperationalStatePanel.TitleOverride = title;
        OperationalStatePanel.DescriptionOverride = description;
        OperationalStatePanel.ActionTextOverride = actionText;
        OperationalStatePanel.Visibility = Visibility.Visible;
        OperationalStateHost.Visibility = Visibility.Visible;
    }

    private void ShowDataSurface()
    {
        OperationalStateHost.Visibility = Visibility.Collapsed;
        OperationalStatePanel.Visibility = Visibility.Collapsed;
        SummaryPanel.Visibility = Visibility.Visible;
        FilterPanel.Visibility = Visibility.Visible;
        ContentPanel.Visibility = Visibility.Visible;
    }

    private async void UploadButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_busy && sender is System.Windows.Controls.Button { Tag: HangarManagementShipRow row })
        {
            await RunRowActionAsync(() => _upload(row), "专属图片已更新。");
        }
    }

    private async void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_busy && sender is System.Windows.Controls.Button { Tag: HangarManagementShipRow row })
        {
            await RunRowActionAsync(() => _remove(row), "已移除这艘舰船的专属图片。");
        }
    }

    private void ShipImage_MouseLeftButtonUp(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { Tag: HangarManagementShipRow row })
        {
            e.Handled = true;
            _preview(row);
        }
    }

    private void PrivacyButton_Click(object sender, RoutedEventArgs e) => _openPrivacySettings();

    private async Task RunRowActionAsync(Func<Task<bool>> action, string successStatus)
    {
        SetBusyState(true);
        StatusText.Text = "正在保存更改…";
        var changed = false;
        try
        {
            changed = await action();
        }
        finally
        {
            SetBusyState(false);
        }

        if (changed)
        {
            await RefreshAsync(successStatus);
        }
    }

    private void SetBusyState(bool busy)
    {
        _busy = busy;
        HangarLoadingIndicator.IsActive = busy;
        HangarLoadingIndicator.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        ScanButton.IsEnabled = !busy;
        RefreshButton.IsEnabled = !busy;
    }

}
