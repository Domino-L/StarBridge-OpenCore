import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/classic_font_scope.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

const _cn = Locale('zh', 'CN');

ThemeData _theme([AppearanceMode mode = AppearanceMode.dark]) =>
    buildStarBridgeTheme(
      StyleRegistry()
          .resolve(AppPreferences.defaults.designStyleId, mode)
          .tokens,
      _cn,
    );

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  setUpAll(() async {
    for (final font in <String, String>{
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  test('数字和西文用 Saira，标题用 Rajdhani，中文仍是思源', () {
    final text = _theme().textTheme;
    for (final style in [text.bodyMedium, text.bodySmall, text.labelLarge]) {
      expect(style!.fontFamily, 'Saira');
      expect(style.fontFamilyFallback!.first, 'Source Han Sans CN');
    }
    for (final style in [
      text.displaySmall,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
    ]) {
      expect(style!.fontFamily, 'Rajdhani');
      expect(style.fontFamilyFallback!.first, 'Source Han Sans CN');
    }
  });

  test('数字位用的等宽字体也换成 Saira，并保留原等宽字体兜底', () {
    final typography = _theme().extension<StarBridgeTokens>()!.typography;
    expect(typography.monoFamily, 'Saira');
    expect(typography.monoFallbacks.first, 'Source Code Pro');
  });

  test('Saira 的数字真的等宽', () {
    final style = _theme().textTheme.bodyMedium!;
    expect(_width('1111', style), _width('8888', style));
    final proportional = style.copyWith(fontFeatures: const <FontFeature>[]);
    expect(
      _width('1111', proportional),
      isNot(_width('8888', proportional)),
    );
  });

  test('中文保持 Saira 原宽，其他语言收窄到原字体的宽度', () {
    expect(_theme().textTheme.bodyMedium!.fontVariations, isNull);
    final english = buildStarBridgeTheme(
      StyleRegistry()
          .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
          .tokens,
      const Locale('en'),
    ).textTheme.bodyMedium!;
    expect(english.fontVariations, [const FontVariation('wdth', 88)]);
    const sample = 'Members Ships Chat Announcements Overview 12,171';
    final full = english.copyWith(fontVariations: const <FontVariation>[]);
    expect(_width(sample, english), lessThan(_width(sample, full)));
    final sans = buildMenuOverlayTheme(const Locale('en')).textTheme.bodyMedium!;
    expect(sans.fontVariations, isNull);
  });

  test('Saira 的自然行高和原字体一样，没写行高的文字不会变高', () {
    double lineHeight(String family) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Hg',
          style: TextStyle(fontFamily: family, fontSize: 100),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    expect(lineHeight('Saira'), closeTo(lineHeight('Source Sans 3'), 1));
    expect(_theme().textTheme.labelLarge!.height, isNull);
  });

  test('游戏内菜单保留原字体', () {
    final theme = buildMenuOverlayTheme(_cn);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Source Sans 3');
    expect(theme.textTheme.titleLarge!.fontFamily, 'Source Sans 3');
    expect(
      theme.extension<StarBridgeTokens>()!.typography.monoFamily,
      'Source Code Pro',
    );
  });

  testWidgets('全息页范围内保留原字体，颜色不变，范围外不受影响', (tester) async {
    late BuildContext inner;
    late BuildContext outer;
    final theme = _theme();
    await tester.pumpWidget(
      MaterialApp(
        locale: _cn,
        supportedLocales: const [_cn],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme,
        home: Builder(
          builder: (context) {
            outer = context;
            return ClassicFontScope(
              child: Builder(
                builder: (context) {
                  inner = context;
                  return const Text('全息');
                },
              ),
            );
          },
        ),
      ),
    );
    expect(Theme.of(outer).textTheme.bodyMedium!.fontFamily, 'Saira');
    final holo = Theme.of(inner);
    expect(holo.textTheme.bodyMedium!.fontFamily, 'Source Sans 3');
    expect(holo.textTheme.titleLarge!.fontFamily, 'Source Sans 3');
    expect(
      holo.extension<StarBridgeTokens>()!.typography.monoFamily,
      'Source Code Pro',
    );
    expect(
      holo.extension<StarBridgeTokens>()!.colors,
      theme.extension<StarBridgeTokens>()!.colors,
    );
    expect(DefaultTextStyle.of(inner).style.fontFamily, 'Source Sans 3');
  });
}
