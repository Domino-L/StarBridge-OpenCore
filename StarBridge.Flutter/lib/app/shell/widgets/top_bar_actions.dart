import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_projection.dart';
import '../shell_layout_mode.dart';
import 'account_menu.dart';
import 'attention_badge.dart';
import 'navigation_prefetch.dart';

class TopBarActions extends StatelessWidget {
  const TopBarActions({
    required this.descriptors,
    required this.accountMenuDestinations,
    required this.projection,
    required this.mode,
    required this.onSelect,
    required this.onAccountLogin,
    required this.onAccountLogout,
    required this.onAccountIssueAction,
    this.sharingIndicator,
    super.key,
  });

  final List<FeatureDescriptor> descriptors;
  final List<FeatureDescriptor> accountMenuDestinations;
  final ShellChromeProjection projection;
  final ShellLayoutMode mode;
  final ValueChanged<FeatureDescriptor> onSelect;
  final VoidCallback onAccountLogin;
  final VoidCallback onAccountLogout;
  final VoidCallback onAccountIssueAction;
  final Widget? sharingIndicator;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TopActionCluster(
          descriptors: descriptors,
          projection: projection,
          onSelect: onSelect,
        ),
        const TopBarDivider(),
        AccountMenu(
          destinations: accountMenuDestinations,
          projection: projection,
          expanded: mode == ShellLayoutMode.wide,
          onSelect: onSelect,
          onLogin: onAccountLogin,
          onLogout: onAccountLogout,
          onIssueAction: onAccountIssueAction,
        ),
        ?sharingIndicator,
      ],
    );
  }
}

class _TopActionCluster extends StatelessWidget {
  const _TopActionCluster({
    required this.descriptors,
    required this.projection,
    required this.onSelect,
  });

  final List<FeatureDescriptor> descriptors;
  final ShellChromeProjection projection;
  final ValueChanged<FeatureDescriptor> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Plain icons (QualityPass ⑦ A): no boxed group and no dividers between
    // them; hover/focus still light each button. Hit area is unchanged.
    return SizedBox(
      key: const Key('top-action-cluster'),
      height: tokens.density.controlHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < descriptors.length; index++) ...[
            if (index > 0) SizedBox(width: tokens.space.xxs),
            _action(descriptors[index]),
          ],
        ],
      ),
    );
  }

  int _attentionCount(FeatureDescriptor descriptor) {
    return switch (descriptor.icon) {
      StarBridgeIconSemantic.friends => projection.friendAttentionCount,
      StarBridgeIconSemantic.notifications => projection.notificationCount,
      _ => 0,
    };
  }

  Widget _action(FeatureDescriptor descriptor) {
    Widget button(int value) => _TopIconButton(
      count: value,
      descriptor: descriptor,
      onPressed: () => onSelect(descriptor),
    );
    final count = descriptor.attentionCount;
    if (count == null) {
      return button(_attentionCount(descriptor));
    }
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, value, child) => button(value),
    );
  }
}

/// Thin vertical rule between the title bar's groups (selector, icons,
/// account). Low contrast; it separates without boxing anything.
class TopBarDivider extends StatelessWidget {
  const TopBarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.xs),
      child: SizedBox(
        width: tokens.stroke.hairline,
        height: tokens.icons.medium,
        child: ColoredBox(color: tokens.surfaces.chrome.border),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.descriptor,
    required this.onPressed,
    required this.count,
  });

  final FeatureDescriptor descriptor;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppStrings.of(context).text(descriptor.labelKey);
    return NavigationPrefetch(
      prepare: descriptor.prefetch,
      child: StarBridgeNativeIconAction(
        controlKey: ValueKey('top-action-${descriptor.id}'),
        onActivate: (_) => onPressed(),
        label: label,
        semanticLabel: count > 0 ? '$label\n$count' : label,
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.square(
              tokens.density.controlHeight - tokens.stroke.strong * 2,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: tokens.shape.small),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(
                color: tokens.colors.focusRing,
                width: tokens.stroke.focusWidth,
              );
            }
            return BorderSide.none;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return tokens.surfaces.selected.fill;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? tokens.colors.accent
                : tokens.colors.textSecondary;
          }),
          overlayColor: WidgetStatePropertyAll(
            tokens.colors.accent.withValues(alpha: 0.10),
          ),
        ),
        icon: AttentionBadge(
          key: ValueKey('activity-${descriptor.id}'),
          count: count,
          child: StarBridgeIcon(descriptor.icon, size: tokens.icons.medium),
        ),
      ),
    );
  }
}
