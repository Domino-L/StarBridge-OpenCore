import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/style_registry.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class GeneralSettingsAppearanceChoices extends StatelessWidget {
  const GeneralSettingsAppearanceChoices({
    required this.value,
    required this.styleId,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final AppearanceMode value;
  final String styleId;
  final bool enabled;
  final Future<bool> Function(AppearanceMode value) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final choices = [
      for (final mode in AppearanceMode.values)
        _AppearanceChoice(
          mode: mode,
          styleId: styleId,
          selected: value == mode,
          enabled: enabled,
          onTap: () => onChanged(mode),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              choices.first,
              SizedBox(height: tokens.space.sm),
              choices.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: choices.first),
            SizedBox(width: tokens.space.md),
            Expanded(child: choices.last),
          ],
        );
      },
    );
  }
}

class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({
    required this.mode,
    required this.styleId,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppearanceMode mode;
  final String styleId;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final preview = StyleRegistry().resolve(styleId, mode).tokens;
    final dark = mode == AppearanceMode.dark;
    return Material(
      color: selected
          ? tokens.surfaces.selected.fill
          : tokens.surfaces.raised.fill,
      borderRadius: tokens.shape.medium,
      child: InkWell(
        key: Key('general-appearance-${mode.name}'),
        onTap: enabled ? onTap : null,
        borderRadius: tokens.shape.medium,
        child: Container(
          padding: EdgeInsets.all(tokens.space.sm),
          decoration: BoxDecoration(
            borderRadius: tokens.shape.medium,
            border: Border.all(
              color: selected
                  ? tokens.colors.accent
                  : tokens.surfaces.raised.border,
              width: selected ? tokens.stroke.strong : tokens.stroke.regular,
            ),
          ),
          child: Row(
            children: [
              _MiniAppearancePreview(tokens: preview),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text(
                        dark
                            ? 'settings.general.appearance.dark'
                            : 'settings.general.appearance.light',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text(
                        dark
                            ? 'settings.general.appearance.darkDescription'
                            : 'settings.general.appearance.lightDescription',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                StarBridgeIcon(
                  StarBridgeIconSemantic.connected,
                  size: tokens.icons.medium,
                  color: tokens.colors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAppearancePreview extends StatelessWidget {
  const _MiniAppearancePreview({required this.tokens});

  final StarBridgeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final preview = tokens;
    return Container(
      width: 76,
      height: 54,
      padding: EdgeInsets.all(preview.space.xs),
      decoration: BoxDecoration(
        color: preview.surfaces.ground.fill,
        borderRadius: preview.shape.small,
        border: Border.all(
          color: preview.surfaces.ground.border,
          width: preview.stroke.regular,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 14,
            decoration: BoxDecoration(
              color: preview.surfaces.navigation.fill,
              borderRadius: preview.shape.small,
            ),
          ),
          SizedBox(width: preview.space.xxs),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: preview.surfaces.chrome.fill,
                    borderRadius: preview.shape.small,
                  ),
                ),
                SizedBox(height: preview.space.xxs),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: preview.surfaces.panel.fill,
                      borderRadius: preview.shape.small,
                    ),
                  ),
                ),
                SizedBox(height: preview.space.xxs),
                Container(height: 4, color: preview.colors.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
