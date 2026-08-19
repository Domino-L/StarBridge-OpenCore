using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using WpfButton = System.Windows.Controls.Button;
using WpfFrameworkElement = System.Windows.FrameworkElement;
using WpfKeyEventArgs = System.Windows.Input.KeyEventArgs;
using WpfToggleButton = System.Windows.Controls.Primitives.ToggleButton;

namespace StarBridge.Desktop;

public partial class InGameFleetWindow : Window
{
    private bool _allowPermanentClose;
    private InGameFleetSnapshot? _currentSnapshot;
    private string _collaborationFilter = "all";
    private InGameFleetShipOwnerFilter _shipOwnerFilter = InGameFleetShipOwnerFilter.All;
    private string _lastFingerprint = "";

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;
    internal event EventHandler? RefreshRequested;
    internal event EventHandler? CommunicationRequested;
    internal event EventHandler? BroadcastRequested;
    internal event EventHandler<InGameFleetMemberActionRequestedEventArgs>? MemberActionRequested;
    internal event EventHandler<InGameFleetShipImageReportRequestedEventArgs>? ShipImageReportRequested;
    internal event EventHandler<InGameFleetShipImagePreviewRequestedEventArgs>? ShipImagePreviewRequested;

    internal InGameFleetWindow()
    {
        InitializeComponent();
        Theming.BridgeSceneContext.ApplyFixed(this, Theming.BridgeSceneKind.Fleet);
        InGameToolWindowBehavior.PreventSnapMaximize(this);
    }

    internal void ShowForMenu()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
    }

    internal void ApplySnapshot(InGameFleetSnapshot snapshot)
    {
        if (_lastFingerprint.Equals(snapshot.Fingerprint, StringComparison.Ordinal))
        {
            return;
        }

        _lastFingerprint = snapshot.Fingerprint;
        _currentSnapshot = snapshot;
        UnavailablePanel.Visibility = snapshot.IsAvailable
            ? Visibility.Collapsed
            : Visibility.Visible;
        FleetContent.Visibility = snapshot.IsAvailable
            ? Visibility.Visible
            : Visibility.Collapsed;
        UnavailableDetailText.Text = snapshot.StatusText;
        StatusText.Text = snapshot.StatusText;
        Controls.InGameLoadingPresentation.Apply(UnavailableLoadingIndicator, false);
        if (!snapshot.IsAvailable)
        {
            ClearCollections();
            return;
        }

        FleetNameText.Text = string.IsNullOrWhiteSpace(snapshot.FleetName)
            ? "未命名组织"
            : snapshot.FleetName;
        FleetCodeText.Text = string.IsNullOrWhiteSpace(snapshot.FleetCode)
            ? "识别码未设置"
            : snapshot.FleetCode;
        FleetCommanderText.Text = string.IsNullOrWhiteSpace(snapshot.Commander)
            ? "未指定"
            : snapshot.Commander;
        FleetLogoFallbackText.Text = GetInitials(snapshot.FleetName, snapshot.FleetCode);
        FleetLogoImage.Source = string.IsNullOrWhiteSpace(snapshot.LogoSource)
            ? null
            : ImageDecodeCache.Load(snapshot.LogoSource, 136);

        AnnouncementTitleText.Text = string.IsNullOrWhiteSpace(snapshot.AnnouncementTitle)
            ? "暂无当前公告"
            : snapshot.AnnouncementTitle;
        AnnouncementContentText.Text = string.IsNullOrWhiteSpace(snapshot.AnnouncementContent)
            ? "组织发布公告后会显示在这里。"
            : snapshot.AnnouncementContent;
        FleetBroadcastButton.Visibility = snapshot.CanPublishBroadcast
            ? Visibility.Visible
            : Visibility.Collapsed;

        TotalMemberCountText.Text = snapshot.TotalMembers.ToString();
        InGameMemberCountText.Text = snapshot.InGameMembers.ToString();
        OnlineMemberCountText.Text = snapshot.OnlineMembers.ToString();
        AwayMemberCountText.Text = snapshot.AwayMembers.ToString();
        OfflineMemberCountText.Text = snapshot.OfflineMembers.ToString();
        SameServerMemberCountText.Text = snapshot.Members
            .Count(member => member.IsSameServer && !member.IsSelf)
            .ToString();
        ApplySignalWidths(snapshot);

        ApplyCollaborationMembers();
        ApplyFleetShips();
    }

    internal void ResetAccountState(string statusText, bool isLoading = false)
    {
        _lastFingerprint = "";
        ApplySnapshot(InGameFleetSnapshot.Unavailable(statusText));
        Controls.InGameLoadingPresentation.Apply(UnavailableLoadingIndicator, isLoading);
    }

    internal void HideForMenu()
    {
        if (IsVisible)
        {
            Hide();
        }
    }

    internal void CloseForApplication()
    {
        _allowPermanentClose = true;
        Close();
    }

    private void ApplySignalWidths(InGameFleetSnapshot snapshot)
    {
        var hasMembers = snapshot.TotalMembers > 0;
        InGameSignalColumn.Width = SignalWidth(snapshot.InGameMembers, hasMembers);
        OnlineSignalColumn.Width = SignalWidth(snapshot.OnlineMembers, hasMembers);
        AwaySignalColumn.Width = SignalWidth(snapshot.AwayMembers, hasMembers);
        OfflineSignalColumn.Width = SignalWidth(
            snapshot.OfflineMembers,
            hasMembers,
            emptyFallback: 1);
    }

    private static GridLength SignalWidth(
        int count,
        bool hasMembers,
        double emptyFallback = 0) =>
        new(
            hasMembers ? Math.Max(0, count) : emptyFallback,
            GridUnitType.Star);

    private void ClearCollections()
    {
        CollaborationMemberList.ItemsSource = null;
        ShipList.ItemsSource = null;
        CollaborationEmptyText.Visibility = Visibility.Collapsed;
        ShipEmptyText.Visibility = Visibility.Collapsed;
        ShipFilterSummaryText.Text = "0 艘";
    }

    private void ApplyFleetShips()
    {
        if (_currentSnapshot is not { IsAvailable: true } snapshot)
        {
            ShipList.ItemsSource = null;
            ShipEmptyText.Visibility = Visibility.Collapsed;
            ShipFilterSummaryText.Text = "0 艘";
            return;
        }

        var rows = InGameFleetShipFilter.Apply(snapshot.Ships, _shipOwnerFilter);
        ShipList.ItemsSource = rows;
        ShipFilterSummaryText.Text = $"{rows.Length} / {snapshot.Ships.Length} 艘";
        ShipEmptyText.TitleOverride = _shipOwnerFilter switch
        {
            InGameFleetShipOwnerFilter.Online => "当前没有舰长在线的共享舰船",
            InGameFleetShipOwnerFilter.Offline => "当前没有舰长离线的共享舰船",
            _ => "还没有成员共享舰船"
        };
        ShipEmptyText.Visibility = rows.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyCollaborationMembers()
    {
        if (_currentSnapshot is not { IsAvailable: true } snapshot)
        {
            CollaborationMemberList.ItemsSource = null;
            CollaborationEmptyText.Visibility = Visibility.Collapsed;
            return;
        }

        IEnumerable<InGameFleetMemberRow> members = snapshot.Members;
        members = _collaborationFilter switch
        {
            "same-server" => members.Where(member => member.IsSameServer),
            "in-game" => members.Where(member =>
                member.Presence == StarBridge.Core.Presence.PlayerPresenceKind.InGame),
            _ => members
        };

        var search = CollaborationSearchBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(search))
        {
            members = members.Where(member => FleetRosterSearchPolicy.Matches(
                search,
                member.Callsign,
                member.GameId,
                member.RoleText,
                member.ShipText,
                member.LocationText,
                member.ServerText));
        }

        var rows = members.ToArray();
        CollaborationMemberList.ItemsSource = rows;
        CollaborationEmptyText.TitleOverride = !string.IsNullOrWhiteSpace(search)
            ? "没有找到匹配的组织成员"
            : _collaborationFilter switch
            {
                "same-server" => "当前没有识别到同一服务器的组织成员",
                "in-game" => "当前没有组织成员在游戏中",
                _ => "暂无可显示的组织成员"
            };
        CollaborationEmptyText.Visibility = rows.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private static string GetInitials(params string?[] values)
    {
        var source = values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim();
        if (string.IsNullOrWhiteSpace(source))
        {
            return "舰";
        }

        var characters = source
            .Where(character => !char.IsWhiteSpace(character))
            .Take(2)
            .ToArray();
        return characters.Length == 0 ? "舰" : new string(characters).ToUpperInvariant();
    }

    private void CollaborationFilter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfToggleButton
            {
                Tag: string filter
            } selected)
        {
            return;
        }

        _collaborationFilter = filter;
        CollaborationAllFilter.IsChecked = ReferenceEquals(selected, CollaborationAllFilter);
        CollaborationSameServerFilter.IsChecked = ReferenceEquals(selected, CollaborationSameServerFilter);
        CollaborationInGameFilter.IsChecked = ReferenceEquals(selected, CollaborationInGameFilter);
        ApplyCollaborationMembers();
    }

    private void CollaborationSearchBox_TextChanged(object sender, TextChangedEventArgs e) =>
        ApplyCollaborationMembers();

    private void ShipOwnerFilter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfToggleButton
            {
                Tag: string filter
            } selected)
        {
            return;
        }

        _shipOwnerFilter = filter switch
        {
            "online" => InGameFleetShipOwnerFilter.Online,
            "offline" => InGameFleetShipOwnerFilter.Offline,
            _ => InGameFleetShipOwnerFilter.All
        };
        ShipAllFilter.IsChecked = ReferenceEquals(selected, ShipAllFilter);
        ShipOnlineFilter.IsChecked = ReferenceEquals(selected, ShipOnlineFilter);
        ShipOfflineFilter.IsChecked = ReferenceEquals(selected, ShipOfflineFilter);
        ApplyFleetShips();
    }

    private void MemberMoreButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfButton
            {
                ContextMenu: { } menu
            } button)
        {
            return;
        }

        menu.PlacementTarget = button;
        menu.Placement = PlacementMode.Bottom;
        menu.IsOpen = true;
        e.Handled = true;
    }

    private void MemberActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not WpfFrameworkElement
            {
                DataContext: InGameFleetMemberRow member,
                Tag: string action
            })
        {
            return;
        }

        var requestedAction = action.Equals("message", StringComparison.OrdinalIgnoreCase)
            ? InGameFleetMemberAction.SendMessage
            : InGameFleetMemberAction.OpenProfile;
        if (requestedAction == InGameFleetMemberAction.OpenProfile &&
            !member.CanOpenProfile ||
            requestedAction == InGameFleetMemberAction.SendMessage &&
            !member.CanMessage)
        {
            return;
        }

        MemberActionRequested?.Invoke(
            this,
            new InGameFleetMemberActionRequestedEventArgs(member, requestedAction));
    }

    private void ShipImageReportButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is WpfFrameworkElement { DataContext: InGameFleetShipRow ship } && ship.CanReportCustomImage)
        {
            ShipImageReportRequested?.Invoke(this, new InGameFleetShipImageReportRequestedEventArgs(ship));
        }
    }

    private void ShipImagePreview_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (sender is WpfFrameworkElement { DataContext: InGameFleetShipRow ship } &&
            !string.IsNullOrWhiteSpace(ship.ImageSource))
        {
            e.Handled = true;
            ShipImagePreviewRequested?.Invoke(
                this,
                new InGameFleetShipImagePreviewRequestedEventArgs(ship));
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) =>
        RefreshRequested?.Invoke(this, EventArgs.Empty);

    private void OpenCommunicationButton_Click(object sender, RoutedEventArgs e) =>
        CommunicationRequested?.Invoke(this, EventArgs.Empty);

    private void OpenBroadcastButton_Click(object sender, RoutedEventArgs e) =>
        BroadcastRequested?.Invoke(this, EventArgs.Empty);

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        HideForUser();

    private void Window_PreviewKeyDown(object sender, WpfKeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    private void HideForUser()
    {
        HideForMenu();
        ToolHidden?.Invoke(this, EventArgs.Empty);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForUser();
        }

        base.OnClosing(e);
    }
}
