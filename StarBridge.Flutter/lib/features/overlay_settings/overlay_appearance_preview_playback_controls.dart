import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'overlay_appearance_live_session.dart';
import 'overlay_workspace_models.dart';

/// Only projects playback affordances. The live session retains all authority.
class OverlayAppearancePreviewPlaybackControls extends StatelessWidget {
  const OverlayAppearancePreviewPlaybackControls({
    required this.settings,
    required this.editable,
    required this.reduced,
    required this.onPlay,
    required this.onReducedMotion,
    this.status,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final bool editable, reduced;
  final String? status;
  final Future<void> Function(OverlayAppearancePreviewPlayback) onPlay;
  final ValueChanged<bool> onReducedMotion;

  @override
  Widget build(BuildContext context) {
    String copy(String cn, String tw, String en) {
      final locale = Localizations.localeOf(context);
      return locale.languageCode != 'zh'
          ? en
          : locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
          ? tw
          : cn;
    }

    final events =
        settings['showEventNotifications'] == true &&
        settings['eventNotificationTypes'] != 0;
    Widget action(
      OverlayAppearancePreviewPlayback action,
      String cn,
      String tw,
      String en,
      bool allowed,
    ) => StarBridgeActionButton(
      key: Key('appearance-preview-play-${action.name}'),
      onActivate: editable && allowed ? (_) => onPlay(action) : null,
      child: Text(copy(cn, tw, en)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy('浏览动效', '瀏覽動效', 'Browse effects'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              action(
                OverlayAppearancePreviewPlayback.noticeShow,
                '公告展开',
                '公告展開',
                'Show notice',
                settings['showNotice'] == true,
              ),
              action(
                OverlayAppearancePreviewPlayback.noticeHide,
                '公告收起',
                '公告收起',
                'Hide notice',
                true,
              ),
              action(
                OverlayAppearancePreviewPlayback.eventAdd,
                '新事件',
                '新事件',
                'New event',
                events,
              ),
              action(
                OverlayAppearancePreviewPlayback.eventHide,
                '事件收起',
                '事件收起',
                'Hide events',
                true,
              ),
              action(
                OverlayAppearancePreviewPlayback.eventSequence,
                '事件 1→2→1→2→1',
                '事件 1→2→1→2→1',
                'Events 1→2→1→2→1',
                events &&
                    !reduced &&
                    (settings['eventNotificationMaxVisibleCount'] as num) >= 2,
              ),
              action(
                OverlayAppearancePreviewPlayback.barrage,
                '示例弹幕',
                '示例彈幕',
                'Example barrage',
                settings['showChat'] == true &&
                    settings['chatDisplayMode'] == 'FullScreenBarrage',
              ),
              action(
                OverlayAppearancePreviewPlayback.stop,
                '收起公告、事件与转场',
                '收起公告、事件與轉場',
                'Clear notice, events and transition',
                true,
              ),
              action(
                OverlayAppearancePreviewPlayback.transition,
                '播放启动转场',
                '播放啟動轉場',
                'Play startup transition',
                !reduced,
              ),
            ],
          ),
          StarBridgeCheckboxTile(
            key: const Key('appearance-preview-reduced-motion'),
            label: copy(
              '减少动态（仅预览）',
              '減少動態（僅預覽）',
              'Reduce motion (preview only)',
            ),
            value: reduced,
            onChanged:
                editable &&
                    !resolveStarBridgeInteraction(context).reduceMotion &&
                    settings['animationFrameRate'] != 'Off'
                ? onReducedMotion
                : null,
          ),
          Text(
            status ??
                copy(
                  '只发送示例内容，不操控宠物。关闭的模块不播放；双事件示例需要容量至少为 2。',
                  '僅傳送示例內容，不操控寵物。關閉的模組不播放；雙事件示例需要容量至少為 2。',
                  'Example content only; no pet controls. Hidden modules do not play. The event sequence needs capacity of at least 2.',
                ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
