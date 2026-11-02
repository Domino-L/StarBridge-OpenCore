import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_action_row.dart';
import 'starbridge_activation_origin.dart';
import 'starbridge_menu_anchor.dart';
import 'starbridge_select_field.dart';

export 'starbridge_select_field.dart' show StarBridgeSelectOption;

/// Controlled compact choice for existing toolbar dropdowns, not a FormField.
/// Value, enabled options and the result still belong to the caller. A native
/// DropdownButton is retained only as an inert visual/layout projection, so
/// the original intrinsic width, underline, typography and expanded sizing
/// survive without maintaining a second menu, focus target or callback owner.
class StarBridgeCompactSelect<T> extends StatelessWidget {
  const StarBridgeCompactSelect({
    required this.identity,
    required this.semanticLabel,
    required this.options,
    required this.value,
    this.onSelected,
    this.controlKey,
    this.isExpanded = false,
    this.isDense = false,
    this.style,
    this.icon,
    this.selectedMaxLines,
    this.selectedOverflow,
    this.placeholder = '—',
    this.autofocus = false,
    super.key,
  });

  final Object identity;
  final String semanticLabel;
  final List<StarBridgeSelectOption<T>> options;
  final T? value;
  final void Function(T value, InteractionSource source)? onSelected;
  final Key? controlKey;
  final bool isExpanded;
  final bool isDense;
  final TextStyle? style;
  final Widget? icon;
  final int? selectedMaxLines;
  final TextOverflow? selectedOverflow;
  final String placeholder;

  /// Focus the select when its scope has no focus yet (dialog first field).
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final current = options
        .where((option) => option.value == value)
        .firstOrNull;
    final enabled =
        onSelected != null && options.any((option) => option.enabled);
    return StarBridgeMenuAnchor(
      key: ValueKey(identity),
      semanticLabel: '$semanticLabel · ${current?.label ?? placeholder}',
      enabled: enabled,
      retainExitContent: enabled,
      entries: [
        for (final option in options)
          StarBridgeMenuEntry(
            id: (identity, option.value),
            label: option.label,
            selected: option.value == value,
            onActivate: enabled && option.enabled
                ? (source) => unawaited(
                    runStarBridgeActivation<void>(
                      source,
                      () => onSelected!(option.value, source),
                    ),
                  )
                : null,
            child: Text(
              option.label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (_, _, focus, toggle) => StarBridgeActionRow(
        controlKey: controlKey,
        focusNode: focus,
        autofocus: autofocus,
        onActivate: enabled ? (_, source) => toggle(source) : null,
        child: IgnorePointer(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: DropdownButton<T>(
                value: current?.value,
                isExpanded: isExpanded,
                isDense: isDense,
                style: style,
                icon: icon,
                hint: current == null ? Text(placeholder) : null,
                items: [
                  for (final option in options)
                    DropdownMenuItem(
                      value: option.value,
                      enabled: option.enabled,
                      child: Text(
                        option.label,
                        maxLines: selectedMaxLines,
                        overflow: selectedOverflow,
                      ),
                    ),
                ],
                // Keeps native enabled colors only. IgnorePointer,
                // ExcludeFocus and ExcludeSemantics above prevent this
                // visual projection from handling any activation.
                onChanged: enabled ? (_) {} : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
