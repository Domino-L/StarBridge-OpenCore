import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// Approved wait presentation only: no progress estimate or success state.
class FriendsWaitingIndicator extends StatelessWidget {
  const FriendsWaitingIndicator({
    required this.label,
    required this.source,
    required this.controlKey,
    this.showLabel = false,
    super.key,
  });
  final String label;
  final InteractionSource source;
  final Key controlKey;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final reduce =
            data.reduceMotion || source == InteractionSource.keyboard;
        if (reduce) {
          return Semantics(
            liveRegion: true,
            child: Text(label, key: controlKey, textAlign: TextAlign.center),
          );
        }
        return InteractionScope(
          data: data,
          child: Semantics(
            key: controlKey,
            label: label,
            liveRegion: true,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SuiteProgressBar(
                    value: null,
                    phase: ProgressPhase.running,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: 8),
                    Text(label, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
