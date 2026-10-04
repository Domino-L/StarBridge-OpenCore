import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_wallpaper_catalog.dart';

class PersonalProfileWallpaperBackdrop extends StatefulWidget {
  const PersonalProfileWallpaperBackdrop({
    required this.wallpaperId,
    super.key,
  });

  final String wallpaperId;

  @override
  State<PersonalProfileWallpaperBackdrop> createState() => _WallpaperState();
}

class _WallpaperState extends State<PersonalProfileWallpaperBackdrop> {
  Timer? _retry;
  int _attempts = 0, _generation = 0;

  @override
  void didUpdateWidget(covariant PersonalProfileWallpaperBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallpaperId != widget.wallpaperId) {
      _retry?.cancel();
      _retry = null;
      _attempts = 0;
      _generation++;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry(ImageProvider provider) {
    if (_attempts >= 2 || _retry != null) return;
    final generation = _generation;
    _retry = Timer(
      Duration(milliseconds: _attempts == 0 ? 250 : 750),
      () async {
        await provider.evict();
        if (!mounted || generation != _generation) return;
        _retry = null;
        setState(() {
          _attempts++;
          _generation++;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final preset = PersonalProfileWallpaperCatalog.resolve(widget.wallpaperId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final image = preset.assetPath == null
        ? null
        : ResizeImage.resizeIfNeeded(
            2560,
            null,
            AssetImage(
              preset.assetPath!,
              bundle: DefaultAssetBundle.of(context),
            ),
          );

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
                KeyedSubtree(
                  key: ValueKey(_generation),
                  child: Image(
                    image: image!,
                    key: const Key('profile-wallpaper-image'),
                    fit: BoxFit.cover,
                    alignment: preset.focalAlignment,
                    errorBuilder: (context, error, stackTrace) {
                      _scheduleRetry(image);
                      return ColoredBox(
                        color: tokens.surfaces.ground.fill,
                        child: _attempts < 2
                            ? null
                            : Align(
                                alignment: AlignmentDirectional.bottomEnd,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    AppStrings.of(context)
                                        .text('profile.background.loadFailed'),
                                    key: const Key('profile-wallpaper-failed'),
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
                ),
                IgnorePointer(
                  child: ColoredBox(
                    key: const Key('profile-wallpaper-scrim'),
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ],
            ),
    );
  }
}
