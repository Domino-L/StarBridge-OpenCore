import 'package:flutter/widgets.dart';

import '../../features/party_rooms/party_rooms_module.dart';

/// Starts only with a mounted shell, never from a headless composition.
class RoomSessionListener extends StatefulWidget {
  const RoomSessionListener({
    required this.module,
    required this.child,
    super.key,
  });
  final PartyRoomsModule module;
  final Widget child;
  @override
  State<RoomSessionListener> createState() => _RoomSessionListenerState();
}

class _RoomSessionListenerState extends State<RoomSessionListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.module.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      widget.module.startSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.module.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.module.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
