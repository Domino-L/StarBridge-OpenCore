import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_page_motion.dart';

/// Keeps AnimatedSwitcher's original 130 ms outgoing lifetime. The feedback
/// form's mounted receipt handling depends on it; this is not a new data owner.
class HelpSupportTopicTransition extends StatefulWidget {
  const HelpSupportTopicTransition({
    required this.animation,
    required this.child,
    required this.instant,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final bool instant;

  @override
  State<HelpSupportTopicTransition> createState() =>
      _HelpSupportTopicTransitionState();
}

class _HelpSupportTopicTransitionState
    extends State<HelpSupportTopicTransition> {
  bool _instant = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _instant |=
        widget.instant || resolveStarBridgeInteraction(context).reduceMotion;
  }

  @override
  void didUpdateWidget(HelpSupportTopicTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A retired keyboard/reduced entry must not reappear on a later click.
    _instant |= widget.instant;
  }

  @override
  Widget build(BuildContext context) => StarBridgePageTransition(
    animation: widget.animation,
    instant: _instant,
    child: widget.child,
  );
}
