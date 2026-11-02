import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace, flush;
import 'interaction_batch3cp_test.dart' show mount, key;

Finder target(String kind) => key(switch (kind) {
  'url' => 'browser-tab-t1',
  'close' => 'browser-close-t1',
  _ => 'browser-new-tab',
});
SuiteTooltipState hint(WidgetTester t, String kind) => t.state(
  find.ancestor(of: target(kind), matching: find.byType(SuiteTooltip)).first,
);
bool nativeVisible(BrowserFake n) =>
    n.calls.lastWhere((c) => c.$1 == 'browserBounds').$2['visible'] == true;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final kind in ['url', 'close', 'new']) {
      for (final exit in [
        'pointer',
        'reopen',
        'reduce',
        'workspace',
        'scope',
        'disposeOther',
      ]) {
        testWidgets('$suite $kind hint owns native lease through $exit', (
          t,
        ) async {
          final native = BrowserFake(), work = workspace();
          expect(nativeViewportMenus.value, 0);
          final h = await mount(t, native, work, suite);
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(850, 600));
          await mouse.moveTo(t.getCenter(target(kind)));
          await t.pump(const Duration(milliseconds: 500));
          await t.pump(const Duration(milliseconds: 200));
          expect(hint(t, kind).isShowing, true);
          expect(nativeViewportMenus.value, 1);
          expect(nativeVisible(native), false);
          if (exit == 'workspace') {
            work.setVisible(false);
          } else if (exit == 'scope') {
            h.change(() => h.scopeActive = false);
          } else if (exit == 'disposeOther') {
            h.otherOpen!();
            expect(nativeViewportMenus.value, 2);
            h.change(() => h.visible = false);
            await flush(t);
            expect(nativeViewportMenus.value, 1);
            h.otherClose!();
          } else {
            if (exit == 'reduce') {
              h.change(() => h.reduce = true);
              await flush(t);
              expect(nativeViewportMenus.value, 1);
            }
            await mouse.moveTo(const Offset(850, 600));
            await t.pump();
            await t.pump(const Duration(milliseconds: 20));
            if (exit != 'reduce') {
              expect(nativeViewportMenus.value, 1);
              expect(nativeVisible(native), false);
            }
            if (exit == 'reopen') {
              await mouse.moveTo(t.getCenter(target(kind)));
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              expect(nativeViewportMenus.value, 1);
              expect(hint(t, kind).isShowing, true);
              await mouse.moveTo(const Offset(850, 600));
              await t.pump();
            }
            await t.pump(const Duration(milliseconds: 200));
          }
          await flush(t);
          expect(nativeViewportMenus.value, 0);
          if (exit == 'pointer' || exit == 'reopen' || exit == 'reduce') {
            expect(nativeVisible(native), true);
          } else {
            expect(nativeVisible(native), false);
          }
          expect(
            native.calls.where(
              (c) => [
                'browserNavigate',
                'browserNewTab',
                'browserSelectTab',
                'browserCloseTab',
              ].contains(c.$1),
            ),
            isEmpty,
          );
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox());
          work.dispose();
          expect(nativeViewportMenus.value, 0);
          expect(t.takeException(), isNull);
        });
      }
      testWidgets('$suite $kind keyboard hint closes instantly on Escape', (
        t,
      ) async {
        final native = BrowserFake(), work = workspace();
        await mount(t, native, work, suite);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        if (kind == 'url') {
          final text = find
              .descendant(of: target(kind), matching: find.byType(Text))
              .first;
          Focus.of(t.element(text)).requestFocus();
        } else {
          t.widget<IconButton>(target(kind)).focusNode!.requestFocus();
        }
        await flush(t);
        expect(hint(t, kind).isShowing, true);
        expect(nativeViewportMenus.value, 1);
        expect(nativeVisible(native), false);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await flush(t);
        expect(nativeViewportMenus.value, 0);
        expect(nativeVisible(native), true);
        expect(hint(t, kind).isShowing, false);
        await t.pumpWidget(const SizedBox());
        work.dispose();
      });
    }
  }
}
