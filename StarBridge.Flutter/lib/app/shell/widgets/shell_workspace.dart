import 'package:flutter/material.dart';

import 'page_frame_probe.dart';

import '../../../platform/window/native_viewport_visibility.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../feature_registry.dart';
import '../shell_navigation_controller.dart';

class ShellWorkspace extends StatelessWidget {
  const ShellWorkspace({
    required this.selected,
    required this.interaction,
    super.key,
  });

  final FeatureDescriptor selected;
  final NavigationInteraction interaction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final duration = interaction == NavigationInteraction.keyboard
        ? tokens.motion.keyboard
        : tokens.motion.pointerPageSwap;
    return PageFrameProbe(
      route: selected.route,
      child: ColoredBox(
        color: tokens.surfaces.ground.fill,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: duration,
          switchInCurve: tokens.motion.enterCurve,
          switchOutCurve: tokens.motion.exitCurve,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              fit: StackFit.expand,
              children: [
                for (final child in previousChildren)
                  NativeViewportScope(
                    key: child.key,
                    active: false,
                    child: child,
                  ),
                if (currentChild != null)
                  NativeViewportScope(
                    key: currentChild.key,
                    active: true,
                    child: currentChild,
                  ),
              ],
            );
          },
          transitionBuilder: (child, animation) {
            if (duration == Duration.zero) {
              return child;
            }
            // Keep the page's raster layer stationary throughout the transition.
            // Fractional desktop-sized translations caused expensive raster frames
            // even when the widget subtree was already behind a repaint boundary.
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey(selected.route),
            // Reuse the stationary layer while opacity changes.
            child: RepaintBoundary(
              child: Builder(builder: selected.buildDestination),
            ),
          ),
        ),
      ),
    );
  }
}
