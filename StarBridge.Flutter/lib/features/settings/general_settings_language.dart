import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class GeneralSettingsLanguageChoices extends StatelessWidget {
  const GeneralSettingsLanguageChoices({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final Locale value;
  final bool enabled;
  final Future<bool> Function(Locale value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final choices = <(Locale, String)>[
      (
        const Locale('zh', 'CN'),
        strings.text('settings.general.language.zhCN'),
      ),
      (
        const Locale('zh', 'TW'),
        strings.text('settings.general.language.zhTW'),
      ),
      (
        const Locale('en', 'US'),
        strings.text('settings.general.language.enUS'),
      ),
    ];
    return Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      children: [
        for (final choice in choices)
          _LanguageChoice(
            key: Key(
              'general-language-${choice.$1.languageCode}-${choice.$1.countryCode}',
            ),
            label: choice.$2,
            selected: _sameLocale(value, choice.$1),
            enabled: enabled,
            onTap: () => onChanged(choice.$1),
          ),
      ],
    );
  }

  static bool _sameLocale(Locale left, Locale right) =>
      left.languageCode == right.languageCode &&
      left.countryCode == right.countryCode;
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final surface = selected
        ? tokens.surfaces.selected
        : tokens.surfaces.raised;
    return Material(
      color: surface.fill,
      borderRadius: tokens.shape.small,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: tokens.shape.small,
        child: Container(
          constraints: BoxConstraints(
            minWidth: tokens.density.controlHeight * 3,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: tokens.shape.small,
            border: Border.all(
              color: selected ? tokens.colors.accent : surface.border,
              width: selected ? tokens.stroke.strong : tokens.stroke.regular,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                StarBridgeIcon(
                  StarBridgeIconSemantic.connected,
                  size: tokens.icons.small,
                  color: tokens.colors.accent,
                ),
                SizedBox(width: tokens.space.xs),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: enabled
                      ? tokens.colors.textPrimary
                      : tokens.colors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
