import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_slider.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_value_format.dart';
import 'overlay_members_size_buttons.dart';

class OverlayWorkspaceNumberField extends StatelessWidget {
  const OverlayWorkspaceNumberField({
    super.key,
    required this.spec,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.onStep,
  });

  final OverlayWorkspaceFieldSpec spec;
  final String label;
  final Object? value;
  final ValueChanged<Object?>? onChanged;
  final String? helperText;
  final ValueChanged<Object?>? onStep;

  @override
  Widget build(BuildContext context) {
    final number = value is num ? (value as num).toDouble() : spec.minimum;
    final clamped = number.clamp(spec.minimum, spec.maximum).toDouble();
    // JSON writes whole-valued doubles as 0/1, so runtime numeric type cannot
    // determine whether a setting accepts fractions. Counts alone are integral.
    final integral =
        spec.unit == OverlayWorkspaceUnit.count ||
        spec.unit == OverlayWorkspaceUnit.degrees ||
        spec.unit == OverlayWorkspaceUnit.visorPixels;
    return InputDecorator(
      decoration: InputDecoration(
        helperText: helperText,
        helperMaxLines: 3,
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label  ${overlayWorkspaceFormatValue(spec, clamped, AppStrings.of(context))}',
          ),
          // Flutter's Windows AX bridge cannot safely reuse the Slider's
          // OverlayPortal children when enabling replaces their traversal
          // parent. Recreate that local subtree only across enabled changes;
          // keep the value in the draft and preserve normal drag state.
          Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('slider-${spec.field}-${onChanged != null}'),
                  child: StarBridgeSlider(
                    controlKey: Key('overlay-field-${spec.field}'),
                    semanticLabel: label,
                    value: clamped,
                    min: spec.minimum,
                    max: spec.maximum,
                    divisions: spec.divisions,
                    valueLabel: (current) => overlayWorkspaceFormatValue(
                      spec,
                      current,
                      AppStrings.of(context),
                    ),
                    onChanged: onChanged == null
                        ? null
                        : (next) => onChanged!(integral ? next.round() : next),
                  ),
                ),
              ),
              if (spec.field == 'visorMembersHeight' ||
                  spec.field == 'visorMembersWidth')
                OverlayMembersSizeButtons(
                  field: spec.field,
                  value: clamped,
                  onChanged: onChanged == null ? null : (onStep ?? onChanged),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
