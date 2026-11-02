import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../design_system/interaction/starbridge_navigation_target.dart';
import '../../../design_system/interaction/starbridge_tooltip.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../shell_layout_mode.dart';
import 'attention_badge.dart';
import 'attention_detail_hover.dart';
import 'navigation_prefetch.dart';
import '../../../design_system/components/coming_soon.dart';

class ShellNavigationItem extends StatelessWidget {
  const ShellNavigationItem({
    required this.descriptor,
    required this.mode,
    required this.selected,
    required this.onPressed,
    required this.onKeyboardPressed,
    required this.onPrevious,
    required this.onNext,
    this.focusNode,
    this.sharedSelection = false,
    super.key,
  });

  final FeatureDescriptor descriptor;
  final ShellLayoutMode mode;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onKeyboardPressed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final FocusNode? focusNode;
  final bool sharedSelection;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final label = strings.text(descriptor.labelKey);
    final comingSoon =
        descriptor.availability == FeatureAvailability.comingSoon;
    final accessibleLabel = comingSoon
        ? '$label，${strings.text('deferredFeature.title')}'
        : label;
    final icon = StarBridgeIcon(
      descriptor.icon,
      size: tokens.icons.medium,
      color: selected ? tokens.colors.accent : tokens.colors.textSecondary,
    );
    final count = descriptor.attentionCount;
    final detail = descriptor.attentionDetail;
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
                      overflow: TextOverflow.fade,
                      softWrap: false,
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
                  if (comingSoon) const ComingSoonBadge(),
                ],
              ),
      ),
    );
    Widget item(int value) => StarBridgeNavigationTarget(
      focusNode: focusNode,
      sharedSelection: sharedSelection,
      selected: selected,
      label: value > 0
          ? '$accessibleLabel, ${detail?.describe(context) ?? value}'
          : accessibleLabel,
      onPressed: onPressed,
      onKeyboardPressed: onKeyboardPressed,
      onPrevious: onPrevious,
      onNext: onNext,
      selectionStripe: PositionedDirectional(
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
      child: content(value),
    );
    // Option C: the count's breakdown beside the item. Collapsed, the card
    // also carries the label, so it replaces the tooltip there.
    Widget hover(int value) => detail == null
        ? item(value)
        : AttentionDetailHover(
            enabled: value > 0 || mode == ShellLayoutMode.iconOnly,
            detail: (context) => ListenableBuilder(
              listenable: detail.listenable,
              builder: (context, _) => detail.build(context, onPressed),
            ),
            child: item(value),
          );
    final keyboardReady = count == null
        ? hover(0)
        : ValueListenableBuilder<int>(
            valueListenable: count,
            key: ValueKey('activity-${descriptor.id}'),
            builder: (context, value, _) => hover(value),
          );
    if (mode != ShellLayoutMode.iconOnly) {
      return NavigationPrefetch(
        prepare: descriptor.prefetch,
        child: keyboardReady,
      );
    }
    if (detail != null) {
      return NavigationPrefetch(
        prepare: descriptor.prefetch,
        child: keyboardReady,
      );
    }
    return NavigationPrefetch(
      prepare: descriptor.prefetch,
      child: StarBridgeTooltip(
        message: accessibleLabel,
        excludeFromSemantics: true,
        child: keyboardReady,
      ),
    );
  }
}
