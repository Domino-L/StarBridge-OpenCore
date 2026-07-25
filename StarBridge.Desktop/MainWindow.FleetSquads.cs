using StarBridge.Core.FleetChat;
using System.Globalization;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void MySquadDescriptionBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isLoadingSettings || MySquadDescriptionBox is null)
        {
            return;
        }

        var squad = _selectedSquad;
        if (squad is null)
        {
            return;
        }

        squad.Description = MySquadDescriptionBox.Text.Trim();
        MarkLocalSquadEdit(squad);
        squad.RefreshComputed();
        RefreshOverlayWindow();
        SaveCurrentConfig();
        ScheduleFleetSquadSync();
    }

    private void ScheduleFleetSquadSync()
    {
        _squadDescriptionSyncCts?.Cancel();
        var cts = new CancellationTokenSource();
        _squadDescriptionSyncCts = cts;
        _ = SyncFleetSquadsAfterDelayAsync(cts);
    }

    private async Task SyncFleetSquadsAfterDelayAsync(CancellationTokenSource cts)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(800), cts.Token);
            if (cts.IsCancellationRequested || !ReferenceEquals(_squadDescriptionSyncCts, cts))
            {
                return;
            }

            if (!await PushFleetSquadsAsync(silent: false))
            {
                JoinSquadHintText.Text = "小队信息同步失败，本地修改已保留，请稍后重试。";
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            if (ReferenceEquals(_squadDescriptionSyncCts, cts))
            {
                _squadDescriptionSyncCts = null;
            }

            cts.Dispose();
        }
    }

    private void CreateSquad_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建小队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("创建小队"))
        {
            return;
        }

        if (!_hasFleet)
        {
            JoinSquadHintText.Text = "请先加入舰队";
            return;
        }

        RepairLocalSquadLifecycle();
        if (CurrentUserCommandsAnySquad())
        {
            JoinSquadHintText.Text = "每人只能创建一个小队";
            return;
        }

        CreateSquadPanel.Visibility = Visibility.Visible;
        CreateSquadValidationText.Text = "";
        CreateSquadNameBox.Text = "";
        CreateSquadTypeBox.SelectedIndex = 0;
        CreateSquadCustomTypeBox.Text = "";
        CreateSquadCustomTypeBox.Visibility = Visibility.Collapsed;
        CreateSquadDescriptionBox.Text = "No squad briefing yet.";
        CreateSquadNameBox.Focus();
    }

    private void CreateSquadCancel_Click(object sender, RoutedEventArgs e)
    {
        CreateSquadPanel.Visibility = Visibility.Collapsed;
    }

    private void FleetSquadCreateButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建小队需要先登录星海舰桥账号。") ||
            !EnsureIdentityInitialized("创建小队"))
        {
            return;
        }

        if (!_hasFleet)
        {
            StarBridgeMessageBox.Show(
                this,
                "请先加入舰队，再创建舰队小队。",
                "无法创建小队",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        RepairLocalSquadLifecycle();
        if (CurrentUserCommandsAnySquad())
        {
            StarBridgeMessageBox.Show(
                this,
                "你已经负责一个舰队小队。每名成员同时只能担任一个小队的指挥官。",
                "无法创建小队",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        FleetSquadCreateValidationText.Text = string.Empty;
        FleetSquadCreateNameBox.Text = string.Empty;
        FleetSquadCreateTypeBox.SelectedIndex = 0;
        FleetSquadCreateCustomTypeBox.Text = string.Empty;
        FleetSquadCreateCustomTypeBox.Visibility = Visibility.Collapsed;
        FleetSquadCreateDescriptionBox.Text = string.Empty;
        FleetSquadCreateOverlay.Visibility = Visibility.Visible;
        FleetSquadCreateNameBox.Focus();
    }

    private void FleetSquadCreateCancelButton_Click(object sender, RoutedEventArgs e)
    {
        FleetSquadCreateOverlay.Visibility = Visibility.Collapsed;
    }

    private void FleetSquadCreateTypeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (FleetSquadCreateCustomTypeBox is null || FleetSquadCreateTypeBox is null)
        {
            return;
        }

        FleetSquadCreateCustomTypeBox.Visibility = IsFleetSquadCustomTypeSelected()
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private bool IsFleetSquadCustomTypeSelected()
    {
        return string.Equals(
            (FleetSquadCreateTypeBox.SelectedItem as ComboBoxItem)?.Content?.ToString(),
            "自定义",
            StringComparison.OrdinalIgnoreCase);
    }

    private string GetFleetSquadCreateType()
    {
        return IsFleetSquadCustomTypeSelected()
            ? FleetSquadCreateCustomTypeBox.Text.Trim()
            : (FleetSquadCreateTypeBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "突击";
    }

    private async void FleetSquadCreateConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建小队需要先登录星海舰桥账号。") ||
            !EnsureIdentityInitialized("创建小队"))
        {
            return;
        }

        RepairLocalSquadLifecycle();
        if (!_hasFleet)
        {
            FleetSquadCreateValidationText.Text = "请先加入舰队。";
            return;
        }

        if (CurrentUserCommandsAnySquad())
        {
            FleetSquadCreateValidationText.Text = "每名成员同时只能负责一个小队。";
            return;
        }

        var name = FleetSquadCreateNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            FleetSquadCreateValidationText.Text = "请输入小队名称。";
            return;
        }

        if (_squads.Any(squad => squad.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
        {
            FleetSquadCreateValidationText.Text = "已经存在同名小队。";
            return;
        }

        var squadType = GetFleetSquadCreateType();
        if (string.IsNullOrWhiteSpace(squadType))
        {
            FleetSquadCreateValidationText.Text = "请输入自定义小队类型。";
            return;
        }

        if (IsFleetSquadCustomTypeSelected() && !IsValidChineseText(squadType, maxLength: 5))
        {
            FleetSquadCreateValidationText.Text = "自定义类型仅限 5 个中文字以内。";
            return;
        }

        FleetSquadCreateOverlay.Visibility = Visibility.Collapsed;
        var created = await CreateFleetSquadAsync(
            name,
            squadType,
            FleetSquadCreateDescriptionBox.Text.Trim());
        if (!created)
        {
            FleetSquadCreateOverlay.Visibility = Visibility.Visible;
            FleetSquadCreateValidationText.Text = "创建小队同步失败，已恢复原有状态，请稍后重试。";
        }
    }

    private async void CreateSquadConfirm_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建小队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("创建小队"))
        {
            return;
        }

        if (!_hasFleet)
        {
            CreateSquadValidationText.Text = "请先加入舰队。";
            return;
        }

        RepairLocalSquadLifecycle();
        if (CurrentUserCommandsAnySquad())
        {
            CreateSquadValidationText.Text = "每人只能创建一个小队。";
            return;
        }

        var name = CreateSquadNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            CreateSquadValidationText.Text = "请输入小队名称。";
            return;
        }

        if (_squads.Any(squad => squad.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
        {
            CreateSquadValidationText.Text = "已经存在同名小队。";
            return;
        }

        var squadType = GetCreateSquadType();
        if (string.IsNullOrWhiteSpace(squadType))
        {
            CreateSquadValidationText.Text = "请输入自定义小队类型。";
            return;
        }

        if (IsCustomSquadTypeSelected() && !IsValidChineseText(squadType, maxLength: 5))
        {
            CreateSquadValidationText.Text = "自定义类型仅限 5 个中文字以内。";
            return;
        }

        CreateSquadPanel.Visibility = Visibility.Collapsed;
        if (!await CreateFleetSquadAsync(name, squadType, CreateSquadDescriptionBox.Text.Trim()))
        {
            CreateSquadPanel.Visibility = Visibility.Visible;
            CreateSquadValidationText.Text = "创建小队同步失败，已恢复本地状态，请稍后重试。";
        }
    }

    private async Task<bool> CreateFleetSquadAsync(string name, string squadType, string description)
    {
        var rollbackState = CaptureFleetStateForRollback();
        var squad = new SquadRow
        {
            Id = FleetChatIdentity.CreateSquadId(),
            Name = name,
            Icon = GetInitials(name),
            Commander = FormatCommanderName(_callsign, _localPlayer),
            Type = squadType,
            Description = string.IsNullOrWhiteSpace(description) ? "暂无小队介绍" : description
        };
        MarkLocalSquadEdit(squad);

        _squads.Add(squad);
        _selectedSquad = squad;
        _joinedSquad = squad;
        SquadSelectionList.SelectedItem = squad;
        JoinSquadHintText.Text = $"已创建并加入 {squad.Name}";
        AddFleetLog("成员", "创建小队", $"{GetLocalFleetActorDisplayName()} 创建 {squad.Name}");
        RenderSquads();
        RenderMySquad();
        RefreshSquadActionButtons();
        RefreshOverlayWindow();
        SaveCurrentConfig();
        var pushedLocal = await PushLocalSnapshotAsync(silent: false, pushFleetDirectory: false);
        var pushedSquads = pushedLocal && await PushFleetSquadsAsync(silent: false);
        if (pushedLocal && pushedSquads)
        {
            return true;
        }

        RestoreFleetStateAfterFailedMutation(rollbackState, "创建小队同步失败，已恢复本地小队状态。");
        await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        return false;
    }

    private void CreateSquadTypeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (CreateSquadCustomTypeBox is null)
        {
            return;
        }

        CreateSquadCustomTypeBox.Visibility = IsCustomSquadTypeSelected()
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private string GetCreateSquadType()
    {
        return IsCustomSquadTypeSelected()
            ? CreateSquadCustomTypeBox.Text.Trim()
            : (CreateSquadTypeBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "突击";
    }

    private bool IsCustomSquadTypeSelected()
    {
        return string.Equals(
            (CreateSquadTypeBox.SelectedItem as ComboBoxItem)?.Content?.ToString(),
            "自定义",
            StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsValidChineseText(string value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > maxLength)
        {
            return false;
        }

        return value.All(character => character >= '\u4e00' && character <= '\u9fff');
    }

    private async void JoinSquad_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("加入小队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("加入小队"))
        {
            return;
        }

        if (!_hasFleet)
        {
            JoinSquadHintText.Text = "请先加入舰队";
            RefreshSquadActionButtons();
            return;
        }

        if (_selectedSquad is null)
        {
            JoinSquadHintText.Text = "请选择一个小队";
            return;
        }

        if (_joinedSquad is not null &&
            _joinedSquad.Name.Equals(_selectedSquad.Name, StringComparison.OrdinalIgnoreCase))
        {
            JoinSquadHintText.Text = $"已经在 {_joinedSquad.Name}";
            RefreshSquadActionButtons();
            return;
        }

        var targetSquad = _selectedSquad;
        if (_joinedSquad is not null &&
            StarBridgeMessageBox.Show(
                this,
                $"加入 {targetSquad.Name} 后，你将离开当前小队 {_joinedSquad.Name}。是否继续？",
                "更换舰队小队",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        _joinedSquad = targetSquad;
        JoinSquadHintText.Text = $"已加入 {_joinedSquad.Name}";
        AddFleetLog("成员", "加入小队", $"{GetLocalFleetActorDisplayName()} 加入 {_joinedSquad.Name}");
        RenderState();
        RefreshSquadActionButtons();
        var pushedLocal = await PushLocalSnapshotAsync(silent: false, pushFleetDirectory: false);
        var pushedSquads = pushedLocal && await PushFleetSquadsAsync(silent: false);
        if (!pushedLocal || !pushedSquads)
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "加入小队同步失败，已恢复本地小队状态。");
            JoinSquadHintText.Text = "加入小队同步失败，已恢复本地状态。";
            await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        }
    }

    private void SquadSelectionList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _selectedSquad = SquadSelectionList.SelectedItem as SquadRow;
        RefreshSquadActionButtons();
        RenderMySquad();
    }

    private void FleetSquadJoinButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not SquadRow squad)
        {
            return;
        }

        _selectedSquad = squad;
        SquadSelectionList.SelectedItem = squad;
        JoinSquad_Click(sender, e);
    }

    private void FleetSquadLeaveButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is SquadRow squad &&
            (_joinedSquad is null ||
             !squad.Name.Equals(_joinedSquad.Name, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        LeaveSquad_Click(sender, e);
    }

    private void FleetMySquadViewButton_Click(object sender, RoutedEventArgs e)
    {
        if (_joinedSquad is null)
        {
            return;
        }

        var joined = _squads.FirstOrDefault(squad =>
            squad.Name.Equals(_joinedSquad.Name, StringComparison.OrdinalIgnoreCase));
        if (joined is null)
        {
            return;
        }

        foreach (var squad in _squads)
        {
            squad.IsExpanded = ReferenceEquals(squad, joined);
        }

        _selectedSquad = joined;
        SquadSelectionList.SelectedItem = joined;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            (FleetSquadsDeckList.ItemContainerGenerator.ContainerFromItem(joined) as FrameworkElement)?.BringIntoView();
        }));
    }

    private sealed class SquadSuccessorOption
    {
        public SquadSuccessorOption(PlayerRow player)
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

    private bool IsCurrentUserSquadCommander(SquadRow squad)
    {
        if (string.IsNullOrWhiteSpace(_localPlayer))
        {
            return false;
        }

        var commanderGameName = GetGameNameFromDisplayName(squad.Commander);
        var commanderCallsign = GetCallsignFromDisplayName(squad.Commander);
        return commanderGameName.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase) ||
               (!string.IsNullOrWhiteSpace(_callsign) &&
                commanderCallsign.Equals(_callsign, StringComparison.OrdinalIgnoreCase));
    }

    private bool CurrentUserCommandsAnySquad()
    {
        return _squads.Any(IsCurrentUserSquadCommander);
    }

    private static PlayerRow? PickRecommendedSquadSuccessor(IEnumerable<PlayerRow> members)
    {
        return members
            .OrderByDescending(member => member.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenBy(member => DisplayCallsign(member.Callsign, member.Name), StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private SquadSuccessorOption? PromptSquadSuccessor(
        IReadOnlyList<PlayerRow> candidates,
        PlayerRow recommended,
        string squadName)
    {
        var options = candidates
            .OrderByDescending(member => member.Name.Equals(recommended.Name, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(member => member.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenBy(member => DisplayCallsign(member.Callsign, member.Name), StringComparer.OrdinalIgnoreCase)
            .Select(member => new SquadSuccessorOption(member))
            .ToList();
        var selected = options.FirstOrDefault(option =>
                           option.Player.Name.Equals(recommended.Name, StringComparison.OrdinalIgnoreCase)) ??
                       options.FirstOrDefault();
        if (selected is null)
        {
            return null;
        }

        var dialog = new Window
        {
            Owner = this,
            Title = "移交小队指挥权",
            Width = 480,
            SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = FindBrush("PanelBackgroundBrush", new SolidColorBrush(Color.FromRgb(3, 12, 20))),
            Foreground = Brushes.White
        };

        var comboBox = new System.Windows.Controls.ComboBox
        {
            ItemsSource = options,
            SelectedItem = selected,
            DisplayMemberPath = nameof(SquadSuccessorOption.DisplayText),
            Margin = new Thickness(0, 12, 0, 0),
            MinHeight = 34
        };

        var confirmButton = new System.Windows.Controls.Button
        {
            Content = "确认移交并离开",
            Width = 150,
            MinHeight = 34,
            Margin = new Thickness(8, 0, 0, 0)
        };
        var cancelButton = new System.Windows.Controls.Button
        {
            Content = "取消",
            Width = 100,
            MinHeight = 34
        };

        SquadSuccessorOption? result = null;
        confirmButton.Click += (_, _) =>
        {
            result = comboBox.SelectedItem as SquadSuccessorOption;
            dialog.DialogResult = result is not null;
            dialog.Close();
        };
        cancelButton.Click += (_, _) =>
        {
            dialog.DialogResult = false;
            dialog.Close();
        };

        var buttonRow = new StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 18, 0, 0)
        };
        buttonRow.Children.Add(cancelButton);
        buttonRow.Children.Add(confirmButton);

        var panel = new StackPanel
        {
            Margin = new Thickness(24)
        };
        panel.Children.Add(new TextBlock
        {
            Text = "离开前需要移交小队指挥权",
            FontSize = 20,
            FontWeight = FontWeights.Bold,
            Foreground = FindBrush("AccentBrush", Brushes.DeepSkyBlue)
        });
        panel.Children.Add(new TextBlock
        {
            Text = $"小队 {squadName} 仍有其他成员。请选择新的小队指挥官，默认已选择推荐接任者。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 10, 0, 0),
            Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue)
        });
        panel.Children.Add(comboBox);
        panel.Children.Add(buttonRow);
        dialog.Content = panel;

        return dialog.ShowDialog() == true ? result : null;
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

    private Task<SquadSuccessorOption?> ShowFleetSuccessorDialogAsync(
        IReadOnlyList<PlayerRow> candidates,
        PlayerRow recommended)
    {
        _fleetSuccessorSource?.TrySetResult(null);
        _fleetSuccessorSource = new TaskCompletionSource<SquadSuccessorOption?>(TaskCreationOptions.RunContinuationsAsynchronously);

        var options = candidates
            .OrderByDescending(member => member.Name.Equals(recommended.Name, StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(member => member.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenBy(member => DisplayCallsign(member.Callsign, member.Name), StringComparer.OrdinalIgnoreCase)
            .Select(member => new SquadSuccessorOption(member))
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

        FleetSuccessorComboBox.SelectedItem = selectedItem ?? FleetSuccessorComboBox.Items.OfType<ComboBoxItem>().FirstOrDefault();
        FleetSuccessorMessageText.Text = CurrentUserCommandsAnySquad()
            ? "舰队仍有其他成员。请选择新的舰队指挥官。交接完成后你会离开舰队；如果你同时是小队指挥官，离开后对应小队会自动解散。"
            : "舰队仍有其他成员。请选择新的舰队指挥官，交接完成后你会离开舰队。";
        FleetSuccessorOverlay.Visibility = Visibility.Visible;
        FleetSuccessorCancelButton.Focus();
        return _fleetSuccessorSource.Task;
    }

    private void FleetSuccessorPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        var selected = (FleetSuccessorComboBox.SelectedItem as ComboBoxItem)?.Tag as SquadSuccessorOption;
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

    private void CompleteFleetSuccessorDialog(SquadSuccessorOption? selected)
    {
        var source = _fleetSuccessorSource;
        _fleetSuccessorSource = null;
        FleetSuccessorOverlay.Visibility = Visibility.Collapsed;
        FleetSuccessorComboBox.Items.Clear();
        source?.TrySetResult(selected);
    }

    private async void LeaveSquad_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("离开小队需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (_joinedSquad is null)
        {
            JoinSquadHintText.Text = "当前没有加入小队";
            RefreshSquadActionButtons();
            return;
        }

        var squad = _joinedSquad;
        var squadName = squad.Name;
        var isCommander = IsCurrentUserSquadCommander(squad);
        var squadMembers = _players
            .Where(player => player.SquadName.Equals(squadName, StringComparison.OrdinalIgnoreCase))
            .ToList();
        var remainingMembers = squadMembers
            .Where(player => !IsLocalPlayerIdentity(player.Name, player.Callsign))
            .ToList();
        PlayerRow? successor = null;

        if (!isCommander)
        {
            if (StarBridgeMessageBox.Show(
                    this,
                    $"确认离开小队 {squadName}？",
                    "离开小队",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning) != MessageBoxResult.Yes)
            {
                return;
            }
        }
        else if (remainingMembers.Count == 0)
        {
            if (StarBridgeMessageBox.Show(
                    this,
                    $"离开后小队 {squadName} 将解散。确认解散并离开？",
                    "解散小队",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning) != MessageBoxResult.Yes)
            {
                return;
            }
        }
        else
        {
            var recommended = PickRecommendedSquadSuccessor(remainingMembers);
            if (recommended is null)
            {
                JoinSquadHintText.Text = "没有可移交的小队成员";
                return;
            }

            var selection = PromptSquadSuccessor(remainingMembers, recommended, squadName);
            if (selection is null)
            {
                return;
            }

            successor = selection.Player;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/squads/leave",
                new FleetSquadLeaveRequest(
                    _fleetCode,
                    squadName,
                    successor?.Name,
                    successor?.Callsign));
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                JoinSquadHintText.Text = $"离开失败：{error}";
                return;
            }
        }
        catch (Exception ex)
        {
            JoinSquadHintText.Text = UserFacingError.Describe(ex, "暂时无法离开小队，请稍后重试。");
            return;
        }

        for (var i = 0; i < _players.Count; i++)
        {
            var player = _players[i];
            if (IsLocalPlayerIdentity(player.Name, player.Callsign) &&
                player.SquadName.Equals(squadName, StringComparison.OrdinalIgnoreCase))
            {
                _players[i] = player with { SquadName = "Unassigned" };
            }
        }

        if (isCommander && remainingMembers.Count == 0)
        {
            _squads.Remove(squad);
            if (_selectedSquad is not null &&
                _selectedSquad.Name.Equals(squadName, StringComparison.OrdinalIgnoreCase))
            {
                _selectedSquad = null;
                SquadSelectionList.SelectedItem = null;
            }
        }
        else if (successor is not null)
        {
            squad.Commander = FormatCommanderName(successor.Callsign, successor.Name);
            squad.RefreshComputed();
        }

        _joinedSquad = null;
        JoinSquadHintText.Text = isCommander && remainingMembers.Count == 0
            ? $"已解散 {squadName}"
            : $"已离开 {squadName}";
        await PullNetworkFleetsAsync(silent: true);
        await PullNetworkSnapshotsAsync(silent: true);
        RenderState();
        RenderMySquad();
        RefreshSquadActionButtons();
        RefreshOverlayWindow();
        SaveCurrentConfig();
        await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
    }

    private void FleetSquadMemberMoreButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button ||
            button.Tag is not SquadMemberStatusRow row)
        {
            return;
        }

        var squad = _squads.FirstOrDefault(item =>
            item.Name.Equals(row.SquadName, StringComparison.OrdinalIgnoreCase));
        if (squad is null)
        {
            return;
        }

        _selectedSquad = squad;
        SquadSelectionList.SelectedItem = squad;
        var menu = new ContextMenu
        {
            Background = FindBrush("PanelBackgroundBrush", new SolidColorBrush(Color.FromRgb(7, 19, 29))),
            BorderBrush = FindBrush("AccentBorderBrush", new SolidColorBrush(Color.FromRgb(23, 52, 71))),
            BorderThickness = new Thickness(1),
            PlacementTarget = button,
            Style = (Style)FindResource("StarBridgeContextMenu")
        };

        if (row.CanTransferSquadCommand)
        {
            var transferItem = new MenuItem
            {
                Header = "转移队长",
                Tag = row,
                Foreground = FindBrush("PrimaryTextBrush", Brushes.White),
                Background = Brushes.Transparent,
                Style = (Style)FindResource("StarBridgeContextMenuItem")
            };
            transferItem.Click += FleetSquadTransferCommanderMenuItem_Click;
            menu.Items.Add(transferItem);
        }

        if (row.CanRemoveFromSquad)
        {
            var removeItem = new MenuItem
            {
                Header = "移除成员",
                Tag = row,
                Foreground = FindBrush("DangerButtonHoverBorderBrush", new SolidColorBrush(Color.FromRgb(214, 93, 104))),
                Background = Brushes.Transparent,
                Style = (Style)FindResource("StarBridgeContextMenuItem")
            };
            removeItem.Click += FleetSquadRemoveMemberMenuItem_Click;
            menu.Items.Add(removeItem);
        }

        button.ContextMenu = menu;
        menu.IsOpen = menu.Items.Count > 0;
    }

    private async void FleetSquadTransferCommanderMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not SquadMemberStatusRow row ||
            !row.CanTransferSquadCommand)
        {
            return;
        }

        var squad = _squads.FirstOrDefault(item =>
            item.Name.Equals(row.SquadName, StringComparison.OrdinalIgnoreCase));
        if (squad is null || !CanCurrentUserManageSquad(squad))
        {
            return;
        }

        if (StarBridgeMessageBox.Show(
                this,
                $"确认将小队 {squad.Name} 的队长转移给 {row.Callsign} ({row.GameId})？转移后你仍会留在小队中。",
                "转移小队队长",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            var request = new FleetSquadCommanderTransferRequest(
                _fleetCode,
                squad.Name,
                row.GameId,
                row.Callsign == "-" ? null : row.Callsign);
            var response = await PostNetworkJsonAsync("api/fleets/squads/transfer-commander", request);
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                StarBridgeMessageBox.Show(this, $"转移失败：{error}", "转移小队队长", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            squad.Commander = FormatCommanderName(row.Callsign, row.GameId);
            squad.UpdatedAt = DateTimeOffset.UtcNow;
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            RenderState();
            RenderSquads();
            RenderMySquad();
            SaveCurrentConfig();
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(this, UserFacingError.Describe(ex, "小队队长未能转移，请稍后重试。"), "转移小队队长", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void FleetSquadRemoveMemberMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not SquadMemberStatusRow row ||
            !row.CanRemoveFromSquad)
        {
            return;
        }

        var squad = _squads.FirstOrDefault(item =>
            item.Name.Equals(row.SquadName, StringComparison.OrdinalIgnoreCase));
        if (squad is not null)
        {
            await RemoveSquadMemberAsync(squad, row);
        }
    }

    private async void RemoveSquadMember_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: SquadMemberStatusRow row } ||
            _selectedSquad is null ||
            !row.CanRemoveFromSquad)
        {
            return;
        }

        await RemoveSquadMemberAsync(_selectedSquad, row);
    }

    private async Task RemoveSquadMemberAsync(SquadRow squad, SquadMemberStatusRow row)
    {

        if (StarBridgeMessageBox.Show(
                this,
                $"确认将 {row.Callsign} ({row.GameId}) 移出小队 {squad.Name}？",
                "移除小队成员",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            var request = new FleetSquadMemberMutationRequest(
                _fleetCode,
                squad.Name,
                row.GameId,
                row.Callsign == "-" ? null : row.Callsign);
            var response = await PostNetworkJsonAsync("api/fleets/squads/members/remove", request);
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                JoinSquadHintText.Text = $"移除失败：{error}";
                return;
            }

            for (var i = 0; i < _players.Count; i++)
            {
                var player = _players[i];
                var sameSquad = player.SquadName.Equals(squad.Name, StringComparison.OrdinalIgnoreCase);
                var samePlayer = player.Name.Equals(row.GameId, StringComparison.OrdinalIgnoreCase) ||
                                 (!string.IsNullOrWhiteSpace(player.Callsign) &&
                                  player.Callsign.Equals(row.Callsign, StringComparison.OrdinalIgnoreCase));
                if (sameSquad && samePlayer)
                {
                    _players[i] = player with { SquadName = "Unassigned" };
                }
            }

            AddFleetLog("成员", "移除小队成员", $"{row.Callsign} ({row.GameId}) 被移出 {squad.Name}");
            await PullNetworkFleetsAsync(silent: true);
            await PullNetworkSnapshotsAsync(silent: true);
            RenderState();
            RenderMySquad();
            RefreshSquadActionButtons();
            RefreshOverlayWindow();
            JoinSquadHintText.Text = $"已移除 {row.Callsign}";
        }
        catch (Exception ex)
        {
            JoinSquadHintText.Text = UserFacingError.Describe(ex, "成员未能移出小队，请稍后重试。");
        }
    }

    private void RefreshSquadActionButtons()
    {
        if (JoinSquadButton is null || LeaveSquadButton is null || JoinSquadHintText is null)
        {
            return;
        }

        LeaveSquadButton.Visibility = _joinedSquad is null ? Visibility.Collapsed : Visibility.Visible;
        if (!_hasFleet)
        {
            JoinSquadButton.IsEnabled = false;
            JoinSquadButton.Content = "加入小队";
            JoinSquadHintText.Text = "请先加入舰队";
            return;
        }

        if (_selectedSquad is null)
        {
            JoinSquadButton.IsEnabled = false;
            JoinSquadButton.Content = "加入小队";
            JoinSquadHintText.Text = "请选择一个小队";
            return;
        }

        var sameSquad = _joinedSquad is not null &&
                        _joinedSquad.Name.Equals(_selectedSquad.Name, StringComparison.OrdinalIgnoreCase);
        JoinSquadButton.IsEnabled = !sameSquad;
        JoinSquadButton.Content = sameSquad
            ? "已加入"
            : _joinedSquad is null
                ? "加入小队"
                : "切换小队";
        JoinSquadHintText.Text = sameSquad
            ? $"已加入 {_joinedSquad!.Name}"
            : _joinedSquad is null
                ? "可以加入所选小队"
                : $"将从 {_joinedSquad.Name} 切换到 {_selectedSquad.Name}";
    }
}
