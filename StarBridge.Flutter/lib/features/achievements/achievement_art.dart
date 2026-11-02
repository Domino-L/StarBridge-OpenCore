import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/achievement_art_palette.dart';
import 'achievement_catalog.dart';
import 'scm_flat_svg.dart';
import 'scm_holiday_art.dart';
import '../../shared/remote_image.dart';

class AchievementArt extends StatelessWidget {
  const AchievementArt({
    required this.definition,
    required this.earned,
    required this.size,
    super.key,
  });

  final AchievementDefinition definition;
  final bool earned;
  final double size;
  static const _fallback = Center(
    child: StarBridgeIcon(
      StarBridgeIconSemantic.achievement,
      size: 32,
      color: AchievementArtPalette.fallbackIcon,
    ),
  );

  Widget _scmFallback() => earned && definition.remoteImageUrl != null
      ? RemoteImage(
          definition.remoteImageUrl!,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => _fallback,
        )
      : _fallback;

  @override
  Widget build(BuildContext context) {
    final scmArt = scmAchievementArtAsset(
      definition,
      earned: earned,
      logicalSize: size,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: AchievementArtPalette.background,
          child: scmArt != null
              ? scmArt.vector
                    ? ExcludeSemantics(
                        child: ScmFlatSvg(
                          scmArt.path,
                          fallback: _scmFallback(),
                        ),
                      )
                    : Image.asset(
                        scmArt.path,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => _scmFallback(),
                      )
              : definition.source == AchievementSource.scm
              ? _scmFallback()
              : definition.hidden &&
                    !earned &&
                    definition.hiddenLockedAsset == null
              ? const Center(
                  child: StarBridgeIcon(
                    StarBridgeIconSemantic.achievement,
                    size: 32,
                    color: AchievementArtPalette.fallbackIcon,
                  ),
                )
              : Image.asset(
                  !earned && definition.hidden
                      ? definition.hiddenLockedAsset!
                      : definition.artAsset(
                          earned: earned,
                          logicalSize: size,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(
                            context,
                          ),
                        ),
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  // Dedicated paired artwork preserves the approved outline and
                  // hidden visor scene. Never substitute a runtime grayscale filter.
                  errorBuilder: (_, _, _) => const Center(
                    child: StarBridgeIcon(
                      StarBridgeIconSemantic.achievement,
                      size: 32,
                      color: AchievementArtPalette.fallbackIcon,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
