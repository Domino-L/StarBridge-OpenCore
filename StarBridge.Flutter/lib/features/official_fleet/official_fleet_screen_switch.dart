import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_art.dart';
import 'official_fleet_holo_layers.dart';

/// Upper ↔ lower screen of the main fleet (user decision 2026-10-23, preview
/// DesignPreviews/MainFleetBanner/transition.html): never a hard cut. Over
/// 520ms the banner and its bright mirror edge shrink into the lower
/// screen's bar, blurring and darkening; the upper content lifts and fades;
/// the lower screen rises under the edge and one holo scan passes over it.
/// Going back plays the same in reverse. Reduced motion switches at once.
///
/// Each screen is built only while it is visible, under a stable key, so
/// the lower screen keeps its state once it has arrived.
class OfficialFleetScreenSwitch extends StatefulWidget {
  const OfficialFleetScreenSwitch({
    required this.lower,
    required this.upper,
    required this.lowerBuilder,
    required this.banner,
    required this.bannerHeight,
    this.barHeight = 64,
    super.key,
  });

  /// Target screen: false is the upper screen, true the lower one.
  final bool lower;
  final WidgetBuilder upper, lowerBuilder;
  final OrganizationHoloArt? banner;

  /// The upper screen's banner height and the lower screen's bar height:
  /// the two ends of the shrinking deck.
  final double bannerHeight, barHeight;

  static const duration = Duration(milliseconds: 520);

  @override
  State<OfficialFleetScreenSwitch> createState() => _ScreenSwitchState();
}

class _ScreenSwitchState extends State<OfficialFleetScreenSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: OfficialFleetScreenSwitch.duration,
    value: widget.lower ? 1 : 0,
  );

  /// Hidden, not removed, once it has been on screen: coming back rebuilt the
  /// whole upper screen in the switch's first frame (lab 2026-10-31).
  late bool _upperShown = !widget.lower;

  @override
  void didUpdateWidget(OfficialFleetScreenSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lower == widget.lower) return;
    final target = widget.lower ? 1.0 : 0.0;
    if (resolveStarBridgeInteraction(context).reduceMotion) {
      _progress.value = target;
    } else {
      _progress.animateTo(target);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  static double _ease(double x) =>
      x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;

  @override
  Widget build(BuildContext context) {
    // One widget per screen per build of this state: the animation reuses
    // them, so a frame never rebuilds the upper or lower content (loading
    // line 2026-10-29: every frame re-ran both builders).
    final upper = Builder(builder: widget.upper);
    final lower = Builder(builder: widget.lowerBuilder);
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final raw = _progress.value;
        final d = _ease(raw);
        final moving = raw > 0 && raw < 1;
        final upperOpacity = (1 - d / .45).clamp(0.0, 1.0);
        final rise = _ease(((raw - .3) / .7).clamp(0.0, 1.0));
        final lowerOpacity = ((raw - .3) / .4).clamp(0.0, 1.0);
        final deck =
            widget.bannerHeight + (widget.barHeight - widget.bannerHeight) * d;
        final sweep = ((raw - .45) / .55).clamp(0.0, 1.0);
        final upperHidden = raw >= 1;
        if (!upperHidden) _upperShown = true;
        return LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              if (raw > 0)
                Positioned.fill(
                  key: const ValueKey('official-fleet-lower-screen'),
                  child: IgnorePointer(
                    ignoring: moving,
                    child: Opacity(
                      opacity: lowerOpacity,
                      child: Transform.translate(
                        offset: Offset(0, 70 * (1 - rise)),
                        child: Stack(
                          children: [
                            // The mirror under the bar's edge stays on the
                            // lower screen, behind its content.
                            Positioned(
                              left: 0,
                              right: 0,
                              top: widget.barHeight,
                              height: 72,
                              child: RepaintBoundary(
                                child: OfficialFleetDeckMirror(widget.banner),
                              ),
                            ),
                            Positioned.fill(
                              child: RepaintBoundary(child: lower),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (moving) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: deck,
                  child: IgnorePointer(
                    child: _ShrinkingDeck(art: widget.banner, depth: d),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: deck,
                  height: 120 - 48 * d,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: .9 - .35 * d,
                      child: OfficialFleetDeckMirror(widget.banner),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: deck,
                  height: 1,
                  child: const IgnorePointer(child: _DeckEdge()),
                ),
                // The scan passes over the arriving screen only, never the deck.
                if (sweep > 0 && sweep < 1)
                  Positioned(
                    left: 20,
                    right: 20,
                    top: deck,
                    bottom: 0,
                    child: IgnorePointer(
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (box.maxHeight - deck) * sweep - 100,
                              height: 100,
                              child: _Scan(fade: 1 - sweep * .6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              // The upper screen paints above the shrinking deck: its slab and
              // title overlap the banner's lower edge, and the deck must not
              // cut them off while the switch runs (user report 2026-10-25).
              if (_upperShown)
                Positioned.fill(
                  key: const ValueKey('official-fleet-upper-slot'),
                  child: Offstage(
                    offstage: upperHidden,
                    child: TickerMode(
                      key: const ValueKey('official-fleet-upper-screen'),
                      enabled: !upperHidden,
                      child: ExcludeFocus(
                        excluding: upperHidden,
                        child: IgnorePointer(
                          ignoring: moving,
                          child: Opacity(
                            opacity: upperOpacity,
                            child: Transform.translate(
                              offset: Offset(0, -60 * d),
                              child: RepaintBoundary(
                                child: OfficialFleetHoloGlassHold(
                                  hold: moving || upperHidden,
                                  child: upper,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The banner on its way to becoming the bar: more blur and shade the
/// further it shrinks, so the bar ends calm behind its text.
class _ShrinkingDeck extends StatelessWidget {
  const _ShrinkingDeck({required this.art, required this.depth});

  final OrganizationHoloArt? art;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final ground = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 8 * depth,
              sigmaY: 8 * depth,
              tileMode: TileMode.clamp,
            ),
            child: OfficialFleetHoloBannerImage(art),
          ),
          ColoredBox(color: ground.withValues(alpha: .5 * depth)),
        ],
      ),
    );
  }
}

/// The deck's bright edge line, the same light as the holo header's.
class _DeckEdge extends StatelessWidget {
  const _DeckEdge();

  @override
  Widget build(BuildContext context) {
    final light = context.tokens.colors.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            light.withValues(alpha: 0),
            light.withValues(alpha: .55),
            light.withValues(alpha: .55),
            light.withValues(alpha: 0),
          ],
          stops: const [0, .2, .8, 1],
        ),
      ),
    );
  }
}

/// One holo scan passing down over the arriving lower screen.
class _Scan extends StatelessWidget {
  const _Scan({required this.fade});

  final double fade;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    return Opacity(
      opacity: fade,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: .10),
              accent.withValues(alpha: .45),
              accent.withValues(alpha: 0),
            ],
            stops: const [0, .8, .99, 1],
          ),
        ),
      ),
    );
  }
}

/// The banner mirrored and blurred under the deck edge, fading into the page:
/// the "mirror" of the holo deck, kept under the lower screen's bar.
class OfficialFleetDeckMirror extends StatelessWidget {
  const OfficialFleetDeckMirror(this.art, {super.key});

  final OrganizationHoloArt? art;

  @override
  Widget build(BuildContext context) {
    if (art == null) return const SizedBox.shrink();
    final ground = Theme.of(context).scaffoldBackgroundColor;
    return ExcludeSemantics(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The reflection itself fades out, so the page art below shows.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ground.withValues(alpha: .6),
                  ground.withValues(alpha: 0),
                ],
              ).createShader(bounds),
              // Performance (2026-10-24): a 48-pixel decode drawn large is
              // the blur; this mirror stays under the lower screen's bar.
              child: Transform.flip(
                flipY: true,
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  maxHeight: 300,
                  child: SizedBox(
                    height: 300,
                    child: art!.image(
                      cacheWidth: 48,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
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
