import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';
import 'guide_listing_demo.dart';
import 'guide_scope.dart';
import 'guide_tours.dart';
import 'guide_windows_notice.dart';

/// Route → tip id. Coming-soon features ("行动") get none.
const guideTipRoutes = {
  '/fleet': 'fleet',
  '/rooms': 'rooms',
  '/marketplace': 'market',
  '/communities': 'communities',
  '/hangar': 'hangar',
  '/overlay': 'overlay',
  '/tools': 'tools',
  '/settings': 'settings',
  '/friends': 'friends',
  '/messages': 'messages',
  '/notifications': 'notifications',
  '/profile': 'profile',
  '/achievements': 'achievements',
};

/// Wraps a shell destination: records the visit and shows its tip once.
class GuidePageSurface extends StatefulWidget {
  const GuidePageSurface({
    required this.route,
    required this.available,
    required this.child,
    super.key,
  });
  final String route;
  final bool available;
  final Widget child;

  @override
  State<GuidePageSurface> createState() => _GuidePageSurfaceState();
}

class _GuidePageSurfaceState extends State<GuidePageSurface> {
  GuideHub? _hub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hub = GuideScope.maybeOf(context);
    if (!identical(hub, _hub)) {
      _hub = hub;
      _visit();
    }
  }

  @override
  void didUpdateWidget(GuidePageSurface old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route) _visit();
  }

  void _visit() {
    final hub = _hub;
    if (hub == null || !widget.available) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) hub.visit(widget.route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    final tip = guideTipRoutes[widget.route];
    if (hub == null || tip == null || !widget.available) return widget.child;
    final notice = hub.windowsNotice;
    return ListenableBuilder(
      listenable: Listenable.merge([
        hub.controller,
        if (tip == 'notifications' && notice != null) ...[
          notice.state,
          hub.windowsNoticeRequested,
          hub.windowsNoticeEnabledHere,
        ],
      ]),
      child: widget.child,
      builder: (context, child) {
        final state = hub.controller.value;
        final tour = guideTours[tip];
        final tourReplacesTip =
            tour?.route != null &&
            state.eligible &&
            !state.seen.contains(tour!.seenId);
        final show =
            state.available &&
            !state.seen.contains('tip.$tip') &&
            !tourReplacesTip;
        final card =
            tip == 'notifications' &&
            state.available &&
            guideWindowsNoticeCardVisible(hub);
        // The checklist's "Turn on" brings the card back after the tip.
        final cardAlone = card && !show && hub.windowsNoticeRequested.value;
        // The page keeps one fixed slot (keyed) whether or not the tip is
        // shown, so closing or resetting a tip never rebuilds the page.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (show)
              GuideTipStrip(
                key: Key('guide-tip-$tip'),
                tip: tip,
                hub: hub,
                notice: card,
              ),
            if (cardAlone)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.tokens.space.lg,
                  context.tokens.space.md,
                  context.tokens.space.lg,
                  0,
                ),
                child: GuideWindowsNoticeCard(hub: hub),
              ),
            Expanded(key: const ValueKey('guide-page-body'), child: child!),
          ],
        );
      },
    );
  }
}

class GuideTipStrip extends StatelessWidget {
  const GuideTipStrip({
    required this.tip,
    required this.hub,
    this.notice = false,
    super.key,
  });
  final String tip;
  final GuideHub hub;

  /// Shows the Windows notifications card under the tip text.
  final bool notice;

  void _action(BuildContext context) {
    switch (tip) {
      case 'fleet' || 'profile':
        hub.navigate('/settings/privacy');
      case 'market':
        showGuideListingDemo(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final points = copy.maybe('tip.$tip.points')?.split('|') ?? const [];
    final note = copy.maybe('tip.$tip.note');
    final action = copy.maybe('tip.$tip.action');
    final hasTour = guideTours.containsKey(tip);
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colors.accentSoft,
          borderRadius: BorderRadius.circular(t.shape.radiusMedium),
          border: Border(left: BorderSide(color: t.colors.accent, width: 3)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.md,
            t.space.sm,
            t.space.sm,
            t.space.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(copy.text('tip.$tip.title'), style: text.titleSmall),
                    if (points.isNotEmpty) ...[
                      SizedBox(height: t.space.xxs),
                      Wrap(
                        spacing: t.space.md,
                        runSpacing: t.space.xxs,
                        children: [
                          for (final point in points)
                            Text(
                              '· $point',
                              style: text.bodySmall?.copyWith(
                                color: t.colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (note != null) ...[
                      SizedBox(height: t.space.xxs),
                      Text(
                        note,
                        style: text.bodySmall?.copyWith(
                          color: t.colors.textDisabled,
                        ),
                      ),
                    ],
                    if (notice) ...[
                      SizedBox(height: t.space.xs),
                      GuideWindowsNoticeCard(hub: hub),
                    ],
                  ],
                ),
              ),
              SizedBox(width: t.space.sm),
              if (hasTour)
                StarBridgeActionButton(
                  controlKey: Key('guide-tip-$tip-tour'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) {
                    hub.controller.markSeen('tip.$tip');
                    hub.start(tip);
                  },
                  child: Text(copy.text('tip.tour')),
                ),
              if (action != null)
                StarBridgeActionButton(
                  controlKey: Key('guide-tip-$tip-action'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) {
                    // Navigating away retires the tip; the demo keeps it.
                    if (tip != 'market') hub.controller.markSeen('tip.$tip');
                    _action(context);
                  },
                  child: Text(action),
                ),
              StarBridgeActionButton(
                controlKey: Key('guide-tip-$tip-dismiss'),
                kind: StarBridgeActionKind.secondary,
                onActivate: (_) => hub.controller.markSeen('tip.$tip'),
                child: Text(copy.text('tip.gotIt')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
