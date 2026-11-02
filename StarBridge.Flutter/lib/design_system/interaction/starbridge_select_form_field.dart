import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../icons/native_dropdown_indicator_icon.dart';

import 'starbridge_action_row.dart';
import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_menu_anchor.dart';

/// Changes only the native dropdown FormField's presentation seam. SDK state
/// still owns didChange, Form registration, validation, save, reset, dirty state
/// and initialValue updates. There is no second field or mirrored draft value.
class StarBridgeSelectFormField<T> extends DropdownButtonFormField<T> {
  StarBridgeSelectFormField({
    required this.identity,
    required this.items,
    required super.onChanged,
    super.initialValue,
    super.decoration,
    super.onSaved,
    super.validator,
    super.errorBuilder,
    super.forceErrorText,
    super.autovalidateMode,
    this.semanticLabel,
    this.optionLabel,
    this.controlKey,
    this.isDense = true,
    this.isExpanded = false,
    this.icon,
    this.iconSize = 24,
    this.style,
    this.hint,
    this.disabledHint,
    this.alignment = AlignmentDirectional.centerStart,
    this.selectedItemBuilder,
    this.menuFitsContent = false,
    super.key,
  }) : super(
         items: items,
         isDense: isDense,
         isExpanded: isExpanded,
         icon: icon,
         iconSize: iconSize,
         style: style,
         hint: hint,
         disabledHint: disabledHint,
         alignment: alignment,
         selectedItemBuilder: selectedItemBuilder,
       );

  final Object identity;
  final List<DropdownMenuItem<T>>? items;
  final String? semanticLabel;

  /// Required for non-Text option content; do not expose business IDs as labels.
  final String Function(DropdownMenuItem<T> item)? optionLabel;
  final Key? controlKey;
  final bool isDense, isExpanded;
  final Widget? icon, hint, disabledHint;
  final double iconSize;
  final TextStyle? style;
  final AlignmentGeometry alignment;

  /// What the closed field shows per item, when the menu rows carry more
  /// (a tag or a note) than fits in the field.
  final DropdownButtonBuilder? selectedItemBuilder;

  /// Lets the open menu be wider than a narrow field, up to its content.
  final bool menuFitsContent;

  String labelOf(DropdownMenuItem<T> item) {
    if (optionLabel != null) return optionLabel!(item);
    final child = item.child;
    if (child is Text) return child.data ?? child.textSpan!.toPlainText();
    throw ArgumentError('Provide optionLabel for non-Text dropdown content.');
  }

  // Deliberately inherit createState from DropdownButtonFormField. Its private
  // SDK state also sees this subclass, so original callback ordering survives.
  @override
  FormFieldBuilder<T> get builder =>
      (field) =>
          _FormSelectProjection<T>(key: ValueKey(identity), field: field);
}

class _FormSelectProjection<T> extends StatefulWidget {
  const _FormSelectProjection({required this.field, super.key});
  final FormFieldState<T> field;
  @override
  State<_FormSelectProjection<T>> createState() =>
      _FormSelectProjectionState<T>();
}

class _FormSelectProjectionState<T> extends State<_FormSelectProjection<T>> {
  int _nativeEpoch = 0;
  StarBridgeSelectFormField<T> get config =>
      widget.field.widget as StarBridgeSelectFormField<T>;

  void _choose(T? value, InteractionSource source) {
    if (config.onChanged == null) return;
    if (source == InteractionSource.keyboard) setState(() => _nativeEpoch++);
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.field.didChange(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _buildChoice));

  Widget _buildChoice(BuildContext context) {
    final field = widget.field, c = config, data = InteractionScope.of(context);
    final items = c.items ?? <DropdownMenuItem<T>>[];
    final current = items
        .where((item) => item.value == field.value)
        .firstOrNull;
    final enabled = c.onChanged != null && items.any((item) => item.enabled);
    final base = c.decoration.applyDefaults(InputDecorationTheme.of(context));
    final decorationHint = base.hintText == null ? null : Text(base.hintText!);
    final hint = c.hint ?? decorationHint;
    final disabledHint = c.disabledHint ?? hint;
    final hasHint = enabled
        ? hint != null
        : hint != null || disabledHint != null;
    final label = current == null ? '' : c.labelOf(current);
    final error = field.errorText != null && c.errorBuilder != null
        ? c.errorBuilder!(context, field.errorText!)
        : null;
    final effective = (field.errorText != null || base.hintText != null)
        ? base.copyWith(
            error: error,
            errorText: error == null ? field.errorText : null,
            hintText: base.hintText == null ? null : '',
          )
        : base;
    return StarBridgeMenuAnchor(
      key: ValueKey(c.identity),
      semanticLabel: '${c.semanticLabel ?? base.labelText ?? ''} · $label',
      semanticHint: [
        base.helperText,
        field.errorText,
        base.errorText,
      ].whereType<String>().where((s) => s.isNotEmpty).toSet().join('\n'),
      enabled: enabled,
      retainExitContent: enabled,
      matchAnchorWidth: !c.menuFitsContent,
      entries: [
        for (final item in items)
          StarBridgeMenuEntry(
            id: (c.identity, item.value),
            label: c.labelOf(item),
            selected: item.value == field.value,
            onActivate: enabled && item.enabled
                ? (source) => _choose(item.value, source)
                : null,
            child: item.key == null
                ? item.child
                : KeyedSubtree(key: item.key, child: item.child),
          ),
      ],
      builder: (_, _, focus, toggle) {
        // Follow SDK _formField suffix placement, including outlined/filled
        // end margin. Native text/value layout remains the SDK dropdown.
        final endMargin =
            effective.filled == true || effective.border?.isOutline == true
            ? 12.0
            : 0.0;
        final iconColor = Theme.brightnessOf(context) == Brightness.dark
            ? enabled
                  ? Colors.white70
                  : Colors.white10
            : enabled
            ? Colors.grey.shade700
            : Colors.grey.shade400;
        return StarBridgeActionRow(
          controlKey: c.controlKey,
          focusNode: focus,
          onActivate: enabled ? (_, source) => toggle(source) : null,
          child: KeyedSubtree(
            // Land InputDecorator label/error animations, not the FormField
            // state, when keyboard/reader activates or live reduction changes.
            key: ValueKey((
              _nativeEpoch,
              data.reduceMotion,
              focus.hasFocus,
              data.reduceMotion ? field.value : null,
              data.reduceMotion ? field.errorText : null,
            )),
            child: InputDecorator(
              isFocused: focus.hasFocus,
              isEmpty: current == null && !hasHint,
              decoration: effective.copyWith(
                enabled: enabled,
                suffixIconConstraints: BoxConstraints(
                  minWidth: c.iconSize + endMargin,
                  minHeight: c.iconSize,
                ),
                suffixIcon: Padding(
                  padding: EdgeInsetsDirectional.only(end: endMargin),
                  child: IconTheme(
                    data: IconThemeData(color: iconColor, size: c.iconSize),
                    child:
                        c.icon ??
                        effective.suffixIcon ??
                        const NativeDropdownIndicatorIcon(),
                  ),
                ),
              ),
              child: IgnorePointer(
                child: ExcludeFocus(
                  child: ExcludeSemantics(
                    child: DropdownButtonHideUnderline(
                      child: ButtonTheme.fromButtonThemeData(
                        data: ButtonTheme.of(context)
                            .copyWith(alignedDropdown: false),
                        child: DropdownButton<T>(
                          items: items,
                          selectedItemBuilder: c.selectedItemBuilder,
                          value: current == null ? null : field.value,
                          isDense: c.isDense,
                          isExpanded: c.isExpanded,
                          style: c.style,
                          hint: hint,
                          disabledHint: disabledHint,
                          alignment: c.alignment,
                          itemHeight: null,
                          icon: const SizedBox.shrink(),
                          iconSize: c.iconSize,
                          // Inert SDK typography/layout projection only.
                          onChanged: enabled ? (_) {} : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
