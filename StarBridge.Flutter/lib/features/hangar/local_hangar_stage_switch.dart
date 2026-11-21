import 'package:flutter/material.dart';

import '../../design_system/styles/hangar_wall_palette.dart';

/// Changing ship on the stage: the next picture slides in a little from the
/// side it comes from while it fades in over the last one, which stays put
/// underneath until it is covered. Under reduced motion it simply cuts.
class LocalHangarStageSwitch extends StatelessWidget {
  const LocalHangarStageSwitch({
    required this.shipId,
    required this.direction,
    required this.child,
    super.key,
  });

  static const duration = Duration(milliseconds: 220);

  /// Share of the width the incoming picture travels.
  static const travel = .04;

  final String shipId;

  /// 1 when the next ship is to the right, -1 to the left.
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final ground = HangarWallPalette.of(context).stageGround;
    return AnimatedSwitcher(
      duration: still ? Duration.zero : duration,
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        // The last picture stays whole beneath, so the moving edge of the
        // next one never shows an empty strip.
        if (child.key != ValueKey(shipId)) return child;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(travel * direction, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(shipId),
        // Each picture is opaque, so the one beneath leaves no trace once
        // covered and nothing flashes when it goes.
        child: ColoredBox(color: ground, child: child),
      ),
    );
  }
}
