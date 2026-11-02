import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module_grid.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_drag_surface.dart';

import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ac_test.dart' show LiveState;
import 'interaction_batch3at_test.dart' show projection, item;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

class Harness extends StatefulWidget {
  const Harness({super.key});
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  PersonalProfileProjection data = projection();
  List<PersonalProfileModuleLayoutItem> layout =
      PersonalProfileLayout.normalize([item]);
  bool editing = true;
  bool active = true;
  bool visible = true;
  bool localReduce = false;
  final calls = <List<PersonalProfileModuleLayoutItem>>[];
  void change(VoidCallback update) => setState(update);

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: localReduce),
    child: NativeViewportScope(
      active: active,
      child: visible
          ? SingleChildScrollView(
              child: PersonalProfileModuleGrid(
                projection: data,
                visitorView: false,
                editing: editing,
                layout: layout,
                onLayoutChanged: (next) {
                  calls.add(next);
                  setState(() => layout = next);
                },
              ),
            )
          : const Text('Source removed'),
    ),
  );
}

Future<HarnessState> harness(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<HarnessState>();
  await mount(t, Harness(key: key), suite, width: 1100);
  return key.currentState!;
}

Future<TestGesture> dragTo(WidgetTester t, int cell) async {
  final destination = find.byKey(Key('profile-grid-cell-$cell'));
  await t.ensureVisible(destination);
  await settleCommunityImages(t);
  final start = t.getCenter(
    find.byKey(const Key('profile-module-drag-favorite-ships')),
  );
  final gesture = await t.startGesture(start);
  await gesture.moveBy(const Offset(24, 0));
  await t.pump();
  await gesture.moveTo(t.getCenter(destination));
  await t.pump();
  return gesture;
}

List<dynamic> painters(WidgetTester t) => t
    .widgetList<CustomPaint>(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.foregroundPainter.runtimeType.toString() == '_DragPainter',
      ),
    )
    .map((w) => w.foregroundPainter as dynamic)
    .toList();

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pump();
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final directory = Directory('build/reviews/interaction-batch3av');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final reason in ['projection', 'editing', 'viewport', 'layout']) {
      testWidgets(
        'drag scope $reason cannot commit old preview ${suite.name}',
        (t) async {
          final state = await harness(t, suite);
          final original = state.layout;
          final gesture = await dragTo(t, 2);
          expect(state.calls, isEmpty);
          state.change(() {
            switch (reason) {
              case 'projection':
                state.data = state.data.copyWith(callSign: 'New scope');
              case 'editing':
                state.editing = false;
              case 'viewport':
                state.active = false;
              case 'layout':
                state.layout = PersonalProfileLayout.move(
                  original,
                  'favorite-ships',
                  1,
                ).layout;
            }
          });
          final expected = state.layout;
          await t.pump();
          await t.pump();
          expect(painters(t), isEmpty);
          await gesture.up();
          await settleCommunityImages(t);
          expect(state.calls, isEmpty);
          expect(
            PersonalProfileLayout.hasSameLayout(state.layout, expected),
            isTrue,
          );
          expect(t.takeException(), isNull);
        },
      );
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('physical drag commits exactly once at scale $scale $suite', (
        t,
      ) async {
        final key = GlobalKey<HarnessState>();
        await mount(t, Harness(key: key), suite, width: 1100, scale: scale);
        final state = key.currentState!;
        final original = state.layout;
        final gesture = await dragTo(t, 2);
        expect(state.calls, isEmpty);
        expect(painters(t), hasLength(2));
        await gesture.up();
        await settleCommunityImages(t);
        expect(state.calls, hasLength(1));
        expect(
          PersonalProfileLayout.hasSameLayout(
            state.layout,
            PersonalProfileLayout.move(original, 'favorite-ships', 2).layout,
          ),
          isTrue,
        );
        expect(painters(t), isEmpty);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets(
      'rapid target reversal retains latest cue without queued commits $suite',
      (t) async {
        final state = await harness(t, suite);
        final gesture = await dragTo(t, 2);
        for (final cell in [1, 2, 1, 2]) {
          await gesture.moveTo(
            t.getCenter(find.byKey(Key('profile-grid-cell-$cell'))),
          );
          await t.pump();
          expect(
            find.byKey(ValueKey('profile-drop-position-$cell')),
            findsOneWidget,
          );
          expect(painters(t), hasLength(2));
          final target = painters(t).first;
          expect(target.data.suite, suite);
          expect(
            target.progress,
            suite == InteractionSuite.standard ? 1 : lessThan(1),
          );
          expect(state.calls, isEmpty);
        }
        await gesture.up();
        await settleCommunityImages(t);
        expect(state.calls, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('leaving retires native ghost before pointer-up $suite', (
      t,
    ) async {
      final state = await harness(t, suite);
      final gesture = await dragTo(t, 2);
      state.change(() => state.visible = false);
      await t.pump();
      await t.pump();
      expect(painters(t), isEmpty);
      expect(find.text('Source removed'), findsOneWidget);
      await gesture.up();
      await settleCommunityImages(t);
      expect(state.calls, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'live suite and reduce stop only decoration not physical drag $suite',
      (t) async {
        final key = GlobalKey<HarnessState>();
        final LiveState live = await mount(
          t,
          Harness(key: key),
          suite,
          width: 1100,
        );
        final state = key.currentState!;
        final gesture = await dragTo(t, 2);
        live.change(() {
          live.suite = InteractionSuite.scan;
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(painters(t), hasLength(2));
        for (final painter in painters(t)) {
          expect(painter.data.suite, InteractionSuite.scan);
          expect(painter.data.reduceMotion, isTrue);
          expect(painter.data.palette.brightness, Brightness.light);
          expect(painter.progress, 1);
        }
        await gesture.moveTo(
          t.getCenter(find.byKey(const Key('profile-grid-cell-1'))),
        );
        await t.pump();
        expect(
          find.byKey(const ValueKey('profile-drop-position-1')),
          findsOneWidget,
        );
        expect(painters(t).every((p) => p.progress == 1), isTrue);
        await gesture.up();
        await settleCommunityImages(t);
        expect(state.calls, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('outside canvas cancel never commits $suite', (t) async {
      final state = await harness(t, suite);
      final gesture = await dragTo(t, 2);
      await gesture.moveTo(const Offset(1, 1));
      await t.pump();
      expect(painters(t), hasLength(1));
      await gesture.up();
      await settleCommunityImages(t);
      expect(state.calls, isEmpty);
      expect(painters(t), isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'feedback observes existing frames only and retires once $suite',
      (t) async {
        var current = true;
        var checks = 0;
        await mount(
          t,
          StarBridgeDragSurface(
            isCurrent: () {
              checks++;
              return current;
            },
            child: const SizedBox(
              width: 200,
              height: 100,
              child: Text('Ghost'),
            ),
          ),
          suite,
        );
        await settleCommunityImages(t);
        expect(t.binding.hasScheduledFrame, isFalse);
        final before = checks;
        for (var i = 0; i < 5; i++) {
          t.binding.scheduleFrame();
          await t.pump();
        }
        expect(checks - before, 5);
        current = false;
        t.binding.scheduleFrame();
        await t.pump();
        await t.pump();
        expect(find.text('Ghost'), findsNothing);
        final retired = checks;
        current = true;
        t.binding.scheduleFrame();
        await t.pump();
        expect(checks, retired);
        expect(find.text('Ghost'), findsNothing);
        await t.pumpWidget(const SizedBox.shrink());
        t.binding.scheduleFrame();
        await t.pump();
        expect(checks, retired);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'late first gesture cannot cancel a second module drag $suite',
      (t) async {
        final state = await harness(t, suite);
        state.change(
          () => state.layout = PersonalProfileLayout.show(
            state.layout,
            'skilled-roles',
            requestedPosition: 3,
          ).layout,
        );
        await settleCommunityImages(t);
        final first = await dragTo(t, 2);
        final second = await t.startGesture(
          t.getCenter(
            find.byKey(const Key('profile-module-drag-skilled-roles')),
          ),
          pointer: 2,
        );
        await second.moveBy(const Offset(24, 0));
        await t.pump();
        await second.moveTo(
          t.getCenter(find.byKey(const Key('profile-grid-cell-1'))),
        );
        await t.pump();
        await first.moveTo(const Offset(1, 1));
        await first.up();
        await t.pump();
        expect(
          find.byKey(const ValueKey('profile-drop-position-1')),
          findsOneWidget,
        );
        expect(state.calls, isEmpty);
        await second.up();
        await settleCommunityImages(t);
        expect(state.calls, hasLength(1));
        expect(
          state.layout
              .firstWhere((i) => i.moduleId == 'skilled-roles')
              .position,
          1,
        );
        expect(painters(t), isEmpty);
        expect(t.takeException(), isNull);
      },
    );

    for (final before in [true, false]) {
      testWidgets(
        'caller-local reduced motion follows native ghost before=$before $suite',
        (t) async {
          final state = await harness(t, suite);
          if (before) {
            state.change(() => state.localReduce = true);
            await t.pump();
          }
          final gesture = await dragTo(t, 2);
          if (!before) state.change(() => state.localReduce = true);
          await t.pump();
          await t.pump();
          expect(painters(t), hasLength(2));
          for (final p in painters(t)) {
            expect(p.data.reduceMotion, isTrue);
            expect(p.progress, 1);
          }
          await gesture.up();
          await settleCommunityImages(t);
          expect(state.calls, hasLength(1));
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets('drag feedback cannot claim focus $suite', (t) async {
      await mount(
        t,
        const StarBridgeDragSurface(child: Focus(child: Text('Ghost focus'))),
        suite,
      );
      final node = Focus.of(t.element(find.text('Ghost focus')));
      expect(node.canRequestFocus, isFalse);
      node.requestFocus();
      await t.pump();
      expect(node.hasFocus, isFalse);
      expect(t.takeException(), isNull);
    });

    if (suite != InteractionSuite.standard) {
      testWidgets('drag cue frame review $suite', (t) async {
        final key = GlobalKey<HarnessState>();
        final boundary = GlobalKey();
        await mount(
          t,
          Harness(key: key),
          suite,
          width: 1100,
          capture: boundary,
        );
        final gesture = await dragTo(t, 2);
        await t.pump(const Duration(milliseconds: 60));
        await capture(t, boundary, '${suite.name}-drag');
        await t.pump(const Duration(milliseconds: 200));
        await capture(t, boundary, '${suite.name}-locked');
        await gesture.up();
        await settleCommunityImages(t);
        expect(key.currentState!.calls, hasLength(1));
        expect(t.takeException(), isNull);
      });
    }
  }
}
