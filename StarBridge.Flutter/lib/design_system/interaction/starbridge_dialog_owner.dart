import 'package:flutter/material.dart';

import 'starbridge_dialog.dart';

/// A function-owned dialog follows the lifetime of its actual business caller.
/// Checks run only on rendered frames; never requests extra frames or writes.
/// The caller retains account/selection authorization and request ownership.
class StarBridgeDialogOwnerGuard extends StatefulWidget {
  const StarBridgeDialogOwnerGuard({
    required this.isCurrent,
    required this.child,
    super.key,
  });
  final bool Function() isCurrent;
  final Widget child;
  @override
  State<StarBridgeDialogOwnerGuard> createState() => _OwnerGuardState();
}

class _OwnerGuardState extends State<StarBridgeDialogOwnerGuard> {
  bool _queued = false, _retired = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    if (!mounted || _queued || _retired) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _retired) return;
      if (!widget.isCurrent()) {
        _retired = true;
        final route = ModalRoute.of(context);
        if (route is StarBridgeDialogRoute) retireStarBridgeDialog(route);
        return;
      }
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
