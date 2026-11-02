import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import 'room_member_removal.dart';
import 'room_member_transfer.dart';

/// Shared member-card action surface. Callers supply only authorized actions.
class RoomMemberMenu extends StatelessWidget {
  const RoomMemberMenu({super.key, this.onRemove, this.onTransfer});
  final ValueChanged<InteractionSource>? onRemove;
  final ValueChanged<InteractionSource>? onTransfer;
  @override
  Widget build(BuildContext context) => NativeViewportMenu(
    builder: (onOpen, onClose) => StarBridgeMenuAnchor(
      onOpen: onOpen,
      onClose: onClose,
      semanticLabel: MaterialLocalizations.of(context).moreButtonTooltip,
      enabled: onRemove != null || onTransfer != null,
      retainExitContent: onRemove != null || onTransfer != null,
      entries: [
        if (onTransfer != null)
          StarBridgeMenuEntry(
            id: 'transfer',
            label: roomTransferText(context, 'transfer'),
            onActivate: onTransfer,
            child: Text(roomTransferText(context, 'transfer')),
          ),
        if (onRemove != null)
          StarBridgeMenuEntry(
            id: 'remove',
            label: roomRemovalText(context, 'remove'),
            onActivate: onRemove,
            child: Text(
              roomRemovalText(context, 'remove'),
              style: TextStyle(color: context.tokens.colors.danger),
            ),
          ),
      ],
      builder: (context, controller, focus, toggle) => StarBridgeIconAction(
        label: MaterialLocalizations.of(context).moreButtonTooltip,
        icon: const StandardIcon(StandardIconSemantic.moreHoriz),
        focusNode: focus,
        onActivate: onRemove != null || onTransfer != null ? toggle : null,
      ),
    ),
  );
}
