import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_holo_art.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_holo_layers.dart';

const _placeholder = Key('official-fleet-holo-banner-placeholder');

Future<void> _pump(WidgetTester tester, Widget child, Brightness brightness) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(
            brightness == Brightness.dark
                ? AppearanceMode.dark
                : AppearanceMode.light,
          ),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(body: SizedBox(width: 900, height: 300, child: child)),
      ),
    );

String _asset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byKey(_placeholder));
  return (image.image as AssetImage).assetName;
}

void main() {
  for (final name in ['dark', 'light']) {
    test('the $name picture is a 2560 by 854 still', () async {
      final bytes = File(
        'assets/brand/default_banner_$name.png',
      ).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (2560, 854));
      expect(codec.frameCount, 1);
      frame.image.dispose();
      codec.dispose();
    });
  }

  testWidgets('no banner shows the picture of the theme, drawn from no code', (
    tester,
  ) async {
    await _pump(
      tester,
      const OfficialFleetHoloBannerImage(null),
      Brightness.dark,
    );
    expect(_asset(tester), 'assets/brand/default_banner_dark.png');
    expect(
      find.descendant(
        of: find.byType(OfficialFleetHoloBannerImage),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await _pump(
      tester,
      const OfficialFleetHoloBannerImage(null),
      Brightness.light,
    );
    await tester.pumpAndSettle(); // MaterialApp animates a theme change.
    expect(_asset(tester), 'assets/brand/default_banner_light.png');
  });

  testWidgets('a banner that fails to load falls back to the same picture', (
    tester,
  ) async {
    await _pump(
      tester,
      OfficialFleetHoloBannerImage(
        OrganizationHoloArt.bytes(Uint8List.fromList(const [1, 2, 3])),
      ),
      Brightness.dark,
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(_asset(tester), 'assets/brand/default_banner_dark.png');
  });
}
