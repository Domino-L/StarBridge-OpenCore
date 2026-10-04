import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'room_member_removal.dart';
import 'room_member_transfer.dart';

/// Shared member-card action surface. Callers supply only authorized actions.
class RoomMemberMenu extends StatefulWidget {
  const RoomMemberMenu({super.key, this.onRemove, this.onTransfer});
  final VoidCallback? onRemove;
  final VoidCallback? onTransfer;
  @override
  State<RoomMemberMenu> createState() => _RoomMemberMenuState();
}

class _RoomMemberMenuState extends State<RoomMemberMenu> {
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
    useRootNavigator: false,
    enabled: widget.onRemove != null || widget.onTransfer != null,
    icon: const StandardIcon(StandardIconSemantic.moreHoriz),
    onSelected: (action) {
      if (!mounted) return;
      if (action == 'transfer') widget.onTransfer?.call();
      if (action == 'remove') widget.onRemove?.call();
    },
    itemBuilder: (context) => [
      if (widget.onTransfer != null)
        PopupMenuItem(
          value: 'transfer',
          child: Text(roomTransferText(context, 'transfer')),
        ),
      if (widget.onRemove != null)
        PopupMenuItem(
          value: 'remove',
          child: Text(
            roomRemovalText(context, 'remove'),
            style: TextStyle(color: context.tokens.colors.danger),
          ),
        ),
    ],
  );
}
