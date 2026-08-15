using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using WinForms = System.Windows.Forms;
using ControlsImage = System.Windows.Controls.Image;
using ControlsOrientation = System.Windows.Controls.Orientation;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void ApplyOverlayEventOptionLanguage(bool zh)
    {
        ApplyOverlayEventCountComboLanguage(OverlayEventMaxCountBox, zh);
        ApplyOverlayEventSpeedComboLanguage(OverlayEventAnimationSpeedBox, zh);
        RefreshOverlayEventDurationOverrideControls();
    }

    private void RefreshOverlayCommunicationEventControls()
    {
        if (OverlayInspectorCommunicationFriendEventsCheck is null ||
            OverlayInspectorCommunicationMessagePreviewCheck is null ||
            OverlayInspectorCommunicationDurationSlider is null)
        {
            return;
        }

        var enabled = ShowNoticePanelCheck?.IsChecked == true;
        OverlayInspectorCommunicationFriendEventsCheck.IsEnabled = enabled;
        OverlayInspectorCommunicationFriendEventsCheck.Opacity = enabled ? 1.0 : 0.58;
        var friendEventsEnabled = enabled && OverlayInspectorCommunicationFriendEventsCheck.IsChecked == true;
        OverlayInspectorCommunicationMessagePreviewCheck.IsEnabled = friendEventsEnabled;
        OverlayInspectorCommunicationMessagePreviewCheck.Opacity = friendEventsEnabled ? 1.0 : 0.58;
        OverlayInspectorCommunicationDurationSlider.IsEnabled = enabled;
        OverlayInspectorCommunicationDurationSlider.Opacity = enabled ? 1.0 : 0.58;
    }

    private static void ApplyOverlayEventCountComboLanguage(System.Windows.Controls.ComboBox? comboBox, bool zh)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (!int.TryParse(item.Tag?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var count))
            {
                continue;
            }

            item.Content = zh
                ? $"{count.ToString(CultureInfo.InvariantCulture)} 条"
                : count == 1 ? "1 item" : $"{count.ToString(CultureInfo.InvariantCulture)} items";
        }
    }

    private static void ApplyCommunicationDockComboLanguage(System.Windows.Controls.ComboBox? comboBox, bool zh)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            item.Content = item.Tag?.ToString() switch
            {
                "Bottom" => zh ? "底部" : "Bottom",
                _ => zh ? "顶部" : "Top"
            };
        }
    }

    private static void ApplyOverlayEventSpeedComboLanguage(System.Windows.Controls.ComboBox? comboBox, bool zh)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            item.Content = item.Tag?.ToString() switch
            {
                "Slow" => zh ? "舒缓" : "Slow",
                "Fast" => zh ? "快速" : "Fast",
                _ => zh ? "标准" : "Normal"
            };
        }
    }

    private void ApplyOverlayModuleStyleLanguage(bool zh)
    {
        if (OverlayInspectorModuleAppearanceTitleText is not null)
        {
            OverlayInspectorModuleAppearanceTitleText.Text = zh ? "模块独立设置" : "MODULE STYLE";
        }

        if (OverlayInspectorModuleLockCheck is not null)
        {
            OverlayInspectorModuleLockCheck.Content = zh ? "锁定此模块" : "Lock this module";
        }

        if (OverlayInspectorTextOpacityLabel is not null)
        {
            OverlayInspectorTextOpacityLabel.Text = zh ? "文字不透明度" : "TEXT OPACITY";
        }

        if (OverlayInspectorBackgroundOpacityLabel is not null)
        {
            OverlayInspectorBackgroundOpacityLabel.Text = zh ? "背景不透明度" : "BACKGROUND OPACITY";
        }

        if (OverlayFullScreenModuleLockCheck is not null)
        {
            OverlayFullScreenModuleLockCheck.Content = zh ? "锁定此模块" : "Lock this module";
        }

        if (OverlayFullScreenTextOpacityLabel is not null)
        {
            OverlayFullScreenTextOpacityLabel.Text = zh ? "文字不透明度" : "TEXT OPACITY";
        }

        if (OverlayFullScreenBackgroundOpacityLabel is not null)
        {
            OverlayFullScreenBackgroundOpacityLabel.Text = zh ? "背景不透明度" : "BACKGROUND OPACITY";
        }

    }

    private void ApplyLanguageToControls()
    {
        var zh = _language == "zh";
        _inGameMenuCoordinator.SetImageLanguage(_language);
        Title = GetAppDisplayTitle();
        WindowTitleText.Text = Title;

        LanguageBox.SelectionChanged -= LanguageBox_SelectionChanged;
        LanguageBox.SelectedIndex = zh ? 1 : 0;
        LanguageBox.SelectionChanged += LanguageBox_SelectionChanged;

        FindFleetNavText.Text = zh ? "寻找组织" : "Find Organization";
        MyFleetNavText.Text = zh ? "我的组织" : "My Organization";
        BridgeFindFleetSectionButton.Content = zh ? "寻找组织" : "Find Organization";
        System.Windows.Automation.AutomationProperties.SetName(
            BridgeFindFleetSectionButton,
            zh ? "寻找组织" : "Find Organization");
        BridgeMyFleetSectionButton.Content = zh ? "我的组织" : "My Organization";
        System.Windows.Automation.AutomationProperties.SetName(
            BridgeMyFleetSectionButton,
            zh ? "我的组织" : "My Organization");
        BridgePartyNavText.Text = zh ? "房间" : "Rooms";
        BridgePartyNavButton.ToolTip = zh ? "房间" : "Rooms";
        System.Windows.Automation.AutomationProperties.SetName(
            BridgePartyNavButton,
            zh ? "房间" : "Rooms");
        BridgeOverlayNavText.Text = zh ? "浮层" : "Overlay";
        BridgeOverlayNavButton.ToolTip = zh ? "游戏浮层" : "In-game Overlay";
        System.Windows.Automation.AutomationProperties.SetName(
            BridgeOverlayNavButton,
            zh ? "浮层" : "Overlay");
        BridgeInfoNavText.Text = zh ? "信息" : "Info";
        BridgeInfoNavButton.ToolTip = zh ? "说明、版本与反馈" : "Guides, versions, and feedback";
        System.Windows.Automation.AutomationProperties.SetName(
            BridgeInfoNavButton,
            zh ? "信息" : "Info");
        MySquadNavText.Text = zh ? "组队大厅" : "Party Lobby";
        OverlayNavText.Text = zh ? "游戏浮层" : "Overlay";
        FindFleetTab.Header = zh ? "寻找组织" : "Find Organization";
        FindFleetTitleText.Text = zh ? "寻找组织" : "Find Organization";
        FindFleetPlaceholderText.Text = zh
            ? "搜索公开组织，确认加入规则后加入同一组织以同步信息。"
            : "Search public organizations, confirm the join policy, then join the same organization for synchronization.";
        RefreshFleetDirectoryButton.Content = zh ? "刷新组织" : "Refresh Organizations";
        SelectLogButton.Content = zh ? "选择日志" : "Select Log";
        ToggleOverlayButton.Content = zh ? "切换浮层" : "Toggle Overlay";
        NetworkTestNavButton.Content = zh ? "联网测试 / 监控" : "Network / Monitor";
        HotkeyLimitHintText.Text = zh
            ? "热键会在桌面与游戏内保持可用；若提示按键被占用，请更换组合键。"
            : "The shortcut stays available on desktop and in game. Choose another combination if it is already in use.";
        FleetTab.Header = zh ? "组织" : "Organization";
        MySquadTab.Header = zh ? "组队大厅" : "Party Lobby";
        ApplyPartyLobbyLanguage(zh);
        RefreshFleetRailHeaders();
        OverlayEditTab.Header = zh ? "浮层设置" : "Overlay Settings";
        PersonalTab.Header = zh ? "个人" : "Personal";
        SettingsTab.Header = zh ? "设置" : "Settings";
        MonitorTab.Header = zh ? "监控" : "Monitor";
        FleetCommanderLabel.Text = zh ? "指挥官" : "COMMANDER";
        FleetActivityLabel.Text = zh ? "活动时间" : "ACTIVITY";
        TotalMembersLabel.Text = zh ? "总人数" : "TOTAL MEMBERS";
        OnlineLabel.Text = zh ? "在线" : "ONLINE";
        FleetShipsLabel.Text = zh ? "舰船统计" : "SHIPS";
        FleetHeaderAnnouncementLabelText.Text = zh ? "公告" : "BULLETIN";
        FleetNoticeInfoTabButton.Content = zh ? "公告" : "Notice";
        FleetCurrentTaskInfoTabButton.Content = zh ? "任务" : "Task";
        FleetActionPlanInfoTabButton.Content = zh ? "计划" : "Plan";
        PlayerNameColumn.Header = zh ? "游戏名" : "Name";
        PlayerStatusColumn.Header = zh ? "状态" : "Status";
        PlayerShipColumn.Header = zh ? "飞船" : "Ship";
        PlayerLocationColumn.Header = zh ? "位置" : "Location";
        OverlayPresetLabel.Text = zh ? "预设与恢复" : "PRESETS AND RECOVERY";
        OverlayHotkeyLabel.Text = zh ? "打开方式" : "OPENING";
        OverlayHotkeyGroupLabel.Text = zh ? "信息浮层热键" : "INFORMATION OVERLAY HOTKEY";
        OverlayQuickSettingsGroupText.Text = zh ? "快速设置" : "QUICK SETTINGS";
        OverlayContentLayoutGroupText.Text = zh ? "内容与布局" : "CONTENT AND LAYOUT";
        OverlayVisualExperienceGroupText.Text = zh ? "视觉体验" : "VISUAL EXPERIENCE";
        OverlayManagementGroupText.Text = zh ? "管理" : "MANAGEMENT";
        OverlayOverviewCategoryButton.Content = zh ? "总览" : "Overview";
        OverlayStartupCategoryButton.Content = zh ? "打开方式" : "Opening";
        OverlayDisplayBehaviorCategoryButton.Content = zh ? "跟随游戏" : "Follow game";
        OverlayModulesCategoryButton.Content = zh ? "模块与内容" : "Modules and content";
        OverlayPlacementCategoryButton.Content = zh ? "屏幕布局" : "Screen layout";
        OverlayCrosshairCategoryButton.Content = zh ? "虚拟准星" : "Virtual crosshair";
        OverlayAppearanceCategoryButton.Content = zh ? "外观" : "Appearance";
        OverlayMotionCategoryButton.Content = zh ? "动画与性能" : "Motion and performance";
        OverlayPresetCategoryButton.Content = zh ? "预设与恢复" : "Presets and recovery";
        OverlaySettingsScopeLabelText.Text = zh ? "设置范围" : "SETTING SCOPE";
        OverlaySettingsGlobalScopeText.Text = zh ? "通用" : "GLOBAL";
        OverlaySettingsPresetScopeText.Text = zh ? "当前预设" : "ACTIVE PRESET";
        OverlaySettingsScopeHintText.Text = zh
            ? "打开方式作用于所有预设；布局、内容和外观保存到当前预设。"
            : "Opening applies to every preset. Layout, content, and appearance are saved to the active preset.";
        RefreshOverlayPresetBoxItems();
        OverlayRenamePresetButton.Content = zh ? "重命名" : "Rename";
        OverlayDuplicatePresetButton.Content = zh ? "复制" : "Copy";
        OverlayDeletePresetButton.Content = zh ? "删除" : "Delete";
        OverlayImportPresetButton.Content = zh ? "导入预设" : "Import";
        OverlayExportPresetButton.Content = zh ? "导出预设" : "Export";
        OverlayOverviewTitleText.Text = zh ? "总览" : "OVERVIEW";
        OverlayOverviewDescriptionText.Text = zh
            ? "从这里检查当前浮层的预设、模块与启动行为。右侧屏幕布局就是游戏内布局的编辑面。"
            : "Review the active preset, information modules, and launch state. The screen layout on the right is the in-game editing surface.";
        OverlayOverviewStatusLabel.Text = zh ? "浮层状态" : "OVERLAY STATUS";
        OverlayOverviewPresetLabel.Text = zh ? "当前预设" : "ACTIVE PRESET";
        OverlayOverviewModuleCountLabel.Text = zh ? "信息模块" : "INFO MODULES";
        OverlayOverviewLayoutLabel.Text = zh ? "目标画布" : "TARGET CANVAS";
        OverlayOverviewCanvasHintText.Text = zh ? "自动匹配当前显示器" : "Matches the active display";
        OverlayOverviewSavedLabel.Text = zh ? "本次保存" : "SESSION SAVE";
        OverlayOverviewDirtyLabel.Text = zh ? "未保存更改" : "UNSAVED CHANGES";
        OverlayOverviewActionsHintText.Text = zh
            ? "打开、保存和放弃更改统一位于页面顶部；恢复操作集中在“预设与恢复”。"
            : "Open, save, and discard are kept at the top. Recovery actions are grouped under Presets and recovery.";
        OverlayHeaderDiscardButton.Content = zh ? "放弃更改" : "Discard changes";
        SaveLayoutButton.Content = zh ? "保存更改" : "Save changes";
        OverlayOptionsLabel.Text = zh ? "模块与内容" : "MODULES AND CONTENT";
        OverlayModuleWorkbenchEntryTitleText.Text = zh ? "模块工作台" : "MODULE WORKBENCH";
        OverlayModuleWorkbenchEntryDescriptionText.Text = zh
            ? "选择模块，调整内容、显示规则、停留时间、位置与外观。"
            : "Choose a module, then adjust its content, display rules, duration, position, and appearance.";
        OverlayOpenModuleWorkbenchButton.Content = zh ? "打开工作台" : "Open workbench";
        OverlayModuleTogglesGroupLabel.Text = zh ? "全部模块" : "ALL MODULES";
        OverlayModuleSettingsOwnershipHintText.Text = zh
            ? "可点击右侧画布中的模块快速调整，也可从上方模块工作台统一选择。"
            : "Select a module on the canvas for a quick edit, or use the workbench above to browse every module.";
        OverlayEventRailGroupLabel.Text = zh ? "显示规则" : "DISPLAY RULES";
        ShowNoticePanelCheck.Content = zh ? "显示通讯提醒" : "Show communication alerts";
        ShowSquadsPanelCheck.Content = zh ? "显示舰队总览" : "Show fleet overview";
        ShowMembersPanelCheck.Content = zh ? "显示成员信息" : "Show member information";
        ShowChatPanelCheck.Content = zh ? "显示场景通讯" : "Show scene communication";
        ShowEventNotificationsCheck.Content = zh ? "显示事件通知" : "Show event notifications";
        OverlayEventSettingsTitleText.Text = zh ? "事件内容" : "EVENT CONTENT";
        OverlayEventSettingsDescriptionText.Text = zh
            ? "管理事件类型、显示数量和停留规则。"
            : "Manage event types, display count, and duration rules.";
        OverlayEventMaxCountLabel.Text = zh ? "最大显示" : "MAX VISIBLE";
        OverlayEventPinImportantCheck.Content = zh ? "重要事件常驻" : "Keep important events";
        OverlayEventAnimationSpeedLabel.Text = zh ? "弹出速度" : "ANIMATION";
        OverlayEventTypesLabel.Text = zh ? "播报类型" : "EVENT TYPES";
        EventNotifyMemberPresenceCheck.Content = zh ? "成员上线/离线" : "Member online/offline";
        EventNotifyMemberServerCheck.Content = zh ? "成员进出服务器" : "Member enters/leaves server";
        EventNotifySameServerCheck.Content = zh ? "同服提醒与概况" : "Same-server alerts";
        EventNotifyShipChangeCheck.Content = zh ? "飞船变化" : "Ship changes";
        EventNotifyLocationChangeCheck.Content = zh ? "地点变化" : "Location changes";
        EventNotifyOnlineSummaryCheck.Content = zh ? "在线人数变化" : "Online count changes";
        EventNotifyPrimaryServerCheck.Content = zh ? "主服务器变化" : "Primary server changes";
        EventNotifyDeathAndRespawnCheck.Content = zh ? "倒地 / 死亡 / 获救 / 重生" : "Downed / death / revived / respawn";
        EventNotifyLocalPlayReminderCheck.Content = zh
            ? "连续游戏提醒（每 2 小时）"
            : "Continuous play reminder (every 2 hours)";
        ApplyOverlayEventOptionLanguage(zh);
        OverlayModuleLibraryTitleText.Text = zh ? "隐藏模块" : "HIDDEN MODULES";
        OverlayModuleLibraryHintText.Text = zh
            ? "点击模块可恢复到上次布局位置。"
            : "Click a module to restore it to its previous layout position.";
        OverlayEventNotificationSideLabel.Text = zh ? "弹出侧" : "POP SIDE";
        OverlayEventNotificationDurationLabel.Text = zh ? "显示时长" : "DISPLAY TIME";
        OverlaySettingsShowGridCheck.Content = zh ? "显示网格" : "Show grid";
        OverlaySettingsSnapGridCheck.Content = zh ? "吸附到网格" : "Snap to grid";
        OverlaySettingsSnapEdgeCheck.Content = zh ? "吸附到边缘与中心线" : "Snap to edges and center";
        OverlaySettingsLockLayoutCheck.Content = zh ? "锁定布局" : "Lock layout";
        OverlayEditorUndoButton.Content = zh ? "撤销" : "Undo";
        OverlayEditorRedoButton.Content = zh ? "重做" : "Redo";
        RefreshOverlaySceneChrome();
        ApplyOverlaySceneComboLanguage(OverlaySceneModeBox, zh);
        ApplyOverlaySceneComboLanguage(OverlayBehaviorSceneModeBox, zh);
        ApplyOverlaySceneComboLanguage(OverlayFullScreenSceneModeBox, zh);
        OverlayFullScreenToolsTitleText.Text = zh ? "专注编辑工具" : "Focus edit tools";
        OverlayFullScreenToolsHintText.Text = zh
            ? "不退出全屏即可调整常用设置。"
            : "Adjust common settings without leaving fullscreen.";
        OverlayFullScreenToolsToggleButton.Content = zh ? "工具" : "Tools";
        OverlayFullScreenExitButton.Content = zh ? "退出全屏" : "Exit fullscreen";
        OverlayFullScreenUndoButton.Content = zh ? "撤销" : "Undo";
        OverlayFullScreenRedoButton.Content = zh ? "重做" : "Redo";
        OverlayFullScreenSaveButton.Content = zh ? "保存更改" : "Save changes";
        OverlayFullScreenDiscardButton.Content = zh ? "放弃更改" : "Discard changes";
        OverlayFullScreenResetLayoutButton.Content = zh ? "重置布局" : "Reset layout";
        OverlayFullScreenCurrentModuleTitleText.Text = zh ? "当前模块" : "CURRENT MODULE";
        OverlayFullScreenPlacementTitleText.Text = zh ? "编辑辅助" : "EDIT AIDS";
        OverlayFullScreenShowGridCheck.Content = zh ? "显示网格" : "Show grid";
        OverlayFullScreenSnapGridCheck.Content = zh ? "吸附到网格" : "Snap to grid";
        OverlayFullScreenSnapEdgeCheck.Content = zh ? "吸附到边缘与中心线" : "Snap to edges and center";
        OverlayFullScreenLockLayoutCheck.Content = zh ? "锁定布局" : "Lock layout";
        OverlayFullScreenLivePreviewCheck.Content = zh ? "模拟信息" : "Simulated data";
        OverlayFullScreenModuleLibraryTitleText.Text = zh ? "隐藏模块" : "HIDDEN MODULES";
        OverlayFullScreenGlobalActionsTitleText.Text = zh ? "全局操作" : "GLOBAL ACTIONS";
        OverlayFullScreenInspectorResetButton.Content = zh ? "重置模块" : "Reset module";
        OverlayFullScreenInspectorHideButton.Content = zh ? "隐藏模块" : "Hide module";
        OverlayFullScreenModuleSettingsTitleText.Text = zh ? "模块设置" : "MODULE SETTINGS";
        OverlayFullScreenEventSideLabel.Text = zh ? "弹出侧" : "POP SIDE";
        OverlayFullScreenEventDurationLabel.Text = zh ? "显示时长（秒）" : "DISPLAY TIME (SEC)";
        OverlayFullScreenNoticeHintText.Text = zh
            ? "无事件时自动隐藏；位置仅可贴合画布顶部或底部。"
            : "Hidden while idle. This module can only dock to the top or bottom edge.";
        OverlayFullScreenCommunicationFriendEventsCheck.Content = zh ? "好友通讯提醒" : "Friend communication alerts";
        OverlayFullScreenCommunicationMessagePreviewCheck.Content = zh ? "显示私信正文预览" : "Show private-message preview";
        OverlayFullScreenCommunicationDockLabel.Text = zh ? "吸附位置" : "DOCK POSITION";
        ApplyCommunicationDockComboLanguage(OverlayFullScreenCommunicationDockBox, zh);
        OverlayFullScreenCommunicationDurationLabel.Text = zh ? "停留时间" : "DURATION";
        OverlayFullScreenSquadModeLabel.Text = zh ? "态势显示" : "STATUS VIEW";
        OverlayFullScreenHideSquadIconsCheck.Content = zh ? "隐藏小队图标" : "Hide squad icons";
        OverlayFullScreenMemberScopeLabel.Text = zh ? "显示范围" : "SCOPE";
        OverlayFullScreenHideOfflineMembersCheck.Content = zh ? "隐藏离线小队成员" : "Hide offline squad members";
        OverlayFullScreenHideMemberOnlineStatusCheck.Content = zh ? "隐藏成员在线状态" : "Hide member online status";
        OverlayFullScreenHideSelfMemberCheck.Content = zh ? "隐藏自己" : "Hide self";
        OverlayFullScreenMemberPriorityLabel.Text = zh ? "优先显示" : "PRIORITY";
        OverlayFullScreenMemberNameModeLabel.Text = zh ? "名称显示" : "NAME MODE";
        OverlayInspectorHeaderText.Text = zh ? "模块工作台" : "Module workbench";
        OverlayInspectorCloseButton.Content = zh ? "返回设置" : "Back to settings";
        OverlayInspectorCloseButton.ToolTip = zh ? "返回之前查看的设置" : "Return to the settings you were viewing";
        OverlayInspectorHintText.Text = zh
            ? "调整当前模块，右侧画面会立即显示结果。"
            : "Adjust the current module while the preview updates immediately.";
        OverlayInspectorSwitchModuleText.Text = zh ? "切换模块" : "Switch module";
        OverlayInspectorModulePickerHintText.Text = zh
            ? "选择模块后，设置区会立即切换并保持右侧预览。"
            : "Choose a module to switch its settings while keeping the preview visible.";
        OverlayEventInspectorSectionTitleText.Text = zh ? "弹出行为" : "POP BEHAVIOR";
        OverlayNoticeInspectorSectionTitleText.Text = zh ? "通讯提醒" : "COMMUNICATION ALERTS";
        OverlayNoticeInspectorEmptyText.Text = zh
            ? "无事件时自动隐藏；位置仅可贴合画布顶部或底部。"
            : "Hidden while idle. This module can only dock to the top or bottom edge.";
        OverlayInspectorCommunicationFriendEventsCheck.Content = zh ? "好友通讯提醒" : "Friend communication alerts";
        OverlayInspectorCommunicationMessagePreviewCheck.Content = zh ? "显示私信正文预览" : "Show private-message preview";
        OverlayInspectorCommunicationDockLabel.Text = zh ? "吸附位置" : "DOCK POSITION";
        ApplyCommunicationDockComboLanguage(OverlayInspectorCommunicationDockBox, zh);
        OverlayInspectorCommunicationDurationLabel.Text = zh ? "停留时间" : "DURATION";
        OverlaySquadsInspectorSectionTitleText.Text = zh ? "态势内容" : "STATUS CONTENT";
        OverlayMembersInspectorSectionTitleText.Text = zh ? "成员显示" : "MEMBER DISPLAY";
        OverlayHiddenModuleLibraryTitleText.Text = zh ? "模块库" : "MODULE LIBRARY";
        OverlayHiddenModuleLibraryHintText.Text = zh
            ? "被隐藏的模块可在这里恢复到上次布局位置。"
            : "Hidden modules can be restored here to their previous layout position.";
        RefreshOverlayHiddenModuleLibrary();
        OverlayInspectorResetButton.Content = zh ? "恢复模块默认" : "Restore module defaults";
        OverlayInspectorHideButton.Content = zh ? "从画面隐藏" : "Hide from canvas";
        OverlayInspectorHideSquadIconsCheck.Content = zh ? "隐藏小队图标" : "Hide squad icons";
        OverlayInspectorHideOfflineMembersCheck.Content = zh ? "隐藏离线小队成员" : "Hide offline squad members";
        OverlayInspectorHideMemberOnlineStatusCheck.Content = zh ? "隐藏成员在线状态" : "Hide member online status";
        OverlayInspectorHideSelfMemberCheck.Content = zh ? "隐藏自己" : "Hide self";
        if (OverlayEventNotificationSideBox.Items.Count >= 2)
        {
            ((ComboBoxItem)OverlayEventNotificationSideBox.Items[0]).Content = zh ? "左侧" : "Left";
            ((ComboBoxItem)OverlayEventNotificationSideBox.Items[1]).Content = zh ? "右侧" : "Right";
        }
        if (OverlayFullScreenEventSideBox.Items.Count >= 2)
        {
            ((ComboBoxItem)OverlayFullScreenEventSideBox.Items[0]).Content = zh ? "左侧" : "Left";
            ((ComboBoxItem)OverlayFullScreenEventSideBox.Items[1]).Content = zh ? "右侧" : "Right";
        }
        if (OverlayInspectorSquadStatusModeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorSquadStatusModeBox.Items[0]).Content = zh ? "自动" : "Auto";
            ((ComboBoxItem)OverlayInspectorSquadStatusModeBox.Items[1]).Content = zh ? "精简" : "Compact";
            ((ComboBoxItem)OverlayInspectorSquadStatusModeBox.Items[2]).Content = zh ? "详细" : "Detailed";
        }
        if (OverlayFullScreenSquadStatusModeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenSquadStatusModeBox.Items[0]).Content = zh ? "自动" : "Auto";
            ((ComboBoxItem)OverlayFullScreenSquadStatusModeBox.Items[1]).Content = zh ? "精简" : "Compact";
            ((ComboBoxItem)OverlayFullScreenSquadStatusModeBox.Items[2]).Content = zh ? "详细" : "Detailed";
        }
        if (OverlayInspectorMemberScopeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorMemberScopeBox.Items[0]).Content = zh ? "当前小队" : "Current squad";
            ((ComboBoxItem)OverlayInspectorMemberScopeBox.Items[1]).Content = zh ? "全组织" : "All organization";
            ((ComboBoxItem)OverlayInspectorMemberScopeBox.Items[2]).Content = zh ? "其他小队" : "Other squads";
        }
        if (OverlayFullScreenMemberScopeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenMemberScopeBox.Items[0]).Content = zh ? "当前小队" : "Current squad";
            ((ComboBoxItem)OverlayFullScreenMemberScopeBox.Items[1]).Content = zh ? "全组织" : "All organization";
            ((ComboBoxItem)OverlayFullScreenMemberScopeBox.Items[2]).Content = zh ? "其他小队" : "Other squads";
        }
        if (OverlayInspectorMemberPriorityBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorMemberPriorityBox.Items[0]).Content = zh ? "默认" : "Default";
            ((ComboBoxItem)OverlayInspectorMemberPriorityBox.Items[1]).Content = zh ? "自己" : "Self";
            ((ComboBoxItem)OverlayInspectorMemberPriorityBox.Items[2]).Content = zh ? "小队长" : "Squad lead";
        }
        if (OverlayFullScreenMemberPriorityBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenMemberPriorityBox.Items[0]).Content = zh ? "默认" : "Default";
            ((ComboBoxItem)OverlayFullScreenMemberPriorityBox.Items[1]).Content = zh ? "自己" : "Self";
            ((ComboBoxItem)OverlayFullScreenMemberPriorityBox.Items[2]).Content = zh ? "小队长" : "Squad lead";
        }
        if (OverlayInspectorMemberNameModeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorMemberNameModeBox.Items[0]).Content = zh ? "呼号 + 游戏名" : "Callsign + game name";
            ((ComboBoxItem)OverlayInspectorMemberNameModeBox.Items[1]).Content = zh ? "仅呼号" : "Only callsign";
            ((ComboBoxItem)OverlayInspectorMemberNameModeBox.Items[2]).Content = zh ? "仅游戏名" : "Only game name";
        }
        if (OverlayFullScreenMemberNameModeBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenMemberNameModeBox.Items[0]).Content = zh ? "呼号 + 游戏名" : "Callsign + game name";
            ((ComboBoxItem)OverlayFullScreenMemberNameModeBox.Items[1]).Content = zh ? "仅呼号" : "Only callsign";
            ((ComboBoxItem)OverlayFullScreenMemberNameModeBox.Items[2]).Content = zh ? "仅游戏名" : "Only game name";
        }
        if (OverlayInspectorHorizontalAnchorBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorHorizontalAnchorBox.Items[0]).Content = zh ? "左" : "Left";
            ((ComboBoxItem)OverlayInspectorHorizontalAnchorBox.Items[1]).Content = zh ? "居中" : "Center";
            ((ComboBoxItem)OverlayInspectorHorizontalAnchorBox.Items[2]).Content = zh ? "右" : "Right";
        }
        if (OverlayFullScreenHorizontalAnchorBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenHorizontalAnchorBox.Items[0]).Content = zh ? "左" : "Left";
            ((ComboBoxItem)OverlayFullScreenHorizontalAnchorBox.Items[1]).Content = zh ? "居中" : "Center";
            ((ComboBoxItem)OverlayFullScreenHorizontalAnchorBox.Items[2]).Content = zh ? "右" : "Right";
        }
        if (OverlayInspectorVerticalAnchorBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayInspectorVerticalAnchorBox.Items[0]).Content = zh ? "上" : "Top";
            ((ComboBoxItem)OverlayInspectorVerticalAnchorBox.Items[1]).Content = zh ? "居中" : "Middle";
            ((ComboBoxItem)OverlayInspectorVerticalAnchorBox.Items[2]).Content = zh ? "下" : "Bottom";
        }
        if (OverlayFullScreenVerticalAnchorBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayFullScreenVerticalAnchorBox.Items[0]).Content = zh ? "上" : "Top";
            ((ComboBoxItem)OverlayFullScreenVerticalAnchorBox.Items[1]).Content = zh ? "居中" : "Middle";
            ((ComboBoxItem)OverlayFullScreenVerticalAnchorBox.Items[2]).Content = zh ? "下" : "Bottom";
        }
        RefreshOverlayOverviewSummary();
        OverlayThemeLabel.Text = zh ? "外观" : "APPEARANCE";
        OverlayAppearanceDescriptionText.Text = zh
            ? "选择一种外观，再调整该外观支持的配色与显示强度。"
            : "Choose an appearance, then tune the colors and display strength it supports.";
        OverlaySkinHeaderText.Text = zh ? "外观" : "Appearance";
        OverlaySkinDescriptionText.Text = zh
            ? "外观会统一浮层的结构、配色、泛光与转场。"
            : "An appearance unifies overlay structure, color, bloom, and transitions.";
        RefreshOverlaySkinOptions();
        OverlayNightShadowBloomLabel.Text = zh ? "风格泛光效果" : "Style bloom";
        if (OverlayNightShadowBloomBox.Items.Count >= 3)
        {
            ((ComboBoxItem)OverlayNightShadowBloomBox.Items[0]).Content = zh ? "关闭" : "Off";
            ((ComboBoxItem)OverlayNightShadowBloomBox.Items[1]).Content = zh ? "标准" : "Standard";
            ((ComboBoxItem)OverlayNightShadowBloomBox.Items[2]).Content = zh ? "强化" : "Strong";
        }
        OverlayAnimationFrameRateLabel.Text = zh ? "常驻动效帧率" : "AMBIENT MOTION FRAME RATE";
        OverlayAnimationFrameRateHintText.Text = zh
            ? "控制模块流光、事件弹出等持续动画；不会改变启动转场帧率。"
            : "Controls persistent module flows and event motion without changing the startup transition frame rate.";
        if (OverlayAnimationFrameRateBox.Items.Count >= 4)
        {
            ((ComboBoxItem)OverlayAnimationFrameRateBox.Items[0]).Content = zh ? "关闭" : "Off";
            ((ComboBoxItem)OverlayAnimationFrameRateBox.Items[1]).Content = "30 FPS";
            ((ComboBoxItem)OverlayAnimationFrameRateBox.Items[2]).Content = "60 FPS";
            ((ComboBoxItem)OverlayAnimationFrameRateBox.Items[3]).Content = "120 FPS";
        }
        OverlayThemeSelectLabel.Text = zh ? "颜色方案" : "COLOR SCHEME";
        OverlayThemeLockedValueText.Text = zh
            ? "固定配色由当前风格决定"
            : "The fixed palette is defined by the current style";
        AutoThemeByShipCheck.Content = zh ? "自动切换至当前飞船厂商风格" : "Auto switch to current ship manufacturer style";
        if (OverlayThemeBox.Items.Count >= 13)
        {
            ((ComboBoxItem)OverlayThemeBox.Items[0]).Content = zh ? "默认" : "Default";
            ((ComboBoxItem)OverlayThemeBox.Items[1]).Content = zh ? "铁砧" : "Anvil";
            ((ComboBoxItem)OverlayThemeBox.Items[2]).Content = zh ? "德雷克" : "Drake";
            ((ComboBoxItem)OverlayThemeBox.Items[3]).Content = zh ? "南船座" : "Argo";
            ((ComboBoxItem)OverlayThemeBox.Items[4]).Content = zh ? "武藏" : "MISC";
            ((ComboBoxItem)OverlayThemeBox.Items[5]).Content = zh ? "未来" : "Mirai";
            ((ComboBoxItem)OverlayThemeBox.Items[6]).Content = zh ? "十字军" : "Crusader";
            ((ComboBoxItem)OverlayThemeBox.Items[7]).Content = zh ? "圣盾" : "Aegis";
            ((ComboBoxItem)OverlayThemeBox.Items[8]).Content = "RSI";
            ((ComboBoxItem)OverlayThemeBox.Items[9]).Content = zh ? "起源" : "Origin";
            ((ComboBoxItem)OverlayThemeBox.Items[10]).Content = zh ? "奥波亚" : "Aopoa";
            ((ComboBoxItem)OverlayThemeBox.Items[11]).Content = zh ? "埃斯佩里亚" : "Esperia";
            ((ComboBoxItem)OverlayThemeBox.Items[12]).Content = zh ? "盖塔克" : "Gatac";
        }
        CrosshairLabel.Text = zh ? "虚拟准星" : "VIRTUAL CROSSHAIR";
        OverlayTransitionLabel.Text = zh ? "动画与性能" : "MOTION AND PERFORMANCE";
        OverlayMotionDescriptionText.Text = zh
            ? "选择常用体验方案，或继续分别调整转场与常驻动画。"
            : "Choose a common experience profile or tune transitions and ambient motion separately.";
        OverlayExperiencePresetLabelText.Text = zh ? "快速体验设置" : "QUICK EXPERIENCE";
        OverlayExperienceSmoothButton.Content = zh ? "流畅优先" : "Smooth";
        OverlayExperienceBalancedButton.Content = zh ? "均衡" : "Balanced";
        OverlayExperienceReducedMotionButton.Content = zh ? "减少动画" : "Reduced motion";
        OverlayExperiencePresetHintText.Text = zh
            ? "此操作会同时调整启动转场与常驻动画帧率，可撤销，也可继续单独修改。"
            : "This changes both the opening transition and ambient frame rate. It can be undone or tuned further.";
        OverlayStartupTransitionGroupLabel.Text = zh ? "风格对应转场" : "APPEARANCE TRANSITION";
        OverlayTransitionFrameRateLabel.Text = zh ? "转场帧率" : "TRANSITION FRAME RATE";
        OverlayTransitionEnabledCheck.Content = zh ? "启动浮层时播放转场" : "Play transition when overlay opens";
        OverlaySkipTransitionInGameCheck.Content = zh ? "游戏内开启时跳过转场" : "Skip transition when opened in game";
        OverlaySkipTransitionInGameCheck.ToolTip = zh
            ? "Star Citizen 位于前台时，开启浮层将直接显示内容。"
            : "Show the overlay immediately when Star Citizen is in the foreground.";
        OverlayGlobalHotkeyEnabledCheck.Content = zh
            ? "启用信息浮层热键"
            : "Enable information overlay hotkey";
        OverlayAutoFocusGameWindowCheck.Content = zh ? "启动浮层时自动切换至游戏窗口" : "Switch to game window when overlay opens";
        OverlayAutoOpenOnGameStartCheck.Content = zh ? "启动游戏时自动开启浮层" : "Open overlay when the game starts";
        OverlayAutoOpenOnGameForegroundCheck.Content = zh ? "回到游戏窗口时开启浮层" : "Open overlay when returning to the game";
        OverlayAutoCloseOnGameBackgroundCheck.Content = zh ? "离开游戏窗口时关闭浮层" : "Close overlay when leaving the game window";
        SetOverlayHotkeyRegistrationState(_overlayHotkeyRegistrationState);
        if (OverlayTransitionFrameRateBox.Items.Count >= 4)
        {
            ((ComboBoxItem)OverlayTransitionFrameRateBox.Items[0]).Content = zh ? "性能优先 30 FPS" : "Performance 30 FPS";
            ((ComboBoxItem)OverlayTransitionFrameRateBox.Items[1]).Content = zh ? "均衡 45 FPS" : "Balanced 45 FPS";
            ((ComboBoxItem)OverlayTransitionFrameRateBox.Items[2]).Content = zh ? "流畅 60 FPS" : "Smooth 60 FPS";
            ((ComboBoxItem)OverlayTransitionFrameRateBox.Items[3]).Content = zh ? "极致 120 FPS" : "Ultra 120 FPS";
        }
        ShowCrosshairCheck.Content = zh ? "显示虚拟准星" : "Show virtual crosshair";
        CrosshairModeLabel.Text = zh ? "样式" : "STYLE";
        ApplyOverlayCrosshairModeLanguage(CrosshairModeBox, zh);
        ApplyOverlayCrosshairModeLanguage(OverlayInspectorCrosshairModeBox, zh);
        ApplyOverlayCrosshairModeLanguage(OverlayFullScreenCrosshairModeBox, zh);
        CrosshairThemeColorCheck.Content = zh ? "跟随当前风格颜色" : "Use current theme color";
        CrosshairSizeLabel.Text = zh ? "整体大小" : "OVERALL SIZE";
        CrosshairThicknessLabel.Text = zh ? "粗细" : "THICKNESS";
        CrosshairGapLabel.Text = zh ? "中心间距" : "CENTER GAP";
        CrosshairCenterMarkCheck.Content = zh ? "显示中心点" : "Show center dot";
        CrosshairCenterSizeLabel.Text = zh ? "中心点大小" : "CENTER DOT SIZE";
        CrosshairOpacityLabel.Text = zh ? "准星不透明度" : "CROSSHAIR OPACITY";
        CrosshairOutlineOpacityLabel.Text = zh ? "边缘增强" : "EDGE BOOST";
        CrosshairColorPickerButton.Content = zh ? "选择颜色" : "Pick color";
        CrosshairColorPreview.ToolTip = zh ? "选择颜色" : "Pick color";
        OverlayDisplayBehaviorTitleText.Text = zh ? "跟随游戏" : "FOLLOW GAME";
        OverlayDisplayBehaviorDescriptionText.Text = zh
            ? "决定浮层显示什么内容，以及它如何跟随游戏窗口。"
            : "Choose the content Overlay shows and how it follows the game window.";
        OverlaySceneSourceLabel.Text = zh ? "内容场景" : "CONTENT SCENE";
        OverlaySceneSourceHintText.Text = zh
            ? "自动模式会在加入组队房间时显示房间内容，其余时间显示舰队内容。"
            : "Auto shows the party room while joined and fleet content at other times.";
        OverlayGameWindowLinkLabel.Text = zh ? "游戏窗口联动" : "GAME WINDOW LINK";
        OverlayMainWindowBehaviorLabel.Text = zh ? "主窗口行为" : "MAIN WINDOW BEHAVIOR";
        TrayModeCheck.Content = zh ? "窗口最小化时仍然可以显示浮层" : "Keep overlay visible when minimized";
        TrayModeHintText.Text = zh
            ? "启用后，主窗口最小化时不会隐藏已经开启的浮层。"
            : "When enabled, minimizing the main window will not hide an active Overlay.";
        AvatarPlaceholderText.Content = zh ? "头像" : "AVATAR";
        ChooseAvatarButton.Content = zh ? "更换头像" : "Change Avatar";
        FeedbackButton.Content = zh ? "反馈" : "Feedback";
        PersonalProfileSectionButton.Content = zh ? "个人资料" : "Profile";
        PersonalDataSyncSectionButton.Content = zh ? "同步与隐私" : "Sync & Privacy";
        PersonalAppSettingsSectionButton.Content = zh ? "应用设置" : "App Settings";
        PersonalNotificationsSectionButton.Content = zh ? "通知偏好" : "Notifications";
        PlayerNameLabel.Text = zh ? "游戏名" : "Player Name";
        PlayerIdLabel.Text = zh ? "玩家 ID" : "Player ID";
        CallsignLabel.Text = zh ? "呼号" : "Callsign";
        EmailNotificationsCheck.Content = zh ? "允许" : "Allow";
        FleetLabel.Text = zh ? "组织" : "Organization";
        LocalFleetText.Text = zh ? "本地组织" : "Local Organization";
        StatusLabel.Text = zh ? "状态" : "Status";
        ShipDatabaseTitleText.Text = zh ? "个人舰船库" : "Personal Ship Database";
        ShipDatabaseHintText.Text = zh
            ? "来自官网机库整库读取，用于个人资产查看与组织舰船库同步。不会保存 RSI 账号密码。"
            : "Read from the official hangar for personal asset review and fleet ship database sync. RSI credentials are never saved.";
        OpenHangarReaderButton.Content = zh ? "读取官网机库" : "Read Hangar";
        ClearShipDatabaseButton.Content = zh ? "清空舰船库" : "Clear Ships";
        OwnedShipNameColumn.Header = zh ? "舰船" : "Ship";
        OwnedShipCodeColumn.Header = zh ? "代码" : "Code";
        OwnedShipValueColumn.Header = zh ? "价值" : "Value";
        OwnedShipSourceColumn.Header = zh ? "来源" : "Source";
        OwnedShipImportedAtColumn.Header = zh ? "入库时间" : "Acquired";
        OwnedShipSyncedAtColumn.Header = zh ? "同步时间" : "Synced";
        UpdateShipDatabaseSummary();
        RenderOverlayEditor();
        ApplyOverlaySettingsWorkspacePresentation();
    }

    private static string NormalizeLanguage(string? language)
    {
        return "zh";
    }

    private void LoadAvatarPreview()
    {
        if (!IsLoggedIn)
        {
            AvatarImage.Source = null;
            AvatarPlaceholderText.Content = "请登录";
            AvatarPlaceholderText.Visibility = Visibility.Visible;
            return;
        }

        if (string.IsNullOrWhiteSpace(_avatarPath) || !File.Exists(_avatarPath))
        {
            AvatarImage.Source = null;
            AvatarPlaceholderText.Content = _language == "zh" ? "头像" : "AVATAR";
            AvatarPlaceholderText.Visibility = Visibility.Visible;
            return;
        }

        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(_avatarPath);
        image.EndInit();
        image.Freeze();

        AvatarImage.Source = image;
        AvatarPlaceholderText.Visibility = Visibility.Collapsed;
    }

    private void LoadCreateFleetLogoPreview()
    {
        if (CreateFleetLogoImage is null || CreateFleetLogoText is null)
        {
            return;
        }

        if (!TryLoadBitmapImage(_createFleetLogoPath, out var image))
        {
            CreateFleetLogoImage.Source = null;
            CreateFleetLogoText.Visibility = Visibility.Visible;
            return;
        }

        CreateFleetLogoImage.Source = image;
        CreateFleetLogoText.Visibility = Visibility.Collapsed;
    }

    private void LoadCreateFleetBannerPreview()
    {
        if (CreateFleetBannerImage is null || CreateFleetBannerText is null)
        {
            return;
        }

        if (!TryLoadBitmapImage(_fleetBannerPath, out var image))
        {
            CreateFleetBannerImage.Source = null;
            CreateFleetBannerText.Visibility = Visibility.Visible;
            return;
        }

        CreateFleetBannerImage.Source = image;
        CreateFleetBannerText.Visibility = Visibility.Collapsed;
    }

    private void LoadFleetHeaderLogoPreview()
    {
        if (FleetHeaderLogoImage is null || FleetHeaderLogoText is null)
        {
            return;
        }

        if (!TryLoadBitmapImage(_fleetLogoPath, out var image))
        {
            FleetHeaderLogoImage.Source = null;
            FleetHeaderLogoText.Visibility = Visibility.Visible;
            return;
        }

        FleetHeaderLogoImage.Source = image;
        FleetHeaderLogoText.Visibility = Visibility.Collapsed;
    }

    private void RefreshBridgeFleetIdentityMark()
    {
        if (BridgeFleetIdentityMark is null || BridgeFleetIdentityLogoImage is null)
        {
            return;
        }

        BridgeFleetIdentityLogoImage.Source = null;
        BridgeFleetIdentityMark.ToolTip = null;
        BridgeFleetIdentityMark.Visibility = Visibility.Collapsed;

        if (!_hasFleet || !TryLoadBitmapImage(_fleetLogoPath, out var image))
        {
            return;
        }

        BridgeFleetIdentityLogoImage.Source = image;
        BridgeFleetIdentityMark.ToolTip = string.IsNullOrWhiteSpace(_fleetName)
            ? "当前组织"
            : _fleetName;
        BridgeFleetIdentityMark.Visibility = Visibility.Visible;
    }

    private void LoadFleetHeaderBannerPreview()
    {
        if (!TryLoadBitmapImage(_fleetBannerPath, out var image))
        {
            ApplyFleetHeaderBannerImage(null);
            return;
        }

        ApplyFleetHeaderBannerImage(image);
    }

    private void ApplyFleetHeaderBannerImage(ImageSource? image)
    {
        var hasBanner = image is not null;

        if (TopBannerReserveRow is not null)
        {
            TopBannerReserveRow.Height = new GridLength(0);
        }

        if (TopFleetBannerLayer is not null)
        {
            TopFleetBannerLayer.Visibility = Visibility.Collapsed;
        }

        if (TopFleetBannerImage is not null)
        {
            TopFleetBannerImage.Source = null;
        }

        if (FleetHeaderBannerImage is not null)
        {
            FleetHeaderBannerImage.Source = image;
            FleetHeaderBannerImage.Visibility = hasBanner ? Visibility.Visible : Visibility.Collapsed;
        }

        if (FleetHeaderBannerScrim is not null)
        {
            FleetHeaderBannerScrim.Visibility = hasBanner ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void RefreshPersonalHeaderFleetCard()
    {
        if (PersonalHeaderFleetNameText is null ||
            PersonalHeaderFleetCodeText is null ||
            PersonalHeaderFleetLogoImage is null ||
            PersonalHeaderFleetRoleText is null)
        {
            return;
        }

        var mutedBrush = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        var disabledBrush = FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);

        PersonalHeaderFleetNameText.Text = _hasFleet ? _fleetName : "暂无所属组织";
        PersonalHeaderFleetCodeText.Text = _hasFleet
            ? string.IsNullOrWhiteSpace(_fleetCode) ? "识别码未设置" : _fleetCode
            : "";
        PersonalHeaderFleetCodeText.Foreground = _hasFleet ? mutedBrush : disabledBrush;
        PersonalHeaderFleetRoleText.Text = _hasFleet
            ? GetFleetRole(_localPlayer ?? "", _callsign)
            : "";
        PersonalHeaderFleetRoleText.Visibility = _hasFleet
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalHeaderFleetRoleText.Foreground = _hasFleet
            ? GetFleetRoleBrush(_localPlayer ?? "", _callsign)
            : disabledBrush;

        if (!TryLoadBitmapImage(_fleetLogoPath, out var image))
        {
            PersonalHeaderFleetLogoImage.Source = null;
            if (PersonalHeaderFleetLogoText is not null)
            {
                PersonalHeaderFleetLogoText.Visibility = Visibility.Visible;
            }

            return;
        }

        PersonalHeaderFleetLogoImage.Source = image;
        if (PersonalHeaderFleetLogoText is not null)
        {
            PersonalHeaderFleetLogoText.Visibility = Visibility.Collapsed;
        }
    }

    private void RefreshFleetHeader()
    {
        RefreshBridgeFleetIdentityMark();

        if (FleetHeaderCodeText is null)
        {
            return;
        }

        FleetHeaderCodeText.Text = _hasFleet ? _fleetCode : "暂无";
        FleetCommanderText.Text = FormatCommanderName(_callsign, _localPlayer, _fleetChiefCommander);
        FleetDeputyCommanderText.Text = $"副指挥官 / {_fleetDeputyCommander}";
        RefreshFleetActivityHeaderPresentation();
        RefreshFleetHeaderAnnouncement();
        RefreshFleetHeaderExternalContacts();

        RefreshFleetClockDisplays();

        RefreshFleetInfoPanel();
        RefreshTaskManagementPanel();

        LoadFleetHeaderLogoPreview();
        LoadFleetHeaderBannerPreview();
        RefreshPersonalHeaderFleetCard();
        RefreshFleetManagementPermissions();
    }

    private void RefreshFleetHeaderExternalContacts()
    {
        if (FleetHeaderExternalContactsHost is null ||
            FleetHeaderExternalContactsLabelText is null ||
            FleetHeaderExternalContactsText is null)
        {
            return;
        }

        var useChinese = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var presentation = FleetHeaderExternalContactProjection.Project(
            _hasFleet,
            _fleetExternalContacts,
            useChinese);

        FleetHeaderExternalContactsHost.Visibility = presentation.IsVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetHeaderExternalContactsLabelText.Text = useChinese ? "联系方式" : "Contacts";
        FleetHeaderExternalContactsText.Text = presentation.InlineText;
        FleetHeaderExternalContactsHost.IsEnabled = presentation.Entries.Count > 0;
        FleetHeaderExternalContactsHost.ToolTip = presentation.Entries.Count > 0
            ? useChinese
                ? $"{presentation.AccessibleText}{Environment.NewLine}点击查看并复制"
                : $"{presentation.AccessibleText}{Environment.NewLine}Open and copy"
            : presentation.AccessibleText;
        _fleetHeaderExternalContactsAccessibleText = presentation.AccessibleText;
        System.Windows.Automation.AutomationProperties.SetName(
            FleetHeaderExternalContactsHost,
            useChinese
                ? $"外部联系方式：{presentation.AccessibleText}"
                : $"External contacts: {presentation.AccessibleText}");
    }

    private void RefreshFleetClockDisplays()
    {
        var localNow = DateTimeOffset.Now;
        var fleetNow = GetCurrentFleetTime();
        var fleetOffset = FormatUtcOffset(fleetNow.Offset);

        if (FleetFooterLocalTimeText is not null)
        {
            FleetFooterLocalTimeText.Text = FormatDateTimeForDisplay(localNow, includeSeconds: true);
        }

        if (FleetFooterFleetTimeText is not null)
        {
            FleetFooterFleetTimeText.Text = $"{FormatDateTimeForDisplay(fleetNow, includeSeconds: false)} {fleetOffset}";
        }

        if (FleetFooterGameStatusText is not null)
        {
            var gameStatus = !_isGameProcessRunning
                ? "未启动"
                : IsGameServerRegionCurrent() ? "已进入服务器" : "运行中";
            FleetFooterGameStatusText.Text = gameStatus;
            FleetFooterGameStatusText.Foreground = !_isGameProcessRunning
                ? FindBrush("MutedTextBrush", Brushes.LightSlateGray)
                : FindBrush("StatusSuccessBrush", Brushes.LightGreen);
        }

        if (FleetFooterServerText is not null)
        {
            var server = IsGameServerRegionCurrent()
                ? string.Join(" · ", new[] { _gameServerRegion, _gameServerShard }
                    .Where(value => !string.IsNullOrWhiteSpace(value)))
                : _isGameProcessRunning ? "等待识别" : "等待进入游戏";
            FleetFooterServerText.Text = server;
            FleetFooterServerText.Foreground = IsGameServerRegionCurrent()
                ? FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue)
                : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        }

        if (FleetFooterSyncText is not null)
        {
            var syncStatus = _networkSyncFailureCount > 0
                ? "等待重试"
                : GetNetworkSyncStatusText();
            FleetFooterSyncText.Text = syncStatus;
            FleetFooterSyncText.Foreground = _networkSyncFailureCount > 0
                ? FindBrush("StatusDangerBrush", Brushes.IndianRed)
                : _isNetworkSyncRunning
                    ? FindBrush("StatusWarningBrush", Brushes.Goldenrod)
                    : IsLoggedIn
                        ? FindBrush("StatusSuccessBrush", Brushes.LightGreen)
                        : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        }

        if (FleetFooterLatencyText is not null)
        {
            FleetFooterLatencyText.Text = _lastRelayLatencyMs >= 0
                ? $"{_lastRelayLatencyMs} ms"
                : "--";
            FleetFooterLatencyText.Foreground = _lastRelayLatencyMs switch
            {
                < 0 => FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                <= 120 => FindBrush("StatusSuccessBrush", Brushes.LightGreen),
                <= 300 => FindBrush("StatusWarningBrush", Brushes.Goldenrod),
                _ => FindBrush("StatusDangerBrush", Brushes.IndianRed)
            };
        }

        if (FleetFooterOverlayText is not null)
        {
            FleetFooterOverlayText.Text = IsOverlayRunning
                ? "运行中"
                : "未开启";
            FleetFooterOverlayText.Foreground = IsOverlayRunning
                ? FindBrush("StatusSuccessBrush", Brushes.LightGreen)
                : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        }

    }

    private DateTimeOffset GetCurrentFleetTime()
    {
        var fleetTimeZone = ResolveFleetTimeZone();
        return TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, fleetTimeZone);
    }

    private TimeZoneInfo ResolveFleetTimeZone()
    {
        if (!string.IsNullOrWhiteSpace(_fleetTimeZoneId))
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(_fleetTimeZoneId);
            }
            catch (TimeZoneNotFoundException)
            {
            }
            catch (InvalidTimeZoneException)
            {
            }
        }

        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById("China Standard Time");
        }
        catch (TimeZoneNotFoundException)
        {
            return TimeZoneInfo.Local;
        }
        catch (InvalidTimeZoneException)
        {
            return TimeZoneInfo.Local;
        }
    }

    private static string FormatDateTimeForDisplay(DateTimeOffset value, bool includeSeconds)
    {
        var timePattern = UsesTwentyFourHourClock()
            ? includeSeconds ? "HH:mm:ss" : "HH:mm"
            : includeSeconds ? "h:mm:ss tt" : "h:mm tt";

        return value.ToString($"yyyy-MM-dd {timePattern}", CultureInfo.CurrentCulture);
    }

    private static string FormatCompactDateTimeForDisplay(DateTimeOffset value)
    {
        var timePattern = UsesTwentyFourHourClock()
            ? "HH:mm"
            : "h:mm tt";

        return value.ToString($"MM-dd {timePattern}", CultureInfo.CurrentCulture);
    }

    private static bool UsesTwentyFourHourClock()
    {
        return CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern.Contains('H');
    }

    private static string FormatUtcOffset(TimeSpan offset)
    {
        var sign = offset < TimeSpan.Zero ? "-" : "+";
        var absoluteOffset = offset.Duration();
        return absoluteOffset.Minutes == 0
            ? $"UTC{sign}{absoluteOffset.Hours:00}"
            : $"UTC{sign}{absoluteOffset.Hours:00}:{absoluteOffset.Minutes:00}";
    }

    private static string FormatCommanderName(string? callsign, string? gameName, string fallback = "Unassigned")
    {
        var safeCallsign = NormalizeDisplayIdentityPart(callsign);
        var safeGameName = NormalizeDisplayIdentityPart(gameName);
        var safeFallback = NormalizeDisplayIdentityPart(fallback);
        if (string.IsNullOrWhiteSpace(safeFallback))
        {
            safeFallback = "未知玩家";
        }

        if (string.IsNullOrWhiteSpace(safeGameName))
        {
            return string.IsNullOrWhiteSpace(safeCallsign) ? safeFallback : safeCallsign;
        }

        if (string.IsNullOrWhiteSpace(safeCallsign) ||
            safeCallsign.Equals(safeGameName, StringComparison.OrdinalIgnoreCase))
        {
            return safeGameName;
        }

        return $"{safeCallsign} ({safeGameName})";
    }

    private static string DisplayCallsign(string? callsign, string? gameName, string fallback = "Unknown")
    {
        var safeCallsign = NormalizeDisplayIdentityPart(callsign);
        if (!string.IsNullOrWhiteSpace(safeCallsign))
        {
            return safeCallsign;
        }

        var safeGameName = NormalizeDisplayIdentityPart(gameName);
        if (!string.IsNullOrWhiteSpace(safeGameName))
        {
            return safeGameName;
        }

        return fallback;
    }

    private string GetLocalFleetActorDisplayName()
    {
        return FormatCommanderName(_callsign, _localPlayer, "未知玩家");
    }

    private static string NormalizeDisplayIdentityPart(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var trimmed = value.Trim();
        return IsEmailLikeIdentity(trimmed) ? "" : trimmed;
    }

    private static bool IsEmailLikeIdentity(string value)
    {
        return EmailAddressRegex.Match(value) is { Success: true } match &&
               match.Value.Equals(value.Trim(), StringComparison.OrdinalIgnoreCase);
    }
}
