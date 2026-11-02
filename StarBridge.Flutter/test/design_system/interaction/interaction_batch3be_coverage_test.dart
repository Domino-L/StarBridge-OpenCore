import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_route.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_page_motion.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bd_test.dart' show Fixture;
import 'interaction_batch3bb_coverage_test.dart' show activate;

InteractionData waitData(WidgetTester t) =>
    InteractionScope.of(t.element(find.byType(SuiteBusyFrame).first));

FeatureDescriptor feature(Widget child) => FeatureDescriptor(
  id: 'fixture',
  route: '/fixture',
  labelKey: 'fixture',
  descriptionKey: 'fixture',
  icon: StarBridgeIconSemantic.settings,
  navigationRegion: NavigationRegion.primary,
  order: 0,
  buildDestination: (_) => child,
);

void main() {
  setUpAll(loadFonts);
  for (final local in [false, true]) {
    testWidgets('activation origin is local to the typed route $local', (
      t,
    ) async {
      final fixture = Fixture('player'),
          origin = ValueNotifier(InteractionSource.keyboard);
      late BuildContext caller;
      await mount(
        t,
        local
            ? Builder(
                builder: (c) {
                  caller = c;
                  return const Text('Open');
                },
              )
            : StarBridgeActivationOrigin(
                source: origin,
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (c) {
                      caller = c;
                      return const Text('Nested open');
                    },
                  ),
                ),
              ),
        InteractionSuite.rail,
      );
      final pending = Navigator.of(caller).push(
        StarBridgePageRoute<void>.fromContext(
          caller,
          source: InteractionSource.pointer,
          builder: (_) => Scaffold(
            body: SizedBox(
              width: 700,
              child: local
                  ? StarBridgeActivationOrigin(
                      source: origin,
                      child: fixture.child,
                    )
                  : fixture.child,
            ),
          ),
        ),
      );
      try {
        await t.pump();
        await t.pump();
        expect(waitData(t).reduceMotion, local);
      } finally {
        fixture.finish();
        await t.pump();
        await t.pumpAndSettle();
        Navigator.of(caller).pop();
        await t.pumpAndSettle();
        await pending;
        await t.pumpWidget(const SizedBox());
        fixture.dispose();
        origin.dispose();
      }
    });
  }
  for (final suite in InteractionSuite.values) {
    for (final kind in ['player', 'audio', 'play', 'sources', 'history']) {
      testWidgets(
        '$suite actual ShellWorkspace $kind inherits keyboard selection',
        (t) async {
          final fixture = Fixture(kind);
          var visible = false;
          late StateSetter update;
          await mount(
            t,
            StatefulBuilder(
              builder: (_, s) {
                update = s;
                return visible
                    ? ShellWorkspace(
                        selected: feature(fixture.child),
                        interaction: NavigationInteraction.keyboard,
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
            expect(fixture.reads(), 1);
            expect(waitData(t).reduceMotion, true);
          } finally {
            fixture.finish();
            await t.pump();
            await t.pumpAndSettle();
            await t.pumpWidget(const SizedBox());
            fixture.dispose();
          }
        },
      );
      for (final mode in ['route', 'switcher']) {
        for (final source in ['pointer', 'keyboard']) {
          testWidgets(
            '$suite $kind $mode keyboard open then $source retry retains current feedback',
            (t) async {
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
                pending = Navigator.of(caller).push(
                  StarBridgePageRoute<void>.fromContext(
                    caller,
                    source: InteractionSource.keyboard,
                    builder: (_) => Scaffold(
                      body: SizedBox(width: 700, child: fixture.child),
                    ),
                  ),
                );
              } else {
                update(() => visible = true);
              }
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
                if (pending != null) {
                  Navigator.of(caller).pop();
                  await t.pumpAndSettle();
                  await pending;
                }
                await t.pumpWidget(const SizedBox());
                fixture.dispose();
              }
            },
          );
        }
        testWidgets('$suite $kind ordinary $mode keeps initial feedback', (
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
                            instant: false,
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
            pending = Navigator.of(caller).push(
              StarBridgePageRoute<void>.fromContext(
                caller,
                source: InteractionSource.pointer,
                builder: (_) =>
                    Scaffold(body: SizedBox(width: 700, child: fixture.child)),
              ),
            );
          } else {
            update(() => visible = true);
          }
          try {
            await t.pump();
            await t.pump();
            expect(waitData(t).reduceMotion, false);
            expect(fixture.reads(), 1);
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
        testWidgets(
          '$suite $kind $mode replaced owner retains opening source',
          (t) async {
            final a = Fixture(kind), b = Fixture(kind);
            var current = a;
            late StateSetter update;
            late BuildContext caller;
            Future<void>? pending;
            Widget body() => StatefulBuilder(
              builder: (_, s) {
                update = s;
                return current.child;
              },
            );
            await mount(
              t,
              Builder(
                builder: (c) {
                  caller = c;
                  return mode == 'route'
                      ? const Text('Open')
                      : StarBridgePageSwitcher(instant: true, child: body());
                },
              ),
              suite,
            );
            if (mode == 'route') {
              pending = Navigator.of(caller).push(
                StarBridgePageRoute<void>.fromContext(
                  caller,
                  source: InteractionSource.keyboard,
                  builder: (_) =>
                      Scaffold(body: SizedBox(width: 700, child: body())),
                ),
              );
            }
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
              a.finish();
              await t.pump();
              expect(waitData(t).reduceMotion, true);
            } finally {
              a.finish();
              b.finish();
              await t.pump();
              await t.pumpAndSettle();
              if (pending != null) {
                Navigator.of(caller).pop();
                await t.pumpAndSettle();
                await pending;
              }
              await t.pumpWidget(const SizedBox());
              a.dispose();
              b.dispose();
            }
          },
        );
      }
    }
  }
  for (final innerKeyboard in [false, true]) {
    testWidgets(
      'nested route owns source rather than opposite ancestor $innerKeyboard',
      (t) async {
        final fixture = Fixture('player');
        late BuildContext caller;
        await mount(
          t,
          StarBridgePageSwitcher(
            instant: !innerKeyboard,
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (c) {
                  caller = c;
                  return const Text('Nested open');
                },
              ),
            ),
          ),
          InteractionSuite.rail,
        );
        final pending = Navigator.of(caller).push(
          StarBridgePageRoute<void>.fromContext(
            caller,
            source: innerKeyboard
                ? InteractionSource.keyboard
                : InteractionSource.pointer,
            builder: (_) =>
                Scaffold(body: SizedBox(width: 700, child: fixture.child)),
          ),
        );
        try {
          await t.pump();
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame).first))
                .reduceMotion,
            innerKeyboard,
          );
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
}
