using System.ComponentModel;
using System.Windows.Controls;
using System.Windows.Data;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private ListCollectionView? _fleetMemberSearchView;
    private bool _fleetMemberReorderPending;

    private void InitializeFleetRosterSearch()
    {
        _fleetMemberSearchView = new ListCollectionView(_players)
        {
            Filter = FleetMemberMatchesSearch
        };
        FleetMembersDeckList.ItemsSource = _fleetMemberSearchView;
        _fleetMemberSearchView.MoveCurrentToPosition(-1);
    }

    private void SynchronizeFleetMemberRows(IReadOnlyList<PlayerRow> nextPlayers)
    {
        var currentMember = _fleetMemberSearchView?.CurrentItem as PlayerRow;
        var isLiveMemberView = ReferenceEquals(FleetMembersDeckList.ItemsSource, _fleetMemberSearchView);
        var deferReorder = isLiveMemberView && FleetMembersDeckList.IsMouseOver;
        var rows = deferReorder
            ? FleetMemberRosterOrderPolicy.PreserveDisplayOrder(_players, nextPlayers)
            : FleetMemberRosterOrderPolicy.OrderForDisplay(nextPlayers);

        _fleetMemberReorderPending = deferReorder;
        PlayerRowCollectionSynchronizer.Synchronize(_players, rows);
        RestoreFleetMemberCurrentItem(currentMember);
    }

    private void FleetMembersDeckList_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_fleetMemberReorderPending ||
            !ReferenceEquals(FleetMembersDeckList.ItemsSource, _fleetMemberSearchView))
        {
            return;
        }

        var currentMember = _fleetMemberSearchView?.CurrentItem as PlayerRow;
        _fleetMemberReorderPending = false;
        PlayerRowCollectionSynchronizer.Synchronize(
            _players,
            FleetMemberRosterOrderPolicy.OrderForDisplay(_players));
        RestoreFleetMemberCurrentItem(currentMember);
    }

    private void RestoreFleetMemberCurrentItem(PlayerRow? previousCurrent)
    {
        _fleetMemberSearchView?.Refresh();
        if (_fleetMemberSearchView is null)
        {
            return;
        }

        if (previousCurrent is null)
        {
            _fleetMemberSearchView.MoveCurrentToPosition(-1);
            RefreshFleetRightContextSidebar();
            return;
        }

        var updatedCurrent = _fleetMemberSearchView.Cast<object>().OfType<PlayerRow>().FirstOrDefault(candidate =>
            PlayerRowCollectionSynchronizer.HasSameIdentity(previousCurrent, candidate));
        if (updatedCurrent is not null)
        {
            _fleetMemberSearchView.MoveCurrentTo(updatedCurrent);
            RefreshFleetRightContextSidebar();
            return;
        }

        _fleetMemberSearchView.MoveCurrentToPosition(-1);
        RefreshFleetRightContextSidebar();
    }

    private bool FleetMemberMatchesSearch(object item) =>
        item is PlayerRow member && member.MatchesFleetSearch(FleetMembersSearchBox.Text);

    private void FleetMembersSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        RestoreFleetMemberCurrentItem(_fleetMemberSearchView?.CurrentItem as PlayerRow);
        var isSearching = !string.IsNullOrWhiteSpace(FleetMembersSearchBox.Text);
        FleetMembersSearchEmptyText.Text = isSearching
            ? "没有找到匹配的组织成员"
            : "暂无组织成员";
        FleetMembersSearchEmptyDetailText.Text = isSearching
            ? "可尝试搜索呼号、游戏 ID、服务器、角色、飞船或地点。"
            : "成员加入组织后将在此显示。";
    }
}
