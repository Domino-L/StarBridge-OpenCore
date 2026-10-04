import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

void main() {
  testWidgets(
    'menu motion honors system, user and safe mode without freezing controls',
    (tester) async {
      for (final system in [false, true]) {
        for (final user in [false, true]) {
          for (final safe in [false, true]) {
            final reduced = system || user || safe;
            var tapped = false;
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(disableAnimations: system),
                  child: MenuPresentation(
                    safeMode: safe,
                    reduceMotion: user,
                    child: Builder(
                      builder: (context) {
                        expect(
                          MediaQuery.disableAnimationsOf(context),
                          reduced,
                        );
                  expect(TickerMode.valuesOf(context).enabled, true);
                        final motion = Theme.of(context)
                            .extension<StarBridgeTokens>()!
                            .motion;
                        expect(motion.pointerMicro == Duration.zero, reduced);
                        expect(motion.surfaceEnter == Duration.zero, reduced);
                        expect(motion.pageOffset == 0, reduced);
                        return TextButton(
                          onPressed: () => tapped = true,
                          child: const Text('Action'),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Action'));
            expect(tapped, true);
          }
        }
      }
    },
  );
}
