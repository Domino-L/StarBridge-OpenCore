import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_row.dart';

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
  final void Function(RoomPresetChoice, InteractionSource) onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final choice in choices)
        StarBridgeActionRow(
          controlKey: ValueKey('room-preset-choice-${choice.id}'),
          semanticLabel: choice.name,
          onActivate: enabled
              ? (_, source) => onSelected(choice, source)
              : null,
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: ListTile(
                title: Text(choice.name),
                trailing: const StarBridgeIcon(StarBridgeIconSemantic.forward),
              ),
            ),
          ),
        ),
    ],
  );
}
