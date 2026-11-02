import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_layers.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';

const _probe = Color(0xFF00FF00);
const _banner = 300.0;

// The upper screen's title band rises 30px into the banner, like the holo
// header's slab. The shrinking deck must never paint over it mid-switch.
Widget _app(bool lower, {List<bool>? holds}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: RepaintBoundary(
    key: const Key('capture'),
    child: Scaffold(
      body: OfficialFleetScreenSwitch(
        lower: lower,
        upper: (context) => Stack(
          children: [
            if (holds != null)
              Builder(
                builder: (context) {
                  holds.add(OfficialFleetHoloGlassHold.of(context));
                  return const SizedBox.shrink();
                },
              ),
            Positioned(
              left: 0,
              right: 0,
              top: _banner - 30,
              height: 60,
              child: const ColoredBox(color: _probe),
            ),
          ],
        ),
        lowerBuilder: (_) => const SizedBox.expand(),
        banner: null,
        bannerHeight: _banner,
      ),
    ),
  ),
);

Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  late Color color;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.round() * image.width + at.dx.round()) * 4;
    color = Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    image.dispose();
  });
  return color;
}

void main() {
  for (final (label, from, to) in [
    ('to the lower screen', false, true),
    ('back to the upper screen', true, false),
  ]) {
    testWidgets('the title band over the banner edge stays whole $label', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(from));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(to));
      // The first moving frame: the upper screen is still fully shown and
      // the deck sits exactly on the banner, where the band overlaps it.
      await tester.pump(Duration(milliseconds: from ? 518 : 2));
      expect(
        find.byKey(const ValueKey('official-fleet-upper-screen')),
        findsOneWidget,
      );
      final inside = await _pixel(tester, const Offset(640, _banner - 15));
      expect(
        inside.g > .8 && inside.r < .2,
        isTrue,
        reason: 'Banner overlap of the title band is painted over: $inside',
      );
      await tester.pumpAndSettle();
    });
  }

  testWidgets('the title glass holds its blur only while the switch runs', (
    tester,
  ) async {
    // User report 2026-10-27: a stutter just before the switch back ends.
    final holds = <bool>[];
    await tester.pumpWidget(_app(true, holds: holds));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(false, holds: holds));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump(OfficialFleetScreenSwitch.duration ~/ 2);
    expect(holds.last, isTrue);
    await tester.pumpAndSettle();
    expect(holds.last, isFalse);
  });
}
