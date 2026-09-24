import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../localization/app_strings.dart';
import '../shell/chrome/presence_color.dart';
import 'manual_presence.dart';

String manualPresenceText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final shared = AppStrings.resolve(locale).text(key);
  if (shared != key) return shared;
  final labels = <String, (String, String, String)>{
    'presence.title': ('对外状态', '對外狀態', 'Visibility'),
    'presence.selectOnline': ('在线', '在線', 'Online'),
    'presence.invisible': ('隐身', '隱身', 'Invisible'),
    'presence.inGame': ('游戏中', '遊戲中', 'In game'),
    'presence.away': ('暂离', '暫離', 'Away'),
    'presence.unknown': ('状态待确认', '狀態待確認', 'Status unconfirmed'),
    'presence.working': ('正在切换…', '正在切換…', 'Updating…'),
    'presence.failed': (
      '状态未更新，请重试。',
      '狀態未更新，請重試。',
      'Status not updated. Try again.',
    ),
    'presence.unavailable': (
      '暂时无法切换状态',
      '暫時無法切換狀態',
      'Status changes unavailable',
    ),
  };
  final value = labels[key]!;
  if (locale.languageCode == 'en') return value.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return value.$2;
  }
  return value.$1;
}

class ManualPresenceBadge extends StatelessWidget {
  const ManualPresenceBadge({required this.controller, super.key});
  final ManualPresenceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final key = controller.snapshot.selfKey;
      final color = key == 'presence.invisible'
          ? context.tokens.colors.offline
          : presenceColor(context.tokens.colors, key);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              manualPresenceText(context, key),
              key: const Key('manual-presence-self'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      );
    },
  );
}

/// Intended for the existing avatar menu and the tray's status submenu.
class ManualPresenceChoices extends StatelessWidget {
  const ManualPresenceChoices({required this.controller, super.key});
  final ManualPresenceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Game activity is detected, not a manually selectable status. Keep
        // the historical enum/wire value readable without rewriting preferences.
        for (final mode in [
          PresenceVisibility.online,
          PresenceVisibility.invisible,
        ])
          MenuItemButton(
            key: Key('manual-presence-${mode.name}'),
            closeOnActivate: false,
            leadingIcon: DecoratedBox(
              key: ValueKey('manual-presence-dot-${mode.name}'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mode == PresenceVisibility.online
                    ? context.tokens.colors.info
                    : context.tokens.colors.offline,
              ),
              child: const SizedBox.square(dimension: 8),
            ),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                final color = mode == PresenceVisibility.online
                    ? context.tokens.colors.info
                    : context.tokens.colors.offline;
                return states.contains(WidgetState.disabled)
                    ? color.withValues(alpha: .45)
                    : color;
              }),
            ),
            onPressed: controller.canChange
                ? () => controller.select(mode)
                : null,
            trailingIcon: controller.snapshot.confirmedMode == mode
                ? const StarBridgeIcon(
                    StarBridgeIconSemantic.connected,
                    size: 16,
                  )
                : const SizedBox(width: 16),
            child: Text(
              manualPresenceText(
                context,
                mode == PresenceVisibility.online
                    ? 'presence.selectOnline'
                    : 'presence.invisible',
              ),
            ),
          ),
        if (controller.busy || controller.failed || !controller.canChange)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              manualPresenceText(
                context,
                controller.busy
                    ? 'presence.working'
                    : controller.failed
                    ? 'presence.failed'
                    : 'presence.unavailable',
              ),
              key: const Key('manual-presence-feedback'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: controller.failed
                    ? context.tokens.colors.warning
                    : context.tokens.colors.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );
}
