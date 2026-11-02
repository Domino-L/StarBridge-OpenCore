import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_frame.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cw_test.dart' show sampleFrame, focusTarget;
import 'interaction_batch3cw_lifecycle_test.dart' show hover;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite repeated active tool clicks retain feedback and execute every time',
      (t) async {
        final boundary = GlobalKey();
        var calls = 0;
        try {
          await t.pumpWidget(
            host(
              RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 750,
                  height: 500,
                  child: sampleFrame((_) => calls++),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final target = find.byKey(const ValueKey('menu-tool-probe'));
          for (var i = 0; i < 5; i++) {
            await t.tap(target);
            await t.pump();
            final before = await pixels(t, boundary);
            await t.pump(const Duration(milliseconds: 60));
            expect(await pixels(t, boundary), isNot(orderedEquals(before)));
            expect(calls, i + 1);
          }
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
        }
      },
    );
    testWidgets('$suite tool flags preserve focus when active fill changes', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      var active = false;
      var unread = true;
      late StateSetter update;
      try {
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return host(
                MenuOverlayFrame(
                  contextLabel: '工作区',
                  returnLabel: '返回',
                  settingsLabel: '设置',
                  onReturn: () {},
                  tools: [
                    MenuOverlayTool(
                      id: 'flags',
                      label: '工具',
                      icon: StarBridgeIconSemantic.tools,
                      onActivate: () {},
                      isOpen: true,
                      isActive: active,
                      hasUnread: unread,
                    ),
                  ],
                ),
                suite,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        final target = find.byKey(const ValueKey('menu-tool-flags'));
        final focus = focusTarget(t, target);
        focus.requestFocus();
        await t.pump();
        expect(
          t
              .getSemantics(find.bySemanticsLabel('工具'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          ui.Tristate.isFalse,
        );
        update(() {
          active = true;
          unread = false;
        });
        await t.pump();
        expect(focusTarget(t, target), same(focus));
        expect(focus.hasFocus, isTrue);
        expect(
          t
              .getSemantics(find.bySemanticsLabel('工具'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          ui.Tristate.isTrue,
        );
        expect(
          t
              .widget<Badge>(find.byKey(const ValueKey('menu-unread-flags')))
              .isLabelVisible,
          isFalse,
        );
        expect(find.byKey(const ValueKey('menu-open-flags')), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        semantics.dispose();
        await detach(t);
      }
    });
    testWidgets(
      '$suite live reduce during a held settings press does not cancel the command',
      (t) async {
        var reduce = false;
        late StateSetter update;
        var calls = 0;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(sampleFrame((_) => calls++), suite, reduce: reduce);
              },
            ),
          );
          await t.pumpAndSettle();
          final target = find.byKey(const ValueKey('menu-settings'));
          final focus = focusTarget(t, target);
          final pointer = await t.startGesture(t.getCenter(target));
          await t.pump(const Duration(milliseconds: 30));
          update(() => reduce = true);
          await t.pump();
          await t.pump();
          expect(focusTarget(t, target), same(focus));
          expect(calls, 0);
          await pointer.up();
          expect(calls, 1);
          await t.pump();
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
        }
      },
    );
    testWidgets(
      '$suite hint exit and native scope release only their own viewport lease',
      (t) async {
        var active = true;
        late StateSetter update;
        late VoidCallback openOther, closeOther;
        final baseline = nativeViewportMenus.value;
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  NativeViewportScope(
                    active: active,
                    child: NativeViewportMenu(
                      builder: (open, close) {
                        openOther = open;
                        closeOther = close;
                        return sampleFrame((_) {});
                      },
                    ),
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          openOther();
          await mouse.addPointer(location: Offset.zero);
          await hover(t, mouse, find.byKey(const ValueKey('menu-settings')));
          expect(nativeViewportMenus.value, baseline + 2);
          await mouse.moveTo(Offset.zero);
          await t.pump();
          await t.pump(const Duration(milliseconds: 40));
          expect(nativeViewportMenus.value, baseline + 2);
          await t.pump(const Duration(milliseconds: 60));
          expect(nativeViewportMenus.value, baseline + 1);
          await hover(t, mouse, find.byKey(const ValueKey('menu-settings')));
          expect(nativeViewportMenus.value, baseline + 2);
          update(() => active = false);
          await t.pump();
          await t.pump();
          expect(nativeViewportMenus.value, baseline + 1);
          closeOther();
          expect(nativeViewportMenus.value, baseline);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await detach(t);
          expect(nativeViewportMenus.value, baseline);
        }
      },
    );
  }
}
