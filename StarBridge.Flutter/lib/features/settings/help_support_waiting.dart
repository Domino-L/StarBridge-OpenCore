import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// A request's wait decoration only. The caller owns admission, timeout,
/// result and errors. It must give each new read phase its own identity.
class HelpSupportWaiting extends StatefulWidget {
  const HelpSupportWaiting({
    required this.label,
    required this.source,
    this.inheritOpeningSource = true,
    super.key,
  });
  final String label;
  final InteractionSource source;

  /// Initial automatic reads inherit the opening route. Later background
  /// reads can opt out after their owner has resolved the phase's provenance.
  final bool inheritOpeningSource;

  @override
  State<HelpSupportWaiting> createState() => _HelpSupportWaitingState();
}

class _HelpSupportWaitingState extends State<HelpSupportWaiting> {
  InteractionSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The original request already started in initState. Only its first
    // visible wait resolves the opening fact; later navigation cannot relabel it.
    _source ??= widget.inheritOpeningSource
        ? resolveStarBridgeInitialReadSource(context, widget.source)
        : widget.source;
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return Semantics(
          liveRegion: true,
          label: widget.label,
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.label),
                if (_source != InteractionSource.keyboard &&
                    !data.reduceMotion) ...[
                  const SizedBox(height: 8),
                  const SuiteProgressBar(
                    value: null,
                    phase: ProgressPhase.running,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
