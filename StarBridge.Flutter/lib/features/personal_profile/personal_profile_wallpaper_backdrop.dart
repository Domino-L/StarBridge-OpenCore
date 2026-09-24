import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_wallpaper_catalog.dart';

class PersonalProfileWallpaperBackdrop extends StatelessWidget {
  const PersonalProfileWallpaperBackdrop({
    required this.wallpaperId,
    super.key,
  });

  final String wallpaperId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final preset = PersonalProfileWallpaperCatalog.resolve(wallpaperId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox.expand(
      key: Key('profile-wallpaper-${preset.id}'),
      child: preset.assetPath == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    tokens.domainColors.ship.soft,
                    tokens.surfaces.ground.fill,
                  ],
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  preset.assetPath!,
                  key: const Key('profile-wallpaper-image'),
                  cacheWidth: 2560,
                  fit: BoxFit.cover,
                  alignment: preset.focalAlignment,
                  errorBuilder: (context, error, stackTrace) =>
                      ColoredBox(color: tokens.surfaces.ground.fill),
                ),
                ColoredBox(
                  key: const Key('profile-wallpaper-scrim'),
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.04),
                ),
              ],
            ),
    );
  }
}
