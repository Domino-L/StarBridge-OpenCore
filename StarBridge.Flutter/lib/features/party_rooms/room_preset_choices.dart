import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'room_preset_port.dart';

/// Shared display-only picker; each owner decides what a choice is allowed to do.
class RoomPresetChoices extends StatelessWidget {
  const RoomPresetChoices({
    super.key,
    required this.choices,
    required this.onSelected,
    this.enabled = true,
  });
  final List<RoomPresetChoice> choices;
  final ValueChanged<RoomPresetChoice> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final choice in choices)
        ListTile(
          title: Text(choice.name),
          trailing: const StarBridgeIcon(StarBridgeIconSemantic.forward),
          onTap: enabled ? () => onSelected(choice) : null,
        ),
    ],
  );
}
