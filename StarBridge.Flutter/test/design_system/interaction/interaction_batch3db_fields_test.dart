import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3db');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final interactive in [false, true]) {
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '$suite interactive=$interactive light=$light scale=$scale preserves editor IME/filter and live focus',
            (t) async {
              var style = suite, reduce = false, busy = false;
              late StateSetter update;
              final boundary = GlobalKey();
              final calls = <(String, String, String, InteractionSource)>[];
              t.view.devicePixelRatio = 1;
              t.view.physicalSize = const Size(480, 900);
              try {
                await t.pumpWidget(
                  StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return scopedApp(
                        RepaintBoundary(
                          key: boundary,
                          child: Material(
                            child: MediaQuery(
                              data: MediaQuery.of(
                                context,
                              ).copyWith(textScaler: TextScaler.linear(scale)),
                              child: SizedBox(
                                width: 380,
                                height: 800,
                                child: MenuFriendsPanel(
                                  embedded: true,
                                  view: MenuFriendsView(
                                    'ready',
                                    scope: 'same-scope',
                                    interactive: interactive,
                                    busy: busy,
                                    rows: const [
                                      (
                                        name: 'Alpha',
                                        presence: 'online',
                                        key: 'a',
                                        avatar: null,
                                      ),
                                      (
                                        name: 'Beta',
                                        presence: 'online',
                                        key: 'b',
                                        avatar: null,
                                      ),
                                    ],
                                  ),
                                  onClose: () {},
                                  onAction: (a, k, v) => calls.add((
                                    a,
                                    k,
                                    v,
                                    currentStarBridgeActivationSource,
                                  )),
                                ),
                              ),
                            ),
                          ),
                        ),
                        style,
                        light: light,
                        reduce: reduce,
                      );
                    },
                  ),
                );
                await t.pumpAndSettle();
                final field = find.byKey(
                  ValueKey(
                    interactive
                        ? 'friends-account-search'
                        : 'menu-friends-filter',
                  ),
                );
                await t.enterText(field, 'Alpha');
                await t.pumpAndSettle();
                expect(find.text('Beta'), findsNothing);
                expect(find.text('Alpha'), findsWidgets);
                expect(
                  calls,
                  isEmpty,
                  reason: 'Typing is only local filtering',
                );
                final editable = find.descendant(
                  of: field,
                  matching: find.byType(EditableText),
                );
                final before = t.widget<EditableText>(editable);
                final controller = before.controller, focus = before.focusNode;
                const draft = TextEditingValue(
                  text: 'Alpha舰桥',
                  selection: TextSelection(baseOffset: 1, extentOffset: 3),
                  composing: TextRange(start: 1, end: 4),
                );
                controller.value = draft;
                update(() {
                  style = InteractionSuite.values[(suite.index + 1) % 4];
                  reduce = true;
                  busy = interactive;
                });
                await t.pump();
                await t.pump();
                final after = t.widget<EditableText>(editable);
                expect(after.controller, same(controller));
                expect(after.focusNode, same(focus));
                expect(focus.hasFocus, isTrue);
                expect(controller.value, draft);
                expect(t.widget<TextField>(field).readOnly, interactive);
                expect(t.widget<TextField>(field).enabled, isNot(false));
                expect(
                  InteractionScope.of(t.element(field)).reduceMotion,
                  isTrue,
                );
                final still = await pixels(t, boundary);
                await t.pump(const Duration(milliseconds: 80));
                expect(await pixels(t, boundary), orderedEquals(still));
                await capture(
                  t,
                  boundary,
                  'field-${suite.name}-$interactive-$light-$scale',
                );
                if (interactive) {
                  update(() => busy = false);
                  await t.pump();
                  await t.showKeyboard(field);
                  await t.testTextInput.receiveAction(TextInputAction.search);
                  expect(calls, [
                    ('search', '', draft.text, InteractionSource.keyboard),
                  ]);
                  expect(controller.text, draft.text);
                  await t.enterText(field, 'x' * 129);
                  expect(controller.text.length, lessThanOrEqualTo(128));
                }
                expect(t.takeException(), isNull);
              } finally {
                await t.pumpWidget(const SizedBox());
                await t.pump();
                t.view.reset();
              }
            },
          );
        }
      }
    }
  }
}
