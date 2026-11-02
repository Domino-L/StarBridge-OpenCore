import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../settings/help_support_expansion_tile.dart';

/// Native widgets below are presentation templates, never mounted as a second
/// input target. Their original callbacks, guards, children and public sizing
/// defaults remain authoritative; the approved adapters own input and paint.
class ExecHangarMotionButton extends StatelessWidget {
  const ExecHangarMotionButton(this.button, {super.key});
  final ButtonStyleButton button;

  @override
  Widget build(BuildContext context) {
    final (kind, defaults, themed) = switch (button) {
      FilledButton b => (
        StarBridgeActionKind.primary,
        b.defaultStyleOf(context),
        FilledButtonTheme.of(context).style,
      ),
      OutlinedButton b => (
        StarBridgeActionKind.secondary,
        b.defaultStyleOf(context),
        OutlinedButtonTheme.of(context).style,
      ),
      TextButton b => (
        StarBridgeActionKind.quiet,
        b.defaultStyleOf(context),
        TextButtonTheme.of(context).style,
      ),
      _ => throw ArgumentError('Unsupported executive hangar button'),
    };
    final style = (button.style ?? const ButtonStyle())
        .merge(themed)
        .merge(defaults);
    final states = <WidgetState>{
      if (button.onPressed == null) WidgetState.disabled,
    };
    final theme = Theme.of(context);
    final density =
        (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (style.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final foreground = style.foregroundColor?.resolve(states);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: math.max(
          style.minimumSize!.resolve(states)!.width + density.dx,
          target + density.dx,
        ),
      ),
      child: StarBridgeActionButton(
        controlKey: button.key,
        kind: kind,
        nativeStyle: style,
        minHeight: math.max(
          style.minimumSize!.resolve(states)!.height + density.dy,
          target + density.dy,
        ),
        onActivate: button.onPressed == null
            ? null
            : (_) => button.onPressed!(),
        child: IconTheme.merge(
          data: IconThemeData(
            size: style.iconSize?.resolve(states),
            color: style.iconColor?.resolve(states) ?? foreground,
          ),
          child: DefaultTextStyle.merge(
            style: style.textStyle
                ?.resolve(states)
                ?.copyWith(inherit: false, color: foreground),
            child: button.child!,
          ),
        ),
      ),
    );
  }
}

Widget execHangarCheckbox(CheckboxListTile tile) => StarBridgeCheckboxTile(
  key: tile.key,
  value: tile.value!,
  label: (tile.title as Text).data!,
  subtitle: tile.subtitle is Text ? (tile.subtitle as Text).data : null,
  onChanged: tile.onChanged == null ? null : (value) => tile.onChanged!(value),
  rowBuilder: (control) => ListTile(
    contentPadding: tile.contentPadding,
    dense: tile.dense,
    enabled: tile.onChanged != null,
    // CheckboxListTile uses a 40px shrink-wrapped decorative control. Keep
    // that column while the shared adapter retains its 48px internal face;
    // the row, not this ignored decoration, remains the input target.
    leading: SizedBox(
      width: 40,
      height: 40,
      child: OverflowBox(maxWidth: 48, maxHeight: 48, child: control),
    ),
    title: tile.title,
    subtitle: tile.subtitle,
  ),
);

Widget execHangarSwitch(SwitchListTile tile) => StarBridgeSwitch.tile(
  key: tile.key,
  value: tile.value,
  label: (tile.title as Text).data!,
  subtitle: tile.subtitle is Text ? (tile.subtitle as Text).data : null,
  onChanged: tile.onChanged,
  rowBuilder: (control) => ListTile(
    contentPadding: tile.contentPadding,
    dense: tile.dense,
    enabled: tile.onChanged != null,
    title: tile.title,
    subtitle: tile.subtitle,
    trailing: control,
  ),
);

Widget execHangarDisclosure(ExpansionTile tile) => HelpSupportExpansionTile(
  key: tile.key,
  title: tile.title as Text,
  initiallyExpanded: tile.initiallyExpanded,
  tilePadding: tile.tilePadding,
  childrenPadding: tile.childrenPadding ?? EdgeInsets.zero,
  childrenCrossAxisAlignment:
      tile.expandedCrossAxisAlignment ?? CrossAxisAlignment.center,
  children: tile.children,
);
