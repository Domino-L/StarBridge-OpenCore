import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'bridge_continuous_play.dart';
import 'continuous_play_controller.dart';
import 'continuous_play_connected_panel.dart';
import 'player_activity_controller.dart';
import 'player_activity_dialog.dart';
import 'bridge_notification_sources.dart';
import 'notification_sources_connected_panel.dart';

/// Device-local domains remain usable if another notification read fails.
class NotificationConnectedPanels extends StatefulWidget {
  const NotificationConnectedPanels({required this.session, super.key});
  final BridgeClientSession session;
  @override
  State<NotificationConnectedPanels> createState() =>
      _NotificationConnectedPanelsState();
}

class _NotificationConnectedPanelsState
    extends State<NotificationConnectedPanels> {
  late final activity = PlayerActivityController.bridge(widget.session);
  late final sources = BridgeNotificationSources(widget.session);
  late final play = ContinuousPlayController(
    BridgeContinuousPlay(widget.session),
  );
  @override
  void dispose() {
    activity.dispose();
    sources.dispose();
    play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PlayerActivityConnectedPanel(controller: activity, showClose: false),
      const SizedBox(height: 16),
      NotificationSourcesConnectedPanel(port: sources),
      const SizedBox(height: 16),
      ContinuousPlayConnectedPanel(controller: play),
    ],
  );
}
