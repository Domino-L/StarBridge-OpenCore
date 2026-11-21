import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// "读取自己的血量"的完整说明（用户 11-14："打开开关弹确认弹窗与风险说明"，两个问题都选甲）。
/// [consent] 为 true：打开开关前弹，按钮是"取消 / 同意并开启"，只有点"同意并开启"才返回 true；
/// 每次打开都弹，不记"同意过"，关掉开关不弹。
/// [consent] 为 false："查看说明"，只有"关闭"按钮，不改开关。
Future<bool> showOwnHealthNotes(
  BuildContext context, {
  required bool consent,
}) async {
  final agreed = await showStarBridgeDialog<bool>(
    context,
    builder: (dialog) => OwnHealthNotesDialog(consent: consent),
  );
  return consent && agreed == true;
}

class OwnHealthNotesDialog extends StatelessWidget {
  const OwnHealthNotesDialog({super.key, required this.consent});

  final bool consent;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodySmall?.copyWith(color: tokens.colors.textSecondary);
    Widget section(String key) => Padding(
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.text('settings.general.ownHealth.$key.title'), style: textTheme.titleSmall),
          SizedBox(height: tokens.space.xxs),
          Text(strings.text('settings.general.ownHealth.$key'), style: body),
        ],
      ),
    );
    return AlertDialog(
      key: Key(consent ? 'own-health-consent' : 'own-health-notes'),
      title: Text(
        strings.text(
          consent ? 'settings.general.ownHealth.dialog.title' : 'settings.general.ownHealth.title',
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final key in const ['what', 'how', 'never', 'note']) section(key),
              SizedBox(height: tokens.space.md),
              DecoratedBox(
                key: const Key('own-health-risk'),
                decoration: BoxDecoration(
                  color: tokens.colors.warningSoft,
                  // 只有一边有边框时不能再加圆角（Flutter 会报错），所以这里是直角。
                  border: BorderDirectional(
                    start: BorderSide(color: tokens.colors.warning, width: 3),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space.sm,
                    vertical: tokens.space.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.text('settings.general.ownHealth.risk.title'),
                        style: textTheme.titleSmall?.copyWith(color: tokens.colors.warning),
                      ),
                      SizedBox(height: tokens.space.xxs),
                      Text(
                        strings.text('settings.general.ownHealth.risk'),
                        style: textTheme.bodySmall?.copyWith(color: tokens.colors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              if (consent) ...[
                SizedBox(height: tokens.space.md),
                Text(
                  strings.text('settings.general.ownHealth.dialog.agree'),
                  style: textTheme.bodySmall?.copyWith(color: tokens.colors.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (consent) ...[
          StarBridgeActionButton(
            controlKey: const Key('own-health-consent-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<bool>(context, source: source, result: false),
            child: Text(strings.text('settings.general.ownHealth.dialog.cancel')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('own-health-consent-agree'),
            kind: StarBridgeActionKind.primary,
            onActivate: (source) =>
                dismissStarBridgeDialog<bool>(context, source: source, result: true),
            child: Text(strings.text('settings.general.ownHealth.dialog.confirm')),
          ),
        ] else
          StarBridgeActionButton(
            controlKey: const Key('own-health-notes-close'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<bool>(context, source: source, result: false),
            child: Text(strings.text('settings.general.ownHealth.dialog.close')),
          ),
      ],
    );
  }
}
