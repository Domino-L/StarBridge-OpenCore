using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private sealed class FleetSuccessorOption
    {
        public FleetSuccessorOption(PlayerRow player)
        {
            Player = player;
            DisplayName = FormatCommanderName(player.Callsign, player.Name);
            var status = IsOnlineStatus(player.SharedOnlineStatusValue) ? "在线" : "离线";
            DisplayText = $"{DisplayName} / {status}";
        }

        public PlayerRow Player { get; }
        public string DisplayName { get; }
        public string DisplayText { get; }
    }

    private static PlayerRow? PickRecommendedFleetSuccessor(IEnumerable<PlayerRow> members)
    {
        return members
            .OrderByDescending(member => member.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenBy(member => DisplayCallsign(member.Callsign, member.Name), StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private List<PlayerRow> GetFleetCommanderTransferCandidates()
    {
        return _players
            .Where(player => !IsLocalPlayerIdentity(player.Name, player.Callsign))
            .GroupBy(
                player => $"{NormalizeOptionalField(player.Name)}|{NormalizeOptionalField(player.Callsign)}",
                StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderByDescending(player => IsOnlineStatus(player.SharedOnlineStatusValue))
            .ThenBy(player => DisplayCallsign(player.Callsign, player.Name), StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private Task<FleetSuccessorOption?> ShowFleetSuccessorDialogAsync(
        IReadOnlyList<PlayerRow> candidates,
        PlayerRow recommended)
    {
        _fleetSuccessorSource?.TrySetResult(null);
        _fleetSuccessorSource = new TaskCompletionSource<FleetSuccessorOption?>(TaskCreationOptions.RunContinuationsAsynchronously);

        var options = candidates
            .OrderByDescending(member => member.Name.Equals(recommended.Name, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(member => member.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenBy(member => DisplayCallsign(member.Callsign, member.Name), StringComparer.OrdinalIgnoreCase)
            .Select(member => new FleetSuccessorOption(member))
            .ToList();
        var selected = options.FirstOrDefault(option =>
                           option.Player.Name.Equals(recommended.Name, StringComparison.OrdinalIgnoreCase)) ??
                       options.FirstOrDefault();
        if (selected is null)
        {
            _fleetSuccessorSource.TrySetResult(null);
            return _fleetSuccessorSource.Task;
        }

        FleetSuccessorComboBox.Items.Clear();
        ComboBoxItem? selectedItem = null;
        foreach (var option in options)
        {
            var item = new ComboBoxItem
            {
                Content = option.DisplayText,
                Tag = option,
                Padding = new Thickness(10, 6, 10, 6)
            };
            FleetSuccessorComboBox.Items.Add(item);
            if (option.Player.Name.Equals(selected.Player.Name, StringComparison.OrdinalIgnoreCase))
            {
                selectedItem = item;
            }
        }

        FleetSuccessorComboBox.SelectedItem = selectedItem ??
                                               FleetSuccessorComboBox.Items.OfType<ComboBoxItem>().FirstOrDefault();
        FleetSuccessorMessageText.Text =
            "组织仍有其他成员。请选择新的组织负责人，交接完成后你会离开组织。";
        FleetSuccessorOverlay.Show();
        FleetSuccessorCancelButton.Focus();
        return _fleetSuccessorSource.Task;
    }

    private void FleetSuccessorPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        var selected = (FleetSuccessorComboBox.SelectedItem as ComboBoxItem)?.Tag as FleetSuccessorOption;
        CompleteFleetSuccessorDialog(selected);
    }

    private void FleetSuccessorCancelButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteFleetSuccessorDialog(null);
    }

    private void FleetSuccessorCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteFleetSuccessorDialog(null);
    }

    private void CompleteFleetSuccessorDialog(FleetSuccessorOption? selected)
    {
        var source = _fleetSuccessorSource;
        _fleetSuccessorSource = null;
        FleetSuccessorOverlay.Hide();
        FleetSuccessorComboBox.Items.Clear();
        source?.TrySetResult(selected);
    }
}
