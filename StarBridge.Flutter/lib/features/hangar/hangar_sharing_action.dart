import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

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
  DialogRoute<bool>? _route;

  void _close() {
    final route = _route;
    _route = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
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
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunityHangarSharingDialog(port: port),
    );
    _route = route;
    await Navigator.of(context).push(route);
    if (identical(_route, route)) _route = null;
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('local-hangar-sharing'),
    onPressed: _open,
    icon: const StandardIcon(StandardIconSemantic.share, size: 18),
    label: Text(communityShipsText(context, 'sharingTitle')),
  );
}
