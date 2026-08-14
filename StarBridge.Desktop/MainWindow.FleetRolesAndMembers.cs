using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using StarBridge.Desktop.Theming;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using ControlsOrientation = System.Windows.Controls.Orientation;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void MarkFleetRoleGroupsDirty(string? message = null)
    {
        if (_isFleetRoleGroupsDirty)
        {
            RememberFleetRoleGroupDefinitionsFromRows();
            RefreshFleetRoleGroupsSaveControls();
            if (!string.IsNullOrWhiteSpace(message))
            {
                SetFleetRoleGroupsSaveBarMessage(message, isError: false);
            }

            return;
        }

        _fleetRoleGroupsDraftBaselineJson = JsonSerializer.Serialize(GetFleetRoleGroupDefinitionsForPersistence().ToArray());
        _isFleetRoleGroupsDirty = true;
        RememberFleetRoleGroupDefinitionsFromRows();
        RefreshFleetRoleGroupsSaveControls();
        SetFleetRoleGroupsSaveBarMessage(message ?? "权限改动尚未保存。", isError: false);
    }

    private void ClearFleetRoleGroupsDirty()
    {
        _isFleetRoleGroupsDirty = false;
        _fleetRoleGroupsDraftBaselineJson = null;
        RefreshFleetRoleGroupsSaveControls();
        SetFleetRoleGroupsSaveBarMessage("", isError: false);
    }

    private void RefreshFleetRoleGroupsSaveControls()
    {
        if (FleetRoleUnsavedChangesBar is not null)
        {
            FleetRoleUnsavedChangesBar.Visibility = _isFleetRoleGroupsDirty
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private void SetFleetRoleGroupsSaveBarMessage(string? message, bool isError)
    {
        if (FleetRoleUnsavedChangesStatusText is null)
        {
            return;
        }

        var hasMessage = !string.IsNullOrWhiteSpace(message);
        FleetRoleUnsavedChangesStatusText.Text = hasMessage ? message!.Trim() : "";
        FleetRoleUnsavedChangesStatusText.Visibility = hasMessage
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetRoleUnsavedChangesStatusText.Foreground = GetManageProfileStatusBrush(isError
            ? ManageProfileStatusTone.Danger
            : ManageProfileStatusTone.Warning);

        if (FleetRoleUnsavedChangesBar is not null)
        {
            FleetRoleUnsavedChangesBar.BorderBrush = GetManageProfileStatusBrush(isError
                ? ManageProfileStatusTone.Danger
                : ManageProfileStatusTone.Warning);
        }
    }

    private void ResetFleetRoleGroupsDraftButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isFleetRoleGroupsDirty)
        {
            FleetMemberManagementStatusText.Text = "没有需要放弃的权限改动。";
            return;
        }

        if (TryGetFleetRoleGroupDraftBaseline(out var baseline))
        {
            LoadFleetRoleGroupDefinitions(baseline);
        }

        RefreshFleetRoleGroups();
        ClearFleetRoleGroupsDirty();
        UpdateFleetRoleSelectionOptions();
        FleetMemberManagementStatusText.Text = "已放弃未保存的权限改动。";
    }

    private async void SaveFleetRoleGroupsDraftButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isFleetRoleGroupsDirty)
        {
            FleetMemberManagementStatusText.Text = "没有需要保存的权限改动。";
            return;
        }

        await PersistFleetRoleGroupsAsync("权限与身份组已保存并同步。");
    }

    private void RefreshFleetRoleGroups()
    {
        var selectedKey = _selectedFleetRoleGroup?.Key ?? FleetDeputyCommanderRoleGroupKey;
        EnsureDefaultFleetRoleGroupDefinitions();
        _fleetSystemRoleGroups.Clear();
        _fleetCustomRoleGroups.Clear();

        var commanderCount = _players.Count(player => IsFleetCommander(player.Name, player.Callsign));
        if (commanderCount == 0 && !string.IsNullOrWhiteSpace(_fleetChiefCommander))
        {
            commanderCount = 1;
        }

        var deputyCount = _fleetMemberPermissions.Values.Count(permission =>
            NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle) == FleetDeputyCommanderRoleGroupKey);

        if (FleetCommanderSeatNameText is not null)
        {
            var commander = _players.FirstOrDefault(player => IsFleetCommander(player.Name, player.Callsign));
            var commanderName = commander is null
                ? string.IsNullOrWhiteSpace(_fleetChiefCommander) ? "未指定" : _fleetChiefCommander
                : FormatCommanderName(commander.Callsign, commander.Name);
            FleetCommanderSeatNameText.Text = commanderCount > 1
                ? $"{commanderName} · 仍有 {commanderCount} 个指挥官席位"
                : $"{commanderName} · 全部权限";
        }

        var commanderDefinition = _fleetRoleGroupDefinitions.TryGetValue(FleetCommanderRoleGroupKey, out var commanderRole)
            ? commanderRole
            : null;
        _fleetSystemRoleGroups.Add(CreateFleetRoleGroupRow(
            FleetCommanderRoleGroupKey,
            commanderDefinition?.DisplayName ?? "舰队指挥官",
            commanderDefinition?.Description ?? "舰队的唯一指挥席位，默认拥有全部权限；可调整公开显示的身份颜色。",
            commanderDefinition?.Color ?? FleetCommanderDefaultRoleColor,
            0,
            true,
            commanderCount,
            commanderDefinition?.Permissions,
            commanderDefinition?.CreatedAt ?? default,
            commanderDefinition?.UpdatedAt ?? default));

        var deputyDefinition = _fleetRoleGroupDefinitions.TryGetValue(FleetDeputyCommanderRoleGroupKey, out var deputy)
            ? deputy
            : null;
        _fleetSystemRoleGroups.Add(CreateFleetRoleGroupRow(
            FleetDeputyCommanderRoleGroupKey,
            deputyDefinition?.DisplayName ?? "舰队副指挥官",
            deputyDefinition?.Description ?? "协助舰队指挥官处理日常管理与调度。",
            deputyDefinition?.Color ?? FleetDeputyCommanderDefaultRoleColor,
            1,
            true,
            deputyCount,
            deputyDefinition?.Permissions,
            deputyDefinition?.CreatedAt ?? default,
            deputyDefinition?.UpdatedAt ?? default));

        var customRoles = _fleetMemberPermissions.Values
            .Where(permission => permission.PermissionEnabled)
            .Select(permission => new
            {
                Key = NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle),
                Title = NormalizeRoleTitle(permission.RoleTitle)
            })
            .Where(role => !string.IsNullOrWhiteSpace(role.Key) &&
                           role.Key != "fleet_commander" &&
                           role.Key != "fleet_deputy_commander" &&
                           !role.Title.Equals("成员", StringComparison.OrdinalIgnoreCase) &&
                           !role.Title.Equals("基础成员", StringComparison.OrdinalIgnoreCase))
            .GroupBy(role => role.Key, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.First().Title);

        var memberCountsByRoleKey = customRoles
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);
        var existingCustomRoleKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var definition in _fleetRoleGroupDefinitions.Values
                     .Where(role => IsPersistableFleetRoleGroupKey(role.Key) &&
                                    !role.Key.Equals(FleetCommanderRoleGroupKey, StringComparison.OrdinalIgnoreCase) &&
                                    !role.Key.Equals(FleetDeputyCommanderRoleGroupKey, StringComparison.OrdinalIgnoreCase))
                     .OrderBy(role => role.SortOrder)
                     .ThenBy(role => role.DisplayName, StringComparer.OrdinalIgnoreCase))
        {
            existingCustomRoleKeys.Add(definition.Key);
            memberCountsByRoleKey.TryGetValue(definition.Key, out var memberCount);
            _fleetCustomRoleGroups.Add(CreateFleetRoleGroupRow(
                definition.Key,
                definition.DisplayName,
                definition.Description,
                definition.Color,
                definition.SortOrder,
                false,
                memberCount,
                definition.Permissions,
                definition.CreatedAt,
                definition.UpdatedAt));
        }

        var sort = Math.Max(10, _fleetRoleGroupDefinitions.Values.Select(role => role.SortOrder).DefaultIfEmpty(10).Max() + 1);
        foreach (var group in customRoles)
        {
            if (existingCustomRoleKeys.Contains(group.Key))
            {
                continue;
            }

            var title = group.First().Title;
            var row = CreateFleetRoleGroupRow(
                group.Key,
                title,
                "自定义身份组，可按舰队需要配置权限。",
                FleetRoleColorPalette.Purple,
                sort++,
                false,
                group.Count());
            _fleetCustomRoleGroups.Add(row);
            _fleetRoleGroupDefinitions[row.Key] = ToLocalFleetRoleGroup(row);
        }

        if (_fleetCustomRoleGroups.All(role => !role.Key.Equals(selectedKey, StringComparison.OrdinalIgnoreCase)) &&
            _fleetSystemRoleGroups.All(role => !role.Key.Equals(selectedKey, StringComparison.OrdinalIgnoreCase)))
        {
            selectedKey = FleetDeputyCommanderRoleGroupKey;
        }

        var selected = _fleetSystemRoleGroups
            .Concat(_fleetCustomRoleGroups)
            .FirstOrDefault(role => role.Key.Equals(selectedKey, StringComparison.OrdinalIgnoreCase))
            ?? _fleetSystemRoleGroups.FirstOrDefault();

        if (selected is not null)
        {
            SelectFleetRoleGroup(selected);
        }

        UpdateFleetRoleSelectionOptions();
        if (!_isFleetRoleGroupsDirty)
        {
            RememberFleetRoleGroupDefinitionsFromRows();
        }
    }

    private void SelectFleetRoleGroup_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is FleetRoleGroupRow row)
        {
            SelectFleetRoleGroup(row);
        }
    }

    private void CreateFleetRoleGroup_Click(object sender, RoutedEventArgs e)
    {
        var index = _fleetCustomRoleGroups.Count + 1;
        var row = CreateFleetRoleGroupRow(
            $"custom_role_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}",
            $"自定义身份组 {index}",
            "按舰队需要创建的自定义身份组。",
            FleetRoleColorPalette.Purple,
            100 + index,
            false,
            0);

        _fleetCustomRoleGroups.Add(row);
        SelectFleetRoleGroup(row);
        UpdateFleetRoleSelectionOptions();
        MarkFleetRoleGroupsDirty("已创建身份组，保存后生效。");
        FleetMemberManagementStatusText.Text = "已创建新的自定义身份组，请配置权限后保存。";
    }

    private void RenameFleetRoleGroup_Click(object sender, RoutedEventArgs e)
    {
        BeginFleetRoleGroupNameEdit();
    }

    private void FleetRoleGroupColorButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button || _selectedFleetRoleGroup is null)
        {
            return;
        }

        var menu = new ContextMenu
        {
            PlacementTarget = button,
            Style = (Style)FindResource("StarBridgeContextMenu")
        };
        foreach (var option in FleetRoleColorOptions)
        {
            var header = new StackPanel { Orientation = ControlsOrientation.Horizontal };
            header.Children.Add(new Border
            {
                Width = 11,
                Height = 11,
                Margin = new Thickness(0, 0, 8, 0),
                Background = StatusPalette.BrushFromHex(option.Hex, StatusPalette.InfoBrush),
                BorderBrush = FleetCommandBrush(BridgeBrushToken.Ink2),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(1)
            });
            header.Children.Add(new TextBlock
            {
                Text = _selectedFleetRoleGroup.Color.Equals(option.Hex, StringComparison.OrdinalIgnoreCase)
                    ? $"✓  {option.Name}"
                    : option.Name,
                VerticalAlignment = VerticalAlignment.Center
            });

            var item = new MenuItem
            {
                Header = header,
                Tag = option,
                Style = (Style)FindResource("StarBridgeContextMenuItem")
            };
            item.Click += FleetRoleGroupColorOption_Click;
            menu.Items.Add(item);
        }

        button.ContextMenu = menu;
        menu.IsOpen = true;
    }

    private void FleetRoleGroupColorOption_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetRoleColorOption option ||
            _selectedFleetRoleGroup is null ||
            _selectedFleetRoleGroup.Color.Equals(option.Hex, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _selectedFleetRoleGroup.Color = option.Hex;
        _selectedFleetRoleGroup.UpdatedAt = DateTimeOffset.UtcNow;
        _selectedFleetRoleGroup.RefreshDerived();
        MarkFleetRoleGroupsDirty("身份组标记颜色已修改，保存后生效。");
    }

    private static readonly FleetRoleColorOption[] FleetRoleColorOptions =
    [
        new("蓝色", FleetRoleColorPalette.Blue),
        new("青色", FleetRoleColorPalette.Cyan),
        new("绿色", FleetRoleColorPalette.Green),
        new("黄色", FleetRoleColorPalette.Yellow),
        new("橙色", FleetRoleColorPalette.Orange),
        new("红色", FleetRoleColorPalette.Red),
        new("紫色", FleetRoleColorPalette.Purple),
        new("粉色", FleetRoleColorPalette.Pink),
        new("灰色", FleetRoleColorPalette.Gray),
        new("金色", FleetCommanderDefaultRoleColor)
    ];

    private sealed record FleetRoleColorOption
    {
        private const string FleetRoleColorContrastSurface = FleetRoleColorPalette.ContrastSurface;
        private const double MinimumContrastRatio = 4.5;

        public FleetRoleColorOption(string name, string hex)
        {
            Name = name;
            Hex = hex;
            var contrast = CalculateContrastRatio(hex, FleetRoleColorContrastSurface);
            if (contrast < MinimumContrastRatio)
            {
                throw new InvalidOperationException(
                    $"身份组颜色 {name} ({hex}) 与 BridgePanel 的对比度仅为 {contrast:F2}:1，低于 {MinimumContrastRatio:F1}:1。");
            }
        }

        public string Name { get; }
        public string Hex { get; }

        private static double CalculateContrastRatio(string foregroundHex, string backgroundHex)
        {
            var foreground = CalculateRelativeLuminance(foregroundHex);
            var background = CalculateRelativeLuminance(backgroundHex);
            return (Math.Max(foreground, background) + 0.05) /
                   (Math.Min(foreground, background) + 0.05);
        }

        private static double CalculateRelativeLuminance(string hex)
        {
            var normalized = hex.Trim().TrimStart('#');
            if (normalized.Length != 6 ||
                !byte.TryParse(normalized[..2], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var red) ||
                !byte.TryParse(normalized[2..4], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var green) ||
                !byte.TryParse(normalized[4..6], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var blue))
            {
                throw new InvalidOperationException($"身份组颜色 {hex} 不是有效的 #RRGGBB 颜色。");
            }

            static double Linearize(byte channel)
            {
                var value = channel / 255d;
                return value <= 0.04045
                    ? value / 12.92
                    : Math.Pow((value + 0.055) / 1.055, 2.4);
            }

            return (0.2126 * Linearize(red)) +
                   (0.7152 * Linearize(green)) +
                   (0.0722 * Linearize(blue));
        }
    }

    private void FleetRoleGroupNameBox_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            EndFleetRoleGroupNameEdit();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape)
        {
            EndFleetRoleGroupNameEdit(cancel: true);
            e.Handled = true;
        }
    }

    private void FleetRoleGroupNameBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (_isClosingFleetRoleGroupNameEditor ||
            FleetRoleGroupNameBox is null ||
            FleetRoleGroupNameBox.Visibility != Visibility.Visible)
        {
            return;
        }

        EndFleetRoleGroupNameEdit();
    }

    private void BeginFleetRoleGroupNameEdit()
    {
        if (FleetRoleGroupNameBox is null || _selectedFleetRoleGroup?.CanRenameRole != true)
        {
            return;
        }

        _isClosingFleetRoleGroupNameEditor = false;
        _fleetRoleGroupNameEditSnapshot = _selectedFleetRoleGroup?.DisplayName;

        if (FleetRoleGroupNameDisplayPanel is not null)
        {
            FleetRoleGroupNameDisplayPanel.Visibility = Visibility.Collapsed;
        }

        FleetRoleGroupNameBox.Visibility = Visibility.Visible;
        FleetRoleGroupNameBox.Focus();
        FleetRoleGroupNameBox.SelectAll();
    }

    private void EndFleetRoleGroupNameEdit(bool cancel = false)
    {
        if (FleetRoleGroupNameBox is null ||
            FleetRoleGroupNameBox.Visibility != Visibility.Visible)
        {
            return;
        }

        _isClosingFleetRoleGroupNameEditor = true;
        var shouldPersist = !cancel &&
                            _selectedFleetRoleGroup is not null &&
                            !string.Equals(
                                _fleetRoleGroupNameEditSnapshot,
                                _selectedFleetRoleGroup.DisplayName,
                                StringComparison.Ordinal);

        if (cancel &&
            _selectedFleetRoleGroup is not null &&
            !string.IsNullOrWhiteSpace(_fleetRoleGroupNameEditSnapshot))
        {
            _selectedFleetRoleGroup.DisplayName = _fleetRoleGroupNameEditSnapshot;
        }

        FleetRoleGroupNameBox.Visibility = Visibility.Collapsed;

        if (FleetRoleGroupNameDisplayPanel is not null)
        {
            FleetRoleGroupNameDisplayPanel.Visibility = Visibility.Visible;
        }

        _fleetRoleGroupNameEditSnapshot = null;
        Dispatcher.BeginInvoke(new Action(() => _isClosingFleetRoleGroupNameEditor = false), DispatcherPriority.Background);

        if (shouldPersist)
        {
            _selectedFleetRoleGroup!.UpdatedAt = DateTimeOffset.UtcNow;
            MarkFleetRoleGroupsDirty("身份组名称已修改，保存后生效。");
            FleetMemberManagementStatusText.Text = "身份组名称已修改，请保存更改。";
        }
    }

    private void CopyFleetRoleGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedFleetRoleGroup is null)
        {
            return;
        }

        if (_selectedFleetRoleGroup.IsCommanderSeat)
        {
            FleetMemberManagementStatusText.Text = "舰队指挥官席位不可复制，请新建自定义身份组。";
            return;
        }

        var copy = CreateFleetRoleGroupRow(
            $"custom_role_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}",
            $"{_selectedFleetRoleGroup.DisplayName} 副本",
            _selectedFleetRoleGroup.Description,
            _selectedFleetRoleGroup.Color,
            100 + _fleetCustomRoleGroups.Count + 1,
            false,
            0);

        CopyPermissionState(_selectedFleetRoleGroup, copy);
        _fleetCustomRoleGroups.Add(copy);
        SelectFleetRoleGroup(copy);
        UpdateFleetRoleSelectionOptions();
        MarkFleetRoleGroupsDirty("身份组副本已创建，保存后生效。");
        FleetMemberManagementStatusText.Text = "身份组已复制，请确认名称与权限后保存。";
    }

    private void AssignFleetRoleMembers_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedFleetRoleGroup?.IsCommanderSeat == true)
        {
            FleetMemberManagementStatusText.Text = "舰队指挥官是唯一席位，请在成员页转移指挥官。";
            return;
        }

        FleetMemberManagementStatusText.Text = "成员分配请在成员页编辑，这里只配置权限。";
    }

    private void DeleteFleetRoleGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedFleetRoleGroup is null)
        {
            return;
        }

        if (_selectedFleetRoleGroup.IsSystem)
        {
            FleetMemberManagementStatusText.Text = _selectedFleetRoleGroup.IsCommanderSeat
                ? "舰队指挥官席位不可删除。"
                : "系统默认身份组不可删除，但可以重命名和调整权限。";
            return;
        }

        var message = _selectedFleetRoleGroup.MemberCount > 0
            ? $"“{_selectedFleetRoleGroup.DisplayName}”仍有 {_selectedFleetRoleGroup.MemberCount} 名成员。删除后这些成员将回到基础成员权限，是否继续？"
            : $"确认删除“{_selectedFleetRoleGroup.DisplayName}”？";

        if (StarBridgeMessageBox.Show(this, message, "删除身份组", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        _fleetCustomRoleGroups.Remove(_selectedFleetRoleGroup);
        var next = _fleetSystemRoleGroups.FirstOrDefault();
        if (next is not null)
        {
            SelectFleetRoleGroup(next);
        }

        UpdateFleetRoleSelectionOptions();
        MarkFleetRoleGroupsDirty("身份组已删除，保存后生效。");
        FleetMemberManagementStatusText.Text = "身份组已删除，保存后相关成员将回到基础成员权限。";
    }

    private void FleetRolePermissionChanged_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedFleetRoleGroup is null)
        {
            return;
        }

        if (_selectedFleetRoleGroup.IsCommanderSeat)
        {
            foreach (var permission in _selectedFleetRoleGroup.PermissionGroups.SelectMany(group => group.Items))
            {
                permission.IsAllowed = true;
            }

            FleetMemberManagementStatusText.Text = "舰队指挥官默认拥有全部权限，无法在此关闭。";
            return;
        }

        if ((sender as FrameworkElement)?.DataContext is FleetPermissionItemRow { IsDangerous: true, IsAllowed: true } item)
        {
            if (StarBridgeMessageBox.Show(
                    this,
                    $"确认为“{_selectedFleetRoleGroup.DisplayName}”开启危险权限“{item.Title}”？此操作会写入审计日志。",
                    "舰队任务发布",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning) != MessageBoxResult.Yes)
            {
                item.IsAllowed = false;
                return;
            }

            AddFleetLog("权限", "危险权限", $"{_selectedFleetRoleGroup.DisplayName} 开启 {item.Title}");
        }

        _selectedFleetRoleGroup.UpdatedAt = DateTimeOffset.UtcNow;
        _selectedFleetRoleGroup.RefreshDerived();
        MarkFleetRoleGroupsDirty("权限已调整，保存后生效。");
        FleetMemberManagementStatusText.Text = "权限已调整，请保存更改。";
    }

    private async Task PersistFleetRoleGroupsAsync(string successMessage)
    {
        RememberFleetRoleGroupDefinitionsFromRows();
        ApplyRoleGroupPermissionDefinitionsToAssignedMembers();
        var roleGroupsToSave = BuildFleetRoleGroupSnapshots(
            GetFleetRoleGroupDefinitionsForPersistence().ToArray());

        if (!_hasFleet)
        {
            _isSavingFleetRoleGroupsDraft = true;
            try
            {
                SaveCurrentConfig();
            }
            finally
            {
                _isSavingFleetRoleGroupsDraft = false;
            }

            ClearFleetRoleGroupsDirty();
            FleetMemberManagementStatusText.Text = successMessage;
            RenderState();
            return;
        }

        _isSavingFleetRoleGroupsDraft = true;
        var pushed = false;
        try
        {
            pushed = await PushFleetInfoAsync(
                silent: true,
                scope: FleetInfoUpdateScope.RoleGroups,
                roleGroupsOverride: roleGroupsToSave);
            if (pushed)
            {
                SaveCurrentConfig();
                ClearFleetRoleGroupsDirty();
                FleetMemberManagementStatusText.Text = successMessage;
                RenderState();
                return;
            }
        }
        finally
        {
            _isSavingFleetRoleGroupsDraft = false;
        }

        SetFleetRoleGroupsSaveBarMessage("权限同步失败，改动尚未保存。请检查网络后重试。", isError: true);
        FleetMemberManagementStatusText.Text = "权限同步失败，当前改动仍保留在页面中。";
    }

    private void ApplyRoleGroupPermissionDefinitionsToAssignedMembers()
    {
        var updates = new List<(string Key, LocalFleetMemberPermission Permission)>();
        foreach (var pair in _fleetMemberPermissions)
        {
            var permission = pair.Value;
            if (!permission.PermissionEnabled)
            {
                continue;
            }

            var roleGroupKey = NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle);
            if (string.IsNullOrWhiteSpace(roleGroupKey) ||
                roleGroupKey.Equals("fleet_commander", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var permissionIds = ResolveRoleGroupPermissionIds(roleGroupKey, permission.ExtraAllowedPermissions);
            if (permissionIds.Length == 0)
            {
                continue;
            }

            var flags = MapPermissionIdsToFleetPermissionFlags(permissionIds);
            updates.Add((pair.Key, permission with
            {
                CanRemoveMembers = flags.CanRemoveMembers,
                CanPublishTasks = flags.CanPublishTasks,
                CanPublishPlans = flags.CanPublishPlans,
                CanManageFleetInfo = flags.CanManageFleetInfo,
                ExtraAllowedPermissions = permissionIds,
                UpdatedAt = DateTimeOffset.UtcNow
            }));
        }

        foreach (var update in updates)
        {
            _fleetMemberPermissions[update.Key] = update.Permission;
        }
    }

    private static void CopyPermissionState(FleetRoleGroupRow source, FleetRoleGroupRow target)
    {
        target.HiddenPermissionIds.Clear();
        foreach (var id in source.HiddenPermissionIds)
        {
            target.HiddenPermissionIds.Add(id);
        }

        var sourceItems = source.PermissionGroups.SelectMany(group => group.Items).ToDictionary(item => item.Id, StringComparer.OrdinalIgnoreCase);
        foreach (var targetItem in target.PermissionGroups.SelectMany(group => group.Items))
        {
            if (sourceItems.TryGetValue(targetItem.Id, out var sourceItem) && !targetItem.IsLocked)
            {
                targetItem.IsAllowed = sourceItem.IsAllowed;
            }
        }
    }

    private FleetRoleGroupRow CreateFleetRoleGroupRow(
        string key,
        string displayName,
        string description,
        string color,
        int sortOrder,
        bool isSystem,
        int memberCount,
        IEnumerable<string>? permissionIds = null,
        DateTimeOffset createdAt = default,
        DateTimeOffset updatedAt = default)
    {
        var now = DateTimeOffset.UtcNow;
        var row = new FleetRoleGroupRow
        {
            Key = key,
            DisplayName = displayName,
            Description = description,
            Color = color,
            SortOrder = sortOrder,
            IsSystem = isSystem,
            IsEnabled = true,
            MemberCount = memberCount,
            CreatedAt = createdAt == default ? now : createdAt,
            UpdatedAt = updatedAt == default ? now : updatedAt
        };

        foreach (var group in CreateFleetPermissionGroupsForRole(key))
        {
            row.PermissionGroups.Add(group);
        }

        ApplyFleetRolePermissionIds(row, permissionIds);

        return row;
    }

    private static void ApplyFleetRolePermissionIds(FleetRoleGroupRow role, IEnumerable<string>? permissionIds)
    {
        if (role.IsCommanderSeat || permissionIds is null)
        {
            return;
        }

        var allowedIds = new HashSet<string>(
            permissionIds.Where(id => !string.IsNullOrWhiteSpace(id)).Select(id => id.Trim()),
            StringComparer.OrdinalIgnoreCase);

        foreach (var permission in role.PermissionGroups.SelectMany(group => group.Items))
        {
            if (!permission.IsLocked)
            {
                permission.IsAllowed = allowedIds.Contains(permission.Id);
            }
        }

        var visibleIds = role.PermissionGroups
            .SelectMany(group => group.Items)
            .Select(item => item.Id)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        role.HiddenPermissionIds.Clear();
        foreach (var id in allowedIds.Where(id => !visibleIds.Contains(id)))
        {
            role.HiddenPermissionIds.Add(id);
        }
    }

    private static FleetPermissionGroupRow[] CreateFleetPermissionGroupsForRole(string roleKey)
    {
        var commander = roleKey.Equals("fleet_commander", StringComparison.OrdinalIgnoreCase);
        var deputy = commander || roleKey.Equals("fleet_deputy_commander", StringComparison.OrdinalIgnoreCase);

        FleetPermissionItemRow Item(string id, string title, string description, string module, bool allowed, bool danger = false, bool locked = false)
        {
            return new FleetPermissionItemRow
            {
                Id = id,
                Title = title,
                Description = description,
                ShortModule = module,
                IsAllowed = commander || allowed,
                IsDangerous = danger,
                IsLocked = commander || locked
            };
        }

        return
        [
            new("舰队资料", "管理舰队公开资料与展示资源。",
                [
                    Item(FleetPermissionPolicy.EditFleetProfile, "编辑舰队资料", "维护简介、活跃区域、活动时间和标签。", "资料", deputy),
                    Item(FleetPermissionPolicy.ManageAnnouncements, "维护舰队公告", "发布、修订和撤下舰队公告，并查看历史记录。", "公告", deputy),
                    Item("fleet.avatar.edit", "更换舰队标志", "更新舰队标志和头像资源。", "展示", commander)
                ]),
            new("成员加入与管理", "处理加入申请和成员移除。",
                [
                    Item("members.review", "审核申请", "处理玩家加入申请。", "成员", deputy),
                    Item("members.remove", "移除成员", "从舰队中移除成员。", "成员", deputy)
                ]),
            new("数据与日志", "查看和整理舰队管理日志。",
                [
                    Item("audit.view", "查看舰队完整日志", "查看舰队资料、成员和权限变更记录。", "日志", deputy),
                    Item("audit.delete", "删除日志记录", "删除不需要保留的单条日志。", "日志", commander)
                ])
        ];
    }

    private void SelectFleetRoleGroup(FleetRoleGroupRow row)
    {
        EndFleetRoleGroupNameEdit();

        foreach (var role in _fleetSystemRoleGroups.Concat(_fleetCustomRoleGroups))
        {
            role.IsSelected = ReferenceEquals(role, row);
        }

        _selectedFleetRoleGroup = row;
        _fleetSelectedRolePermissionGroups.Clear();
        foreach (var group in row.PermissionGroups)
        {
            _fleetSelectedRolePermissionGroups.Add(group);
        }

        if (FleetRoleGroupDetailPanel is not null)
        {
            FleetRoleGroupDetailPanel.DataContext = row;
        }
    }

    private void UpdateFleetRoleSelectionOptions()
    {
        var current = FleetRoleSelectionOptions.ToArray();
        var next = _fleetSystemRoleGroups
            .Concat(_fleetCustomRoleGroups)
            .Where(role => !role.IsCommanderSeat)
            .Select(role => role.DisplayName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Concat(["基础成员"])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (current.SequenceEqual(next, StringComparer.OrdinalIgnoreCase))
        {
            return;
        }

        FleetRoleSelectionOptions.Clear();
        foreach (var name in next)
        {
            FleetRoleSelectionOptions.Add(name);
        }
    }

    private void RefreshFleetMemberManagement()
    {
        if (FleetMemberManagementList is null)
        {
            return;
        }

        _fleetMemberRows.Clear();
        if (!_hasFleet)
        {
            _fleetSystemRoleGroups.Clear();
            _fleetCustomRoleGroups.Clear();
            _fleetSelectedRolePermissionGroups.Clear();
            if (FleetMemberManagementEmptyText is not null)
            {
                FleetMemberManagementEmptyText.Visibility = Visibility.Visible;
            }
            return;
        }

        RefreshFleetRoleGroups();

        var canEditPermissions = IsCurrentUserFleetCommander();
        var canTransferCommand = IsCurrentUserFleetCommander();

        foreach (var player in _players
                     .OrderByDescending(player => IsFleetCommander(player.Name, player.Callsign))
                     .ThenBy(player => DisplayCallsign(player.Callsign, player.Name)))
        {
            var isCommander = IsFleetCommander(player.Name, player.Callsign);
            var permission = GetFleetPermission(player.Name);
            var hasInvalidCommanderRole = !isCommander && IsFleetCommanderRole(permission?.RoleGroupKey, permission?.RoleTitle);
            var permissionEnabled = isCommander || (!hasInvalidCommanderRole && permission?.PermissionEnabled == true);
            _fleetMemberRows.Add(new FleetMemberManagementRow
            {
                GameName = player.Name,
                Callsign = DisplayCallsign(player.Callsign, player.Name),
                DisplayName = FormatCommanderName(player.Callsign, player.Name),
                Initials = player.Initials,
                AvatarPath = player.AvatarPath,
                AccountId = player.AccountId,
                OnlineStatus = player.SharedOnlineStatusValue,
                LiveStatus = player.SharedLiveStatusValue,
                RoleTitle = isCommander
                    ? "舰队指挥官"
                    : hasInvalidCommanderRole
                        ? "权限无效"
                        : NormalizeRoleDisplayTitle(permission?.RoleTitle, permission?.RoleGroupKey),
                PermissionEnabled = permissionEnabled,
                CanRemoveMembers = isCommander || (!hasInvalidCommanderRole && permission?.CanRemoveMembers == true),
                CanPublishTasks = isCommander || (!hasInvalidCommanderRole && permission?.CanPublishTasks == true),
                CanPublishPlans = isCommander || (!hasInvalidCommanderRole && permission?.CanPublishPlans == true),
                CanManageFleetInfo = isCommander || (!hasInvalidCommanderRole && permission?.CanManageFleetInfo == true),
                IsSelf = IsLocalPlayer(player.Name),
                IsCommander = isCommander,
                CanCurrentUserEditPermissions = canEditPermissions,
                CanCurrentUserRemove = CanCurrentUserRemoveFleetMember(player.Name, player.Callsign, isCommander),
                CanCurrentUserTransferCommand = canTransferCommand,
                RoleBrush = GetFleetRoleBrush(player.Name, player.Callsign)
            });
        }

        var knownPlayers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in _fleetMemberRows)
        {
            knownPlayers.Add(row.GameName);
            knownPlayers.Add(row.Callsign);
        }

        foreach (var permission in _fleetMemberPermissions.Values
                     .Where(item => !string.IsNullOrWhiteSpace(item.GameName) &&
                                    !knownPlayers.Contains(item.GameName))
                     .OrderBy(item => DisplayCallsign(item.Callsign, item.GameName)))
        {
            var isCommander = IsFleetCommander(permission.GameName, permission.Callsign);
            var hasInvalidCommanderRole = !isCommander && IsFleetCommanderRole(permission.RoleGroupKey, permission.RoleTitle);
            var displayName = FormatCommanderName(permission.Callsign, permission.GameName);

            _fleetMemberRows.Add(new FleetMemberManagementRow
            {
                GameName = permission.GameName,
                Callsign = DisplayCallsign(permission.Callsign, permission.GameName),
                DisplayName = displayName,
                Initials = GetInitials(DisplayCallsign(permission.Callsign, permission.GameName)),
                AvatarPath = "",
                OnlineStatus = "Offline",
                RoleTitle = isCommander
                    ? "舰队指挥官"
                    : hasInvalidCommanderRole
                        ? "权限无效"
                        : NormalizeRoleDisplayTitle(permission.RoleTitle, permission.RoleGroupKey),
                PermissionEnabled = isCommander || (!hasInvalidCommanderRole && permission.PermissionEnabled),
                CanRemoveMembers = isCommander || (!hasInvalidCommanderRole && permission.CanRemoveMembers),
                CanPublishTasks = isCommander || (!hasInvalidCommanderRole && permission.CanPublishTasks),
                CanPublishPlans = isCommander || (!hasInvalidCommanderRole && permission.CanPublishPlans),
                CanManageFleetInfo = isCommander || (!hasInvalidCommanderRole && permission.CanManageFleetInfo),
                IsSelf = IsLocalPlayer(permission.GameName),
                IsCommander = isCommander,
                CanCurrentUserEditPermissions = canEditPermissions,
                CanCurrentUserRemove = CanCurrentUserRemoveFleetMember(permission.GameName, permission.Callsign, isCommander),
                CanCurrentUserTransferCommand = canTransferCommand,
                RoleBrush = GetFleetRoleBrush(permission.GameName, permission.Callsign)
            });
        }

        if (FleetMemberManagementEmptyText is not null)
        {
            FleetMemberManagementEmptyText.Visibility = _fleetMemberRows.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private void RefreshFleetApplications()
    {
        if (FleetApplicationsTab is null || FleetApplicationEmptyText is null)
        {
            return;
        }

        _fleetApplications.Clear();

        var canReviewApplications = _hasFleet && CanCurrentUserReviewFleetApplications();
        FleetApplicationsTab.Visibility = canReviewApplications
            ? Visibility.Visible
            : Visibility.Collapsed;

        var pendingApplications = BuildPendingFleetApplicationRows();

        FleetApplicationsTab.Header = $"招募与加入 {pendingApplications.Length}";
        RefreshManageFleetJoinSettings(pendingApplications.Length);

        if (!canReviewApplications)
        {
            FleetApplicationEmptyText.Visibility = Visibility.Visible;
            FleetApplicationStatusText.Text = "";
            return;
        }

        foreach (var application in pendingApplications)
        {
            _fleetApplications.Add(application);
        }

        FleetApplicationEmptyText.Visibility = _fleetApplications.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        RefreshManageFleetJoinSettings(pendingApplications.Length);
        RefreshFleetNotificationCenter();
        RefreshFleetRightContextSidebar();
    }

    private FleetApplicationRow[] BuildPendingFleetApplicationRows()
    {
        return (_fleetApplicationSnapshots ?? [])
            .Where(application =>
                string.IsNullOrWhiteSpace(application.Status) ||
                application.Status.Equals("Pending", StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(application => application.CreatedAt)
            .Select(CreateFleetApplicationRow)
            .ToArray();
    }

    private FleetApplicationRow CreateFleetApplicationRow(NetworkFleetApplicationSnapshot application)
    {
        var callsign = NormalizeDisplayIdentityPart(NormalizeOptionalField(application.ApplicantCallsign));
        var gameName = NormalizeDisplayIdentityPart(NormalizeOptionalField(application.ApplicantGameName));
        if (string.IsNullOrWhiteSpace(gameName))
        {
            gameName = NormalizeDisplayIdentityPart(application.ApplicantAccount);
        }

        if (string.IsNullOrWhiteSpace(gameName))
        {
            gameName = "未识别玩家";
        }

        var displayName = string.IsNullOrWhiteSpace(callsign) ||
                          callsign.Equals(gameName, StringComparison.OrdinalIgnoreCase)
            ? gameName
            : $"{callsign} ({gameName})";

        return new FleetApplicationRow(
            application.Id,
            displayName,
            gameName,
            callsign,
            application.ApplicantAccount,
            string.IsNullOrWhiteSpace(application.Message) ? "无申请说明" : application.Message,
            string.IsNullOrWhiteSpace(application.Status) ? "Pending" : application.Status,
            application.CreatedAt == default
                ? "-"
                : application.CreatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm"),
            GetInitials(string.IsNullOrWhiteSpace(callsign) ? gameName : callsign),
            application.AvatarImageData);
    }

    private bool CanCurrentUserGenerateFleetInvite()
    {
        return FleetInvitationAccessPolicy.Allows(
            _fleetInviteCodeCreationPolicy,
            _hasFleet,
            IsCurrentUserFleetCommander(),
            HasCurrentUserFleetManagementAccess());
    }

    private bool CanCurrentUserSendFleetInvitationCard()
    {
        return FleetInvitationAccessPolicy.Allows(
            _fleetInvitationCardPolicy,
            _hasFleet,
            IsCurrentUserFleetCommander(),
            HasCurrentUserFleetManagementAccess());
    }

    private bool HasCurrentUserFleetManagementAccess()
    {
        if (IsCurrentUserFleetCommander())
        {
            return true;
        }

        var permission = GetCurrentUserFleetPermission();
        return permission is { PermissionEnabled: true } &&
               (permission.CanManageFleetInfo ||
                permission.CanRemoveMembers ||
                permission.CanPublishTasks ||
                permission.CanPublishPlans);
    }

    private void RefreshFleetInvites()
    {
        if (ManageInviteSection is null)
        {
            return;
        }

        _fleetInviteRows.Clear();
        var canInvite = CanCurrentUserGenerateFleetInvite();
        ManageInviteSection.Visibility = canInvite || CanCurrentUserEditFleetProfile()
            ? Visibility.Visible
            : Visibility.Collapsed;
        GenerateFleetInviteButton.Visibility = canInvite ? Visibility.Visible : Visibility.Collapsed;
        if (FleetMembersGenerateInviteButton is not null)
        {
            FleetMembersGenerateInviteButton.Visibility = canInvite ? Visibility.Visible : Visibility.Collapsed;
        }

        var currentInvite = canInvite ? GetCurrentUserActiveInvite() : null;
        if (FleetMembersViewInviteButton is not null)
        {
            FleetMembersViewInviteButton.Visibility = currentInvite is not null ? Visibility.Visible : Visibility.Collapsed;
        }

        if (!canInvite)
        {
            if (ManageInviteStatusText is not null)
            {
                ManageInviteStatusText.Text = "";
            }

            if (ManageInviteEmptyText is not null)
            {
                ManageInviteEmptyText.Visibility = Visibility.Visible;
            }

            return;
        }

        var invites = (_fleetInviteSnapshots ?? [])
            .OrderBy(invite => IsInviteActive(invite) ? 0 : 1)
            .ThenByDescending(invite => invite.CreatedAt)
            .Take(20)
            .Select(CreateFleetInviteRow)
            .ToArray();
        foreach (var invite in invites)
        {
            _fleetInviteRows.Add(invite);
        }

        if (ManageInviteEmptyText is not null)
        {
            ManageInviteEmptyText.Visibility = _fleetInviteRows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        if (ManageInviteStatusText is not null && string.IsNullOrWhiteSpace(ManageInviteStatusText.Text))
        {
            var activeCount = _fleetInviteRows.Count(row => row.CanRevoke);
            ManageInviteStatusText.Foreground = activeCount > 0
                ? FleetCommandBrush(BridgeBrushToken.StatusOk)
                : FleetCommandBrush(BridgeBrushToken.Ink2);
            ManageInviteStatusText.Text = activeCount > 0 ? $"{activeCount} 个有效邀请码" : "";
        }
    }

    private FleetInviteRow CreateFleetInviteRow(NetworkFleetInviteSnapshot invite)
    {
        var status = NormalizeOptionalField(invite.Status);
        var expired = invite.ExpiresAt != default && invite.ExpiresAt <= DateTimeOffset.UtcNow;
        var usedUp = invite.MaxUses > 0 && invite.UsedCount >= invite.MaxUses;
        var isActiveStatus = string.IsNullOrWhiteSpace(status) ||
            status.Equals("Active", StringComparison.OrdinalIgnoreCase);
        var canRevoke = isActiveStatus && !expired && !usedUp;
        var statusText = status switch
        {
            _ when expired => "已过期",
            _ when usedUp => "已用完",
            _ when status.Equals("Revoked", StringComparison.OrdinalIgnoreCase) => "已撤回",
            _ when status.Equals("Active", StringComparison.OrdinalIgnoreCase) => "有效",
            _ => string.IsNullOrWhiteSpace(status) ? "有效" : status
        };
        var statusBrush = statusText switch
        {
            "有效" => FleetCommandBrush(BridgeBrushToken.StatusOk),
            "已过期" or "已用完" => FleetCommandBrush(BridgeBrushToken.StatusWarn),
            "已撤回" => FleetCommandBrush(BridgeBrushToken.StatusBad),
            _ => FleetCommandBrush(BridgeBrushToken.Ink2)
        };
        var maxUsesText = invite.MaxUses <= 0 ? "不限" : invite.MaxUses.ToString(CultureInfo.InvariantCulture);
        var creatorName = string.IsNullOrWhiteSpace(invite.CreatedBy) ? "未知" : invite.CreatedBy;
        var creatorAvatarPath = ResolveInviteCreatorAvatarPath(invite);
        var creatorInitials = GetInitials(GetCallsignFromDisplayName(creatorName));

        return new FleetInviteRow(
            invite.Id,
            invite.Code,
            creatorName,
            creatorInitials,
            creatorAvatarPath,
            invite.CreatedAt == default ? "-" : invite.CreatedAt.ToLocalTime().ToString("MM-dd HH:mm"),
            invite.ExpiresAt == default ? "长期" : invite.ExpiresAt.ToLocalTime().ToString("MM-dd HH:mm"),
            $"{Math.Max(0, invite.UsedCount)}/{maxUsesText}",
            statusText,
            statusBrush,
            canRevoke);
    }

    private string? ResolveInviteCreatorAvatarPath(NetworkFleetInviteSnapshot invite)
    {
        var candidates = new[]
            {
                NormalizeDisplayIdentityPart(invite.CreatedBy),
                GetGameNameFromDisplayName(NormalizeDisplayIdentityPart(invite.CreatedBy)),
                GetCallsignFromDisplayName(NormalizeDisplayIdentityPart(invite.CreatedBy)),
                NormalizeDisplayIdentityPart(invite.CreatedByAccount)
            }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var creator = _players.FirstOrDefault(player =>
            candidates.Any(candidate =>
                candidate.Equals(player.Name, StringComparison.OrdinalIgnoreCase) ||
                candidate.Equals(player.Callsign ?? "", StringComparison.OrdinalIgnoreCase)));
        if (!string.IsNullOrWhiteSpace(creator?.AvatarPath))
        {
            return creator.AvatarPath;
        }

        if (IsCurrentUserInvite(invite))
        {
            return _avatarPath;
        }

        return null;
    }

    private NetworkFleetInviteSnapshot? GetCurrentUserActiveInvite()
    {
        return (_fleetInviteSnapshots ?? [])
            .Where(IsInviteActive)
            .Where(IsCurrentUserInvite)
            .OrderByDescending(invite => invite.CreatedAt)
            .FirstOrDefault();
    }

    private static bool IsInviteActive(NetworkFleetInviteSnapshot invite)
    {
        if (!invite.Status.Equals("Active", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (invite.ExpiresAt != default && invite.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return false;
        }

        return invite.MaxUses <= 0 || invite.UsedCount < invite.MaxUses;
    }

    private static string FormatInviteRemainingText(NetworkFleetInviteSnapshot invite)
    {
        if (invite.ExpiresAt == default)
        {
            return "长期有效";
        }

        var remaining = invite.ExpiresAt - DateTimeOffset.UtcNow;
        if (remaining <= TimeSpan.Zero)
        {
            return "已失效";
        }

        if (remaining.TotalDays >= 1)
        {
            var days = (int)Math.Floor(remaining.TotalDays);
            var hours = remaining.Hours;
            return hours > 0 ? $"还剩 {days} 天 {hours} 小时" : $"还剩 {days} 天";
        }

        if (remaining.TotalHours >= 1)
        {
            return $"还剩 {(int)Math.Ceiling(remaining.TotalHours)} 小时";
        }

        return $"还剩 {Math.Max(1, (int)Math.Ceiling(remaining.TotalMinutes))} 分钟";
    }

    private static string FormatInviteUsageText(NetworkFleetInviteSnapshot invite)
    {
        var used = Math.Max(0, invite.UsedCount);
        var total = invite.MaxUses <= 0 ? "不限" : invite.MaxUses.ToString(CultureInfo.InvariantCulture);
        return $"已使用 {used} / {total}";
    }

    private bool IsCurrentUserInvite(NetworkFleetInviteSnapshot invite)
    {
        if (!string.IsNullOrWhiteSpace(invite.CreatedByAccount) &&
            !string.IsNullOrWhiteSpace(_accountName) &&
            invite.CreatedByAccount.Trim().Equals(_accountName.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var createdBy = NormalizeDisplayIdentityPart(invite.CreatedBy);
        if (string.IsNullOrWhiteSpace(createdBy))
        {
            return false;
        }

        return EnumerateLocalIdentities()
            .Select(NormalizeDisplayIdentityPart)
            .Where(identity => !string.IsNullOrWhiteSpace(identity))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Any(identity => identity.Equals(createdBy, StringComparison.OrdinalIgnoreCase));
    }

    private void GenerateFleetInviteButton_Click(object sender, RoutedEventArgs e)
    {
        ShowFleetInviteDialog();
    }

    private void FleetMembersGenerateInviteButton_Click(object sender, RoutedEventArgs e)
    {
        ShowFleetInviteDialog();
    }

    private void FleetMembersViewInviteButton_Click(object sender, RoutedEventArgs e)
    {
        ShowCurrentFleetInviteDialog();
    }

    private void ShowFleetInviteDialog()
    {
        if (!EnsureLoggedIn("生成邀请码需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserGenerateFleetInvite())
        {
            SetFleetInviteStatus("当前账号没有生成邀请码的权限。", isError: true);
            return;
        }

        if (FleetInviteDialogStatusText is not null)
        {
            FleetInviteDialogStatusText.Text = "选择规则后点击生成。新邀请码会让你上一个有效邀请码失效。";
            FleetInviteDialogStatusText.Foreground = FleetCommandBrush(BridgeBrushToken.StatusWarn);
        }

        if (ConfirmGenerateFleetInviteButton is not null)
        {
            ConfirmGenerateFleetInviteButton.IsEnabled = true;
        }

        FleetInviteDialogOverlay.Show();
    }

    private void CloseFleetInviteDialog()
    {
        FleetInviteDialogOverlay.Hide();
    }

    private void FleetInviteDialogCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CloseFleetInviteDialog();
    }

    private void ShowCurrentFleetInviteDialog()
    {
        var invite = GetCurrentUserActiveInvite();
        if (invite is null)
        {
            SetFleetInviteStatus("当前账号还没有有效邀请码。", tone: FleetInviteStatusTone.Warning);
            ShowFleetInviteDialog();
            return;
        }

        _currentFleetInviteDialogInvite = invite;
        if (CurrentFleetInviteCodeText is not null)
        {
            CurrentFleetInviteCodeText.Text = invite.Code;
        }

        if (CurrentFleetInviteRemainingText is not null)
        {
            CurrentFleetInviteRemainingText.Text = FormatInviteRemainingText(invite);
        }

        if (CurrentFleetInviteUsageText is not null)
        {
            CurrentFleetInviteUsageText.Text = FormatInviteUsageText(invite);
        }

        if (FleetInviteViewStatusText is not null)
        {
            FleetInviteViewStatusText.Text = "同一账号只能保留一个有效邀请码，生成新的会使旧邀请码失效。";
            FleetInviteViewStatusText.Foreground = FleetCommandBrush(BridgeBrushToken.StatusWarn);
        }

        FleetInviteViewDialogOverlay.Show();
    }

    private void CloseFleetInviteViewDialog()
    {
        _currentFleetInviteDialogInvite = null;
        FleetInviteViewDialogOverlay.Hide();
    }

    private void FleetInviteViewDialogCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CloseFleetInviteViewDialog();
    }

    private void CopyCurrentFleetInviteButton_Click(object sender, RoutedEventArgs e)
    {
        var invite = _currentFleetInviteDialogInvite ?? GetCurrentUserActiveInvite();
        if (invite is null)
        {
            if (FleetInviteViewStatusText is not null)
            {
                FleetInviteViewStatusText.Text = "当前没有可复制的邀请码。";
                FleetInviteViewStatusText.Foreground = FleetCommandBrush(BridgeBrushToken.StatusBad);
            }
            return;
        }

        try
        {
            System.Windows.Clipboard.SetText(invite.Code);
            if (FleetInviteViewStatusText is not null)
            {
                FleetInviteViewStatusText.Text = "邀请码已复制。";
                FleetInviteViewStatusText.Foreground = FleetCommandBrush(BridgeBrushToken.StatusOk);
            }
        }
        catch (Exception ex)
        {
            if (FleetInviteViewStatusText is not null)
            {
                FleetInviteViewStatusText.Text = UserFacingError.Describe(ex, "邀请码未能复制，请稍后重试。");
                FleetInviteViewStatusText.Foreground = FleetCommandBrush(BridgeBrushToken.StatusBad);
            }
        }
    }

    private async void ConfirmGenerateFleetInviteButton_Click(object sender, RoutedEventArgs e)
    {
        if (ConfirmGenerateFleetInviteButton is not null)
        {
            ConfirmGenerateFleetInviteButton.IsEnabled = false;
        }

        try
        {
            if (await CreateFleetInviteAsync())
            {
                CloseFleetInviteDialog();
            }
        }
        finally
        {
            if (ConfirmGenerateFleetInviteButton is not null)
            {
                ConfirmGenerateFleetInviteButton.IsEnabled = true;
            }
        }
    }

    private void CopyFleetInvite_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetInviteRow row)
        {
            return;
        }

        try
        {
            System.Windows.Clipboard.SetText(row.Code);
            SetFleetInviteStatus("邀请码已复制。", tone: FleetInviteStatusTone.Success);
        }
        catch (Exception ex)
        {
            SetFleetInviteStatus(UserFacingError.Describe(ex, "邀请码未能复制，请稍后重试。"), isError: true);
        }
    }

    private async void RevokeFleetInvite_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetInviteRow row)
        {
            return;
        }

        if (StarBridgeMessageBox.Show(
                this,
                $"确认撤回邀请码 {row.Code}？撤回后已持有该邀请码的玩家将无法继续使用。",
                "撤回邀请码",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        await RevokeFleetInviteAsync(row);
    }

    private async Task<bool> CreateFleetInviteAsync()
    {
        if (!EnsureLoggedIn("生成邀请码需要先登录星海舰桥账号。"))
        {
            return false;
        }

        if (!CanCurrentUserGenerateFleetInvite())
        {
            SetFleetInviteStatus("当前账号没有生成邀请码的权限。", isError: true);

            return false;
        }

        var days = GetComboBoxTagInt(ManageInviteExpiryBox, 7);
        var maxUses = GetComboBoxTagInt(ManageInviteUsesBox, 1);
        try
        {
            var previousOwnInvite = (_fleetInviteSnapshots ?? [])
                .Where(IsInviteActive)
                .Where(IsCurrentUserInvite)
                .OrderByDescending(invite => invite.CreatedAt)
                .FirstOrDefault();

            if (previousOwnInvite is not null)
            {
                SetFleetInviteStatus("正在让上一个邀请码失效...", tone: FleetInviteStatusTone.Warning);
                var revokeResponse = await PostNetworkJsonAsync(
                    "api/fleets/invites/revoke",
                    new FleetInviteRevokeRequest(_fleetCode, previousOwnInvite.Id));
                if (!revokeResponse.IsSuccessStatusCode)
                {
                    SetFleetInviteStatus($"旧邀请码失效失败：{await ReadResponseErrorAsync(revokeResponse)}", isError: true);
                    return false;
                }

                var revokedSnapshot = await revokeResponse.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
                if (revokedSnapshot is not null)
                {
                    MergeNetworkFleetState(revokedSnapshot);
                    SaveCurrentConfig();
                }
            }

            SetFleetInviteStatus("正在生成邀请码...", tone: FleetInviteStatusTone.Warning);

            var response = await PostNetworkJsonAsync(
                "api/fleets/invites",
                new FleetInviteCreateRequest(_fleetCode, days, maxUses, "Direct"));
            if (!response.IsSuccessStatusCode)
            {
                SetFleetInviteStatus($"生成失败：{await ReadResponseErrorAsync(response)}", isError: true);

                return false;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is not null)
            {
                MergeNetworkFleetState(snapshot);
                SaveCurrentConfig();
            }

            var newestCode = (snapshot?.Invites ?? _fleetInviteSnapshots ?? [])
                .Where(IsInviteActive)
                .OrderByDescending(invite => invite.CreatedAt)
                .FirstOrDefault()
                ?.Code;
            var copied = false;
            if (!string.IsNullOrWhiteSpace(newestCode))
            {
                try
                {
                    System.Windows.Clipboard.SetText(newestCode);
                    copied = true;
                }
                catch
                {
                    copied = false;
                }
            }

            await PullNetworkFleetsAsync(silent: true);
            SetFleetInviteStatus(
                copied ? "邀请码已生成并复制。上一个有效邀请码已失效。" : "邀请码已生成。上一个有效邀请码已失效。",
                tone: FleetInviteStatusTone.Success);
            return true;
        }
        catch (Exception ex)
        {
            SetFleetInviteStatus(UserFacingError.Describe(ex, "邀请码未能生成，请稍后重试。"), isError: true);
            return false;
        }
    }

    private enum FleetInviteStatusTone
    {
        Neutral,
        Success,
        Warning,
        Error
    }

    private void SetFleetInviteStatus(string text, bool isError = false, FleetInviteStatusTone tone = FleetInviteStatusTone.Neutral)
    {
        if (isError)
        {
            tone = FleetInviteStatusTone.Error;
        }

        var brush = tone switch
        {
            FleetInviteStatusTone.Success => FleetCommandBrush(BridgeBrushToken.StatusOk),
            FleetInviteStatusTone.Warning => FleetCommandBrush(BridgeBrushToken.StatusWarn),
            FleetInviteStatusTone.Error => FleetCommandBrush(BridgeBrushToken.StatusBad),
            _ => FleetCommandBrush(BridgeBrushToken.Ink2)
        };

        if (ManageInviteStatusText is not null)
        {
            ManageInviteStatusText.Text = text;
            ManageInviteStatusText.Foreground = brush;
        }

        if (FleetInviteDialogStatusText is not null)
        {
            FleetInviteDialogStatusText.Text = text;
            FleetInviteDialogStatusText.Foreground = brush;
        }
    }

    private async Task RevokeFleetInviteAsync(FleetInviteRow row)
    {
        try
        {
            SetFleetInviteStatus("正在撤回邀请码...", tone: FleetInviteStatusTone.Warning);

            var response = await PostNetworkJsonAsync(
                "api/fleets/invites/revoke",
                new FleetInviteRevokeRequest(_fleetCode, row.Id));
            if (!response.IsSuccessStatusCode)
            {
                SetFleetInviteStatus($"撤回失败:{await ReadResponseErrorAsync(response)}", isError: true);

                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is not null)
            {
                MergeNetworkFleetState(snapshot);
                SaveCurrentConfig();
            }

            await PullNetworkFleetsAsync(silent: true);
            SetFleetInviteStatus("邀请码已撤回。", tone: FleetInviteStatusTone.Success);
        }
        catch (Exception ex)
        {
            SetFleetInviteStatus(UserFacingError.Describe(ex, "邀请码未能撤回，请稍后重试。"), isError: true);
        }
    }

    private static int GetComboBoxTagInt(System.Windows.Controls.ComboBox? comboBox, int fallback)
    {
        return comboBox?.SelectedItem is ComboBoxItem item &&
               int.TryParse(item.Tag?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;
    }

    private static string GetComboBoxTagText(System.Windows.Controls.ComboBox? comboBox, string fallback)
    {
        return comboBox?.SelectedItem is ComboBoxItem item &&
               !string.IsNullOrWhiteSpace(item.Tag?.ToString())
            ? item.Tag!.ToString()!.Trim()
            : fallback;
    }

    private async void ApproveFleetApplication_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is FleetApplicationRow row)
        {
            await DecideFleetApplicationAsync(row, approve: true);
        }
    }

    private async void RejectFleetApplication_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is FleetApplicationRow row)
        {
            await DecideFleetApplicationAsync(row, approve: false);
        }
    }

    private async Task DecideFleetApplicationAsync(FleetApplicationRow row, bool approve)
    {
        if (!EnsureLoggedIn("审核加入申请需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!CanCurrentUserManageFleetInfo())
        {
            FleetApplicationStatusText.Text = "当前账号没有审核加入申请的权限。";
            return;
        }

        var actionText = approve ? "批准" : "拒绝";
        if (StarBridgeMessageBox.Show(
                this,
                $"确认{actionText} {row.DisplayName} 的加入申请？",
                "审核加入申请",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/applications/decide",
                new FleetApplicationDecisionRequest(_fleetCode, row.Id, approve));
            if (!response.IsSuccessStatusCode)
            {
                FleetApplicationStatusText.Text = $"{actionText}失败：{await ReadResponseErrorAsync(response)}";
                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is not null)
            {
                MergeNetworkFleetState(snapshot);
                SaveCurrentConfig();
            }

            await PullNetworkSnapshotsAsync(silent: true);
            await PullNetworkFleetsAsync(silent: true);
            FleetApplicationStatusText.Text = $"已{actionText} {row.DisplayName}。";
        }
        catch (Exception ex)
        {
            FleetApplicationStatusText.Text = UserFacingError.Describe(ex, $"{actionText}未完成，请稍后重试。");
        }
    }

    private bool CanCurrentUserRemoveFleetMember(string? gameName, string? callsign, bool isCommander)
    {
        if (!_hasFleet || isCommander)
        {
            return false;
        }

        var identity = NormalizeOptionalField(gameName);
        if (IsLocalPlayer(identity) || IsLocalPlayer(callsign ?? ""))
        {
            return false;
        }

        if (IsCurrentUserFleetCommander())
        {
            return true;
        }

        if (!CanCurrentUserRemoveMembers())
        {
            return false;
        }

        var targetPermission = GetFleetPermission(gameName, callsign);
        return targetPermission is null || !targetPermission.PermissionEnabled;
    }

    private async void SaveFleetMemberPermission_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetMemberManagementRow row)
        {
            return;
        }

        if (row.IsCommander)
        {
            FleetMemberManagementStatusText.Text = "舰队指挥官默认拥有所有权限。";
            return;
        }

        if (!row.CanEditPermissions)
        {
            FleetMemberManagementStatusText.Text = "只有舰队指挥官可以分配权限。";
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        var isBaseMember = row.RoleTitle.Equals("基础成员", StringComparison.OrdinalIgnoreCase) ||
                           row.RoleTitle.Equals("成员", StringComparison.OrdinalIgnoreCase) ||
                           row.RoleTitle.Equals("普通成员", StringComparison.OrdinalIgnoreCase);
        if (IsFleetCommanderRole(null, row.RoleTitle))
        {
            FleetMemberManagementStatusText.Text = "舰队指挥官为唯一特殊身份，请通过转移指挥官处理。";
            return;
        }

        var role = isBaseMember ? "成员" : NormalizeRoleTitle(row.RoleTitle);
        var roleGroupKey = isBaseMember ? "" : ResolveRoleGroupKeyFromDisplayName(role);
        if (roleGroupKey.Equals("fleet_commander", StringComparison.OrdinalIgnoreCase))
        {
            FleetMemberManagementStatusText.Text = "舰队指挥官为唯一特殊身份，请通过转移指挥官处理。";
            return;
        }

        row.RoleTitle = role;
        if (isBaseMember)
        {
            row.PermissionEnabled = false;
            row.CanManageFleetInfo = false;
            row.CanRemoveMembers = false;
            row.CanPublishTasks = false;
            row.CanPublishPlans = false;
        }
        else
        {
            row.PermissionEnabled = true;
            var rolePermissionIds = ResolveRoleGroupPermissionIds(roleGroupKey, BuildExtraAllowedPermissions(row));
            var flags = MapPermissionIdsToFleetPermissionFlags(rolePermissionIds);
            row.CanManageFleetInfo = flags.CanManageFleetInfo;
            row.CanRemoveMembers = flags.CanRemoveMembers;
            row.CanPublishTasks = flags.CanPublishTasks;
            row.CanPublishPlans = flags.CanPublishPlans;
        }

        _fleetMemberPermissions[row.GameName] = new LocalFleetMemberPermission(
            row.GameName,
            row.Callsign,
            role,
            row.PermissionEnabled,
            row.CanRemoveMembers,
            row.CanPublishTasks,
            row.CanPublishPlans,
            row.CanManageFleetInfo,
            DateTimeOffset.UtcNow,
            roleGroupKey,
            row.PermissionEnabled ? ResolveRoleGroupPermissionIds(roleGroupKey, BuildExtraAllowedPermissions(row)) : [],
            []);

        AddFleetLog("权限", "成员权限更新", $"{row.DisplayName} -> {role}");
        SaveCurrentConfig();
        var synced = await PushFleetMemberPermissionAsync(row, silent: false);
        if (!synced)
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "成员权限同步失败，已恢复本地权限状态。");
            FleetMemberManagementStatusText.Text = $"保存 {row.DisplayName} 的权限失败，已恢复本地状态。";
            return;
        }

        RefreshFleetMemberManagement();
        FleetMemberManagementStatusText.Text = $"已保存并同步 {row.DisplayName} 的权限。";
    }

    private static string[] BuildExtraAllowedPermissions(FleetMemberManagementRow row)
    {
        var permissions = new List<string>();
        if (row.CanManageFleetInfo)
        {
            permissions.Add("fleet.profile.edit");
        }

        if (row.CanRemoveMembers)
        {
            permissions.Add("members.remove");
        }

        return permissions.ToArray();
    }

    private string[] ResolveRoleGroupPermissionIds(string? roleGroupKey, IEnumerable<string>? fallback = null)
    {
        var normalizedKey = NormalizeRoleGroupKey(roleGroupKey);
        if (!string.IsNullOrWhiteSpace(normalizedKey))
        {
            var row = _fleetSystemRoleGroups
                .Concat(_fleetCustomRoleGroups)
                .FirstOrDefault(role => role.Key.Equals(normalizedKey, StringComparison.OrdinalIgnoreCase));
            if (row is not null)
            {
                return BuildFleetRoleGroupPermissionIds(row);
            }

            if (_fleetRoleGroupDefinitions.TryGetValue(normalizedKey, out var definition))
            {
                return NormalizePermissionIds(definition.Permissions);
            }
        }

        return NormalizePermissionIds(fallback);
    }

    private static string[] NormalizePermissionIds(IEnumerable<string>? permissionIds)
    {
        return (permissionIds ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Where(id => !id.Equals(FleetPermissionPolicy.RetiredInviteMembers, StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(id => id, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static FleetPermissionFlags MapPermissionIdsToFleetPermissionFlags(IEnumerable<string>? permissionIds)
    {
        var ids = NormalizePermissionIds(permissionIds).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var canManageFleetInfo = ids.Any(id =>
            id.StartsWith("fleet.", StringComparison.OrdinalIgnoreCase) ||
            id.Equals("members.review", StringComparison.OrdinalIgnoreCase) ||
            id.Equals("audit.view", StringComparison.OrdinalIgnoreCase) ||
            id.Equals("audit.delete", StringComparison.OrdinalIgnoreCase));
        var canRemoveMembers = ids.Contains("members.remove");
        var canPublishTasks = false;
        var canPublishPlans = false;

        return new FleetPermissionFlags(
            canManageFleetInfo,
            canRemoveMembers,
            canPublishTasks,
            canPublishPlans);
    }

    private readonly record struct FleetPermissionFlags(
        bool CanManageFleetInfo,
        bool CanRemoveMembers,
        bool CanPublishTasks,
        bool CanPublishPlans);

    private void FleetMemberMoreButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button ||
            button.Tag is not PlayerRow row)
        {
            return;
        }

        var isTargetCommander = IsFleetCommander(row.Name, row.Callsign);
        var isCurrentCommander = IsCurrentUserFleetCommander();
        var canChangeRole = isCurrentCommander && !row.IsSelf && !isTargetCommander;
        var canTransferCommand = isCurrentCommander && !row.IsSelf && !isTargetCommander;
        var canRemove = CanCurrentUserRemoveFleetMember(row.Name, row.Callsign, isTargetCommander);
        var menu = new ContextMenu
        {
            Background = FleetCommandBrush(BridgeBrushToken.Panel),
            BorderBrush = FleetCommandBrush(BridgeBrushToken.Hairline),
            BorderThickness = new Thickness(1),
            PlacementTarget = button,
            Style = (Style)FindResource("StarBridgeContextMenu")
        };

        var roleItem = new MenuItem
        {
            Header = "更改身份组",
            IsEnabled = canChangeRole,
            Foreground = canChangeRole
                ? FleetCommandBrush(BridgeBrushToken.Ink)
                : FleetCommandBrush(BridgeBrushToken.Ink2),
            Background = Brushes.Transparent,
            Style = (Style)FindResource("StarBridgeContextMenuItem")
        };
        BuildFleetMemberRoleSubmenu(roleItem, row, canChangeRole);
        menu.Items.Add(roleItem);

        var transferItem = new MenuItem
        {
            Header = "转移舰队指挥官",
            Tag = row,
            IsEnabled = canTransferCommand,
            Foreground = canTransferCommand
                ? FleetCommandBrush(BridgeBrushToken.StatusWarn)
                : FleetCommandBrush(BridgeBrushToken.Ink2),
            Background = Brushes.Transparent,
            Style = (Style)FindResource("StarBridgeContextMenuItem")
        };
        transferItem.Click += TransferFleetCommanderFromDeck_Click;
        menu.Items.Add(transferItem);
        menu.Items.Add(new Separator
        {
            Style = (Style)FindResource("StarBridgeContextMenuSeparator")
        });

        var removeItem = new MenuItem
        {
            Header = "移除成员",
            Tag = row,
            IsEnabled = canRemove,
            Foreground = canRemove
                ? FleetCommandBrush(BridgeBrushToken.StatusBad)
                : FleetCommandBrush(BridgeBrushToken.Ink2),
            Background = Brushes.Transparent,
            Style = (Style)FindResource("StarBridgeContextMenuItem")
        };
        removeItem.Click += RemoveFleetMemberFromDeck_Click;
        menu.Items.Add(removeItem);

        button.ContextMenu = menu;
        menu.IsOpen = true;
    }

    private void BuildFleetMemberRoleSubmenu(MenuItem parent, PlayerRow player, bool canChangeRole)
    {
        if (_fleetSystemRoleGroups.Count == 0 && _fleetCustomRoleGroups.Count == 0)
        {
            RefreshFleetRoleGroups();
        }

        var currentPermission = GetFleetPermission(player.Name, player.Callsign);
        var currentRoleKey = NormalizeRoleGroupKey(currentPermission?.RoleGroupKey, currentPermission?.RoleTitle);
        var baseMemberItem = new MenuItem
        {
            Header = string.IsNullOrWhiteSpace(currentRoleKey) ? "✓  基础成员" : "基础成员",
            IsEnabled = canChangeRole,
            Tag = new FleetMemberRoleMenuAction(player, "", "基础成员"),
            Background = Brushes.Transparent,
            Style = (Style)FindResource("StarBridgeContextMenuItem")
        };
        baseMemberItem.Click += ChangeFleetMemberRoleFromDeck_Click;
        parent.Items.Add(baseMemberItem);

        var roles = _fleetSystemRoleGroups
            .Concat(_fleetCustomRoleGroups)
            .Where(role => role.IsEnabled && !role.IsCommanderSeat)
            .OrderBy(role => role.SortOrder)
            .ThenBy(role => role.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        if (roles.Length > 0)
        {
            parent.Items.Add(new Separator
            {
                Style = (Style)FindResource("StarBridgeContextMenuSeparator")
            });
        }

        foreach (var role in roles)
        {
            var item = new MenuItem
            {
                Header = role.Key.Equals(currentRoleKey, StringComparison.OrdinalIgnoreCase)
                    ? $"✓  {role.DisplayName}"
                    : role.DisplayName,
                IsEnabled = canChangeRole,
                Tag = new FleetMemberRoleMenuAction(player, role.Key, role.DisplayName),
                Foreground = role.AccentBrush,
                Background = Brushes.Transparent,
                Style = (Style)FindResource("StarBridgeContextMenuItem")
            };
            item.Click += ChangeFleetMemberRoleFromDeck_Click;
            parent.Items.Add(item);
        }
    }

    private async void ChangeFleetMemberRoleFromDeck_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetMemberRoleMenuAction action ||
            !IsCurrentUserFleetCommander() ||
            action.Player.IsSelf ||
            IsFleetCommander(action.Player.Name, action.Player.Callsign))
        {
            return;
        }

        var currentPermission = GetFleetPermission(action.Player.Name, action.Player.Callsign);
        var currentRoleKey = NormalizeRoleGroupKey(currentPermission?.RoleGroupKey, currentPermission?.RoleTitle);
        if (currentRoleKey.Equals(action.RoleGroupKey, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var displayName = FormatCommanderName(action.Player.Callsign, action.Player.Name);
        var confirmed = await ShowAppConfirmationAsync(
            "更改身份组",
            $"将 {displayName} 的身份组更改为“{action.RoleTitle}”？",
            "保存后，新身份组的管理权限会立即同步。舰队指挥官是唯一特殊身份，不能通过此菜单授予。",
            "确认更改",
            "取消",
            danger: false,
            footerText: "身份组变更会写入舰队日志。");
        if (!confirmed)
        {
            return;
        }

        var isBaseMember = string.IsNullOrWhiteSpace(action.RoleGroupKey);
        var permissionIds = isBaseMember
            ? []
            : ResolveRoleGroupPermissionIds(action.RoleGroupKey);
        var flags = MapPermissionIdsToFleetPermissionFlags(permissionIds);
        var permission = new NetworkFleetMemberPermissionSnapshot(
            action.Player.Name,
            action.Player.Callsign,
            isBaseMember ? "成员" : action.RoleTitle,
            !isBaseMember,
            !isBaseMember && flags.CanRemoveMembers,
            false,
            false,
            !isBaseMember && flags.CanManageFleetInfo,
            DateTimeOffset.UtcNow,
            isBaseMember ? null : action.RoleGroupKey,
            null,
            null);

        var synced = await PushFleetMutationAsync(
            "api/fleets/permissions",
            new FleetMemberPermissionUpdateRequest(_fleetCode, permission, null),
            $"已将 {displayName} 更改为{action.RoleTitle}",
            "更改身份组失败",
            silent: false);
        if (!synced)
        {
            return;
        }

        await PullNetworkSnapshotsAsync(silent: true);
        await PullNetworkFleetsAsync(silent: true);
        RefreshFleetMemberManagement();
    }

    private async void TransferFleetCommanderFromDeck_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PlayerRow row)
        {
            return;
        }

        await TransferFleetCommanderAsync(
            row.Name,
            row.Callsign,
            FormatCommanderName(row.Callsign, row.Name),
            message => NetworkStatusText.Text = message);
    }

    private async void RemoveFleetMemberFromDeck_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PlayerRow row)
        {
            return;
        }

        await RemoveFleetMemberAsync(
            row.Name,
            row.Callsign,
            FormatCommanderName(row.Callsign, row.Name),
            message => NetworkStatusText.Text = message);
    }

    private async void RemoveFleetMember_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetMemberManagementRow row)
        {
            return;
        }

        await RemoveFleetMemberAsync(
            row.GameName,
            row.Callsign,
            row.DisplayName,
            message => FleetMemberManagementStatusText.Text = message);
    }

    private async Task RemoveFleetMemberAsync(
        string gameName,
        string? callsign,
        string displayName,
        Action<string> setStatus)
    {
        if (!CanCurrentUserRemoveFleetMember(gameName, callsign, IsFleetCommander(gameName, callsign)))
        {
            setStatus("当前账号没有移除此成员的权限。");
            await ShowAppNoticeAsync(
                "无法移除成员",
                "当前账号没有移除此成员的权限。",
                "舰队指挥官不能从成员菜单移除自己，也不能通过成员移除流程处理舰队指挥官。");
            return;
        }

        var confirmed = await ShowAppConfirmationAsync(
            "移除成员",
            $"确认将 {displayName} 移出舰队？",
            "该成员会立即失去舰队同步、舰队成员信息和内部舰队数据访问。此操作会写入舰队日志。",
            "移除成员",
            "取消");
        if (!confirmed)
        {
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/fleets/members/remove",
                new FleetMemberMutationRequest(_fleetCode, gameName));
            if (!response.IsSuccessStatusCode)
            {
                setStatus($"移除失败：{await ReadResponseErrorAsync(response)}");
                return;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is not null)
            {
                MergeNetworkFleetState(snapshot);
            }

            _fleetMemberPermissions.Remove(gameName);
            AddFleetLog("成员", "移除成员", $"{displayName} 被移出舰队");
            await PullNetworkSnapshotsAsync(silent: true);
            await PullNetworkFleetsAsync(silent: true);
            RefreshFleetMemberManagement();
            setStatus($"已移除 {displayName}。");
        }
        catch (Exception ex)
        {
            setStatus(UserFacingError.Describe(ex, "成员未能移除，请稍后重试。"));
        }
    }

    private async void TransferFleetCommander_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FleetMemberManagementRow row)
        {
            return;
        }

        if (!row.CanTransferCommander)
        {
            FleetMemberManagementStatusText.Text = "只有舰队指挥官可以转移指挥权。";
            return;
        }

        await TransferFleetCommanderAsync(
            row.GameName,
            row.Callsign,
            row.DisplayName,
            message => FleetMemberManagementStatusText.Text = message);
    }

    private async Task TransferFleetCommanderAsync(
        string gameName,
        string? callsign,
        string displayName,
        Action<string> setStatus)
    {
        if (!IsCurrentUserFleetCommander() ||
            IsLocalPlayer(gameName) ||
            IsLocalPlayer(callsign ?? "") ||
            IsFleetCommander(gameName, callsign))
        {
            setStatus("只有当前舰队指挥官可以把指挥权转移给其他成员。");
            return;
        }

        var confirmed = await ShowAppConfirmationAsync(
            "转移舰队指挥官",
            $"确认将舰队指挥权转移给 {displayName}？",
            "转移后，对方将成为唯一舰队指挥官并拥有全部权限。你将自动变更为舰队副指挥官；此操作会立即同步且不能在本机撤销。",
            "确认转移",
            "取消",
            danger: true,
            footerText: "为避免舰队失去管理者，服务器会原子完成指挥权交接。");
        if (!confirmed)
        {
            return;
        }

        var synced = await PushFleetMutationAsync(
            "api/fleets/transfer-commander",
            new FleetCommanderTransferRequest(_fleetCode, gameName),
            $"舰队指挥权已转移给 {displayName}",
            "转移舰队指挥官失败",
            silent: false);
        if (!synced)
        {
            setStatus("转移舰队指挥官失败，当前指挥权未改变。");
            return;
        }

        SaveCurrentConfig();
        await PullNetworkSnapshotsAsync(silent: true);
        await PullNetworkFleetsAsync(silent: true);
        RefreshFleetMemberManagement();
        setStatus($"舰队指挥权已转移给 {displayName}。");
    }

    private sealed record FleetMemberRoleMenuAction(
        PlayerRow Player,
        string RoleGroupKey,
        string RoleTitle);

    private static string LimitCallsign(string value)
    {
        var total = 0;
        var builder = new System.Text.StringBuilder();
        foreach (var character in value)
        {
            var weight = IsCjk(character) ? 2 : 1;
            if (total + weight > 10)
            {
                break;
            }

            builder.Append(character);
            total += weight;
        }

        return builder.ToString();
    }

    private static bool IsCjk(char character)
    {
        return (character >= '\u4E00' && character <= '\u9FFF') ||
               (character >= '\u3400' && character <= '\u4DBF') ||
               (character >= '\uF900' && character <= '\uFAFF');
    }
}
