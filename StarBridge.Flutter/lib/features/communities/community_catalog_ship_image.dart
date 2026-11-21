import '../../design_system/icons/standard_icon.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ships_copy.dart';
import '../../shared/ships/scm_ship_thumbnail.dart';

/// Catalog-only artwork; legacy custom images never participate in fallback.
class CommunityCatalogShipImage extends StatelessWidget {
  const CommunityCatalogShipImage({
    required this.asset,
    this.model,
    this.compact = false,
    super.key,
  });
  final String? asset;
  final String? model;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Center(
      child: compact
          ? StandardIcon(
              StandardIconSemantic.rocketLaunch,
              color: context.tokens.colors.textSecondary,
            )
          : Text(
              communityShipsText(context, 'noImage'),
              textAlign: TextAlign.center,
            ),
    );
    Widget missing() => model == null
        ? fallback()
        : ScmShipThumbnail(
            model: model!,
            placeholder: fallback(),
            compact: compact,
            fit: compact ? BoxFit.cover : BoxFit.contain,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: asset == null
          ? missing()
          : Image.asset(
              asset!,
              fit: compact ? BoxFit.cover : BoxFit.contain,
              excludeFromSemantics: compact,
              errorBuilder: (_, _, _) => missing(),
            ),
    );
  }
}
