import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../localization/app_strings.dart';

/// Functional waiting feedback only. The existing recovery owner admits the
/// request, times it out and decides whether its reply is still current.
class MenuRecoveryBusy extends StatelessWidget {
  const MenuRecoveryBusy({required this.source, super.key});
  final InteractionSource source;

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final animate =
            !data.reduceMotion && source == InteractionSource.pointer;
        return InteractionScope(
          data: data.copyWith(reduceMotion: !animate),
          child: Semantics(
            liveRegion: true,
            label: AppStrings.resolve(Localizations.localeOf(context))
                .text('menu.restore.busy'),
            child: ExcludeSemantics(
              // The fixed marker is not a measured progress percentage.
              child: SuiteBusyFrame(
                busy: true,
                radius: 0,
                child: LinearProgressIndicator(
                  value: animate
                      ? (data.suite == InteractionSuite.standard ||
                                data.suite == InteractionSuite.glow
                            ? null
                            : 0)
                      : .5,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
