import 'menu_overlay_locale.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_slider.dart';
import 'menu_bridge_style.dart';

/// Preserve the image toolbar's native icon/label geometry and selected tint.
/// The action and its admission/pending/result owner remain with the caller.
class MenuImageAction extends StatelessWidget {
  const MenuImageAction({
    required this.title,
    required this.icon,
    required this.action,
    this.selected = false,
    super.key,
  });
  final String title;
  final Widget icon;
  final VoidCallback? action;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = OutlinedButtonTheme.of(context).style ?? const ButtonStyle();
    final style =
        (selected
                ? OutlinedButton.styleFrom(foregroundColor: BridgeInk.blue)
                : const ButtonStyle())
            .merge(native);
    final adjustment =
        (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final minimum = style.minimumSize?.resolve({}) ?? const Size(64, 40);
    final target =
        (style.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final labelStyle =
        style.textStyle?.resolve({}) ?? theme.textTheme.labelLarge;
    return StarBridgeActionButton(
      nativeStyle: style,
      minHeight: math.max(
        minimum.height + adjustment.dy,
        target + adjustment.dy,
      ),
      padding: style.padding?.resolve({}),
      semanticLabel: title,
      onActivate: action == null ? null : (_) => action!(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - (scale - 1) * 4,
        children: [
          icon,
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                // Native Material's standalone label style does not inherit the
                // page body tracking; suite defaults merge and otherwise add it.
                letterSpacing: labelStyle?.letterSpacing ?? 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A two-pixel functional track, not a blocking veil or fabricated percentage.
/// Only an admitted explicit pointer operation animates; restored/automatic
/// work and keyboard/reader input have a static status marker.
class MenuImageBusy extends StatelessWidget {
  const MenuImageBusy({required this.source, super.key});
  final InteractionSource source;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final animate =
            !data.reduceMotion && source == InteractionSource.pointer;
        return InteractionScope(
          data: data.copyWith(reduceMotion: !animate),
          child: Semantics(
            label: menuText(context, 'menu.overlay.image.busy'),
            liveRegion: true,
            child: ExcludeSemantics(
              child: SuiteBusyFrame(
                busy: true,
                radius: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: animate
                      ? (data.suite == InteractionSuite.standard ||
                                data.suite == InteractionSuite.glow
                            ? null
                            : 0)
                      : .5,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Same native 48-DIP row/hit height; only the approved slider face varies.
class MenuImageOpacity extends StatelessWidget {
  const MenuImageOpacity({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final double value;
  final String label;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('$label ${(value * 100).round()}%'),
      Expanded(
        child: SizedBox(
          height: 48,
          child: StarBridgeSlider(
            value: value,
            min: .15,
            semanticLabel: label,
            valueLabel: (value) => '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}
