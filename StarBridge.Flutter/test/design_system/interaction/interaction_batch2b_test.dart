import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;

const target = Key('icon-action');
Widget action({
  ValueChanged<InteractionSource>? onActivate,
  bool selected = false,
  FocusNode? focus,
}) => StarBridgeIconAction(
  controlKey: target,
  label: 'Bookmark ship',
  selected: selected,
  focusNode: focus,
  onActivate: onActivate,
  icon: StandardIcon(
    selected ? StandardIconSemantic.bookmarked : StandardIconSemantic.bookmark,
  ),
);

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite every repeated icon press paints feedback', (
      tester,
    ) async {
      final repaint = GlobalKey();
      var calls = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: repaint,
            child: Material(child: action(onActivate: (_) => calls++)),
          ),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      final idle = await pixels(tester, repaint);
      for (var i = 0; i < 5; i++) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(target)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
        expect(await pixels(tester, repaint), isNot(equals(idle)));
        await gesture.up();
        expect(calls, i + 1);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('$suite icon keyboard invokes once without animation', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final sources = <InteractionSource>[];
      await tester.pumpWidget(
        app(
          action(focus: focus, onActivate: sources.add),
          suite: suite,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      focus.requestFocus();
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.numpadEnter,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(sources, List.filled(3, InteractionSource.keyboard));
    });

    for (final enabled in [true, false]) {
      testWidgets(
        '$suite icon has one semantic action and state; enabled=$enabled',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            final focus = FocusNode();
            addTearDown(focus.dispose);
            final sources = <InteractionSource>[];
            await tester.pumpWidget(
              app(
                action(
                  selected: true,
                  focus: focus,
                  onActivate: enabled ? sources.add : null,
                ),
                suite: suite,
              ),
            );
            await tester.pumpAndSettle();
            final named = find.bySemanticsLabel('Bookmark ship');
            expect(named, findsOneWidget);
            final node = tester.getSemantics(named);
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              enabled,
            );
            expect(
              node,
              matchesSemantics(
                label: 'Bookmark ship',
                isButton: true,
                hasEnabledState: true,
                isEnabled: enabled,
                isFocusable: enabled,
                hasToggledState: true,
                isToggled: true,
                hasTapAction: enabled,
                textDirection: TextDirection.ltr,
              ),
            );
            if (enabled) {
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
              expect(sources, [InteractionSource.keyboard]);
            } else {
              focus.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.tap(find.byKey(target), warnIfMissed: false);
              expect(focus.hasFocus, isFalse);
              expect(sources, isEmpty);
            }
          } finally {
            handle.dispose();
          }
        },
      );
    }

    testWidgets('$suite reduced motion keeps immediate active callbacks', (
      tester,
    ) async {
      final sources = <InteractionSource>[];
      await tester.pumpWidget(
        app(action(onActivate: sources.add), suite: suite, reduce: true),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(target));
        expect(sources.length, i + 1);
        await tester.pump();
      }
      expect(sources, everyElement(InteractionSource.pointer));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('$suite enabling reduce during press stops decoration', (
      tester,
    ) async {
      var calls = 0;
      Widget view(bool reduce) => app(
        action(onActivate: (_) => calls++),
        suite: suite,
        reduce: reduce,
      );
      await tester.pumpWidget(view(false));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(target)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(view(true));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    for (final grid in [true, false]) {
      for (final succeeds in [true, false]) {
        testWidgets(
          '$suite real hangar favorite grid=$grid success=$succeeds',
          (tester) async {
            final port = BookmarkPort();
            await tester.pumpWidget(
              app(
                LocalHangarPage(port: port, onRead: () {}),
                suite: suite,
              ),
            );
            await tester.pumpAndSettle();
            if (!grid) {
              await tester.tap(find.byKey(const Key('hangar-list')));
              await tester.pumpAndSettle();
            }
            final button = find.byKey(const ValueKey('hangar-favorite-one'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final viewport =
                Offset.zero &
                (tester.view.physicalSize / tester.view.devicePixelRatio);
            expect(
              viewport.contains(tester.getCenter(button)),
              isTrue,
              reason: 'Wait for the requested scroll layout before pointer hit testing.',
            );
            await tester.tap(button);
            await tester.pump();
            final adapter = find.ancestor(
              of: button,
              matching: find.byType(StarBridgeIconAction),
            );
            expect(
              tester.widget<StarBridgeIconAction>(adapter).selected,
              isFalse,
            );
            expect(
              tester.widget<StarBridgeIconAction>(adapter).onActivate,
              isNull,
            );
            expect(port.writes, 1);
            await tester.tap(button, warnIfMissed: false);
            expect(port.writes, 1);
            if (succeeds) {
              port.pending.complete(snapshot(true, 2));
            } else {
              port.pending.completeError(const LocalHangarFailure('storage'));
            }
            await tester.pumpAndSettle();
            expect(
              tester.widget<StarBridgeIconAction>(adapter).selected,
              succeeds,
            );
            expect(
              tester.widget<StarBridgeIconAction>(adapter).onActivate,
              isNotNull,
            );
            expect(port.request, ('one', true, 1));
            expect(port.reads, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

LocalHangarSnapshot snapshot(bool marked, int revision) => LocalHangarSnapshot(
  revision: revision,
  ships: [LocalHangarShip(id: 'one', title: 'One', isFavorite: marked)],
);

class BookmarkPort implements LocalHangarPort, LocalHangarFavoritesPort {
  int reads = 0, writes = 0;
  final pending = Completer<LocalHangarSnapshot>();
  (String, bool, int)? request;
  @override
  bool get favoritesAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() async {
    reads++;
    return snapshot(false, 1);
  }

  @override
  Future<LocalHangarSnapshot> setFavorite(
    String id,
    bool favorite,
    int expectedRevision,
  ) {
    writes++;
    request = (id, favorite, expectedRevision);
    return pending.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) =>
      throw StateError('Bookmark feedback must not save or rescan inventory.');
}
