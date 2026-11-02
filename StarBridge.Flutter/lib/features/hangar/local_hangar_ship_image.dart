import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';

class LocalHangarShipImage extends StatelessWidget {
  const LocalHangarShipImage({
    required this.item,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    super.key,
  });
  final LocalHangarPresentation item;
  final double width, height;
  final BoxFit fit;

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

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: tokens.shape.small,
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: tokens.surfaces.ground.fill,
            child: item.bundledImage == null
                ? measured(LoadingContentStatus.unavailable, fallback())
                : Image.asset(
                    item.bundledImage!,
                    fit: fit,
                    excludeFromSemantics: true,
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    frameBuilder: (_, child, frame, synchronouslyLoaded) =>
                        frame != null || synchronouslyLoaded
                        ? measured(LoadingContentStatus.data, child)
                        : measured(LoadingContentStatus.waiting, fallback()),
                    errorBuilder: (_, _, _) =>
                        measured(LoadingContentStatus.failed, fallback()),
                  ),
          ),
        ),
      ),
    );
  }
}
