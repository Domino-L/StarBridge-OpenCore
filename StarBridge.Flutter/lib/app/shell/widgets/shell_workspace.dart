import 'package:flutter/material.dart';

import '../../diagnostics/loading_diagnostics.dart';
import '../../../shared/diagnostics/loading_content_probe.dart';
import '../../../shared/diagnostics/loading_metrics.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../../design_system/interaction/starbridge_page_motion.dart';
import '../../feature_registry.dart';
import '../../../shared/guide/guide_page_tip.dart';
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
    return LoadingRouteProbe(
      route: selected.route,
      child: ColoredBox(
        color: tokens.surfaces.ground.fill,
        child: StarBridgeInteractionRegion(
          child: StarBridgePageSwitcher(
            instant: interaction == NavigationInteraction.keyboard,
            child: KeyedSubtree(
              key: ValueKey(selected.route),
              // Reuse the stationary layer while opacity changes.
              child: RepaintBoundary(
                child: Builder(
                  builder: (context) {
                    final content = selected.buildDestination(context);
                    final available =
                        selected.availability != FeatureAvailability.comingSoon;
                    return !available
                        ? LoadingContentProbe(
                            route: selected.route,
                            status: LoadingContentStatus.unavailable,
                            child: content,
                          )
                        : GuidePageSurface(
                            route: selected.route,
                            available: available,
                            child: content,
                          );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
