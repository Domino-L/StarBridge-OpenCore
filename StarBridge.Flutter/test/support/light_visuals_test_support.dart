import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

Widget lightVisualsApp(
  Widget child, {
  AppearanceMode mode = AppearanceMode.dark,
}) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(mode),
    const Locale('en'),
  ),
  home: Scaffold(body: child),
);

/// The app's string delegate loads asynchronously, so the first frame after
/// pumpWidget has no page yet; one more pump builds the real tree.
Future<void> pumpLightVisuals(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
}

/// Opacity layers that cost an offscreen pass. The app shell keeps fully
/// opaque fade layers (alpha 255), which the engine draws directly.
Iterable<OpacityLayer> fractionalOpacityLayers(WidgetTester tester) => tester
    .layers
    .whereType<OpacityLayer>()
    .where((layer) => (layer.alpha ?? 255) > 0 && (layer.alpha ?? 255) < 255);
