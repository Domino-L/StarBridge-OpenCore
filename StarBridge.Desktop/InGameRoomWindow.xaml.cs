using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace StarBridge.Desktop;

public partial class InGameRoomWindow : Window
{
    private bool _allowPermanentClose;
    private bool _applyingSnapshot;
    private bool _isCreatingRoom;
    private bool _showRoomCode = true;
    private InGameRoomSnapshot? _snapshot;
    private PartyLobbyRoomCard? _selectedRoom;
    private readonly HashSet<string> _createGameplayIds =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _createContextIds =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _createTagDraftGameplayIds =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _createTagDraftContextIds =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly ObservableCollection<PartyRoomSelectedTagChip> _createSelectedTags = [];
    private readonly ObservableCollection<PartyRoomSelectedTagChip> _createTagDraftChips = [];
    private readonly List<PartyRoomContextTagChoiceGroup> _createContextTagGroups = [];
    private PartyRoomTagNode? _createTagCurrentNode;

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;
    internal event EventHandler? RefreshRequested;
    internal event EventHandler<InGameRoomJoinRequestedEventArgs>? JoinRequested;
    internal event EventHandler<InGameRoomCreateRequestedEventArgs>? CreateRequested;
    internal event EventHandler? LeaveRequested;
    internal event EventHandler<InGameRoomMessageRequestedEventArgs>? MessageRequested;
    internal event EventHandler<InGameRoomAttachmentRequestedEventArgs>? AttachmentRequested;
    internal event EventHandler<InGameChatAttachmentActionRequestedEventArgs>? AttachmentActionRequested;
    internal event EventHandler<InGameRoomInvitationActionRequestedEventArgs>? InvitationActionRequested;

    internal InGameRoomWindow()
    {
        InitializeComponent();
        Theming.BridgeSceneContext.ApplyFixed(this, Theming.BridgeSceneKind.Party);
        InGameToolWindowBehavior.PreventSnapMaximize(this);
        CreateCapacityBox.ItemsSource = Enumerable.Range(2, 15).ToArray();
        CreateCapacityBox.SelectedItem = 6;
        CreateSelectedTags.ItemsSource = _createSelectedTags;
        CreateTagSelectedItems.ItemsSource = _createTagDraftChips;
        CreateTagLevel1List.ItemsSource = PartyRoomTagCatalog.GameplayRoots;
        _createContextTagGroups.AddRange(
            PartyRoomTagCatalog.ContextGroups.Select(group => new PartyRoomContextTagChoiceGroup(
                group.Name,
                group.Tags
                    .Select(tag => new PartyRoomContextTagChoice(tag.Id, tag.Name))
                    .ToArray())));
        CreateContextTagGroups.ItemsSource = _createContextTagGroups;
        RefreshCreateTagSummary();
        RefreshCreateTagCurrentPath();
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

    internal void ApplySettings(InGameMenuSettings settings)
    {
        _showRoomCode = settings.Normalize().EffectiveShowRoomCode;
        CurrentRoomCodePanel.Visibility = _showRoomCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        CopyCurrentRoomCodeButton.Visibility = _showRoomCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (_snapshot?.CurrentRoom is { } room)
        {
            ApplyCurrentRoom(room);
        }
    }

    internal void ApplySnapshot(InGameRoomSnapshot snapshot)
    {
        _snapshot = snapshot;
        _applyingSnapshot = true;
        try
        {
            UnavailablePanel.Visibility = snapshot.IsAvailable
                ? Visibility.Collapsed
                : Visibility.Visible;
            Controls.InGameLoadingPresentation.Apply(UnavailableLoadingIndicator, false);
            RoomList.IsEnabled = snapshot.IsAvailable;
            LobbyToolbar.IsEnabled = snapshot.IsAvailable;
            ShowCreateButton.IsEnabled = snapshot.IsAvailable;
            SetStatus(snapshot.StatusText);

            if (snapshot.CurrentRoom is not null)
            {
                _isCreatingRoom = false;
                LobbyToolbar.Visibility = Visibility.Collapsed;
                LobbySurface.Visibility = Visibility.Collapsed;
                CreateRoomPanel.Visibility = Visibility.Collapsed;
                RoomCodeJoinPanel.Visibility = Visibility.Collapsed;
                CreateTagPickerPanel.Visibility = Visibility.Collapsed;
                CurrentRoomSurface.Visibility = Visibility.Visible;
                ShowCreateButton.Visibility = Visibility.Collapsed;
                RoomWindowSubtitleText.Text = "查看房间信息、全部成员与房间聊天。";
                ApplyCurrentRoom(snapshot.CurrentRoom);
                ApplyRoomChat(snapshot.Chat);
                ApplyInvitations(snapshot.Invitations);
            }
            else
            {
                LobbyToolbar.Visibility = Visibility.Visible;
                LobbySurface.Visibility = Visibility.Visible;
                CurrentRoomSurface.Visibility = Visibility.Collapsed;
                ShowCreateButton.Visibility = Visibility.Visible;
                CreateRoomPanel.Visibility = _isCreatingRoom
                    ? Visibility.Visible
                    : Visibility.Collapsed;
                InviteFriendsPanel.Visibility = Visibility.Collapsed;
                RoomWindowSubtitleText.Text = "寻找现在可以一起游玩的队友，或创建一支临时队伍。";
            }

            ApplyRoomFilter();
        }
        finally
        {
            _applyingSnapshot = false;
        }
    }

    internal void SetStatus(string text, bool isLoading = false)
    {
        Controls.InGameLoadingPresentation.Apply(
            RoomStatusText,
            RoomStatusLoadingIndicator,
            text,
            isLoading);
        Controls.InGameLoadingPresentation.Apply(
            CreateStatusText,
            CreateStatusLoadingIndicator,
            text,
            isLoading);
        Controls.InGameLoadingPresentation.Apply(
            RoomCodeStatusText,
            RoomCodeLoadingIndicator,
            text,
            isLoading);
        Controls.InGameLoadingPresentation.Apply(
            NoRoomSelectionStatusText,
            NoRoomSelectionLoadingIndicator,
            text,
            isLoading);
        Controls.InGameLoadingPresentation.Apply(
            CurrentRoomFeedbackText,
            CurrentRoomFeedbackLoadingIndicator,
            text,
            isLoading);
    }

    internal void SetInvitationStatus(string text, bool isLoading = false) =>
        Controls.InGameLoadingPresentation.Apply(
            InviteFriendsStatusText,
            InviteFriendsLoadingIndicator,
            text,
            isLoading);

    internal void ResetAccountState(string statusText, bool isLoading = false)
    {
        RoomCodeBox.Clear();
        RoomCodePasswordBox.Clear();
        RoomPasswordBox.Clear();
        CreateTitleBox.Clear();
        CreateGoalBox.Clear();
        CreatePasswordBox.Clear();
        CreatePasswordToggle.IsChecked = false;
        _createGameplayIds.Clear();
        _createContextIds.Clear();
        _createTagDraftGameplayIds.Clear();
        _createTagDraftContextIds.Clear();
        RefreshCreateTagSummary();
        _isCreatingRoom = false;
        CreateRoomPanel.Visibility = Visibility.Collapsed;
        RoomCodeJoinPanel.Visibility = Visibility.Collapsed;
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
        ApplySnapshot(new InGameRoomSnapshot(
            false,
            [],
            null,
            statusText,
            new InGameRoomChatSnapshot([], false, statusText),
            new InGameRoomInvitationSnapshot(false, [], statusText)));
        RoomUnavailableDetailText.Text = statusText;
        SetStatus(statusText, isLoading);
        Controls.InGameLoadingPresentation.Apply(UnavailableLoadingIndicator, isLoading);
        Controls.InGameLoadingPresentation.Apply(
            RoomCountText,
            RoomDirectoryLoadingIndicator,
            statusText,
            isLoading);
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

    private void ApplyRoomFilter()
    {
        if (_snapshot is null)
        {
            return;
        }

        var voiceRequirement = GetSelectedTag(RoomVoiceFilter) switch
        {
            "none" => PartyLobbyVoiceRequirement.None,
            "recommended" => PartyLobbyVoiceRequirement.Recommended,
            "required" => PartyLobbyVoiceRequirement.Required,
            _ => (PartyLobbyVoiceRequirement?)null
        };
        var admissionMode = GetSelectedTag(RoomAdmissionFilter) switch
        {
            "direct" => PartyLobbyAdmissionMode.Direct,
            "approval" => PartyLobbyAdmissionMode.HostApproval,
            _ => (PartyLobbyAdmissionMode?)null
        };
        var filter = new PartyLobbyFilter(
            RoomSearchBox.Text,
            GetSelectedTag(RoomActivityFilter),
            voiceRequirement,
            admissionMode);
        var visibleRooms = _snapshot.Rooms
            .Where(filter.Matches)
            .ToArray();
        var selectedId = _selectedRoom?.RoomId;

        RoomList.ItemsSource = visibleRooms;
        Controls.InGameLoadingPresentation.Apply(
            RoomCountText,
            RoomDirectoryLoadingIndicator,
            $"{visibleRooms.Length} 个房间",
            isLoading: false);
        RoomEmptyState.Visibility = visibleRooms.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        _selectedRoom = visibleRooms.FirstOrDefault(room =>
                            room.RoomId.Equals(
                                selectedId,
                                StringComparison.OrdinalIgnoreCase)) ??
                        visibleRooms.FirstOrDefault();
        RoomList.SelectedItem = _selectedRoom;
        ApplySelectedRoom();
    }

    private void ApplyCurrentRoom(PartyLobbyRoomCard room)
    {
        CurrentRoomSurface.DataContext = room;
        CurrentRoomTitleText.Text = room.Title;
        CurrentRoomGoalText.Text = room.GoalDisplay;
        CurrentRoomAccessText.Text = room.AccessSummary;
        CurrentRoomScheduleText.Text = $"{room.RecruitmentText} · {room.ExpiresAtText}";
        CurrentRoomMemberCountText.Text = room.MemberCountText;
        CurrentRoomMembersList.ItemsSource = room.Members;
        CurrentRoomCodePanel.Visibility = _showRoomCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        CopyCurrentRoomCodeButton.Visibility = _showRoomCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        CurrentRoomCodeText.Text = !_showRoomCode
            ? "房间码已隐藏"
            : string.IsNullOrWhiteSpace(room.RoomCode)
                ? "房间码未提供"
                : $"房间码 {room.RoomCode}";
        CopyCurrentRoomCodeButton.IsEnabled =
            _showRoomCode &&
            !string.IsNullOrWhiteSpace(room.RoomCode);
        Controls.InGameLoadingPresentation.Apply(
            CurrentRoomFeedbackText,
            CurrentRoomFeedbackLoadingIndicator,
            "",
            isLoading: false);
    }

    private void ApplyRoomChat(InGameRoomChatSnapshot chat)
    {
        var messages = InGameSnapshotItemIdentity.PreserveEqualInstances(
            CurrentRoomChatList.ItemsSource as IEnumerable<object>,
            chat.Messages);
        var messagesChanged = !ReferenceEquals(CurrentRoomChatList.ItemsSource, messages);
        if (messagesChanged)
        {
            CurrentRoomChatList.ItemsSource = messages;
        }
        Controls.InGameLoadingPresentation.Apply(
            CurrentRoomChatStatusText,
            CurrentRoomChatLoadingIndicator,
            chat.StatusText,
            chat.IsLoading);
        CurrentRoomChatInputBox.IsEnabled = chat.CanSend;
        CurrentRoomChatSendButton.IsEnabled = chat.CanSend;
        CurrentRoomChatAttachmentButton.IsEnabled = chat.CanSend;
        CurrentRoomChatEmptyPanel.Visibility = chat.Messages.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        CurrentRoomChatList.Visibility = chat.Messages.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (messagesChanged && messages.Length > 0)
        {
            Dispatcher.BeginInvoke(() =>
                CurrentRoomChatList.ScrollIntoView(messages[^1]));
        }
    }

    private void ApplyInvitations(InGameRoomInvitationSnapshot invitations)
    {
        InviteFriendsButton.Visibility = invitations.CanInvite
            ? Visibility.Visible
            : Visibility.Collapsed;
        InviteFriendsList.ItemsSource = invitations.Friends;
        SetInvitationStatus(invitations.StatusText);
        InviteFriendsEmptyText.Visibility = invitations.Friends.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        InviteFriendsList.Visibility = invitations.Friends.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (!invitations.CanInvite)
        {
            InviteFriendsPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void ApplySelectedRoom()
    {
        if (_selectedRoom is null)
        {
            RoomDetailPanel.DataContext = null;
            Controls.InGameLoadingPresentation.Apply(
                NoRoomSelectionStatusText,
                NoRoomSelectionLoadingIndicator,
                _snapshot?.StatusText ?? "",
                isLoading: false);
            NoRoomSelectionState.Visibility = Visibility.Visible;
            RoomDetailPanel.Visibility = Visibility.Collapsed;
            return;
        }

        var current = _snapshot?.CurrentRoom;
        var isCurrent = current is not null &&
                        current.RoomId.Equals(_selectedRoom.RoomId, StringComparison.OrdinalIgnoreCase);
        RoomDetailPanel.DataContext = _selectedRoom;
        NoRoomSelectionState.Visibility = Visibility.Collapsed;
        RoomDetailPanel.Visibility = Visibility.Visible;
        RoomTitleText.Text = _selectedRoom.Title;
        RoomGoalText.Text = _selectedRoom.GoalDisplay;
        RoomAccessText.Text = _selectedRoom.AccessSummary;
        RoomLanguageText.Text = $"主要语言：{_selectedRoom.LanguageText}";
        RoomPasswordRequirementText.Text = _selectedRoom.PasswordText;
        RoomHostText.Text = _selectedRoom.HostDisplay;
        RoomMembersText.Text = $"{_selectedRoom.MemberCountText} · {_selectedRoom.RecruitmentText}";
        RoomPasswordBox.Visibility = !isCurrent && _selectedRoom.PasswordRequired
            ? Visibility.Visible
            : Visibility.Collapsed;
        JoinRoomButton.Visibility = isCurrent ? Visibility.Collapsed : Visibility.Visible;
        JoinRoomButton.IsEnabled = current is null;
        JoinRoomButton.Content = _selectedRoom.AdmissionMode == PartyLobbyAdmissionMode.HostApproval
            ? "申请加入"
            : "直接加入";
        Controls.InGameLoadingPresentation.Apply(
            RoomStatusText,
            RoomStatusLoadingIndicator,
            isCurrent
            ? "你当前在这个房间中。"
            : current is not null
                ? "你已经在另一个房间中，请先退出当前房间。"
                : _snapshot?.StatusText ?? "",
            isLoading: false);
    }

    private void RoomList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_applyingSnapshot)
        {
            return;
        }

        _selectedRoom = RoomList.SelectedItem as PartyLobbyRoomCard;
        ApplySelectedRoom();
    }

    private void RoomSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!IsInitialized || _applyingSnapshot)
        {
            return;
        }

        ApplyRoomFilter();
    }

    private void RoomFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsInitialized || _applyingSnapshot)
        {
            return;
        }

        ApplyRoomFilter();
    }

    private void ClearFiltersButton_Click(object sender, RoutedEventArgs e)
    {
        RoomSearchBox.Clear();
        RoomActivityFilter.SelectedIndex = 0;
        RoomVoiceFilter.SelectedIndex = 0;
        RoomAdmissionFilter.SelectedIndex = 0;
        ApplyRoomFilter();
    }

    private void JoinRoomButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedRoom is null)
        {
            return;
        }

        Controls.InGameLoadingPresentation.Apply(
            RoomStatusText,
            RoomStatusLoadingIndicator,
            "正在加入房间",
            isLoading: true);
        JoinRequested?.Invoke(
            this,
            new InGameRoomJoinRequestedEventArgs(
                _selectedRoom,
                "",
                RoomPasswordBox.Password));
    }

    private void JoinByCodeButton_Click(object sender, RoutedEventArgs e)
    {
        var code = RoomCodeBox.Text.Trim();
        if (code.Length == 0)
        {
            Controls.InGameLoadingPresentation.Apply(
                RoomCodeStatusText,
                RoomCodeLoadingIndicator,
                "请输入房间码。",
                isLoading: false);
            return;
        }

        Controls.InGameLoadingPresentation.Apply(
            RoomCodeStatusText,
            RoomCodeLoadingIndicator,
            "正在查找房间",
            isLoading: true);
        JoinRequested?.Invoke(
            this,
            new InGameRoomJoinRequestedEventArgs(
                null,
                code,
                RoomCodePasswordBox.Password));
    }

    private void ShowRoomCodeButton_Click(object sender, RoutedEventArgs e)
    {
        _isCreatingRoom = false;
        CreateRoomPanel.Visibility = Visibility.Collapsed;
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
        Controls.InGameLoadingPresentation.Apply(
            RoomCodeStatusText,
            RoomCodeLoadingIndicator,
            "",
            isLoading: false);
        RoomCodeJoinPanel.Visibility = Visibility.Visible;
        RoomCodeBox.Focus();
    }

    private void CancelRoomCodeButton_Click(object sender, RoutedEventArgs e)
    {
        RoomCodeJoinPanel.Visibility = Visibility.Collapsed;
        ApplySelectedRoom();
    }

    private void ShowCreateButton_Click(object sender, RoutedEventArgs e)
    {
        if (_snapshot?.CurrentRoom is not null)
        {
            SetStatus("你已经在一个房间中，请先退出当前房间。");
            return;
        }

        _isCreatingRoom = true;
        RoomCodeJoinPanel.Visibility = Visibility.Collapsed;
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
        NoRoomSelectionState.Visibility = Visibility.Collapsed;
        RoomDetailPanel.Visibility = Visibility.Collapsed;
        UnavailablePanel.Visibility = Visibility.Collapsed;
        CreateRoomPanel.Visibility = Visibility.Visible;
        CreateTitleBox.Focus();
    }

    private void CancelCreateButton_Click(object sender, RoutedEventArgs e)
    {
        _isCreatingRoom = false;
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
        CreateRoomPanel.Visibility = Visibility.Collapsed;
        ApplySelectedRoom();
    }

    private void CreateRoomButton_Click(object sender, RoutedEventArgs e)
    {
        if (_createGameplayIds.Count is < 1 or > 3)
        {
            Controls.InGameLoadingPresentation.Apply(
                CreateStatusText,
                CreateStatusLoadingIndicator,
                "请先选择 1–3 条玩法路径。",
                isLoading: false);
            return;
        }

        var voice = GetSelectedTag(CreateVoiceBox) switch
        {
            "required" => PartyLobbyVoiceRequirement.Required,
            "recommended" => PartyLobbyVoiceRequirement.Recommended,
            _ => PartyLobbyVoiceRequirement.None
        };
        var admission = GetSelectedTag(CreateAdmissionBox) == "direct"
            ? PartyLobbyAdmissionMode.Direct
            : PartyLobbyAdmissionMode.HostApproval;
        var draft = new PartyRoomCreateDraft(
            CreateTitleBox.Text,
            CreateGoalBox.Text,
            _createGameplayIds.ToArray(),
            _createContextIds.ToArray(),
            CreateCapacityBox.SelectedItem is int capacity ? capacity : 6,
            GetSelectedTag(CreateVisibilityBox) != "code",
            GetSelectedTag(CreateEligibilityBox) switch
            {
                "friends" => PartyRoomEligibility.HostFriends,
                "fleet" => PartyRoomEligibility.SameFleet,
                "invite" => PartyRoomEligibility.InviteOnly,
                _ => PartyRoomEligibility.Everyone
            },
            admission,
            CreatePasswordToggle.IsChecked == true,
            CreatePasswordBox.Password,
            voice,
            GetSelectedTag(CreateLanguageBox) switch
            {
                "en" => PartyRoomLanguage.English,
                "bilingual" => PartyRoomLanguage.Bilingual,
                _ => PartyRoomLanguage.Chinese
            },
            int.TryParse(GetSelectedTag(CreateRecruitmentBox), out var recruitmentMinutes)
                ? recruitmentMinutes
                : null,
            int.TryParse(GetSelectedTag(CreateDisbandBox), out var disbandHours)
                ? disbandHours
                : 6);
        Controls.InGameLoadingPresentation.Apply(
            CreateStatusText,
            CreateStatusLoadingIndicator,
            "正在创建房间",
            isLoading: true);
        CreateRequested?.Invoke(
            this,
            new InGameRoomCreateRequestedEventArgs(draft));
    }

    private void CreatePasswordToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (CreatePasswordBox is null)
        {
            return;
        }

        var enabled = CreatePasswordToggle.IsChecked == true;
        CreatePasswordBox.IsEnabled = enabled;
        if (!enabled)
        {
            CreatePasswordBox.Clear();
        }
    }

    private void ShowCreateTagPicker_Click(object sender, RoutedEventArgs e)
    {
        _createTagDraftGameplayIds.Clear();
        _createTagDraftGameplayIds.UnionWith(_createGameplayIds);
        _createTagDraftContextIds.Clear();
        _createTagDraftContextIds.UnionWith(_createContextIds);
        foreach (var choice in _createContextTagGroups.SelectMany(group => group.Tags))
        {
            choice.IsSelected = _createTagDraftContextIds.Contains(choice.Id);
        }

        CreateTagValidationText.Text = "";
        CreateTagLevel1List.SelectedIndex = -1;
        CreateTagLevel2List.ItemsSource = null;
        CreateTagLevel3List.ItemsSource = null;
        _createTagCurrentNode = null;
        RefreshCreateTagDraft();
        RefreshCreateTagCurrentPath();
        CreateTagPickerPanel.Visibility = Visibility.Visible;
        CreateTagLevel1List.Focus();
    }

    private void CancelCreateTagPicker_Click(object sender, RoutedEventArgs e)
    {
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
    }

    private void SaveCreateTagPicker_Click(object sender, RoutedEventArgs e)
    {
        if (_createTagDraftGameplayIds.Count is < 1 or > 3)
        {
            CreateTagValidationText.Text = "请选择 1–3 条玩法路径。";
            return;
        }

        if (_createTagDraftContextIds.Count > 3 ||
            _createTagDraftGameplayIds.Count + _createTagDraftContextIds.Count > 5)
        {
            CreateTagValidationText.Text = "附加标签最多 3 个，全部标签合计最多 5 个。";
            return;
        }

        _createGameplayIds.Clear();
        _createGameplayIds.UnionWith(_createTagDraftGameplayIds);
        _createContextIds.Clear();
        _createContextIds.UnionWith(_createTagDraftContextIds);
        RefreshCreateTagSummary();
        Controls.InGameLoadingPresentation.Apply(
            CreateStatusText,
            CreateStatusLoadingIndicator,
            "",
            isLoading: false);
        CreateTagPickerPanel.Visibility = Visibility.Collapsed;
    }

    private void CreateTagLevel1List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = CreateTagLevel1List.SelectedItem as PartyRoomTagNode;
        CreateTagLevel2List.ItemsSource = selected?.Children;
        CreateTagLevel2List.SelectedIndex = -1;
        CreateTagLevel3List.ItemsSource = null;
        _createTagCurrentNode = selected;
        RefreshCreateTagCurrentPath();
    }

    private void CreateTagLevel2List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = CreateTagLevel2List.SelectedItem as PartyRoomTagNode;
        CreateTagLevel3List.ItemsSource = selected?.Children;
        CreateTagLevel3List.SelectedIndex = -1;
        _createTagCurrentNode =
            selected ?? CreateTagLevel1List.SelectedItem as PartyRoomTagNode;
        RefreshCreateTagCurrentPath();
    }

    private void CreateTagLevel3List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _createTagCurrentNode =
            CreateTagLevel3List.SelectedItem as PartyRoomTagNode ??
            CreateTagLevel2List.SelectedItem as PartyRoomTagNode ??
            CreateTagLevel1List.SelectedItem as PartyRoomTagNode;
        RefreshCreateTagCurrentPath();
    }

    private void AddCreateGameplayTag_Click(object sender, RoutedEventArgs e)
    {
        if (_createTagCurrentNode is null)
        {
            CreateTagValidationText.Text = "请先从左侧选择一个玩法层级。";
            return;
        }

        var normalized = PartyRoomTagCatalog.NormalizeGameplaySelection(
            _createTagDraftGameplayIds,
            _createTagCurrentNode.Id);
        if (normalized.Count > 3)
        {
            CreateTagValidationText.Text = "玩法路径最多选择 3 条。";
            return;
        }

        if (normalized.Count + _createTagDraftContextIds.Count > 5)
        {
            CreateTagValidationText.Text = "全部标签合计最多选择 5 个。";
            return;
        }

        _createTagDraftGameplayIds.Clear();
        _createTagDraftGameplayIds.UnionWith(normalized);
        CreateTagValidationText.Text = "";
        RefreshCreateTagDraft();
    }

    private void CreateContextTag_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.CheckBox checkBox ||
            checkBox.DataContext is not PartyRoomContextTagChoice choice)
        {
            return;
        }

        if (checkBox.IsChecked == true)
        {
            if (_createTagDraftContextIds.Count >= 3 ||
                _createTagDraftGameplayIds.Count + _createTagDraftContextIds.Count >= 5)
            {
                choice.IsSelected = false;
                CreateTagValidationText.Text =
                    "附加标签最多 3 个，全部标签合计最多 5 个。";
                return;
            }

            _createTagDraftContextIds.Add(choice.Id);
        }
        else
        {
            _createTagDraftContextIds.Remove(choice.Id);
        }

        CreateTagValidationText.Text = "";
        RefreshCreateTagDraft();
    }

    private void RemoveCreateTag_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not PartyRoomSelectedTagChip chip)
        {
            return;
        }

        if (chip.IsGameplay)
        {
            _createTagDraftGameplayIds.Remove(chip.Id);
        }
        else
        {
            _createTagDraftContextIds.Remove(chip.Id);
            var choice = _createContextTagGroups
                .SelectMany(group => group.Tags)
                .FirstOrDefault(item =>
                    item.Id.Equals(chip.Id, StringComparison.OrdinalIgnoreCase));
            if (choice is not null)
            {
                choice.IsSelected = false;
            }
        }

        CreateTagValidationText.Text = "";
        RefreshCreateTagDraft();
    }

    private void RefreshCreateTagSummary()
    {
        _createSelectedTags.Clear();
        foreach (var id in _createGameplayIds)
        {
            _createSelectedTags.Add(new PartyRoomSelectedTagChip(
                id,
                PartyRoomTagCatalog.GetGameplayPathText(id),
                true));
        }

        foreach (var id in _createContextIds)
        {
            if (PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                _createSelectedTags.Add(new PartyRoomSelectedTagChip(id, tag.Name, false));
            }
        }

        CreateTagEmptyText.Visibility = _createSelectedTags.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        CreateTagCountText.Text = $"{_createSelectedTags.Count} / 5";
    }

    private void RefreshCreateTagDraft()
    {
        _createTagDraftChips.Clear();
        foreach (var id in _createTagDraftGameplayIds)
        {
            _createTagDraftChips.Add(new PartyRoomSelectedTagChip(
                id,
                PartyRoomTagCatalog.GetGameplayPathText(id),
                true));
        }

        foreach (var id in _createTagDraftContextIds)
        {
            if (PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                _createTagDraftChips.Add(new PartyRoomSelectedTagChip(id, tag.Name, false));
            }
        }

        CreateTagSelectionCountText.Text = $"{_createTagDraftChips.Count} / 5";
    }

    private void RefreshCreateTagCurrentPath()
    {
        var hasSelection = _createTagCurrentNode is not null;
        CreateTagCurrentPathText.Text = hasSelection
            ? PartyRoomTagCatalog.GetGameplayPathText(_createTagCurrentNode!.Id)
            : "从一级玩法开始选择";
        CreateTagAddGameplayButton.IsEnabled = hasSelection;
        CreateTagAddGameplayButton.Content = _createTagCurrentNode?.HasChildren == true
            ? "选择当前分类"
            : "添加此玩法";
    }

    private static string GetSelectedTag(System.Windows.Controls.ComboBox comboBox) =>
        (comboBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Tag as string ?? "";

    private void CurrentRoomChatSendButton_Click(object sender, RoutedEventArgs e) =>
        SendCurrentRoomMessage();

    private void CurrentRoomChatInputBox_PreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        if (MessageComposerKeyboardPolicy.Resolve(e.Key, Keyboard.Modifiers) !=
            MessageComposerKeyAction.Send)
        {
            return;
        }

        e.Handled = true;
        SendCurrentRoomMessage();
    }

    private void SendCurrentRoomMessage()
    {
        var text = CurrentRoomChatInputBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            Controls.InGameLoadingPresentation.Apply(
                CurrentRoomChatStatusText,
                CurrentRoomChatLoadingIndicator,
                "输入消息后再发送",
                isLoading: false);
            CurrentRoomChatInputBox.Focus();
            return;
        }

        CurrentRoomChatSendButton.IsEnabled = false;
        CurrentRoomChatAttachmentButton.IsEnabled = false;
        Controls.InGameLoadingPresentation.Apply(
            CurrentRoomChatStatusText,
            CurrentRoomChatLoadingIndicator,
            "正在发送",
            isLoading: true);
        CurrentRoomChatInputBox.Clear();
        MessageRequested?.Invoke(this, new InGameRoomMessageRequestedEventArgs(text));
    }

    private void CurrentRoomChatAttachmentButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button anchor)
        {
            AttachmentRequested?.Invoke(
                this,
                new InGameRoomAttachmentRequestedEventArgs(anchor));
        }
    }

    private void ChatAttachmentActionButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is StarBridge.Core.Chat.ChatAttachmentContract attachment)
        {
            AttachmentActionRequested?.Invoke(
                this,
                new InGameChatAttachmentActionRequestedEventArgs(attachment));
        }
    }

    private void CopyCurrentRoomCodeButton_Click(object sender, RoutedEventArgs e)
    {
        var roomCode = _snapshot?.CurrentRoom?.RoomCode;
        if (string.IsNullOrWhiteSpace(roomCode))
        {
            Controls.InGameLoadingPresentation.Apply(
                CurrentRoomFeedbackText,
                CurrentRoomFeedbackLoadingIndicator,
                "这个房间暂时没有可复制的房间码。",
                isLoading: false);
            return;
        }

        try
        {
            System.Windows.Clipboard.SetText(roomCode);
            Controls.InGameLoadingPresentation.Apply(
                CurrentRoomFeedbackText,
                CurrentRoomFeedbackLoadingIndicator,
                "房间码已复制。",
                isLoading: false);
        }
        catch
        {
            Controls.InGameLoadingPresentation.Apply(
                CurrentRoomFeedbackText,
                CurrentRoomFeedbackLoadingIndicator,
                "未能复制房间码，请稍后重试。",
                isLoading: false);
        }
    }

    private void InviteFriendsButton_Click(object sender, RoutedEventArgs e)
    {
        if (_snapshot?.Invitations.CanInvite != true)
        {
            Controls.InGameLoadingPresentation.Apply(
                CurrentRoomFeedbackText,
                CurrentRoomFeedbackLoadingIndicator,
                "只有房主可以邀请好友加入房间。",
                isLoading: false);
            return;
        }

        InviteFriendsPanel.Visibility = Visibility.Visible;
        SetInvitationStatus("正在同步好友与邀请状态", isLoading: true);
        RefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    private void InviteFriendsCloseButton_Click(object sender, RoutedEventArgs e) =>
        InviteFriendsPanel.Visibility = Visibility.Collapsed;

    private void InviteFriendPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PartyRoomInvitationActionRow row ||
            !row.PrimaryEnabled)
        {
            return;
        }

        SetInvitationStatus(
            $"正在向 {row.Callsign} 发送房间邀请",
            isLoading: true);
        InvitationActionRequested?.Invoke(
            this,
            new InGameRoomInvitationActionRequestedEventArgs(row, row.PrimaryAction));
    }

    private void InviteFriendSecondaryButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not PartyRoomInvitationActionRow row ||
            string.IsNullOrWhiteSpace(row.SecondaryAction))
        {
            return;
        }

        SetInvitationStatus("正在撤回邀请", isLoading: true);
        InvitationActionRequested?.Invoke(
            this,
            new InGameRoomInvitationActionRequestedEventArgs(row, row.SecondaryAction));
    }

    private void LeaveRoomButton_Click(object sender, RoutedEventArgs e)
    {
        Controls.InGameLoadingPresentation.Apply(
            RoomStatusText,
            RoomStatusLoadingIndicator,
            "正在退出房间",
            isLoading: true);
        Controls.InGameLoadingPresentation.Apply(
            CurrentRoomFeedbackText,
            CurrentRoomFeedbackLoadingIndicator,
            "正在退出房间",
            isLoading: true);
        LeaveRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        SetStatus("正在刷新房间", isLoading: true);
        RefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_PreviewKeyDown(
        object sender,
        System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForMenu();
            ToolHidden?.Invoke(this, EventArgs.Empty);
            return;
        }

        base.OnClosing(e);
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        Close();
}
