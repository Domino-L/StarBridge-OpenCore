import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../common/social_read_activity.dart';

/// Only the original owner's pending state mounts this decoration. Phase keys
/// belong to admitted operations, never to a timer tick, timeout or result.
class ExecHangarWaiting extends StatelessWidget {
  const ExecHangarWaiting({
    required this.label,
    required this.source,
    this.opening = false,
    this.active = true,
    super.key,
  });
  final String label;
  final InteractionSource source;
  final bool opening, active;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: TickerMode(
        enabled: active,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const SizedBox(height: 6),
            SocialReadActivity(
              source: source,
              opening: opening,
              label: label,
              height: 4,
            ),
          ],
        ),
      ),
    ),
  );
}
