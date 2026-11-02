import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'client_tooltip_test.dart' show host;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite background hint cannot consume a foreground dialog Escape',
      (t) async {
        final hint = GlobalKey<SuiteTooltipState>();
        await t.pumpWidget(
          host(
            suite,
            SuiteTooltip(
              key: hint,
              message: 'Background hint',
              waitDuration: Duration.zero,
              child: const SizedBox(key: Key('target'), width: 40, height: 40),
            ),
          ),
        );
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: t.getCenter(find.byKey(const Key('target'))),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
        expect(hint.currentState!.isShowing, isTrue);
        // A non-pointer route replacement leaves the old hover geometry in
        // place. Only the new route may own Escape, not that background hint.
        final context = t.element(find.byKey(const Key('target')));
        final dialog = showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Foreground dialog')),
        );
        await t.pumpAndSettle();
        expect(find.text('Foreground dialog'), findsOneWidget);
        expect(hint.currentState!.isShowing, isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        await dialog;
        expect(find.text('Foreground dialog'), findsNothing);
        // Once the route is gone the stationary pointer may legitimately
        // re-enter its old anchor and start a fresh hover hint.
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );

    for (final waiting in [false, true]) {
      for (final consume in [false, true]) {
        testWidgets('$suite passive Escape waiting=$waiting consume=$consume', (
          t,
        ) async {
          if (waiting) {
            // Continuous browsing intentionally skips the hover delay. Allow
            // that real-clock window from the previous test to expire first.
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 410)),
            );
          }
          var escaped = 0;
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final hint = GlobalKey<SuiteTooltipState>();
          await t.pumpWidget(
            host(
              suite,
              Focus(
                focusNode: focus,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    escaped++;
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: SuiteTooltip(
                  key: hint,
                  message: 'Passive hint',
                  consumeEscape: consume,
                  waitDuration: waiting
                      ? const Duration(seconds: 1)
                      : Duration.zero,
                  child: const SizedBox(
                    key: Key('target'),
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          final originalFocus = FocusManager.instance.primaryFocus;
          final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(
            location: t.getCenter(find.byKey(const Key('target'))),
          );
          await t.pump();
          if (!waiting) await t.pump(const Duration(milliseconds: 200));
          expect(hint.currentState!.isShowing, !waiting);
          expect(FocusManager.instance.primaryFocus, same(originalFocus));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(hint.currentState!.isShowing, isFalse);
          expect(find.text('Passive hint'), findsNothing);
          expect(escaped, consume ? 0 : 1);
          await t.pump(const Duration(seconds: 2));
          expect(hint.currentState!.isShowing, isFalse);
          // The transient observer was removed: a subsequent Escape belongs
          // to the original focused owner rather than a hidden tooltip.
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(escaped, consume ? 1 : 2);
          expect(FocusManager.instance.primaryFocus, same(originalFocus));
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox());
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    }

    for (final waiting in [false, true]) {
      testWidgets('$suite removed passive hint unsubscribes waiting=$waiting', (
        t,
      ) async {
        if (waiting) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 410)),
          );
        }
        var escaped = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var visible = true;
        late StateSetter update;
        await t.pumpWidget(
          host(
            suite,
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return Focus(
                  focusNode: focus,
                  autofocus: true,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      escaped++;
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: visible
                      ? SuiteTooltip(
                          message: 'Disposable hint',
                          waitDuration: waiting
                              ? const Duration(seconds: 1)
                              : Duration.zero,
                          child: const SizedBox(
                            key: Key('target'),
                            width: 40,
                            height: 40,
                          ),
                        )
                      : const Text('Removed'),
                );
              },
            ),
          ),
        );
        await t.pump();
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: t.getCenter(find.byKey(const Key('target'))),
        );
        await t.pump();
        if (!waiting) await t.pump(const Duration(milliseconds: 200));
        update(() => visible = false);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump(const Duration(seconds: 2));
        expect(escaped, 1);
        expect(find.text('Disposable hint'), findsNothing);
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  }
}
