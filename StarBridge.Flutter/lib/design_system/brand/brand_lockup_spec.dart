import 'package:flutter/material.dart';

enum BrandLockupScale { navigationCompact, navigationExpanded, display }

@immutable
final class BrandLockupSpec {
  const BrandLockupSpec({
    required this.markAsset,
    required this.markSize,
    required this.wordmarkHeight,
    required this.gap,
    required this.safePadding,
    this.wordmarkAsset,
  });

  final String markAsset;
  final String? wordmarkAsset;
  final double markSize;
  final double wordmarkHeight;
  final double gap;
  final EdgeInsets safePadding;
}

abstract final class BrandLockupResolver {
  static const _assetRoot = 'assets/brand';

  static BrandLockupSpec resolve({
    required Locale locale,
    required Brightness surfaceBrightness,
    required BrandLockupScale scale,
  }) {
    final darkSurface = surfaceBrightness == Brightness.dark;
    final mark = darkSurface
        ? '$_assetRoot/starbridge_mark_dark_surface.png'
        : '$_assetRoot/starbridge_mark_light_surface.png';
    final wordmark = _wordmarkFor(locale, darkSurface);
    return switch (scale) {
      BrandLockupScale.navigationCompact => BrandLockupSpec(
        markAsset: mark,
        markSize: 34,
        wordmarkHeight: 0,
        gap: 0,
        safePadding: const EdgeInsets.all(4),
      ),
      BrandLockupScale.navigationExpanded => BrandLockupSpec(
        markAsset: mark,
        wordmarkAsset: wordmark,
        markSize: 34,
        wordmarkHeight: 22,
        gap: 10,
        safePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      BrandLockupScale.display => BrandLockupSpec(
        markAsset: mark,
        wordmarkAsset: wordmark,
        markSize: 72,
        wordmarkHeight: 42,
        gap: 16,
        safePadding: const EdgeInsets.all(12),
      ),
    };
  }

  static String _wordmarkFor(Locale locale, bool darkSurface) {
    final language = _usesSimplifiedChineseBrand(locale) ? 'zh_hans' : 'en';
    final surface = darkSurface ? 'dark_surface' : 'light_surface';
    return '$_assetRoot/starbridge_wordmark_${language}_text_only_$surface.png';
  }

  static bool _usesSimplifiedChineseBrand(Locale locale) {
    if (locale.languageCode.toLowerCase() != 'zh') {
      return false;
    }
    final script = locale.scriptCode?.toLowerCase();
    final country = locale.countryCode?.toUpperCase();
    if (script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO') {
      return false;
    }
    return true;
  }
}
