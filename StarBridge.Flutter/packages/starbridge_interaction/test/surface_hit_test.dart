import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final reduced in [false, true]) {
      for (final entering in [false, true]) {
        testWidgets(
          'decorative surface cannot consume modal barrier $suite reduced=$reduced entering=$entering',
          (t) async {
            final data = InteractionData(
              suite: suite,
              palette: palette,
              reduceMotion: reduced,
            );
            late SuiteDialogRoute<void> route;
            await t.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: InteractionScope(
                    data: data,
                    child: Builder(
                      builder: (context) => TextButton(
                        onPressed: () {
                          route = SuiteDialogRoute<void>(
                            data: data,
                            builder: (_) => const AlertDialog(
                              content: Text('Actual surface'),
                            ),
                            surfaceBuilder: (_, animation, child) =>
                                SuiteSurfaceTransition(
                                  animation: animation,
                                  kind: SurfaceKind.dialog,
                                  surfaceBounds: const Rect.fromLTRB(
                                    220,
                                    180,
                                    580,
                                    420,
                                  ),
                                  child: child,
                                ),
                          );
                          unawaited(Navigator.of(context).push(route));
                        },
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            await t.tap(find.text('Open'));
            await t.pump();
            if (entering && !reduced) {
              await t.pump(route.transitionDuration ~/ 2);
              expect(route.animation!.value, inExclusiveRange(0, 1));
            } else {
              await t.pumpAndSettle();
            }
            await t.tapAt(const Offset(12, 12));
            await t.pump();
            expect(route.isCurrent, false);
            await t.pumpAndSettle();
            expect(find.text('Actual surface'), findsNothing);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
}
