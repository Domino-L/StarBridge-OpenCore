import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'general_settings_own_health_notes.dart';

/// "读取自己的血量"：单独的开关，默认关。开关旁只留一句话和"查看说明"；
/// 完整说明和风险说明放进打开前的确认框（用户 11-14）。
class GeneralSettingsOwnHealth extends StatelessWidget {
  const GeneralSettingsOwnHealth({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('settings.general.ownHealth.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                strings.text(
                  value
                      ? 'settings.general.ownHealth.summary.on'
                      : 'settings.general.ownHealth.summary.off',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: tokens.space.xxs),
              StarBridgeActionButton(
                controlKey: const Key('general-read-own-health-notes'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => showOwnHealthNotes(context, consent: false),
                child: Text(strings.text('settings.general.ownHealth.viewNotes')),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space.md),
        StarBridgeSwitch(
          controlKey: const Key('general-read-own-health'),
          label: strings.text('settings.general.ownHealth.title'),
          value: value,
          onChanged: enabled ? (next) => _change(context, next) : null,
        ),
      ],
    );
  }

  // 打开前先弹确认框，点"同意并开启"才真正打开；取消、Esc、点框外都保持关闭。关掉不弹。
  Future<void> _change(BuildContext context, bool next) async {
    if (!next) {
      await onChanged(false);
      return;
    }
    final agreed = await showOwnHealthNotes(context, consent: true);
    if (agreed && context.mounted) await onChanged(true);
  }
}

/// "游戏在后台时也读取"：读血的子开关，默认关（用户 11-13"默认关"）。读血关着时不能改。
class GeneralSettingsOwnHealthBackground extends StatelessWidget {
  const GeneralSettingsOwnHealthBackground({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('settings.general.ownHealth.background.title'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                strings.text('settings.general.ownHealth.background.what'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space.md),
        StarBridgeSwitch(
          controlKey: const Key('general-read-own-health-background'),
          label: strings.text('settings.general.ownHealth.background.title'),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
