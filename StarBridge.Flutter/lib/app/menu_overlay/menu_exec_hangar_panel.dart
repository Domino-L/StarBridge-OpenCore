import 'package:flutter/material.dart';

import '../../features/tools/exec_hangar_page.dart';
import '../../features/tools/exec_hangar_port.dart';

/// Prepared menu content. The menu owner must supply its opening-scoped port;
/// this widget never creates a Host, owns monitoring, or stops it on disposal.
/// Keep it mounted while hiding the menu, and call confirmClose before removing
/// its workspace lease so an unsaved reminder draft cannot be lost silently.
final class MenuExecHangarPanel extends StatefulWidget {
  const MenuExecHangarPanel({
    super.key,
    required this.port,
    this.visible = true,
  });
  final ExecHangarPort port;
  final bool visible;

  @override
  MenuExecHangarPanelState createState() => MenuExecHangarPanelState();
}

final class MenuExecHangarPanelState extends State<MenuExecHangarPanel> {
  final _page = GlobalKey<ExecHangarPageState>();

  Future<bool> confirmClose() =>
      _page.currentState?.confirmLeave(context) ?? Future.value(true);

  @override
  Widget build(BuildContext context) => ExecHangarPage(
    key: _page,
    port: widget.port,
    embedded: true,
    active: widget.visible,
  );
}
