import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/styles/hangar_wall_palette.dart';
import 'local_hangar_card_image.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_presentation.dart';

/// The stage picture, always whole. A picture narrower than the stage sits in
/// the middle at full height and fades out at its own edges, over the stage's
/// soft backdrop of the same picture; one about as wide as the stage, or a
/// little wider, fills it. Only a picture far wider than the stage keeps bands
/// above and below.
class LocalHangarStageFill extends StatefulWidget {
  const LocalHangarStageFill({
    required this.item,
    required this.width,
    required this.height,
    required this.placeholder,
    required this.imagePort,
    required this.cache,
    required this.cacheKey,
    super.key,
  });
  final LocalHangarPresentation item;
  final double width, height;
  final Widget placeholder;
  final LocalHangarImagePort? imagePort;
  final LocalHangarImageCache cache;
  final String cacheKey;

  /// Filling a stage this much narrower than the picture crops little enough.
  static const fillTolerance = 1.2;

  /// A picture this little narrower than the stage fills it too: the few rows
  /// cropped are worth more than two thin soft bands.
  static const narrowTolerance = 1.06;

  /// Reads a picture's shape ahead of showing it, for the ships either side.
  static void prepare(String asset) =>
      unawaited(_LocalHangarStageFillState.read(asset));

  /// Where the picture goes in a stage of [box]. Without a known shape it
  /// fills the box whole, as the picture is still on its way.
  static LocalHangarStageArtLayout layoutFor(double? aspect, Size box) {
    final w = box.width, h = box.height, ratio = w / h;
    if (aspect == null || aspect <= 0) {
      return LocalHangarStageArtLayout(box, fill: true, fadeAcross: true);
    }
    if (aspect < ratio && ratio / aspect > narrowTolerance) {
      return LocalHangarStageArtLayout(
        Size(h * aspect, h),
        fill: false,
        fadeAcross: true,
      );
    }
    if (aspect > ratio && aspect / ratio > fillTolerance) {
      return LocalHangarStageArtLayout(
        Size(w, w / aspect),
        fill: false,
        fadeAcross: false,
      );
    }
    return LocalHangarStageArtLayout(box, fill: true, fadeAcross: true);
  }

  /// Strength of the soft backdrop that carries the picture past its edges.
  static const backdropDark = .8, backdropLight = .6;

  /// Softening of that backdrop, in logical pixels.
  static const backdropBlur = 28.0;

  /// Fade at each edge, as a share of the drawn picture.
  static const edgeFade = .06;

  @override
  State<LocalHangarStageFill> createState() => _LocalHangarStageFillState();
}

/// Drawn size of the stage picture, whether it is cropped to fill, and
/// whether it fades out at its left and right edges or at top and bottom.
@immutable
class LocalHangarStageArtLayout {
  const LocalHangarStageArtLayout(
    this.size, {
    required this.fill,
    required this.fadeAcross,
  });
  final Size size;
  final bool fill, fadeAcross;
}

class _LocalHangarStageFillState extends State<LocalHangarStageFill> {
  // Width over height of each bundled picture, read once from its header.
  static final _bundled = <String, double>{};
  Uint8List? _custom;
  double? _customAspect;

  @override
  void initState() {
    super.initState();
    _readBundled();
  }

  @override
  void didUpdateWidget(LocalHangarStageFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.bundledImage != widget.item.bundledImage) {
      _readBundled();
    }
    if (oldWidget.cacheKey != widget.cacheKey) {
      _custom = null;
      _customAspect = null;
    }
  }

  void _readBundled() {
    final asset = widget.item.bundledImage;
    if (asset == null || _bundled.containsKey(asset)) return;
    unawaited(
      _LocalHangarStageFillState.read(asset).then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  static final _reading = <String, Future<void>>{};

  /// Reads the shape of a bundled picture once; later calls share the read.
  static Future<void> read(String asset) {
    if (_bundled.containsKey(asset)) return Future.value();
    return _reading[asset] ??= () async {
      try {
        final data = await rootBundle.load(asset);
        final aspect = await _aspectOf(data.buffer.asUint8List());
        if (aspect != null) _bundled[asset] = aspect;
      } catch (_) {
        /* Without the size the picture stays whole in the full box. */
      } finally {
        _reading.remove(asset);
      }
    }();
  }

  void _onCustom(Uint8List? bytes) {
    if (identical(bytes, _custom)) return;
    _custom = bytes;
    _customAspect = null;
    if (bytes == null) {
      if (mounted) setState(() {});
      return;
    }
    unawaited(() async {
      final aspect = await _aspectOf(bytes);
      if (mounted && identical(bytes, _custom)) {
        setState(() => _customAspect = aspect);
      }
    }());
  }

  static Future<double?> _aspectOf(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final aspect = descriptor.height == 0
          ? null
          : descriptor.width / descriptor.height;
      descriptor.dispose();
      return aspect;
    } finally {
      buffer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = widget.height;
    final asset = widget.item.bundledImage;
    final aspect = _custom != null
        ? _customAspect
        : (asset == null ? null : _bundled[asset]);
    final art = LocalHangarStageFill.layoutFor(aspect, Size(w, h));
    final drawW = art.size.width, drawH = art.size.height, fill = art.fill;
    final horizontal = art.fadeAcross;
    final image = LocalHangarCardImage(
      key: ValueKey('hangar-stage-image:${widget.cacheKey}'),
      item: widget.item,
      width: drawW,
      height: drawH,
      fit: fill ? BoxFit.cover : BoxFit.contain,
      placeholder: widget.placeholder,
      imagePort: widget.imagePort,
      cache: widget.cache,
      cacheKey: widget.cacheKey,
      onCustomImage: _onCustom,
    );
    // Until the size is known the picture waits rather than jump into place.
    final waiting = aspect == null && (asset != null || _custom != null);
    final picture = Center(
      child: SizedBox(
        width: drawW,
        height: drawH,
        child: Opacity(
          opacity: waiting ? 0 : 1,
          child: ShaderMask(
            key: const ValueKey('hangar-stage-edge-fade'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
              end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
              stops: const [
                0,
                LocalHangarStageFill.edgeFade,
                1 - LocalHangarStageFill.edgeFade,
                1,
              ],
              colors: const [
                HangarWallPalette.artScrimClear,
                HangarWallPalette.onArt,
                HangarWallPalette.onArt,
                HangarWallPalette.artScrimClear,
              ],
            ).createShader(rect),
            child: image,
          ),
        ),
      ),
    );
    final custom = _custom;
    if (custom == null) return picture;
    // The stage backdrop is drawn from the catalog picture; the player's own
    // picture carries its own colors past its edges instead.
    final palette = HangarWallPalette.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          key: const ValueKey('hangar-stage-own-backdrop'),
          color: palette.stageGround,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: LocalHangarStageFill.backdropBlur,
              sigmaY: LocalHangarStageFill.backdropBlur,
              tileMode: TileMode.clamp,
            ),
            child: Image.memory(
              custom,
              fit: BoxFit.cover,
              cacheWidth: 48,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              opacity: AlwaysStoppedAnimation(
                palette.isDark
                    ? LocalHangarStageFill.backdropDark
                    : LocalHangarStageFill.backdropLight,
              ),
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        picture,
      ],
    );
  }
}
