import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import '../communities/community_hangar_sharing_dialog.dart';
import '../communities/community_hangar_sharing_port.dart';
import '../communities/community_ships_copy.dart';

/// A second entry to the existing audience editor, not a separate consent store.
/// Mounted per account generation by HangarPage.
class HangarSharingAction extends StatefulWidget {
  const HangarSharingAction({required this.port, super.key});
  final CommunityHangarSharingPort port;

  @override
  State<HangarSharingAction> createState() => _HangarSharingActionState();
}

class _HangarSharingActionState extends State<HangarSharingAction> {
  StarBridgeDialogRoute<bool>? _route;

  void _close() {
    final route = _route;
    _route = null;
    retireStarBridgeDialog(route);
  }

  @override
  void didUpdateWidget(covariant HangarSharingAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.port, widget.port)) _close();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  Future<void> _open() async {
    if (_route != null || !widget.port.hangarSharingAvailable) return;
    final port = widget.port;
    StarBridgeDialogRoute<bool>? opened;
    await showStarBridgeDialog<bool>(
      context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => CommunityHangarSharingDialog(port: port),
      onRouteCreated: (route) => _route = opened = route,
    );
    if (identical(_route, opened)) _route = null;
  }

  @override
  Widget build(BuildContext context) => StarBridgeActionButton(
    controlKey: const Key('local-hangar-sharing'),
    onActivate: (_) => _open(),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StandardIcon(StandardIconSemantic.share, size: 18),
        const SizedBox(width: 8),
        Text(communityShipsText(context, 'sharingTitle')),
      ],
    ),
  );
}
