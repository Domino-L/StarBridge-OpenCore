import 'package:flutter/material.dart';

import '../../shared/inline_image_cache.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_models.dart';

class PersonalProfileAffiliationMark extends StatelessWidget {
  const PersonalProfileAffiliationMark({
    required this.affiliation,
    this.size = 36,
    super.key,
  });

  final PersonalProfileAffiliationSummary affiliation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = _AffiliationFallback(
      kind: affiliation.kind,
      color: _foreground(tokens),
    );
    final image = _embeddedImage(context, fallback) ?? _networkImage(fallback);
    return Container(
      key: Key('profile-affiliation-mark-${affiliation.kind.name}'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _softColor(tokens),
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.hairline,
        ),
      ),
      child: image ?? fallback,
    );
  }

  Widget? _embeddedImage(BuildContext context, Widget fallback) {
    final source = affiliation.logoImageData;
    if (source == null ||
        source.length > 699120 ||
        !(source.startsWith('data:image/png;base64,') ||
            source.startsWith('data:image/jpeg;base64,'))) {
      return null;
    }
    final image = InlineImageCacheScope.resolve(context, source);
    if (image == null) return null;
    return Image(
      image: ResizeImage.resizeIfNeeded(
        InlineImageCache.decodeWidth,
        null,
        image,
      ),
      key: Key('profile-affiliation-logo-${affiliation.kind.name}'),
      fit: BoxFit.cover,
      semanticLabel: affiliation.name,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Widget? _networkImage(Widget fallback) {
    final source = affiliation.logoUrl;
    if (source == null) return null;
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return Image.network(
      source,
      key: Key('profile-affiliation-logo-${affiliation.kind.name}'),
      fit: BoxFit.cover,
      semanticLabel: affiliation.name,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Color _foreground(StarBridgeTokens tokens) => switch (affiliation.kind) {
    PersonalProfileAffiliationKind.officialFleet =>
      tokens.domainColors.command.foreground,
    PersonalProfileAffiliationKind.featuredCommunity =>
      tokens.domainColors.logistics.foreground,
  };

  Color _softColor(StarBridgeTokens tokens) => switch (affiliation.kind) {
    PersonalProfileAffiliationKind.officialFleet =>
      tokens.domainColors.command.soft,
    PersonalProfileAffiliationKind.featuredCommunity =>
      tokens.domainColors.logistics.soft,
  };
}

class _AffiliationFallback extends StatelessWidget {
  const _AffiliationFallback({required this.kind, required this.color});

  final PersonalProfileAffiliationKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: StarBridgeIcon(
      kind == PersonalProfileAffiliationKind.officialFleet
          ? StarBridgeIconSemantic.officialFleet
          : StarBridgeIconSemantic.community,
      key: Key('profile-affiliation-fallback-${kind.name}'),
      size: context.tokens.icons.medium,
      color: color,
    ),
  );
}
