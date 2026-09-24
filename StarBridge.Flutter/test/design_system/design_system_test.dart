import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/brand/brand_lockup_spec.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon_set.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/styles/probe_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

void main() {
  test('Direction A is the only selectable style and resolves both modes', () {
    final registry = StyleRegistry();
    expect(registry.userSelectable.map((item) => item.id), [
      FutureRestraintStyle.id,
    ]);
    for (final mode in AppearanceMode.values) {
      final result = registry.resolve(FutureRestraintStyle.id, mode);
      expect(result.didFallback, isFalse);
      expect(result.tokens.appearanceMode, mode);
      expect(result.tokens.styleId, FutureRestraintStyle.id);
    }
  });

  test('unknown styles fall back visibly without changing appearance mode', () {
    final result = StyleRegistry().resolve(
      'missing-style',
      AppearanceMode.light,
    );
    expect(result.didFallback, isTrue);
    expect(result.fallbackReason, 'style_not_registered');
    expect(result.tokens.styleId, FutureRestraintStyle.id);
    expect(result.tokens.appearanceMode, AppearanceMode.light);
  });

  test('probe changes every visual axis and is never user selectable', () {
    final registry = StyleRegistry();
    final base = registry
        .resolve(FutureRestraintStyle.id, AppearanceMode.dark)
        .tokens;
    final probe = registry.resolve(ProbeStyle.id, AppearanceMode.dark).tokens;
    expect(
      registry.userSelectable.any((item) => item.id == ProbeStyle.id),
      isFalse,
    );
    expect(probe.shape.radiusMedium, isNot(base.shape.radiusMedium));
    expect(probe.typography.body, isNot(base.typography.body));
    expect(probe.space.md, isNot(base.space.md));
    expect(probe.stroke.regular, isNot(base.stroke.regular));
    expect(probe.motion.pointerPageSwap, Duration.zero);
    expect(probe.icons.medium, isNot(base.icons.medium));
    expect(probe.colors.accent, isNot(base.colors.accent));
  });

  test('dark and light use independent surface-level mechanisms', () {
    final dark = FutureRestraintStyle.resolve(AppearanceMode.dark);
    final light = FutureRestraintStyle.resolve(AppearanceMode.light);
    expect(dark.surfaces.panel.shadows, isEmpty);
    expect(light.surfaces.panel.shadows, isNotEmpty);
    expect(dark.surfaces.panel.fill, isNot(dark.surfaces.raised.fill));
    expect(light.surfaces.panel.fill, isNot(light.surfaces.raised.fill));
  });

  test('contrast floors hold for both modes', () {
    for (final mode in AppearanceMode.values) {
      final tokens = FutureRestraintStyle.resolve(mode);
      final ground = tokens.surfaces.ground.fill;
      expect(
        _contrast(tokens.colors.textPrimary, ground),
        greaterThanOrEqualTo(7),
      );
      expect(
        _contrast(tokens.colors.textSecondary, ground),
        greaterThanOrEqualTo(5.5),
      );
      expect(
        _contrast(tokens.surfaces.panel.border, ground),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(tokens.colors.focusRing, ground),
        greaterThanOrEqualTo(3),
      );
    }
  });

  test('reduced motion keeps final state but removes functional movement', () {
    final base = FutureRestraintStyle.resolve(AppearanceMode.dark);
    final reduced = base.withReducedMotion(true);
    expect(base.motion.pointerPageSwap, isNot(Duration.zero));
    expect(reduced.motion.pointerPageSwap, Duration.zero);
    expect(reduced.motion.surfaceEnter, Duration.zero);
    expect(reduced.motion.pageOffset, 0);
    expect(reduced.motion.splashEnabled, isFalse);
    expect(reduced.motion.keyboard, Duration.zero);
  });

  test('locale-specific font and brand fallbacks are explicit', () {
    final typography = FutureRestraintStyle.typography;
    expect(
      typography.fallbacksFor(const Locale('zh', 'CN')).first,
      'Source Han Sans CN',
    );
    expect(
      typography
          .fallbacksFor(
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          )
          .first,
      'Microsoft JhengHei UI',
    );

    final simplified = BrandLockupResolver.resolve(
      locale: const Locale('zh', 'CN'),
      surfaceBrightness: Brightness.dark,
      scale: BrandLockupScale.navigationExpanded,
    );
    final traditional = BrandLockupResolver.resolve(
      locale: const Locale('zh', 'TW'),
      surfaceBrightness: Brightness.dark,
      scale: BrandLockupScale.navigationExpanded,
    );
    expect(simplified.wordmarkAsset, contains('zh_hans'));
    expect(traditional.wordmarkAsset, contains('wordmark_en'));
  });

  test('every semantic icon resolves through the StarBridge outline set', () {
    expect(FutureRestraintStyle.icons.setId, StarBridgeIconSet.id);
    expect(FutureRestraintStyle.icons.small, 16);
    expect(FutureRestraintStyle.icons.medium, 20);
    expect(FutureRestraintStyle.icons.large, 24);
    for (final semantic in StarBridgeIconSemantic.values) {
      final glyph = StarBridgeIconSet.resolve(semantic);
      expect(glyph.semantic, semantic);
    }
  });

  test('ThemeData is derived from and retains the resolved token package', () {
    final tokens = FutureRestraintStyle.resolve(AppearanceMode.dark);
    final theme = buildStarBridgeTheme(tokens, const Locale('zh', 'CN'));
    expect(theme.extension<StarBridgeTokens>(), same(tokens));
    expect(theme.scaffoldBackgroundColor, tokens.surfaces.ground.fill);
    expect(theme.brightness, Brightness.dark);
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
