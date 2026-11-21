import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';
import '../../shared/ships/scm_ship_thumbnail.dart';

class LocalHangarShipImage extends StatelessWidget {
  const LocalHangarShipImage({
    required this.item,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    this.tint,
    this.sharp = false,
    super.key,
  });
  final LocalHangarPresentation item;
  final double width, height;
  final BoxFit fit;

  /// Painted over the artwork without a layer, so a wall of cards stays cheap.
  final Color? tint;

  /// For artwork drawn much smaller than its file. Decoding exactly at display
  /// size goes in one bilinear step, and a wider picture cropped to the box then
  /// has to be enlarged again: both read as soft. Decode at twice the size and
  /// let the mipmapped filter do the last step.
  final bool sharp;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    Widget fallback() => StarBridgeTooltip(
      message: c.imageUnavailable,
      child: Center(
        child: StarBridgeIcon(
          StarBridgeIconSemantic.hangar,
          color: tokens.colors.textSecondary,
          size: 24,
        ),
      ),
    );
    Widget measured(LoadingContentStatus status, Widget child) {
      final metrics = LoadingMetrics.current;
      if (metrics == null || metrics.stopped) return child;
      return LoadingContentProbe(
        route: '/hangar',
        visualPart: LoadingVisualPart.hangarThumbnail,
        status: status,
        items: status == LoadingContentStatus.data ? 1 : 0,
        child: child,
      );
    }

    Widget missing(LoadingContentStatus status) => ScmShipThumbnail(
      model: item.ship.title,
      fit: fit,
      compact: true,
      placeholder: measured(status, fallback()),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: tokens.shape.small,
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: tokens.surfaces.ground.fill,
            child: item.bundledImage == null
                ? missing(LoadingContentStatus.unavailable)
                : Image.asset(
                    item.bundledImage!,
                    fit: fit,
                    color: tint,
                    colorBlendMode: tint == null ? null : BlendMode.srcATop,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    filterQuality: sharp
                        ? FilterQuality.medium
                        : FilterQuality.low,
                    cacheWidth:
                        (width *
                                MediaQuery.devicePixelRatioOf(context) *
                                (sharp ? 2 : 1))
                            .ceil(),
                    frameBuilder: (_, child, frame, synchronouslyLoaded) =>
                        frame != null || synchronouslyLoaded
                        ? measured(LoadingContentStatus.data, child)
                        : measured(LoadingContentStatus.waiting, fallback()),
                    errorBuilder: (_, _, _) =>
                        missing(LoadingContentStatus.failed),
                  ),
          ),
        ),
      ),
    );
  }
}
