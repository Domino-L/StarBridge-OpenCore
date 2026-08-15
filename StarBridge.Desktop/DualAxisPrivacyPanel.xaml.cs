using StarBridge.Core.Presence;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public partial class DualAxisPrivacyPanel : System.Windows.Controls.UserControl
{
    private const double CompactLayoutThreshold = 680;
    private bool _isApplying;

    public ObservableCollection<DualAxisPrivacyFieldRow> StatusFields { get; } =
    [
        new(PlayerSharedStateFields.Presence, "在线状态", "是否在线与当前在线状态"),
        new(PlayerSharedStateFields.Ship, "当前飞船", "当前识别到的飞船与置信度"),
        new(PlayerSharedStateFields.Location, "当前位置", "经过位置保护后的地点摘要"),
        new(PlayerSharedStateFields.Server, "服务器信息", "当前服务器分片与区域"),
        new(PlayerSharedStateFields.PersonalHangar, "个人机库", "已同步的个人舰船资料")
    ];

    internal event EventHandler? SettingsChanged;
    internal event EventHandler? GameIdVisibilityChanged;
    internal event EventHandler? CreateGroupRequested;
    internal event EventHandler<PrivateVisibilityGroupRow>? EditGroupRequested;

    public DualAxisPrivacyPanel()
    {
        InitializeComponent();
    }

    protected override void OnRenderSizeChanged(SizeChangedInfo sizeInfo)
    {
        base.OnRenderSizeChanged(sizeInfo);
        ApplyResponsiveLayout(sizeInfo.NewSize.Width);
    }

    private void ApplyResponsiveLayout(double availableWidth)
    {
        var compact = availableWidth < CompactLayoutThreshold;

        AudienceCardsLayout.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
        AudienceCardsLayout.ColumnDefinitions[1].Width = compact
            ? new GridLength(0)
            : new GridLength(1, GridUnitType.Star);
        Grid.SetRow(FleetAudienceCard, 0);
        Grid.SetColumn(FleetAudienceCard, 0);
        Grid.SetRow(RoomAudienceCard, compact ? 1 : 0);
        Grid.SetColumn(RoomAudienceCard, compact ? 0 : 1);
        FleetAudienceCard.Margin = compact
            ? new Thickness(0)
            : new Thickness(0, 0, 5, 0);
        RoomAudienceCard.Margin = compact
            ? new Thickness(0, 10, 0, 0)
            : new Thickness(5, 0, 0, 0);

        GameIdVisibilityLayout.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
        GameIdVisibilityLayout.ColumnDefinitions[1].Width = compact
            ? new GridLength(0)
            : GridLength.Auto;
        Grid.SetRow(GameIdVisibilityDescription, 0);
        Grid.SetColumn(GameIdVisibilityDescription, 0);
        Grid.SetRow(GameIdVisibilityOptions, compact ? 1 : 0);
        Grid.SetColumn(GameIdVisibilityOptions, compact ? 0 : 1);
        GameIdVisibilityDescription.Margin = compact
            ? new Thickness(0)
            : new Thickness(0, 0, 18, 0);
        GameIdVisibilityOptions.Margin = compact
            ? new Thickness(0, 10, 0, 0)
            : new Thickness(0);

        SharedEventLayout.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
        SharedEventLayout.ColumnDefinitions[1].Width = compact
            ? new GridLength(0)
            : GridLength.Auto;
        SharedEventLayout.ColumnDefinitions[2].Width = compact
            ? new GridLength(0)
            : GridLength.Auto;
        Grid.SetRow(SharedEventDescription, 0);
        Grid.SetColumn(SharedEventDescription, 0);
        Grid.SetRow(FleetEventAudienceOption, compact ? 1 : 0);
        Grid.SetColumn(FleetEventAudienceOption, compact ? 0 : 1);
        Grid.SetRow(RoomEventAudienceOption, compact ? 2 : 0);
        Grid.SetColumn(RoomEventAudienceOption, compact ? 0 : 2);
        SharedEventDescription.Margin = compact
            ? new Thickness(0)
            : new Thickness(0, 0, 18, 0);
        FleetEventAudienceOption.Margin = compact
            ? new Thickness(0, 10, 0, 0)
            : new Thickness(0, 0, 18, 0);
        RoomEventAudienceOption.Margin = compact
            ? new Thickness(0, 8, 0, 0)
            : new Thickness(0);
    }

    internal void SetGroups(IEnumerable<PrivateVisibilityGroupRow> groups)
    {
        var rows = groups.ToArray();
        _isApplying = true;
        try
        {
            FleetVisibilityGroupList.ItemsSource = rows;
            FleetGroupsEmptyText.Visibility = rows.Length > 0 ? Visibility.Collapsed : Visibility.Visible;
        }
        finally
        {
            _isApplying = false;
        }
    }

    internal void SetGroupStatus(string? text)
    {
        GroupStatusText.Text = text ?? "";
    }

    internal void Apply(
        DualAxisPrivacySettings settings,
        PlayerSharedStateAudienceProjection projection)
    {
        var normalized = settings.Normalize();
        _isApplying = true;
        try
        {
            FleetAllMembersCheck.IsChecked = normalized.Fleet.AllMembersCanView;
            FleetAdministratorsCheck.IsChecked = !normalized.Fleet.AllMembersCanView &&
                                                  normalized.Fleet.AdministratorsCanView;
            FleetSpecifiedPeopleCheck.IsChecked = !normalized.Fleet.AllMembersCanView &&
                                                   normalized.Fleet.VisibilityGroupIds is { Length: > 0 };
            RoomAllMembersCheck.IsChecked = normalized.Room.AllMembersCanView;
            FleetEventsCheck.IsChecked = normalized.Fleet.Fields.HasFlag(PlayerSharedStateFields.SharedEvents);
            RoomEventsCheck.IsChecked = normalized.Room.Fields.HasFlag(PlayerSharedStateFields.SharedEvents);
            foreach (var row in StatusFields)
            {
                row.FleetEnabled = normalized.Fleet.Fields.HasFlag(row.Field);
                row.RoomEnabled = normalized.Room.Fields.HasFlag(row.Field);
            }

            PolicySummaryText.Text = FormatPolicySummary(projection);
            FleetAudienceSummaryText.Text = FormatFleetSummary(projection);
            RoomAudienceSummaryText.Text = FormatRoomSummary(projection);
            RefreshProgressiveDisclosure();
        }
        finally
        {
            _isApplying = false;
        }
    }

    internal DualAxisPrivacySettings Read(DualAxisPrivacySettings baseline)
    {
        var fleetFields = StatusFields
            .Where(row => row.FleetEnabled)
            .Aggregate(PlayerSharedStateFields.None, (fields, row) => fields | row.Field);
        var roomFields = StatusFields
            .Where(row => row.RoomEnabled)
            .Aggregate(PlayerSharedStateFields.None, (fields, row) => fields | row.Field);
        if (FleetEventsCheck.IsChecked == true)
        {
            fleetFields |= PlayerSharedStateFields.SharedEvents;
        }

        if (RoomEventsCheck.IsChecked == true)
        {
            roomFields |= PlayerSharedStateFields.SharedEvents;
        }

        var groups = FleetVisibilityGroupList.ItemsSource?.Cast<PrivateVisibilityGroupRow>().ToArray() ?? [];
        return (baseline with
        {
            Fleet = baseline.Fleet with
            {
                Fields = fleetFields,
                AdministratorsCanView = FleetAdministratorsCheck.IsChecked == true,
                AllMembersCanView = FleetAllMembersCheck.IsChecked == true,
                VisibilityGroupIds = FleetSpecifiedPeopleCheck.IsChecked == true
                    ? groups.Where(row => row.FleetSelected).Select(row => row.GroupId).ToArray()
                    : []
            },
            Room = baseline.Room with
            {
                Fields = roomFields,
                AllMembersCanView = RoomAllMembersCheck.IsChecked == true,
                VisibilityGroupIds = []
            }
        }).Normalize();
    }

    internal void ApplyGameIdVisibility(GameIdVisibilityPreference preference)
    {
        _isApplying = true;
        try
        {
            GameIdFleetCheck.IsChecked = preference.Locations.HasFlag(GameIdVisibilityLocations.Fleet);
            GameIdRoomCheck.IsChecked = preference.Locations.HasFlag(GameIdVisibilityLocations.PartyRoom);
            GameIdFriendsCheck.IsChecked = preference.Locations.HasFlag(GameIdVisibilityLocations.Friends);
            GameIdPersonalProfileCheck.IsChecked = preference.Locations.HasFlag(GameIdVisibilityLocations.PersonalProfile);
            GameIdVisibilityOptions.IsEnabled = preference.CanConfigure;
            GameIdVisibilityHintText.Text = preference.CanConfigure
                ? "选择可以显示游戏 ID 的位置；其他位置会优先显示呼号。"
                : "没有可替代显示的呼号，游戏 ID 将在所有位置显示。";
        }
        finally
        {
            _isApplying = false;
        }
    }

    internal GameIdVisibilityLocations ReadGameIdVisibility()
    {
        if (!GameIdVisibilityOptions.IsEnabled)
        {
            return GameIdVisibilityLocations.All;
        }

        var locations = GameIdVisibilityLocations.None;
        if (GameIdFleetCheck.IsChecked == true) locations |= GameIdVisibilityLocations.Fleet;
        if (GameIdRoomCheck.IsChecked == true) locations |= GameIdVisibilityLocations.PartyRoom;
        if (GameIdFriendsCheck.IsChecked == true) locations |= GameIdVisibilityLocations.Friends;
        if (GameIdPersonalProfileCheck.IsChecked == true) locations |= GameIdVisibilityLocations.PersonalProfile;
        return locations;
    }

    internal static string FormatPolicySummary(PlayerSharedStateAudienceProjection projection)
    {
        var parts = new List<string>();
        if (projection.FleetStatusFields != PlayerSharedStateFields.None)
        {
            parts.Add(FormatFleetSummary(projection));
        }

        if (projection.RoomStatusFields != PlayerSharedStateFields.None)
        {
            parts.Add(FormatRoomSummary(projection));
        }

        if (projection.AcceptedFriends.StatusFields != PlayerSharedStateFields.None)
        {
            parts.Add($"好友可查看{FormatFields(projection.AcceptedFriends.StatusFields)}");
        }

        return parts.Count > 0
            ? string.Join("；", parts)
            : "目前没有向其他人共享状态";
    }

    internal static string FormatFleetSummary(PlayerSharedStateAudienceProjection projection)
    {
        var fields = projection.FleetStatusFields;
        if (fields == PlayerSharedStateFields.None)
        {
            return "不向组织成员共享状态";
        }

        var hasAdministrators = projection.FleetAdministrators.StatusFields != PlayerSharedStateFields.None;
        var hasMembers = projection.FleetMembers.StatusFields != PlayerSharedStateFields.None;
        var hasSpecifiedPeople = projection.SelectedFleetGroupMembers.StatusFields != PlayerSharedStateFields.None;
        var audience = hasMembers
            ? "所有组织成员"
            : hasAdministrators && hasSpecifiedPeople
                ? "组织管理者和指定人员"
                : hasAdministrators
                    ? "仅组织管理者"
                    : "组织内的指定人员";
        return $"{audience}可查看{FormatFields(fields)}";
    }

    internal static string FormatRoomSummary(PlayerSharedStateAudienceProjection projection)
    {
        var fields = projection.RoomStatusFields;
        if (fields == PlayerSharedStateFields.None)
        {
            return "不向同房间的人共享状态";
        }

        return projection.RoomMembers.StatusFields != PlayerSharedStateFields.None
            ? $"所有同房间的人可查看{FormatFields(fields)}"
            : "不向同房间的人共享状态";
    }

    private static string FormatFields(PlayerSharedStateFields fields)
    {
        var labels = StatusFieldsForSummary
            .Where(field => fields.HasFlag(field.Field))
            .Select(field => field.Label)
            .ToArray();
        return labels.Length == 0 ? "状态" : string.Join("、", labels);
    }

    private static readonly (PlayerSharedStateFields Field, string Label)[] StatusFieldsForSummary =
    [
        (PlayerSharedStateFields.Presence, "在线"),
        (PlayerSharedStateFields.Ship, "飞船"),
        (PlayerSharedStateFields.Location, "位置"),
        (PlayerSharedStateFields.Server, "服务器"),
        (PlayerSharedStateFields.PersonalHangar, "机库")
    ];

    private void RefreshProgressiveDisclosure()
    {
        // Private groups remain a supported model capability, but the current
        // people-first editor deliberately keeps the specified-people control
        // out of the interaction surface until that workflow is reintroduced.
        FleetSpecifiedPeopleSection.Visibility = Visibility.Collapsed;
    }

    private void Control_Changed(object sender, RoutedEventArgs e)
    {
        if (!_isApplying)
        {
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void GameIdVisibility_Changed(object sender, RoutedEventArgs e)
    {
        if (!_isApplying)
        {
            GameIdVisibilityChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void FleetAudienceChoice_Changed(object sender, RoutedEventArgs e)
    {
        if (_isApplying)
        {
            return;
        }

        _isApplying = true;
        try
        {
            if (ReferenceEquals(sender, FleetAllMembersCheck) && FleetAllMembersCheck.IsChecked == true)
            {
                FleetAdministratorsCheck.IsChecked = false;
                FleetSpecifiedPeopleCheck.IsChecked = false;
                foreach (var group in FleetVisibilityGroupList.ItemsSource?.Cast<PrivateVisibilityGroupRow>() ?? [])
                {
                    group.FleetSelected = false;
                }
            }
            else if ((ReferenceEquals(sender, FleetAdministratorsCheck) ||
                      ReferenceEquals(sender, FleetSpecifiedPeopleCheck)) &&
                     sender is System.Windows.Controls.CheckBox { IsChecked: true })
            {
                FleetAllMembersCheck.IsChecked = false;
            }

            RefreshProgressiveDisclosure();
        }
        finally
        {
            _isApplying = false;
        }

        SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void GroupSelection_Changed(object sender, RoutedEventArgs e) => Control_Changed(sender, e);

    private void AudienceDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        var expand = FleetDetailsPanel.Visibility != Visibility.Visible ||
                     RoomDetailsPanel.Visibility != Visibility.Visible;
        var visibility = expand ? Visibility.Visible : Visibility.Collapsed;
        FleetDetailsPanel.Visibility = visibility;
        RoomDetailsPanel.Visibility = visibility;
        AudienceDetailsButton.Content = expand ? "收起" : "调整";
    }

    private void CreateGroupButton_Click(object sender, RoutedEventArgs e) =>
        CreateGroupRequested?.Invoke(this, EventArgs.Empty);

    private void EditGroupButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button { DataContext: PrivateVisibilityGroupRow row })
        {
            EditGroupRequested?.Invoke(this, row);
        }
    }
}

public sealed class DualAxisPrivacyFieldRow(
    PlayerSharedStateFields field,
    string label,
    string description) : INotifyPropertyChanged
{
    private bool _fleetEnabled;
    private bool _roomEnabled;

    internal PlayerSharedStateFields Field { get; } = field;
    public string Label { get; } = label;
    public string Description { get; } = description;

    public bool FleetEnabled
    {
        get => _fleetEnabled;
        set
        {
            if (_fleetEnabled == value) return;
            _fleetEnabled = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(FleetEnabled)));
        }
    }

    public bool RoomEnabled
    {
        get => _roomEnabled;
        set
        {
            if (_roomEnabled == value) return;
            _roomEnabled = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(RoomEnabled)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
