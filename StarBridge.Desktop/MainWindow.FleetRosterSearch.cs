using System.Windows.Controls;
using System.Windows.Data;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private ListCollectionView? _fleetMemberSearchView;
    private ListCollectionView? _fleetSquadSearchView;

    private void InitializeFleetRosterSearch()
    {
        _fleetMemberSearchView = new ListCollectionView(_players)
        {
            Filter = FleetMemberMatchesSearch
        };
        _fleetSquadSearchView = new ListCollectionView(_squads)
        {
            Filter = FleetSquadMatchesSearch
        };
        FleetMembersDeckList.ItemsSource = _fleetMemberSearchView;
        FleetSquadsDeckList.ItemsSource = _fleetSquadSearchView;
    }

    private bool FleetMemberMatchesSearch(object item) =>
        item is PlayerRow member && FleetRosterSearchPolicy.Matches(
            FleetMembersSearchBox.Text,
            member.Name,
            member.Callsign,
            member.Role,
            member.SquadName,
            member.SharedPresenceText,
            member.SharedShipText,
            member.SharedLocationText,
            member.ServerShard,
            member.ServerRegion);

    private bool FleetSquadMatchesSearch(object item)
    {
        if (item is not SquadRow squad)
        {
            return false;
        }

        return FleetRosterSearchPolicy.Matches(
            FleetSquadsSearchBox.Text,
            squad.Name,
            squad.Commander,
            squad.Type,
            squad.Description,
            squad.Mission,
            squad.RallyPoint,
            string.Join(" ", squad.Members.Select(member => member.Name)),
            string.Join(" ", squad.Members.Select(member => member.Callsign)),
            string.Join(" ", squad.Members.Select(member => member.GameId)));
    }

    private void FleetMembersSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _fleetMemberSearchView?.Refresh();
        var isSearching = !string.IsNullOrWhiteSpace(FleetMembersSearchBox.Text);
        FleetMembersSearchEmptyText.Text = isSearching
            ? "没有找到匹配的舰队成员"
            : "暂无舰队成员";
        FleetMembersSearchEmptyDetailText.Text = isSearching
            ? "可尝试搜索呼号、游戏 ID、小队、角色、飞船或地点。"
            : "成员加入舰队后将在此显示。";
    }

    private void FleetSquadsSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _fleetSquadSearchView?.Refresh();
        var isSearching = !string.IsNullOrWhiteSpace(FleetSquadsSearchBox.Text);
        FleetSquadsSearchEmptyText.Text = isSearching
            ? "没有找到匹配的舰队小队"
            : "暂无舰队小队";
        FleetSquadsSearchEmptyDetailText.Text = isSearching
            ? "可尝试搜索小队名称、指挥官、成员、类型或集结点。"
            : "创建小队后将在此显示。";
    }
}
