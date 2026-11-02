import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../platform/window/menu_read_feedback.dart';

/// Functional feedback only. Reduced motion keeps a static progress track and
/// the accompanying status text; cached content remains fully interactive.
class MenuLoading extends StatelessWidget {
  const MenuLoading({super.key, this.feedback, this.label});
  final MenuReadFeedback? feedback;
  final String? label;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final motion =
            !data.reduceMotion && feedback?.origin == MenuReadOrigin.pointer;
        return InteractionScope(
          data: data.copyWith(reduceMotion: !motion),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: RepaintBoundary(
              child: Semantics(
                label:
                    label ?? menuText(context, 'menu.overlay.window.reading'),
                child: ExcludeSemantics(
                  // Keep the existing slim footprint, not a blocking panel veil or a
                  // fabricated percentage. Approved rail/scan frame carries the motion;
                  // standard/glow retain the existing indeterminate track treatment.
                  child: SuiteBusyFrame(
                    busy: true,
                    radius: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value:
                          motion &&
                              (data.suite == InteractionSuite.standard ||
                                  data.suite == InteractionSuite.glow)
                          ? null
                          : .5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Reserve a separate gutter so the thumb never covers message portraits.
class MenuChatScroll extends StatelessWidget {
  const MenuChatScroll({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      key: const ValueKey('menu-chat-scrollbar'),
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 8,
      radius: const Radius.circular(4),
      child: Padding(padding: const EdgeInsets.only(right: 16), child: child),
    ),
  );
}
