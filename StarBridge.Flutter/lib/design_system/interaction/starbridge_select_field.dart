import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../icons/icon_semantic.dart';
import '../icons/starbridge_icon.dart';
import 'starbridge_action_row.dart';
import 'starbridge_menu_anchor.dart';

@immutable
class StarBridgeSelectOption<T> {
  const StarBridgeSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });
  final T value;
  final String label;
  final bool enabled;
}

/// A controlled choice projection. The caller owns the accepted value, draft,
/// qualification and async result; this widget never selects optimistically.
class StarBridgeSelectField<T> extends StatelessWidget {
  const StarBridgeSelectField({
    required this.identity,
    required this.options,
    required this.value,
    required this.decoration,
    this.onSelected,
    this.placeholder = '—',
    super.key,
  });
  final Object identity;
  final List<StarBridgeSelectOption<T>> options;
  final T? value;
  final InputDecoration decoration;
  final void Function(T value, InteractionSource source)? onSelected;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final current = options
        .where((option) => option.value == value)
        .firstOrNull;
    final label = current?.label ?? placeholder;
    final enabled =
        onSelected != null && options.any((option) => option.enabled);
    return StarBridgeMenuAnchor(
      key: ValueKey(identity),
      semanticLabel: '${decoration.labelText ?? ''} · $label',
      semanticHint: decoration.helperText,
      enabled: enabled,
      retainExitContent: enabled,
      matchAnchorWidth: true,
      entries: [
        for (final option in options)
          StarBridgeMenuEntry(
            id: (identity, option.value),
            label: option.label,
            selected: option.value == value,
            onActivate: enabled && option.enabled
                ? (source) => onSelected!(option.value, source)
                : null,
            child: Text(
              option.label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      builder: (_, _, focus, toggle) => StarBridgeActionRow(
        focusNode: focus,
        onActivate: enabled ? (_, source) => toggle(source) : null,
        child: InputDecorator(
          decoration: decoration.copyWith(enabled: enabled),
          isEmpty: current == null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  // Match the original SDK dropdown's value text, not the
                  // surrounding description/body text inherited by a row.
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: enabled ? null : Theme.of(context).disabledColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 8),
              const StarBridgeIcon(StarBridgeIconSemantic.menuDown, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
