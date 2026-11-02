import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/icons/standard_icon.dart';

/// Native help/release header geometry, with the approved suite owning the
/// single activation target and body reveal. No read/write port is involved.
class HelpSupportExpansionTile extends StatelessWidget {
  const HelpSupportExpansionTile({
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.trailing,
    this.tilePadding,
    this.childrenPadding = EdgeInsets.zero,
    this.childrenCrossAxisAlignment = CrossAxisAlignment.center,
    this.initiallyExpanded = false,
    super.key,
  });

  final Text title;
  final List<Widget> children;
  final Text? subtitle;
  final Widget? leading, trailing;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry childrenPadding;
  final CrossAxisAlignment childrenCrossAxisAlignment;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    // All callers use Text titles/subtitles, as their original ExpansionTile did.
    final label = title.data ?? title.textSpan!.toPlainText();
    final value = subtitle?.data ?? subtitle?.textSpan?.toPlainText();
    // Native ExpansionTile's default transparent top/bottom borders each
    // occupy one logical pixel. Keep this layout inset, not a second frame.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: StarBridgeExpansionTile(
        title: label,
        subtitle: value,
        initiallyExpanded: initiallyExpanded,
        useNativePageStorage: true,
        headerMinHeight: 0,
        childrenPadding: childrenPadding,
        childrenCrossAxisAlignment: childrenCrossAxisAlignment,
        headerBuilder: (context, visual, open) {
          final theme = Theme.of(context);
          final data = InteractionScope.of(context);
          final expansion = ExpansionTileTheme.of(context);
          final progress = SuiteMotion.curve.transform(open);
          final textColor = Color.lerp(
            expansion.collapsedTextColor ??
                (theme.useMaterial3
                    ? theme.colorScheme.onSurface
                    : theme.textTheme.titleMedium?.color),
            expansion.textColor ??
                (theme.useMaterial3
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.primary),
            progress,
          );
          final iconColor = Color.lerp(
            expansion.collapsedIconColor ??
                (theme.useMaterial3
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.unselectedWidgetColor),
            expansion.iconColor ?? theme.colorScheme.primary,
            progress,
          );
          // ListTile is intentionally non-interactive: its parent SuitePressable
          // owns pointer, keyboard and reader activation, including disabled state.
          return ListTileTheme.merge(
            textColor: textColor,
            iconColor: iconColor,
            child: ListTile(
              // This is a pure presentation header: reset native implicit
              // TextStyle tweens at an immediate endpoint or live theme change.
              // Focus/gesture/state ownership remains outside this subtree.
              key: ValueKey((
                data.animates ? null : theme,
                open <= 0
                    ? 0
                    : open >= 1
                    ? 1
                    : 2,
              )),
              mouseCursor: MouseCursor.defer,
              contentPadding: tilePadding ?? expansion.tilePadding,
              leading: leading,
              title: title,
              subtitle: subtitle,
              trailing:
                  trailing ??
                  Transform.rotate(
                    angle: math.pi * progress,
                    child: const StandardIcon(StandardIconSemantic.expandMore),
                  ),
            ),
          );
        },
        children: children,
      ),
    );
  }
}
