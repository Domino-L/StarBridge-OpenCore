import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_read_source_argument.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cj_provider_test.dart' show HeldRoomPort;
import 'interaction_batch3ct_test.dart' show host, detach;

FocusNode focusOfTarget(WidgetTester t, Finder target) {
  var widget = t.widget(target);
  if (widget is! SuitePressable && widget is! ButtonStyleButton) {
    widget = t.widget(
      find
          .descendant(
            of: target,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SuitePressable || widget is ButtonStyleButton,
            ),
          )
          .first,
    );
  }
  return switch (widget) {
    SuitePressable(:final focusNode) => focusNode!,
    ButtonStyleButton(:final focusNode) => focusNode!,
    _ => throw StateError('Expected an exposed action target'),
  };
}

Future<void> activate(WidgetTester t, String source, Finder target) async {
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    focusOfTarget(t, target).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final text = t
        .widget<Text>(
          find.descendant(of: target, matching: find.byType(Text)).first,
        )
        .data!;
    final named = find.bySemanticsLabel(text);
    expect(named, findsOneWidget);
    final node = t.getSemantics(named);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: t.view.viewId,
        nodeId: node.id,
      ),
    );
  }
}

Future<(MenuFeatureView, MenuRoomsSession)> roomFixture(
  WidgetTester t, {
  bool compatible = false,
  bool busy = false,
}) async {
  final views = <Map<String, Object?>>[];
  final session = MenuRoomsSession(HeldRoomPort(), views.add)..show(true);
  await t.pump();
  final raw = {...views.last, 'busy': busy};
  if (compatible) {
    raw['room'] = Map<String, Object?>.from(raw['room'] as Map)
      ..remove('management');
  }
  return (MenuFeatureView.parse(raw), session);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final id in ['menu-room-refresh', 'menu-room-message-refresh']) {
        testWidgets(
          '$suite $source $id keeps exact refresh intent and expiring display source',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(1600, 1100);
            final semantics = t.ensureSemantics();
            final (view, session) = await roomFixture(t);
            final calls = <Object?>[];
            try {
              await t.pumpWidget(
                host(
                  MenuRoomsPanel(
                    view: view,
                    active: true,
                    onAction: (key, value) {
                      calls.add(
                        menuReadSourceArgument('featureAction', {
                          'opening': 7,
                          'tool': 'rooms',
                          'key': key,
                          'value': value,
                        }),
                      );
                    },
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              await activate(t, source, find.byKey(Key(id)));
              expect(calls, [
                {
                  'opening': 7,
                  'tool': 'rooms',
                  'key': 'refresh',
                  'value': '',
                  'motionSource': source == 'pointer' ? 'pointer' : 'keyboard',
                },
              ]);
              await t.pump();
              final outside = {
                'opening': 7,
                'tool': 'rooms',
                'key': 'refresh',
                'value': '',
              };
              expect(
                menuReadSourceArgument('featureAction', outside),
                same(outside),
              );
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await detach(t);
              session.dispose();
              await t.pump();
              t.view.reset();
            }
          },
        );
      }
      testWidgets(
        '$suite compatible settings $source uses the original live dialog and cancels without a write',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1600, 1100);
          final semantics = t.ensureSemantics();
          final (view, session) = await roomFixture(t, compatible: true);
          final calls = <(String, String)>[];
          try {
            await t.pumpWidget(
              host(
                MenuRoomsPanel(
                  view: view,
                  onAction: (key, value) => calls.add((key, value)),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await activate(
              t,
              source,
              find.byKey(const ValueKey('menu-room-settings')),
            );
            await t.pump();
            await t.pump();
            final title = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('房间设置'),
            );
            expect(title, findsOneWidget);
            final route =
                ModalRoute.of(t.element(title))! as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            if (source != 'pointer') expect(route.animation!.value, 1);
            expect(calls, isEmpty);
            // Pointer scan starts as a line; cancel becomes hit-testable after
            // the real entrance. Keyboard/reader immediacy was checked above.
            await t.pumpAndSettle();
            final cancel = find
                .ancestor(
                  of: find.text('取消'),
                  matching: find.byType(StarBridgeActionButton),
                )
                .first;
            await activate(t, source, cancel);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(calls, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await detach(t);
            session.dispose();
            await t.pump();
            t.view.reset();
          }
        },
      );
    }
    testWidgets(
      '$suite busy preserves all three disabled entries and their semantics',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1600, 1100);
        final semantics = t.ensureSemantics();
        final (view, session) = await roomFixture(
          t,
          compatible: true,
          busy: true,
        );
        final calls = <(String, String)>[];
        try {
          await t.pumpWidget(
            host(
              MenuRoomsPanel(
                view: view,
                onAction: (key, value) => calls.add((key, value)),
              ),
              suite,
            ),
          );
          await t.pump();
          for (final key in const [
            Key('menu-room-refresh'),
            Key('menu-room-message-refresh'),
            ValueKey('menu-room-settings'),
          ]) {
            final target = find.byKey(key);
            expect(target, findsOneWidget);
            await t.tap(target, warnIfMissed: false);
            final text = t
                .widget<Text>(
                  find
                      .descendant(of: target, matching: find.byType(Text))
                      .first,
                )
                .data!;
            final data = t
                .getSemantics(find.bySemanticsLabel(text))
                .getSemanticsData();
            expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
            expect(data.flagsCollection.isFocused, ui.Tristate.none);
          }
          expect(calls, isEmpty);
          expect(find.byType(AlertDialog), findsNothing);
        } finally {
          semantics.dispose();
          await detach(t);
          session.dispose();
          await t.pump();
          t.view.reset();
        }
      },
    );
    testWidgets(
      '$suite live suite/reduce keeps refresh focus and room chat draft value',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1600, 1100);
        final (view, session) = await roomFixture(t);
        var current = suite, reduce = false;
        late StateSetter update;
        final calls = <(String, String)>[];
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  MenuRoomsPanel(
                    view: view,
                    active: true,
                    onAction: (key, value) => calls.add((key, value)),
                  ),
                  current,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          final input = t.widget<TextField>(
            find.byKey(const ValueKey('menu-channel-draft')),
          );
          const draft = TextEditingValue(
            text: '草稿 Draft',
            selection: TextSelection(baseOffset: 1, extentOffset: 5),
            composing: TextRange(start: 0, end: 2),
          );
          input.controller!.value = draft;
          await t.pump();
          final target = find.byKey(const Key('menu-room-refresh'));
          final focus = focusOfTarget(t, target)..requestFocus();
          await t.pump();
          update(() {
            current = InteractionSuite
                .values[(suite.index + 1) % InteractionSuite.values.length];
            reduce = true;
          });
          await t.pump();
          await t.pump();
          expect(focusOfTarget(t, target), same(focus));
          expect(focus.hasFocus, isTrue);
          expect(
            t
                .widget<TextField>(
                  find.byKey(const ValueKey('menu-channel-draft')),
                )
                .controller!
                .value,
            draft,
          );
          expect(InteractionScope.of(t.element(target)).reduceMotion, isTrue);
          await activate(t, 'keyboard', target);
          expect(calls, [('refresh', '')]);
        } finally {
          await detach(t);
          session.dispose();
          await t.pump();
          t.view.reset();
        }
      },
    );
  }
  testWidgets(
    'compatible room settings entry follows the selected scan suite',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1600, 1100);
      final views = <Map<String, Object?>>[];
      final session = MenuRoomsSession(HeldRoomPort(), views.add)..show(true);
      try {
        await t.pump();
        final room = Map<String, Object?>.from(views.last['room'] as Map)
          ..remove('management');
        final view = MenuFeatureView.parse({...views.last, 'room': room});
        expect(view.room!.settings!.action, isNotNull);
        await t.pumpWidget(
          host(
            MenuRoomsPanel(view: view, onAction: (_, _) {}),
            InteractionSuite.scan,
          ),
        );
        await t.pumpAndSettle();
        final target = find.byKey(const ValueKey('menu-room-settings'));
        expect(target, findsOneWidget);
        expect(t.widget(target), isA<SuitePressable>());
      } finally {
        await detach(t);
        session.dispose();
        await t.pump();
        t.view.reset();
      }
    },
  );
  testWidgets(
    'actual room and message refresh follow the selected scan suite',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1600, 1100);
      final views = <Map<String, Object?>>[];
      final port = HeldRoomPort();
      final session = MenuRoomsSession(port, views.add)..show(true);
      try {
        await t.pump();
        final view = MenuFeatureView.parse(views.last);
        expect(view.room!.canChat, isTrue);
        await t.pumpWidget(
          host(
            MenuRoomsPanel(view: view, onAction: (_, _) {}, active: true),
            InteractionSuite.scan,
          ),
        );
        await t.pump();
        for (final label in ['刷新房间', '刷新消息']) {
          expect(find.text(label), findsOneWidget);
          final target = find.ancestor(
            of: find.text(label),
            matching: find.byType(SuitePressable),
          );
          expect(target, findsOneWidget);
          expect(
            InteractionScope.of(t.element(target)).suite,
            InteractionSuite.scan,
          );
        }
      } finally {
        await detach(t);
        session.dispose();
        await t.pump();
        t.view.reset();
      }
    },
  );
}
