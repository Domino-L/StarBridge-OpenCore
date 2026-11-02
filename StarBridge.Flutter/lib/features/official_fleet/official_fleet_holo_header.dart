import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/styles/official_fleet_holo_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_art.dart';
import '../common/organization_holo_deck.dart';
import 'official_fleet_holo_layers.dart';
import 'official_fleet_holo_paint.dart';
import 'official_fleet_holo_readouts.dart';
import 'official_fleet_holo_timeline.dart';

/// Main-fleet header, direction 4 "镜面全息台" (approved 2026-10-21):
/// full-bleed 3:1 banner that nothing opaque covers, a mirror deck that
/// reflects it, a slanted glass slab straddling its lower edge, and the
/// fleet's SID sunk into the reflection. Data is exactly the old header's.
class OfficialFleetHoloHeader extends StatefulWidget {
  const OfficialFleetHoloHeader({
    required this.deck,
    required this.maxBannerHeight,
    this.entry = OfficialFleetHoloEntry.full,
    super.key,
  });

  /// What to show: the main fleet's or a community's deck.
  final OrganizationHoloDeck deck;
  final double maxBannerHeight;

  /// Full once a day, quick on later visits, none after a collapse.
  final OfficialFleetHoloEntry entry;

  @override
  State<OfficialFleetHoloHeader> createState() =>
      _OfficialFleetHoloHeaderState();
}

class _OfficialFleetHoloHeaderState extends State<OfficialFleetHoloHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: widget.entry == OfficialFleetHoloEntry.quick
          ? officialFleetHoloQuickMs
          : officialFleetHoloFullMs,
    ),
  );
  late final OfficialFleetHoloTimeline _timeline = OfficialFleetHoloTimeline(
    _entry,
    quick: widget.entry == OfficialFleetHoloEntry.quick,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.entry == OfficialFleetHoloEntry.none ||
        resolveStarBridgeInteraction(context).reduceMotion) {
      _entry.value = 1;
    } else {
      _entry.forward();
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final narrow = width < 900;
      final bannerHeight = math.min(width / 3, widget.maxBannerHeight);
      final banner = widget.deck.banner;
      return Column(
        key: const Key('official-fleet-context-header'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const Key('official-fleet-holo-banner'),
            height: bannerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipPath(
                  clipper: OfficialFleetUnveilClipper(_timeline.unveil),
                  child: RepaintBoundary(
                    child: OfficialFleetHoloBannerImage(banner),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: OfficialFleetUnveilEdgePainter(
                      _timeline.unveil,
                      context.tokens.colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Deck(
            deck: widget.deck,
            banner: banner,
            bannerHeight: bannerHeight,
            narrow: narrow,
            timeline: _timeline,
          ),
        ],
      );
    },
  );
}

class _Deck extends StatelessWidget {
  const _Deck({
    required this.deck,
    required this.banner,
    required this.bannerHeight,
    required this.narrow,
    required this.timeline,
  });

  final OrganizationHoloDeck deck;
  final OrganizationHoloArt? banner;
  final double bannerHeight;
  final bool narrow;
  final OfficialFleetHoloTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final light = Theme.of(context).brightness == Brightness.light;
    final ground = tokens.surfaces.ground.fill;
    final facts = deck.readouts.isNotEmpty;
    final slab = Transform.translate(
      // Wide decks with facts lift the slab together with them (see OfficialFleetHoloLift).
      offset: Offset(0, narrow ? -18 : (facts ? 0 : -30)),
      // Slides only: the slab fades its glass and content itself, because a
      // backdrop blur inside a fading layer shows no blur until it ends.
      child: _SlideIn(
        animation: timeline.slab,
        dx: timeline.slabOffset,
        fade: false,
        child: _Slab(
          deck: deck,
          narrow: narrow,
          edge: timeline.edge,
          appear: timeline.slab,
        ),
      ),
    );
    final stats = _Stats(
      stats: deck.stats,
      readouts: const [],
      readoutsKey: null,
      timeline: timeline,
      narrow: narrow,
    );
    // The facts read like the counters but sit on the left, under the slab.
    final readouts = facts
        ? _Stats(
            stats: const [],
            readouts: deck.readouts,
            readoutsKey: deck.readoutsKey,
            timeline: timeline,
            narrow: true,
          )
        : null;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: narrow ? 0 : 168),
      child: Stack(
        children: [
          Positioned.fill(
            // The deck's art layers settle after the entry; keep them apart
            // from the slab and stats that may still move.
            child: RepaintBoundary(
              child: IgnorePointer(
                child: ClipRect(
                  child: Stack(
                    children: [
                      if (banner != null)
                        Positioned.fill(
                          child: FadeTransition(
                            opacity: timeline.ambient,
                            child: OfficialFleetHoloAmbient(banner!),
                          ),
                        ),
                      if (banner != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: bannerHeight,
                          child: FadeTransition(
                            opacity: timeline.mirror,
                            child: OfficialFleetHoloMirror(
                              banner!,
                              light: light,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0, .48, .92],
                              colors: [
                                ground.withValues(alpha: light ? .1 : .04),
                                ground.withValues(alpha: light ? .55 : .5),
                                ground.withValues(alpha: light ? .94 : .9),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 1,
                        child: ScaleTransition(
                          scale: timeline.seam,
                          alignment: Alignment.center,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  OfficialFleetHoloPalette.clearWhite,
                                  OfficialFleetHoloPalette.sweepWhite,
                                  OfficialFleetHoloPalette.sweepWhite,
                                  OfficialFleetHoloPalette.clearWhite,
                                ],
                                stops: [0, .3, .7, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: OfficialFleetDeckScanPainter(timeline.scan),
                        ),
                      ),
                      Positioned(
                        right: narrow ? 12 : 24,
                        top: narrow ? null : 0,
                        bottom: narrow ? 64 : null,
                        child: OfficialFleetHoloGhostSid(
                          deck.code,
                          size: narrow ? 84 : 116,
                          light: light,
                          reveal: timeline.code,
                          accent: tokens.colors.accent,
                          detailed: !timeline.quick,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (narrow)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The slab fits its title and announcement here too (user
                // 2026-10-29: "左侧这个斜条过长" on a small window); the
                // ghost code keeps the right.
                LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: AlignmentDirectional.topStart,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: math.min(320, box.maxWidth),
                        maxWidth: math.max(
                          math.min(320, box.maxWidth),
                          math.min(box.maxWidth - 40, box.maxWidth * .72),
                        ),
                      ),
                      child: IntrinsicWidth(child: slab),
                    ),
                  ),
                ),
                if (readouts != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                    child: readouts,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: stats,
                ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // The slab fits its title and announcement (user report
                    // 2026-10-28: a bar stretched to half the deck left empty
                    // glass); the readouts take the room it frees.
                    // The facts sit on the counters' baseline, right under the
                    // title; slab and facts rise into the banner as one group,
                    // leaving no empty band below (user 2026-10-29).
                    if (readouts == null)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: 460,
                          maxWidth: math.max(460, constraints.maxWidth * .52),
                        ),
                        child: IntrinsicWidth(child: slab),
                      )
                    else
                      OfficialFleetHoloLift(
                        lift: 30,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: 460,
                                maxWidth: math.max(
                                  460,
                                  constraints.maxWidth * .52,
                                ),
                              ),
                              child: IntrinsicWidth(child: slab),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(
                                  460,
                                  constraints.maxWidth * .6,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 26,
                                  top: 4,
                                ),
                                child: readouts,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.bottomEnd,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 22),
                          child: stats,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // One glint over the whole deck closes the full entry.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: OfficialFleetGlintPainter(timeline.glint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slab extends StatelessWidget {
  const _Slab({
    required this.deck,
    required this.narrow,
    required this.edge,
    required this.appear,
  });

  final OrganizationHoloDeck deck;
  final bool narrow;
  final Animation<double> edge;

  /// 0 to 1 while the slab arrives: the glass frosts in and the content fades.
  final Animation<double> appear;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final ink = tokens.colors.textPrimary;
    final glass = light
        ? OfficialFleetHoloPalette.glassLight
        : OfficialFleetHoloPalette.glassDark;
    final announcement = deck.line?.call(narrow);
    final mono = tokens.typography.monoFamily;
    final emblem = narrow ? 56.0 : 76.0;
    final slantRun = (narrow ? 130 : 150) * officialFleetHoloSlant;
    return CustomPaint(
      foregroundPainter: OfficialFleetSlabEdgePainter(
        grow: edge,
        accent: tokens.colors.accent,
        highlight: OfficialFleetHoloPalette.highlight,
        fade: appear,
      ),
      child: ClipPath(
        clipper: const OfficialFleetSlantClipper(),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: appear,
                builder: (context, _) {
                  final t = appear.value.clamp(0.0, 1.0);
                  if (t <= 0) return const SizedBox.shrink();
                  // The frosted glass stays at rest (user report 2026-10-25:
                  // a static tint, however dense, shows the banner and its
                  // mirror sharply). It is the shell's one backdrop blur.
                  if (t < 1) {
                    return _slabGlass(
                      glass,
                      light,
                      frost: 1,
                      sigma: 8 * t,
                      fade: t,
                    );
                  }
                  return _SettledGlass(
                    glass: glass,
                    light: light,
                    hold: OfficialFleetHoloGlassHold.of(context),
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: appear,
              builder: (context, child) =>
                  Opacity(opacity: appear.value.clamp(0.0, 1.0), child: child),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: narrow ? 130 : 150),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    narrow ? 18 : 26,
                    narrow ? 22 : 30,
                    slantRun + 8,
                    narrow ? 14 : 16,
                  ),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: emblem,
                        // The emblem is never clipped (user 2026-10-29: keep it whole).
                        child: KeyedSubtree(
                          key: const Key('official-fleet-logo'),
                          child: OrganizationHoloEmblem(
                            deck.logo,
                            fallback: deck.code,
                          ),
                        ),
                      ),
                      SizedBox(width: narrow ? 14 : 18),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deck.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineMedium?.copyWith(
                                color: ink,
                                fontSize: narrow ? 24 : 31,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  deck.code,
                                  style: text.labelLarge?.copyWith(
                                    fontFamily: mono,
                                    letterSpacing: 3,
                                    color: ink.withValues(alpha: .75),
                                  ),
                                ),
                                if (deck.tag != null)
                                  OfficialFleetSkewTag(
                                    color: ink,
                                    child: Text(
                                      deck.tag!,
                                      key: const Key(
                                        'official-fleet-my-official-position',
                                      ),
                                      style: text.labelMedium?.copyWith(
                                        color: ink,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (announcement != null) ...[
                              const SizedBox(height: 9),
                              DefaultTextStyle.merge(
                                style: TextStyle(color: ink),
                                child: announcement,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.stats,
    required this.readouts,
    required this.readoutsKey,
    required this.timeline,
    required this.narrow,
  });

  final List<OrganizationHoloStat> stats;
  final List<OrganizationHoloReadout> readouts;
  final Key? readoutsKey;
  final OfficialFleetHoloTimeline timeline;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final line = tokens.colors.textPrimary.withValues(alpha: .22);
    final label = text.labelMedium?.copyWith(
      color: tokens.colors.textSecondary,
    );
    // Readouts come first, so the counters keep the deck's right edge.
    final cells = <(Animation<double>, Widget)>[
      for (final item in readouts)
        (timeline.stat(0), OfficialFleetHoloReadout(item, label: label)),
      for (final (index, item) in stats.indexed)
        (
          timeline.stat(index),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label, style: label),
              const SizedBox(height: 5),
              // The full entry counts each number up to its value.
              AnimatedBuilder(
                animation: timeline.stat(index),
                builder: (context, _) => Text(
                  item.value == null
                      ? '—'
                      : timeline.countUp
                      ? '${(item.value! * timeline.stat(index).value.clamp(0.0, 1.0)).round()}'
                      : '${item.value}',
                  style: text.headlineMedium?.copyWith(
                    fontFamily: tokens.typography.monoFamily,
                    fontFamilyFallback: tokens.typography.monoFallbacks,
                    fontWeight: FontWeight.w600,
                    fontSize: 30,
                    height: 1.05,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                    color: item.accent
                        ? tokens.colors.stateAccent
                        : tokens.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
    final row = Wrap(
      key: stats.isEmpty ? null : const Key('official-fleet-holo-stats'),
      alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
      // Labels share one top line; values and counters hang under them.
      crossAxisAlignment: WrapCrossAlignment.start,
      runSpacing: 10,
      children: [
        for (final (index, (animation, cell)) in cells.indexed)
          _SlideIn(
            animation: animation,
            dy: 14,
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: OfficialFleetSkewedDivider(color: line),
                    ),
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: index == 0 ? 0 : 24,
                      end: index == cells.length - 1 ? 0 : 24,
                    ),
                    child: cell,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return readoutsKey == null
        ? row
        : KeyedSubtree(key: readoutsKey, child: row);
  }
}

/// Opacity + offset entry used by every element of the timeline.
class _SlideIn extends StatelessWidget {
  const _SlideIn({
    required this.animation,
    required this.child,
    this.dx = 0,
    this.dy = 0,
    this.fade = true,
  });

  final Animation<double> animation;
  final double dx, dy;
  final bool fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final moved = Transform.translate(
        offset: Offset(dx, dy) * (1 - animation.value),
        child: child,
      );
      return fade
          ? Opacity(opacity: animation.value.clamp(0, 1), child: moved)
          : moved;
    },
  );
}

/// The slab's glass: [frost] 1 is the frosted tint over a [sigma] blur,
/// 0 the dense tint that stands in for it without a blur.
Widget _slabGlass(
  Color glass,
  bool light, {
  required double frost,
  required double sigma,
  double fade = 1,
}) {
  double alpha(double dense, double frosted) =>
      (dense + (frosted - dense) * frost) * fade;
  final tint = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: const Alignment(-1, -.2),
        end: const Alignment(1, .2),
        colors: [
          glass.withValues(alpha: light ? alpha(.9, .6) : alpha(.88, .56)),
          glass.withValues(alpha: light ? alpha(.72, .36) : alpha(.66, .3)),
        ],
      ),
    ),
  );
  if (sigma <= 0) return tint;
  return BackdropFilter(
    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: tint,
  );
}

/// The arrived glass. While [hold] is on (the screen switch is running) it
/// is the dense tint without a blur; once released the blur frosts back in.
class _SettledGlass extends StatefulWidget {
  const _SettledGlass({
    required this.glass,
    required this.light,
    required this.hold,
  });

  final Color glass;
  final bool light;
  final bool hold;

  @override
  State<_SettledGlass> createState() => _SettledGlassState();
}

class _SettledGlassState extends State<_SettledGlass>
    with SingleTickerProviderStateMixin {
  late final _frost = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.hold ? 0 : 1,
  );

  @override
  void didUpdateWidget(_SettledGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hold) {
      _frost.value = 0;
    } else if (oldWidget.hold) {
      if (resolveStarBridgeInteraction(context).reduceMotion) {
        _frost.value = 1;
      } else {
        _frost.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _frost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _frost,
    builder: (context, _) {
      final frost = Curves.easeOut.transform(_frost.value);
      return _slabGlass(
        widget.glass,
        widget.light,
        frost: frost,
        sigma: 8 * frost,
      );
    },
  );
}
