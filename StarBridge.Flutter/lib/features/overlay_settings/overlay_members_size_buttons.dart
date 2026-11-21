import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import 'overlay_members_size.dart';

class OverlayMembersSizeButtons extends StatelessWidget {
  const OverlayMembersSizeButtons({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String field;
  final num value;
  final ValueChanged<Object?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final height = field == 'visorMembersHeight';
    final spec = height ? OverlayMembersSize.height : OverlayMembersSize.width;
    final rows = OverlayMembersSize.rows(value);
    final copy = AppStrings.of(context).text;
    Widget button(int direction) {
      final next = height
          ? OverlayMembersSize.stepHeight(value, direction)
          : OverlayMembersSize.stepWidth(value, direction);
      final canStep = direction > 0
          ? value < spec.maximum
          : value > spec.minimum;
      final changesRows = !height || OverlayMembersSize.rows(next) != rows;
      final action = height
          ? (direction > 0 ? 'addRow' : 'removeRow')
          : (direction > 0 ? 'widen' : 'narrow');
      return IconButton(
        key: Key('overlay-$field-${direction > 0 ? 'plus' : 'minus'}'),
        tooltip: copy('overlay.workspace.membersSize.$action'),
        onPressed: onChanged != null && canStep && changesRows
            ? () => onChanged!(next)
            : null,
        icon: StarBridgeIcon(
          direction > 0
              ? StarBridgeIconSemantic.add
              : StarBridgeIconSemantic.remove,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(-1),
        if (height)
          Text(
            copy('overlay.workspace.membersSize.rows')
                .replaceAll('{rows}', '$rows'),
          ),
        button(1),
      ],
    );
  }
}
