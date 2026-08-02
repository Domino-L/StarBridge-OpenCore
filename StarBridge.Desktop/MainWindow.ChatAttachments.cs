using StarBridge.Core.Chat;
using StarBridge.Core.Fleets;
using StarBridge.Core.Friends;
using StarBridge.Core.PartyRooms;
using System.IO;
using System.Net.Http.Json;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private enum ChatAttachmentTarget
    {
        FleetChannel,
        PartyRoom,
        DirectMessage
    }

    private sealed record ChatAttachmentDestination(
        Button Anchor,
        ChatAttachmentTarget Target);

    private void FleetChatAttachmentButton_Click(object sender, RoutedEventArgs e) =>
        OpenChatAttachmentMenu((Button)sender, ChatAttachmentTarget.FleetChannel);

    private void PartyRoomChatAttachmentButton_Click(object sender, RoutedEventArgs e) =>
        OpenChatAttachmentMenu((Button)sender, ChatAttachmentTarget.PartyRoom);

    private void FriendChatAttachmentButton_Click(object sender, RoutedEventArgs e) =>
        OpenChatAttachmentMenu((Button)sender, ChatAttachmentTarget.DirectMessage);

    private void OpenChatAttachmentMenu(Button anchor, ChatAttachmentTarget target) =>
        OpenChatAttachmentMenu(new ChatAttachmentDestination(anchor, target));

    private void OpenChatAttachmentMenu(ChatAttachmentDestination destination)
    {
        var menu = new ContextMenu
        {
            PlacementTarget = destination.Anchor,
            Placement = PlacementMode.Top,
            HorizontalOffset = 0,
            VerticalOffset = -4
        };
        if (TryFindResource("StarBridgeContextMenu") is Style menuStyle)
        {
            menu.Style = menuStyle;
        }

        menu.Items.Add(CreateOverlayPresetAttachmentMenu(destination));

        if (destination.Target is ChatAttachmentTarget.PartyRoom or ChatAttachmentTarget.DirectMessage)
        {
            var separator = new Separator();
            if (TryFindResource("StarBridgeContextMenuSeparator") is Style separatorStyle)
            {
                separator.Style = separatorStyle;
            }
            menu.Items.Add(separator);

            var isDirectMessage = destination.Target == ChatAttachmentTarget.DirectMessage;
            var friendAlreadyInFleet = isDirectMessage && IsActiveFriendInCurrentFleet();
            var eligibleRoomMembers = isDirectMessage ? 0 : CountPartyRoomFleetInvitationRecipients();
            var canSendFleetCard = CanCurrentUserSendFleetInvitationCard();
            menu.Items.Add(CreateChatAttachmentMenuItem(
                ResolveFleetInvitationMenuText(isDirectMessage, friendAlreadyInFleet, eligibleRoomMembers, canSendFleetCard),
                canSendFleetCard && (isDirectMessage
                    ? _activeFriendChatUser is not null && !friendAlreadyInFleet
                    : eligibleRoomMembers > 0),
                async () => await SendFleetInvitationToChatAsync(destination)));

            if (isDirectMessage)
            {
                var friendAlreadyInRoom = IsActiveFriendInCurrentPartyRoom();
                var roomInvitationPending = HasPendingPartyRoomInvitationForActiveFriend();
                menu.Items.Add(CreateChatAttachmentMenuItem(
                    friendAlreadyInRoom
                        ? "已在当前房间"
                        : roomInvitationPending
                            ? "房间邀请已发送"
                            : "发送房间邀请",
                    _activeFriendChatUser is not null &&
                    !friendAlreadyInRoom &&
                    !roomInvitationPending &&
                    _currentPartyRoom is { ViewerIsHost: true },
                    SendPartyRoomInvitationToActiveChatAsync));
            }
        }

        menu.IsOpen = true;
    }

    private MenuItem CreateOverlayPresetAttachmentMenu(ChatAttachmentDestination destination)
    {
        if (_overlayPresetEntries.Count == 0)
        {
            LoadOverlayPresetEntries();
        }

        var presetMenu = new MenuItem
        {
            Header = "发送浮层预设",
            IsEnabled = _overlayPresetEntries.Count > 0
        };
        if (TryFindResource("StarBridgeContextMenuItem") is Style itemStyle)
        {
            presetMenu.Style = itemStyle;
        }

        foreach (var preset in _overlayPresetEntries.ToArray())
        {
            var isCurrent = preset.Id.Equals(_activeOverlayPreset, StringComparison.OrdinalIgnoreCase);
            presetMenu.Items.Add(CreateChatAttachmentMenuItem(
                isCurrent ? $"{preset.Name} · 当前" : preset.Name,
                true,
                async () => await SendOverlayPresetAsync(destination, preset)));
        }

        return presetMenu;
    }

    private bool IsActiveFriendInCurrentFleet()
    {
        return IsAccountInCurrentFleet(_activeFriendChatUser?.AccountId);
    }

    private bool IsAccountInCurrentFleet(string? accountId)
    {
        return _hasFleet &&
               !string.IsNullOrWhiteSpace(accountId) &&
               _networkSnapshots.Values.Any(member =>
                   !string.IsNullOrWhiteSpace(member.AccountId) &&
                   member.AccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase));
    }

    private int CountPartyRoomFleetInvitationRecipients()
    {
        if (_currentPartyRoom is null)
        {
            return 0;
        }

        return _currentPartyRoom.Members.Count(member =>
            !string.IsNullOrWhiteSpace(member.AccountId) &&
            !member.AccountId.Equals(_accountId, StringComparison.OrdinalIgnoreCase) &&
            !IsAccountInCurrentFleet(member.AccountId));
    }

    private string ResolveFleetInvitationMenuText(
        bool isDirectMessage,
        bool friendAlreadyInFleet,
        int eligibleRoomMembers,
        bool canSendFleetCard)
    {
        if (!_hasFleet)
        {
            return "当前未加入舰队";
        }

        if (!canSendFleetCard)
        {
            return "无权发送舰队邀请";
        }

        if (isDirectMessage)
        {
            return friendAlreadyInFleet ? "已在当前舰队" : "邀请加入舰队";
        }

        return eligibleRoomMembers > 0 ? "邀请房间成员加入舰队" : "房间成员均在当前舰队";
    }

    private bool IsActiveFriendInCurrentPartyRoom()
    {
        var accountId = _activeFriendChatUser?.AccountId;
        return !string.IsNullOrWhiteSpace(accountId) &&
               _currentPartyRoom?.Members.Any(member =>
                   !string.IsNullOrWhiteSpace(member.AccountId) &&
                   member.AccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase)) == true;
    }

    private bool HasPendingPartyRoomInvitationForActiveFriend()
    {
        var accountId = _activeFriendChatUser?.AccountId;
        var roomId = _currentPartyRoom?.RoomId;
        return !string.IsNullOrWhiteSpace(accountId) &&
               !string.IsNullOrWhiteSpace(roomId) &&
               _sentPartyRoomInvitations.Any(invitation =>
                   invitation.RoomId.Equals(roomId, StringComparison.OrdinalIgnoreCase) &&
                   invitation.RecipientAccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase) &&
                   invitation.ExpiresAt > DateTimeOffset.UtcNow);
    }

    private MenuItem CreateChatAttachmentMenuItem(string header, bool enabled, Func<Task> action)
    {
        var item = new MenuItem
        {
            Header = header,
            IsEnabled = enabled
        };
        if (TryFindResource("StarBridgeContextMenuItem") is Style itemStyle)
        {
            item.Style = itemStyle;
        }

        item.Click += async (_, _) => await action();
        return item;
    }

    private ChatAttachmentContract BuildOverlayPresetAttachment(OverlayPresetEntry preset)
    {
        var isCurrent = preset.Id.Equals(_activeOverlayPreset, StringComparison.OrdinalIgnoreCase);
        var savedSettings = DesktopAppConfig.LoadOverlayPresetSettings(preset.Id);
        var savedLayout = DesktopAppConfig.LoadOverlayPresetLayout(preset.Id);
        var settings = isCurrent
            ? _overlaySettings.Serialize()
            : string.IsNullOrWhiteSpace(savedSettings)
                ? CreateDefaultOverlaySettings(preset.Id).Serialize()
                : savedSettings;
        var layout = isCurrent
            ? SerializeOverlayLayout()
            : string.IsNullOrWhiteSpace(savedLayout)
                ? SerializeOverlayLayout(CreateDefaultOverlayLayout(preset.Id))
                : savedLayout;
        var package = new OverlayPresetPackage(
            1,
            preset.Name,
            settings,
            layout);
        return new ChatAttachmentContract(
            ChatAttachmentKinds.OverlayPreset,
            $"浮层预设 · {preset.Name}",
            "包含布局、模块显示与外观设置。导入前可先确认。",
            OverlayPresetPackage: JsonSerializer.Serialize(package, OverlayPresetJsonOptions));
    }

    private async Task SendOverlayPresetAsync(
        ChatAttachmentDestination destination,
        OverlayPresetEntry preset)
    {
        var attachment = BuildOverlayPresetAttachment(preset);
        await SendChatAttachmentAsync(destination, attachment);
    }

    private async Task SendChatAttachmentAsync(
        ChatAttachmentDestination destination,
        ChatAttachmentContract attachment)
    {
        switch (destination.Target)
        {
            case ChatAttachmentTarget.FleetChannel:
                await SendFleetChatMessageAsync("", attachment);
                break;
            case ChatAttachmentTarget.PartyRoom:
                await SendPartyRoomChatMessageAsync("", attachment);
                break;
            case ChatAttachmentTarget.DirectMessage:
                await SendFriendChatMessageAsync("", attachment);
                break;
        }

        RefreshInGameSocialSnapshot();
        RefreshInGameRoomSnapshot();
    }

    private async Task SendFleetInvitationToChatAsync(ChatAttachmentDestination destination)
    {
        var isPartyRoom = destination.Target == ChatAttachmentTarget.PartyRoom;
        var eligibleRoomMembers = isPartyRoom ? CountPartyRoomFleetInvitationRecipients() : 0;
        if (!CanCurrentUserSendFleetInvitationCard() ||
            isPartyRoom && eligibleRoomMembers <= 0 ||
            !isPartyRoom && (_activeFriendChatUser is null || IsActiveFriendInCurrentFleet()))
        {
            return;
        }

        var statusText = isPartyRoom ? PartyRoomChatStatusText : FriendChatStatusText;
        statusText.Text = "正在生成舰队邀请…";
        statusText.Foreground = StatusPalette.InfoBrush;
        try
        {
            using var response = await PostNetworkJsonAsync(
                "api/fleets/invites",
                new FleetInviteCreateRequest(
                    _fleetCode,
                    7,
                    isPartyRoom ? Math.Clamp(eligibleRoomMembers, 1, 50) : 1,
                    "Direct",
                    "card"));
            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (!response.IsSuccessStatusCode || snapshot is null)
            {
                statusText.Text = await ReadResponseErrorAsync(response);
                statusText.Foreground = StatusPalette.DangerBrush;
                return;
            }

            MergeNetworkFleetState(snapshot);
            SaveCurrentConfig();
            var invite = (snapshot.Invites ?? [])
                .Where(IsInviteActive)
                .OrderByDescending(candidate => candidate.CreatedAt)
                .FirstOrDefault();
            if (invite is null)
            {
                statusText.Text = "邀请已生成，但未能读取邀请信息。";
                statusText.Foreground = StatusPalette.WarningBrush;
                return;
            }

            var attachment = new ChatAttachmentContract(
                ChatAttachmentKinds.FleetInvitation,
                $"舰队邀请 · {snapshot.Name}",
                isPartyRoom
                    ? $"可供当前房间中尚未加入舰队的 {eligibleRoomMembers} 位成员使用。打开名片可查看舰队详情。"
                    : "打开名片可查看舰队详情；当前未加入舰队时可接受邀请。",
                FleetInviteCode: invite.Code,
                ExpiresAt: invite.ExpiresAt);
            if (isPartyRoom)
            {
                await SendChatAttachmentAsync(destination, attachment);
            }
            else
            {
                await SendChatAttachmentAsync(destination, attachment);
            }
        }
        catch (Exception ex)
        {
            statusText.Text = UserFacingError.Describe(ex, "舰队邀请未发送，请检查网络后重试。");
            statusText.Foreground = StatusPalette.DangerBrush;
        }
    }

    private async Task SendPartyRoomInvitationToActiveChatAsync()
    {
        if (_activeFriendChatUser is null ||
            IsActiveFriendInCurrentPartyRoom() ||
            HasPendingPartyRoomInvitationForActiveFriend() ||
            _currentPartyRoom is not { ViewerIsHost: true } room)
        {
            return;
        }

        var user = _activeFriendChatUser;
        FriendChatStatusText.Text = "正在发送房间邀请…";
        FriendChatStatusText.Foreground = StatusPalette.InfoBrush;
        var row = new PartyRoomInvitationActionRow(
            user.AccountId,
            user.Callsign,
            user.GameId,
            user.AvatarImageData,
            "通过私聊发送房间邀请",
            "邀请",
            "invite",
            true,
            "",
            "",
            room.RoomId);
        var sent = await CreatePartyRoomInvitationAsync(row, FriendChatStatusText);
        if (!sent)
        {
            return;
        }

        await RefreshFriendChatAsync(showErrors: false);
        FriendChatStatusText.Text = "房间邀请已发送";
        FriendChatStatusText.Foreground = StatusPalette.SuccessBrush;
    }

    private async void ChatAttachmentActionButton_Click(object sender, RoutedEventArgs e)
    {
        var attachment = (sender as FrameworkElement)?.DataContext switch
        {
            FriendChatMessageRow row => row.Attachment,
            FleetChatMessageRow row => row.Attachment,
            PartyRoomChatMessageView row => row.Attachment,
            _ => null
        };
        if (attachment is null)
        {
            return;
        }

        await HandleChatAttachmentActionAsync(attachment);
    }

    private async Task HandleChatAttachmentActionAsync(ChatAttachmentContract attachment)
    {
        if (attachment.ExpiresAt is { } expiresAt && expiresAt <= DateTimeOffset.UtcNow)
        {
            StarBridgeMessageBox.Show(this, "这条邀请已过期。", "邀请已失效", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        switch (attachment.Kind)
        {
            case ChatAttachmentKinds.OverlayPreset:
                ImportOverlayPresetFromChat(attachment);
                break;
            case ChatAttachmentKinds.FleetInvitation:
                OpenFleetInviteFromChat(attachment);
                break;
            case ChatAttachmentKinds.PartyRoomInvitation:
                await OpenPartyRoomInvitationFromChatAsync(attachment);
                break;
        }
    }

    private void ImportOverlayPresetFromChat(ChatAttachmentContract attachment)
    {
        if (string.IsNullOrWhiteSpace(attachment.OverlayPresetPackage))
        {
            return;
        }

        var answer = StarBridgeMessageBox.Show(
            this,
            $"{attachment.Title}\n\n{attachment.Summary}\n\n导入后会创建一份新预设，不会覆盖你现有的预设。",
            "导入浮层预设",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (answer != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            var package = JsonSerializer.Deserialize<OverlayPresetPackage>(
                attachment.OverlayPresetPackage,
                OverlayPresetJsonOptions);
            if (package is null || string.IsNullOrWhiteSpace(package.Settings) || string.IsNullOrWhiteSpace(package.Layout))
            {
                throw new InvalidDataException("预设内容不完整。");
            }

            var importedSettings = ApplyOverlayFeatureLocks(OverlayDisplaySettings.Parse(package.Settings)).Serialize();
            var importedLayout = OverlayLayoutItem.ParseMany(package.Layout).ToArray();
            var importedLayoutPayload = SerializeOverlayLayout(importedLayout.Length == 0
                ? CreateDefaultOverlayLayout(OverlayPresetDefault)
                : importedLayout);
            var id = CreateOverlayPresetId();
            var name = CreateUniqueOverlayPresetName(CleanOverlayPresetName(package.Name) ?? "收到的预设");
            DesktopAppConfig.SaveOverlayPresetSettings(id, importedSettings);
            DesktopAppConfig.SaveOverlayPresetLayout(id, importedLayoutPayload);
            _overlayPresetEntries.Add(new OverlayPresetEntry(id, name));
            SaveOverlayPresetManifest();
            LoadOverlayPreset(id);
            StarBridgeMessageBox.Show(this, $"已导入预设“{name}”。", "导入完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(this, UserFacingError.Describe(ex, "无法导入这份预设，请确认文件有效后重试。"), "导入失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void OpenFleetInviteFromChat(ChatAttachmentContract attachment)
    {
        if (string.IsNullOrWhiteSpace(attachment.FleetInviteCode))
        {
            return;
        }

        OpenFindFleetInviteDialog();
        FindFleetInviteCodeBox.Text = attachment.FleetInviteCode;
        FindFleetInviteVerifyButton_Click(this, new RoutedEventArgs());
    }

    private async Task OpenPartyRoomInvitationFromChatAsync(ChatAttachmentContract attachment)
    {
        if (string.IsNullOrWhiteSpace(attachment.RoomId) || string.IsNullOrWhiteSpace(attachment.RoomInvitationId))
        {
            return;
        }

        try
        {
            using var response = await _relayClient.PostJsonAsync(
                "api/party-rooms/invitations/preview",
                new PartyRoomInvitePreviewRequest(attachment.RoomId, attachment.RoomInvitationId));
            var mutation = await response.Content.ReadFromJsonAsync<PartyRoomMutationResponse>();
            if (!response.IsSuccessStatusCode || mutation?.Room is null)
            {
                StarBridgeMessageBox.Show(
                    this,
                    mutation?.Error ?? "这条房间邀请已经失效。",
                    "无法查看房间",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                return;
            }

            NavigateToPartyLobby(animate: true, showGuideHint: false);
            if (!ReferenceEquals(MainTabs.SelectedItem, MySquadTab))
            {
                return;
            }

            _partyRoomJoinTarget = ToPartyLobbyRoomCard(mutation.Room);
            _partyRoomJoinInvitationId = attachment.RoomInvitationId;
            PartyRoomJoinCodeBox.Clear();
            PartyRoomJoinPasswordBox.Clear();
            PartyRoomJoinValidationText.Text = _currentPartyRoom is null
                ? "邀请有效。确认房间信息后可以加入。"
                : "你当前已在一个临时房间中；仍可查看这张邀请名片。";
            RefreshPartyRoomJoinOverlay();
            PartyRoomJoinOverlay.Visibility = Visibility.Visible;
        }
        catch
        {
            StarBridgeMessageBox.Show(
                this,
                "暂时无法读取房间详情，请稍后重试。",
                "无法查看房间",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }
}
