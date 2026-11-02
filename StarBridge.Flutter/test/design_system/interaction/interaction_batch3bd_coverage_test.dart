import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bb_coverage_test.dart' show activate;
import 'interaction_batch3bd_test.dart' show Fixture;

InteractionData waitData(WidgetTester t) =>
    InteractionScope.of(t.element(find.byType(SuiteBusyFrame).first));

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['player', 'audio', 'play', 'sources', 'history']) {
      testWidgets(
        '$suite $kind inherited keyboard origin keeps initial page read static',
        (t) async {
          final fixture = Fixture(kind);
          final origin = ValueNotifier(InteractionSource.keyboard);
          var visible = false;
          late StateSetter update;
          await mount(
            t,
            StatefulBuilder(
              builder: (_, s) {
                update = s;
                return visible
                    ? StarBridgeActivationOrigin(
                        source: origin,
                        child: fixture.child,
                      )
                    : const SizedBox();
              },
            ),
            suite,
          );
          try {
            update(() => visible = true);
            await t.pump();
            await t.pump();
            expect(waitData(t).reduceMotion, true);
            await t.pumpAndSettle();
            expect(t.binding.hasScheduledFrame, false);
            expect(fixture.reads(), 1);
          } finally {
            fixture.finish();
            await t.pump();
            await t.pumpAndSettle();
            await t.pumpWidget(const SizedBox());
            fixture.dispose();
            origin.dispose();
          }
        },
      );
      for (final local in [false, true]) {
        testWidgets(
          '$suite $kind live ${local ? 'local' : 'global'} reduce stops and restores loading feedback',
          (t) async {
            final fixture = Fixture(kind);
            late BuildContext caller;
            late StateSetter update;
            var localReduce = false;
            final live = await mount(
              t,
              Builder(
                builder: (c) {
                  caller = c;
                  return const Text('Open');
                },
              ),
              suite,
            );
            final pending = showStarBridgeDialog<void>(
              caller,
              source: InteractionSource.programmatic,
              builder: (c) => Dialog(
                child: SizedBox(
                  width: 700,
                  child: StatefulBuilder(
                    builder: (c, s) {
                      update = s;
                      return MediaQuery(
                        data: MediaQuery.of(c)
                            .copyWith(disableAnimations: localReduce),
                        child: fixture.child,
                      );
                    },
                  ),
                ),
              ),
            );
            try {
              await t.pump();
              await t.pump();
              expect(waitData(t).reduceMotion, false);
              if (local) {
                update(() => localReduce = true);
              } else {
                live.change(() => live.reduce = true);
              }
              await t.pump();
              await t.pump();
              await t.pumpAndSettle();
              expect(waitData(t).reduceMotion, true);
              expect(t.binding.hasScheduledFrame, false);
              if (local) {
                update(() => localReduce = false);
              } else {
                live.change(() => live.reduce = false);
              }
              await t.pump();
              await t.pump();
              expect(waitData(t).reduceMotion, false);
              expect(fixture.reads(), 1);
            } finally {
              fixture.finish();
              await t.pump();
              await t.pumpAndSettle();
              Navigator.of(caller).pop();
              await t.pumpAndSettle();
              await pending;
              await t.pumpWidget(const SizedBox());
              fixture.dispose();
            }
          },
        );
      }
      for (final source in ['pointer', 'keyboard']) {
        testWidgets(
          '$suite $kind initial failure then $source retry uses current source',
          (t) async {
            final fixture = Fixture(kind);
            late BuildContext caller;
            await mount(
              t,
              Builder(
                builder: (c) {
                  caller = c;
                  return const Text('Open');
                },
              ),
              suite,
            );
            final pending = showStarBridgeDialog<void>(
              caller,
              source: InteractionSource.keyboard,
              builder: (_) =>
                  Dialog(child: SizedBox(width: 700, child: fixture.child)),
            );
            try {
              await t.pump();
              await t.pump();
              fixture.finish(fail: true);
              await t.pump();
              await t.pumpAndSettle();
              fixture.renew();
              await activate(t, fixture.reload, source);
              await t.pump();
              expect(fixture.reads(), 2);
              expect(waitData(t).reduceMotion, source == 'keyboard');
              if (source == 'keyboard') {
                await t.pumpAndSettle();
                expect(t.binding.hasScheduledFrame, false);
              }
            } finally {
              fixture.finish();
              await t.pump();
              await t.pumpAndSettle();
              Navigator.of(caller).pop();
              await t.pumpAndSettle();
              await pending;
              await t.pumpWidget(const SizedBox());
              fixture.dispose();
            }
          },
        );
      }
      testWidgets('$suite $kind ordinary opening keeps initial feedback', (
        t,
      ) async {
        final fixture = Fixture(kind);
        late BuildContext caller;
        await mount(
          t,
          Builder(
            builder: (c) {
              caller = c;
              return const Text('Open');
            },
          ),
          suite,
        );
        final pending = showStarBridgeDialog<void>(
          caller,
          source: InteractionSource.programmatic,
          builder: (_) =>
              Dialog(child: SizedBox(width: 700, child: fixture.child)),
        );
        try {
          await t.pump();
          await t.pump();
          expect(fixture.reads(), 1);
          expect(waitData(t).reduceMotion, false);
        } finally {
          fixture.finish();
          await t.pump();
          await t.pumpAndSettle();
          Navigator.of(caller).pop();
          await t.pumpAndSettle();
          await pending;
          await t.pumpWidget(const SizedBox());
          fixture.dispose();
        }
      });
      testWidgets(
        '$suite $kind replacement in keyboard-opened dialog remains static',
        (t) async {
          final a = Fixture(kind), b = Fixture(kind);
          var current = a;
          late BuildContext caller;
          late StateSetter update;
          await mount(
            t,
            Builder(
              builder: (c) {
                caller = c;
                return const Text('Open');
              },
            ),
            suite,
          );
          final pending = showStarBridgeDialog<void>(
            caller,
            source: InteractionSource.keyboard,
            builder: (_) => Dialog(
              child: SizedBox(
                width: 700,
                child: StatefulBuilder(
                  builder: (_, s) {
                    update = s;
                    return current.child;
                  },
                ),
              ),
            ),
          );
          try {
            await t.pump();
            await t.pump();
            update(() => current = b);
            await t.pump();
            await t.pump();
            expect(a.reads(), 1);
            expect(b.reads(), 1);
            expect(waitData(t).reduceMotion, true);
            await t.pumpAndSettle();
            expect(t.binding.hasScheduledFrame, false);
            a.finish();
            await t.pump();
            expect(waitData(t).reduceMotion, true);
          } finally {
            a.finish();
            b.finish();
            await t.pump();
            await t.pumpAndSettle();
            Navigator.of(caller).pop();
            await t.pumpAndSettle();
            await pending;
            await t.pumpWidget(const SizedBox());
            a.dispose();
            b.dispose();
          }
        },
      );
      testWidgets('$suite $kind reader opening has no loading loop', (t) async {
        final fixture = Fixture(kind), semantics = t.ensureSemantics();
        late BuildContext caller;
        late Future<void> pending;
        await mount(
          t,
          Builder(
            builder: (c) {
              caller = c;
              return StarBridgeActionButton(
                controlKey: const Key('reader-open'),
                semanticLabel: 'Open settings',
                onActivate: (source) {
                  pending = showStarBridgeDialog<void>(
                    c,
                    source: source,
                    builder: (_) => Dialog(
                      child: SizedBox(width: 700, child: fixture.child),
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
          suite,
        );
        try {
          await activate(t, 'reader-open', 'reader');
          await t.pump();
          expect(waitData(t).reduceMotion, true);
          await t.pumpAndSettle();
          expect(t.binding.hasScheduledFrame, false);
        } finally {
          fixture.finish();
          await t.pump();
          await t.pumpAndSettle();
          Navigator.of(caller).pop();
          await t.pumpAndSettle();
          await pending;
          await t.pumpWidget(const SizedBox());
          fixture.dispose();
          semantics.dispose();
        }
      });
    }
  }
}
