import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  // A menu that must match its field stays that wide through the whole motion.
  for (final suite in InteractionSuite.values) {
    for (final kind in SurfaceKind.values) {
      for (final entering in [true, false]) {
        testWidgets(
          'surface keeps its width $suite $kind entering=$entering',
          (t) async {
            final animation = AnimationController(
              vsync: const TestVSync(),
              duration: const Duration(milliseconds: 100),
              value: entering ? 0 : 1,
            );
            addTearDown(animation.dispose);
            final key = GlobalKey();
            await t.pumpWidget(
              MaterialApp(
                home: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints.tightFor(width: 300),
                    child: InteractionScope(
                      data: InteractionData(suite: suite, palette: palette),
                      child: SuiteSurfaceTransition(
                        animation: animation,
                        kind: kind,
                        child: IntrinsicWidth(
                          child: Text(
                            'short',
                            key: key,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            if (entering) {
              animation.forward();
            } else {
              animation.reverse();
            }
            for (var i = 0; i < 4; i++) {
              await t.pump(const Duration(milliseconds: 20));
              expect(
                t.getSize(find.byKey(key)).width,
                300,
                reason: 'frame $i at ${animation.value}',
              );
              if (kind == SurfaceKind.menu && entering) {
                expect(
                  t.getRect(find.byKey(key)).width,
                  300,
                  reason: 'painted width, frame $i at ${animation.value}',
                );
              }
            }
            animation.stop();
          },
        );
      }
    }
  }
}
