import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_route.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bd_test.dart' show Fixture;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['player', 'audio', 'play', 'sources', 'history']) {
      for (final mode in ['route', 'switcher']) {
        testWidgets('$suite $kind keyboard $mode carries initial source', (
          t,
        ) async {
          final fixture = Fixture(kind);
          late BuildContext caller;
          late StateSetter update;
          var visible = false;
          Future<void>? pending;
          await mount(
            t,
            Builder(
              builder: (c) {
                caller = c;
                return mode == 'route'
                    ? const Text('Open')
                    : StatefulBuilder(
                        builder: (_, s) {
                          update = s;
                          return StarBridgePageSwitcher(
                            instant: true,
                            child: visible
                                ? KeyedSubtree(
                                    key: const ValueKey('new'),
                                    child: fixture.child,
                                  )
                                : const SizedBox(key: ValueKey('old')),
                          );
                        },
                      );
              },
            ),
            suite,
          );
          if (mode == 'route') {
            final route = StarBridgePageRoute<void>.fromContext(
              caller,
              source: InteractionSource.keyboard,
              builder: (_) =>
                  Scaffold(body: SizedBox(width: 700, child: fixture.child)),
            );
            pending = Navigator.of(caller).push(route);
          } else {
            update(() => visible = true);
          }
          try {
            await t.pump();
            await t.pump();
            expect(fixture.reads(), 1);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteBusyFrame).first))
                  .reduceMotion,
              true,
            );
            await t.pumpAndSettle();
            expect(t.binding.hasScheduledFrame, false);
          } finally {
            fixture.finish();
            await t.pump();
            await t.pumpAndSettle();
            if (pending != null) {
              Navigator.of(caller).pop();
              await t.pumpAndSettle();
              await pending;
            }
            await t.pumpWidget(const SizedBox());
            fixture.dispose();
          }
        });
      }
    }
  }
}
