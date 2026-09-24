import 'package:flutter/widgets.dart';

import 'overlay_settings_module.dart';

/// Automatic recovery while this page is mounted. The module shares
/// this watch with the tray, so opening settings cannot create a second poller.
class OverlaySettingsRefreshScope extends StatefulWidget {
  const OverlaySettingsRefreshScope({
    required this.module,
    required this.child,
    super.key,
  });
  final OverlaySettingsModule module;
  final Widget child;
  @override
  State<OverlaySettingsRefreshScope> createState() =>
      _OverlaySettingsRefreshScopeState();
}

class _OverlaySettingsRefreshScopeState
    extends State<OverlaySettingsRefreshScope> {
  late VoidCallback _release;
  @override
  void initState() {
    super.initState();
    _release = widget.module.watch();
  }

  @override
  void didUpdateWidget(OverlaySettingsRefreshScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      _release();
      _release = widget.module.watch();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
