import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../shell_layout_mode.dart';
import 'attention_badge.dart';
import 'navigation_prefetch.dart';

class ShellNavigationItem extends StatelessWidget {
  const ShellNavigationItem({
    required this.descriptor,
    required this.mode,
    required this.selected,
    required this.onPressed,
    required this.onKeyboardPressed,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final FeatureDescriptor descriptor;
  final ShellLayoutMode mode;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onKeyboardPressed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final label = strings.text(descriptor.labelKey);
    final icon = StarBridgeIcon(
      descriptor.icon,
      size: tokens.icons.medium,
      color: selected ? tokens.colors.accent : tokens.colors.textSecondary,
    );
    final count = descriptor.attentionCount;
    Widget content(int value) => SizedBox(
      width: double.infinity,
      height: tokens.density.navigationItemHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: mode == ShellLayoutMode.iconOnly
              ? tokens.space.xxs
              : tokens.space.sm,
        ),
        child: mode == ShellLayoutMode.iconOnly
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: icon),
                  if (value > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IgnorePointer(child: AttentionCount(count: value)),
                    ),
                ],
              )
            : Row(
                children: [
                  icon,
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? tokens.colors.accent
                            : tokens.colors.textSecondary,
                        fontWeight: selected
                            ? tokens.typography.emphasisWeight
                            : tokens.typography.bodyWeight,
                      ),
                    ),
                  ),
                  if (value > 0) ...[
                    SizedBox(width: tokens.space.xs),
                    AttentionCount(count: value),
                  ],
                ],
              ),
      ),
    );
    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? tokens.surfaces.selected.fill
            : tokens.surfaces.navigation.fill,
        borderRadius: tokens.shape.small,
        child: InkWell(
          onTap: onPressed,
          borderRadius: tokens.shape.small,
          focusColor: tokens.colors.focusRing.withValues(alpha: 0.16),
          child: Stack(
            children: [
              if (count == null)
                content(0)
              else
                ValueListenableBuilder<int>(
                  valueListenable: count,
                  key: ValueKey('activity-${descriptor.id}'),
                  builder: (context, value, child) => content(value),
                ),
              if (selected)
                PositionedDirectional(
                  start: 0,
                  top: tokens.space.sm,
                  bottom: tokens.space.sm,
                  child: Container(
                    width: tokens.stroke.strong + tokens.stroke.regular,
                    decoration: BoxDecoration(
                      color: tokens.colors.accent,
                      borderRadius: tokens.shape.pill,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final keyboardReady = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): onKeyboardPressed,
        const SingleActivator(LogicalKeyboardKey.space): onKeyboardPressed,
        const SingleActivator(LogicalKeyboardKey.arrowUp): onPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowDown): onNext,
      },
      child: item,
    );
    if (mode != ShellLayoutMode.iconOnly) {
      return NavigationPrefetch(
        prepare: descriptor.prefetch,
        child: keyboardReady,
      );
    }
    return NavigationPrefetch(
      prepare: descriptor.prefetch,
      child: Tooltip(message: label, child: keyboardReady),
    );
  }
}
