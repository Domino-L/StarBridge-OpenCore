import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../features/party_rooms/room_action_dialogs.dart';
import '../../features/party_rooms/room_member_menu.dart';
import 'menu_feature_view.dart';

/// The menu engine keeps only the opaque action and its display confirmation.
class MenuRoomMemberMenu extends StatefulWidget {
  const MenuRoomMemberMenu({
    super.key,
    this.action,
    this.transferAction,
    required this.enabled,
    required this.dispatch,
  });
  final MenuFeatureButton? action, transferAction;
  final bool enabled;
  final void Function(String, String) dispatch;
  @override
  State<MenuRoomMemberMenu> createState() => _MenuMemberState();
}

class _MenuMemberState extends State<MenuRoomMemberMenu> {
  Future<void> _confirm(
    MenuFeatureButton action,
    InteractionSource source,
  ) async {
    if (!widget.enabled || action.confirm == null) return;
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      source: source,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(action.label),
        content: Text(action.confirm!),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            child: Text(roomActionText(context, 'cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            tone: action.key != widget.action?.key ? null : ActionTone.danger,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        widget.enabled &&
        [widget.action, widget.transferAction].any(
          (current) =>
              current != null &&
              (current.role ?? current.label) == (action.role ?? action.label) &&
              current.confirm == action.confirm,
        )) {
      // Keep the exact confirmed target. Background reads renew presentation
      // references; the primary session retains their bounded lease and Host
      // revalidates the original membership token before dispatching a write.
      widget.dispatch(action.key, '');
    }
  }

  @override
  Widget build(BuildContext context) => RoomMemberMenu(
    onRemove: widget.enabled && widget.action != null
        ? (source) => _confirm(widget.action!, source)
        : null,
    onTransfer: widget.enabled && widget.transferAction != null
        ? (source) => _confirm(widget.transferAction!, source)
        : null,
  );
}
