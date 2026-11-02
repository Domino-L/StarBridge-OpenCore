import 'package:flutter/widgets.dart';

import '../../platform/window/native_viewport_visibility.dart';
import '../common/organization_chat_preview.dart';
import '../common/organization_communication.dart';
import '../common/user_input_idle_watcher.dart';

/// The main fleet's channel tile. Reports whether it is really on screen, so
/// author names are renewed only while someone can see them. A client left
/// open with nobody using it stops too; any input brings the names back.
class OfficialFleetChatTile extends StatefulWidget {
  const OfficialFleetChatTile({
    required this.communication,
    required this.unread,
    required this.height,
    required this.onScreen,
    super.key,
  });

  final OrganizationCommunication communication;
  final int unread;
  final double height;

  /// False once the page has moved to a lower screen.
  final bool onScreen;

  @override
  State<OfficialFleetChatTile> createState() => _OfficialFleetChatTileState();
}

class _OfficialFleetChatTileState extends State<OfficialFleetChatTile>
    with WidgetsBindingObserver {
  final _owner = Object();
  late final _idle = UserInputIdleWatcher(onChanged: _sync);
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idle;
  }

  void _sync() {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    widget.communication.setChatPreviewVisible(
      _owner,
      visible:
          mounted &&
          _idle.active &&
          widget.onScreen &&
          TickerMode.valuesOf(context).enabled &&
          NativeViewportScope.isActive(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant OfficialFleetChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.communication, widget.communication)) {
      oldWidget.communication.setChatPreviewVisible(_owner, visible: false);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle.dispose();
    widget.communication.setChatPreviewVisible(_owner, visible: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.communication.chatRecent;
    final shown = OrganizationChatPreview.fitCount(
      context,
      widget.height,
      messages.length,
    );
    if (shown != _shown) {
      _shown = shown;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.communication.chatPreviewCount = _shown;
      });
    }
    return OrganizationChatPreview(
      messages: messages,
      unread: widget.unread,
      height: widget.height,
    );
  }
}
