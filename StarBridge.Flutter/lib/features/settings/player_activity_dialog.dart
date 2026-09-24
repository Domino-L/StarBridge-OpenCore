import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_activity.dart';
import 'notification_settings_models.dart';
import 'player_activity_controller.dart';
import 'notification_editor_frame.dart';
import 'notification_settings_comparison.dart';

Future<void> showPlayerActivityDialog(
  BuildContext context,
  BridgeClientSession session,
) async {
  final controller = PlayerActivityController.bridge(session);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const Key('settings-entry-player-activity'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: StarBridgeSurface(
          role: SurfaceRole.floating,
          child: SizedBox(
            width: 760,
            child: PlayerActivityConnectedPanel(controller: controller),
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

class PlayerActivityConnectedPanel extends StatefulWidget {
  const PlayerActivityConnectedPanel({
    required this.controller,
    this.showClose = true,
    super.key,
  });
  final PlayerActivityController controller;
  final bool showClose;
  @override
  State<PlayerActivityConnectedPanel> createState() =>
      _PlayerActivityConnectedPanelState();
}

class _PlayerActivityConnectedPanelState
    extends State<PlayerActivityConnectedPanel> {
  int form = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.refresh();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (!widget.controller.busy) form++;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, current = c.current;
    final drafts = NotificationDraftScope.of(context);
    final desired = current == null
        ? null
        : drafts?.value('notification-activity', (
                current.settings,
                current.position,
              )) ??
              (current.settings, current.position);
    final editable = c.canEdit && !(drafts?.saving ?? false);
    Future<bool> stage(
      PlayerActivityNotificationSettings settings,
      int position,
    ) async {
      if (drafts == null) return c.save(settings, position);
      if (current == null) return false;
      drafts.edit(
        'notification-activity',
        (current.settings, current.position),
        (
          playerActivityKey(settings) == playerActivityKey(current.settings)
              ? current.settings
              : settings,
          position,
        ),
        (next) async {
          if (c.current?.revision != current.revision) return false;
          return c.save(next.$1, next.$2);
        },
      );
      return true;
    }

    final locale = Localizations.localeOf(context);
    String copy(String cn, String tw, String en) => locale.languageCode == 'en'
        ? en
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? tw
        : cn;
    final tokens = context.tokens;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(tokens.space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.failed) ...[
              Text(
                copy(
                  '暂时无法完成操作，请重新读取设置。',
                  '暫時無法完成操作，請重新讀取設定。',
                  'Unable to complete the request. Reload settings.',
                ),
                style: TextStyle(color: tokens.colors.warning),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: c.busy ? null : c.refresh,
                  child: Text(copy('重新读取', '重新讀取', 'Reload settings')),
                ),
              ),
            ],
            if (current != null) ...[
              PlayerActivityNotificationPanel(
                // Only playerActivity is read by the reused panel; the rest is
                // a presentation envelope, never submitted as notification settings.
                settings: NotificationSettingsValue(
                  localInAppOnly: true,
                  channels: NotificationChannelSettings.newDevice(),
                  sourceRules: const [],
                  previewMode: NotificationPreviewMode.hiddenDetails,
                  playerActivity: desired!.$1,
                  continuousPlay:
                      ContinuousPlayReminderSettings.migratedDefault(),
                ),
                communityAudienceLabel: copy(
                  '社区组织成员',
                  '社區組織成員',
                  'Community members',
                ),
                enabled: editable,
                onSave: (value) => stage(value.playerActivity, desired.$2),
              ),
              Text(
                copy(
                  '目前随好友、房间及组织列表刷新。',
                  '目前隨好友、房間及組織列表更新。',
                  'Activity updates when friends, room or community lists refresh.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: tokens.space.md),
              DropdownButtonFormField<int>(
                key: ValueKey(('activity-position', form, drafts?.epoch)),
                initialValue: desired.$2,
                decoration: InputDecoration(
                  labelText: copy(
                    '玩家动态提醒位置',
                    '玩家動態提醒位置',
                    'Player activity position',
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(copy('左上角', '左上角', 'Top left')),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(copy('左下角', '左下角', 'Bottom left')),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(copy('右上角', '右上角', 'Top right')),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text(copy('右下角', '右下角', 'Bottom right')),
                  ),
                ],
                onChanged: editable
                    ? (v) {
                        if (v != null) stage(desired.$1, v);
                      }
                    : null,
              ),
              SizedBox(height: tokens.space.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: const Key('player-activity-test'),
                  onPressed: editable ? c.test : null,
                  child: Text(
                    copy('测试玩家提醒', '測試玩家提醒', 'Test player notification'),
                  ),
                ),
              ),
              if (c.testResult != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.testResult == 'submitted'
                        ? copy(
                            '测试提醒已发送。',
                            '測試提醒已傳送。',
                            'Test notification sent.',
                          )
                        : c.testResult == 'unavailable'
                        ? copy(
                            '测试提醒暂时未能发送，请稍后再试。设置仍可编辑。',
                            '測試提醒暫時未能傳送，請稍後再試。設定仍可編輯。',
                            'Test notification could not be sent. Try again shortly. Settings remain editable.',
                          )
                        : copy(
                            '当前提醒设置或系统状态阻止了显示。',
                            '目前提醒設定或系統狀態阻止了顯示。',
                            'Current notification settings or system state prevent display.',
                          ),
                  ),
                ),
            ],
            if (widget.showClose)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(copy('关闭', '關閉', 'Close')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
