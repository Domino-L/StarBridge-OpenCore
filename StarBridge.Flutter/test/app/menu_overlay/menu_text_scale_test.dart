import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.8 : fontSize * 1.4;
  @override
  double get textScaleFactor => 1.8;
}

void main() {
  testWidgets(
    'menu text size composes nonlinear system scaling without changing bounds',
    (tester) async {
      MediaQueryData? actual;
      for (final percent in [100, 110, 125]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1280, 900),
                textScaler: _NonlinearScaler(),
              ),
              child: MenuPresentation(
                safeMode: false,
                textScalePercent: percent,
                child: Builder(
                  builder: (context) {
                    actual = MediaQuery.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );
        expect(
          actual!.textScaler.scale(14),
          closeTo(14 * 1.8 * percent / 100, .0001),
        );
        expect(
          actual!.textScaler.scale(28),
          closeTo(28 * 1.4 * percent / 100, .0001),
        );
        expect(actual!.size, const Size(1280, 900));
        expect(actual!.disableAnimations, false);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
