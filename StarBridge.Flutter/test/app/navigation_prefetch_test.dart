import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_prefetch.dart';

void main() {
  testWidgets(
    'intent prefetch waits for dwell, cancels pass-through and never locks a click',
    (tester) async {
      var reads = 0, clicks = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NavigationPrefetch(
                prepare: () {
                  reads++;
                  return pending.future;
                },
                child: TextButton(
                  onPressed: () => clicks++,
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(reads, 0, reason: 'Mounting is not a prefetch signal.');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final center = tester.getCenter(find.text('Open'));
      await mouse.moveTo(center);
      await tester.pump(const Duration(milliseconds: 200));
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 400));
      expect(reads, 0);
      await mouse.moveTo(center);
      await tester.pump(const Duration(milliseconds: 350));
      expect(reads, 1);
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(clicks, 1, reason: 'A held prefetch cannot lock navigation.');
      await tester.pump(const Duration(seconds: 2));
      expect(
        reads,
        1,
        reason: 'Remaining over the same target is not polling.',
      );
      await mouse.removePointer();
      pending.complete();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keyboard focus warms once; disposal cancels scheduled work; failure is optional',
    (tester) async {
      var reads = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget view() => MaterialApp(
        home: NavigationPrefetch(
          prepare: () async {
            reads++;
            throw StateError('offline');
          },
          child: Focus(
            focusNode: focus,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      await tester.pumpWidget(view());
      focus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(reads, 1);
      expect(tester.takeException(), isNull);
      focus.unfocus();
      await tester.pump();
      focus.requestFocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 1);
    },
  );
}
