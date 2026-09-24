import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
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
        SizedBox(width: context.tokens.space.xs),
        AccountMenu(
          destinations: accountMenuDestinations,
          projection: projection,
          expanded: mode == ShellLayoutMode.wide,
          onSelect: onSelect,
          onLogin: onAccountLogin,
          onLogout: onAccountLogout,
          onIssueAction: onAccountIssueAction,
        ),
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
    return Container(
      key: const Key('top-action-cluster'),
      height: tokens.density.controlHeight,
      decoration: BoxDecoration(
        color: tokens.surfaces.raised.fill,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.regular,
        ),
        boxShadow: tokens.surfaces.raised.shadows,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < descriptors.length; index++) ...[
            if (index > 0)
              Container(
                width: tokens.stroke.hairline,
                height: tokens.icons.medium,
                color: tokens.surfaces.chrome.border,
              ),
            _action(descriptors[index], index),
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

  Widget _action(FeatureDescriptor descriptor, int index) {
    Widget button(int value) => _TopIconButton(
      count: value,
      descriptor: descriptor,
      position: index,
      total: descriptors.length,
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

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.descriptor,
    required this.position,
    required this.total,
    required this.onPressed,
    required this.count,
  });

  final FeatureDescriptor descriptor;
  final int position;
  final int total;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppStrings.of(context).text(descriptor.labelKey);
    return NavigationPrefetch(
      prepare: descriptor.prefetch,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.square(
              tokens.density.controlHeight - tokens.stroke.strong * 2,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadiusDirectional.only(
                topStart: position == 0
                    ? Radius.circular(tokens.shape.radiusSmall)
                    : Radius.zero,
                bottomStart: position == 0
                    ? Radius.circular(tokens.shape.radiusSmall)
                    : Radius.zero,
                topEnd: position == total - 1
                    ? Radius.circular(tokens.shape.radiusSmall)
                    : Radius.zero,
                bottomEnd: position == total - 1
                    ? Radius.circular(tokens.shape.radiusSmall)
                    : Radius.zero,
              ),
            ),
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
