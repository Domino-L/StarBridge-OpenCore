import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../feature_registry.dart';
import '../localization/app_strings.dart';

/// A truthful destination for a product area whose feature work is deferred.
///
/// It intentionally exposes no action controls. Keeping this as a real route
/// preserves navigation and deep-link stability without suggesting that an
/// unavailable capability already works.
class DeferredDestination extends StatelessWidget {
  const DeferredDestination({
    required this.destinationKey,
    required this.icon,
    required this.bodyKey,
    super.key,
  });

  final String destinationKey;
  final StarBridgeIconSemantic icon;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final panel = tokens.surfaces.panel;

    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.density.pagePadding),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Container(
            key: Key('$destinationKey-deferred-destination'),
            padding: EdgeInsets.all(tokens.density.panelPadding),
            decoration: BoxDecoration(
              color: panel.fill,
              border: Border.all(
                color: panel.border,
                width: tokens.stroke.hairline,
              ),
              borderRadius: tokens.shape.medium,
              boxShadow: panel.shadows,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.colors.accentSoft,
                    borderRadius: tokens.shape.small,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(tokens.space.sm),
                    child: StarBridgeIcon(
                      icon,
                      size: tokens.icons.large,
                      color: tokens.colors.accent,
                    ),
                  ),
                ),
                SizedBox(width: tokens.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.text('deferredFeature.title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: tokens.space.xs),
                      Text(
                        strings.text(bodyKey),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: tokens.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
