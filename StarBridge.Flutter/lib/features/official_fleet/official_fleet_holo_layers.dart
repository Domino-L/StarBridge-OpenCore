import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/styles/official_fleet_holo_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_art.dart';
import 'official_fleet_holo_paint.dart';
import 'official_fleet_models.dart';

/// Image layers of the main-fleet holo header: the banner, its colour bleed,
/// its reflection, the sunken SID and the emblem.
class OfficialFleetHoloBannerImage extends StatelessWidget {
  const OfficialFleetHoloBannerImage(this.art, {super.key});

  final OrganizationHoloArt? art;

  @override
  Widget build(BuildContext context) {
    final placeholder = _BannerPlaceholder(
      light: Theme.of(context).brightness == Brightness.light,
    );
    return ColoredBox(
      color: context.tokens.surfaces.raised.fill,
      child: art == null
          ? placeholder
          : art!.image(
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// No banner, or it failed to load: a picture of slanted glass panes on a dim
/// gradient. Drawn live, these took the raster thread past the frame on every
/// screen switch and the process over 3 GB when maximized (user report and lab,
/// 2026-10-31). See docs/brand-assets/default-banner/README.md.
class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder({required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) => Image.asset(
    light
        ? 'assets/brand/default_banner_light.png'
        : 'assets/brand/default_banner_dark.png',
    key: const Key('official-fleet-holo-banner-placeholder'),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// Banner colour bleeding onto the deck (heavily blurred, decoded small).
class OfficialFleetHoloAmbient extends StatelessWidget {
  const OfficialFleetHoloAmbient(this.art, {super.key});

  final OrganizationHoloArt art;

  @override
  // Performance (2026-10-24): a 12-pixel decode drawn large is the blur; no
  // image filter or Opacity layer recomputed on every frame.
  Widget build(BuildContext context) => art.image(
    cacheWidth: 12,
    alignment: Alignment.bottomCenter,
    filterQuality: FilterQuality.high,
    opacity: AlwaysStoppedAnimation(
      Theme.of(context).brightness == Brightness.light ? .42 : .62,
    ),
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

/// The banner reflected in the deck: flipped, slightly blurred, fading out.
class OfficialFleetHoloMirror extends StatelessWidget {
  const OfficialFleetHoloMirror(this.art, {required this.light, super.key});

  final OrganizationHoloArt art;
  final bool light;

  @override
  // Performance (2026-10-24): the slight blur comes from a smaller decode and
  // the opacity from the image itself; only the fade keeps one mask layer.
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0, .22, .52],
      colors: [
        OfficialFleetHoloPalette.fadeOpaque,
        OfficialFleetHoloPalette.fadeHalf,
        OfficialFleetHoloPalette.fadeClear,
      ],
    ).createShader(bounds),
    child: Transform.flip(
      flipY: true,
      child: art.image(
        cacheWidth: 640,
        filterQuality: FilterQuality.high,
        opacity: AlwaysStoppedAnimation(light ? .34 : .6),
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}

/// The SID as outlined giant type, sunk into the reflection. At rest it is
/// exactly the approved outline. [reveal] drives its entrance: on the full
/// entry ([detailed]) each letter glitches in -- it flickers, is torn into
/// horizontally shifted bands and split into fleet-colour/white ghosts --
/// and settles to the plain outline. The glitch is deterministic (no random
/// state), so every run and every test frame is the same.
class OfficialFleetHoloGhostSid extends StatelessWidget {
  const OfficialFleetHoloGhostSid(
    this.sid, {
    required this.size,
    required this.light,
    required this.reveal,
    required this.accent,
    this.detailed = true,
    super.key,
  });

  final String sid;
  final double size;
  final bool light;
  final Animation<double> reveal;
  final Color accent;
  final bool detailed;

  static double _noise(int a, int b) =>
      (((a + 1) * 73856093) ^ ((b + 7) * 19349663)) % 1000 / 1000;

  @override
  Widget build(BuildContext context) {
    final ink = light
        ? OfficialFleetHoloPalette.outlineLight
        : OfficialFleetHoloPalette.outlineDark;
    final glitchWhite = Colors.white.withValues(alpha: light ? .5 : .75);
    final letters = sid.characters.toList();
    final glyphStyle = TextStyle(
      fontFamily: 'Source Sans 3',
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: 6,
    );
    Widget glyph(
      String letter,
      Color color, {
      bool fill = false,
      bool fade = false,
    }) => fill
        ? Text(
            letter,
            maxLines: 1,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: glyphStyle.copyWith(color: color),
          )
        : OfficialFleetOutlineText(
            letter,
            style: glyphStyle,
            color: color,
            strokeWidth: 1.5,
            fade: fade,
          );
    Widget letter(int index, String character, double t, bool settled) {
      // Letters start one after another and overlap.
      final count = letters.length;
      final begin = count <= 1 ? 0.0 : index * .5 / (count - 1);
      final p = ((t - begin) / .5).clamp(0.0, 1.0);
      final rest = glyph(character, ink, fade: settled);
      if (p >= 1) return rest;
      if (p <= 0) return Opacity(opacity: 0, child: rest);
      if (!detailed) return Opacity(opacity: p, child: rest);
      // Twelve steps per letter; early steps are mostly dark, late ones lit.
      final step = (p * 12).floor();
      final calm = Curves.easeIn.transform(p);
      if (_noise(index, step) > .25 + .75 * calm) {
        return Opacity(opacity: 0, child: rest);
      }
      final tear = 18 * (1 - calm);
      final split = 6 * (1 - calm);
      Widget band(int band, double from, double to) => ClipRect(
        clipper: _GlitchBand(from, to),
        child: Transform.translate(
          offset: Offset((_noise(index * 3 + band, step) - .5) * 2 * tear, 0),
          child: rest,
        ),
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(-split, 0),
            child: Opacity(
              opacity: .8 * (1 - calm),
              child: glyph(character, accent),
            ),
          ),
          Transform.translate(
            offset: Offset(split, 0),
            child: Opacity(
              opacity: .6 * (1 - calm),
              child: glyph(character, glitchWhite),
            ),
          ),
          // A brief flash of fill on some steps.
          if (_noise(index + 11, step) > .78)
            Opacity(
              opacity: .3 * (1 - calm),
              child: glyph(character, accent, fill: true),
            ),
          band(0, 0, .38),
          band(1, .38, .62),
          band(2, .62, 1),
        ],
      );
    }

    // Performance (2026-10-24): once the letters have arrived the fade is
    // baked into each outline image; the mask layer exists only during entry.
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, _) {
        final settled = reveal.value >= 1;
        final row = Transform(
          transform: Matrix4.skewX(-12 * math.pi / 180),
          child: Row(
            key: const Key('official-fleet-holo-ghost-sid'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, character) in letters.indexed)
                letter(index, character, reveal.value, settled),
            ],
          ),
        );
        if (settled) return row;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [.3, 1],
            colors: [
              OfficialFleetHoloPalette.fadeOpaque,
              OfficialFleetHoloPalette.fadeClear,
            ],
          ).createShader(bounds),
          child: row,
        );
      },
    );
  }
}

/// One horizontal band of a glyph, wide enough to keep a torn slice visible.
class _GlitchBand extends CustomClipper<Rect> {
  const _GlitchBand(this.from, this.to);

  final double from, to;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, size.height * from, size.width + 40, size.height * to);

  @override
  bool shouldReclip(_GlitchBand oldClipper) =>
      oldClipper.from != from || oldClipper.to != to;
}

class OfficialFleetHoloEmblem extends StatelessWidget {
  const OfficialFleetHoloEmblem(this.fleet, {super.key});

  final OfficialFleetSummary fleet;

  @override
  Widget build(BuildContext context) => OrganizationHoloEmblem(
    OrganizationHoloArt.fromUrl(fleet.displayLogoUrl),
    fallback: fleet.sid,
    key: const Key('official-fleet-logo'),
  );
}

/// An organization's logo, or the first two letters of its code.
class OrganizationHoloEmblem extends StatelessWidget {
  const OrganizationHoloEmblem(this.art, {required this.fallback, super.key});

  final OrganizationHoloArt? art;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final initials = ColoredBox(
      color: context.tokens.domainColors.command.soft,
      child: Center(child: Text(fallback.characters.take(2).toString())),
    );
    return art == null
        ? initials
        : art!.image(errorBuilder: (_, _, _) => initials);
  }
}

/// Holds the title glass's backdrop blur off while the screen switch runs.
/// The switch fades the whole upper screen, and a blur inside that fading
/// layer renders the screen offscreen on every frame (user report
/// 2026-10-27: a clear stutter just before the switch back ends).
class OfficialFleetHoloGlassHold extends InheritedWidget {
  const OfficialFleetHoloGlassHold({
    required this.hold,
    required super.child,
    super.key,
  });

  final bool hold;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OfficialFleetHoloGlassHold>()
          ?.hold ??
      false;

  @override
  bool updateShouldNotify(OfficialFleetHoloGlassHold oldWidget) =>
      hold != oldWidget.hold;
}
