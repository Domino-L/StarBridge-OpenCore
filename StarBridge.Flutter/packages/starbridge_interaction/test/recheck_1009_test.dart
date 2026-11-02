// 2026-10-09 recheck R1: the caller's *effective* settings — including a
// local MediaQuery.disableAnimations below the navigator — must reach menus
// and dialogs mounted in the overlay, live, before / during entrance and
// during exit, with the scope above or below the navigator, nested, and
// with the global system setting as a control.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

const _animated = [InteractionSuite.rail, InteractionSuite.scan, InteractionSuite.glow];

enum _Surface { menu, dialog }

/// [local] drives a MediaQuery override wrapped around the page, below the
/// navigator. [scopeAbove] puts the InteractionScope above MaterialApp
/// instead of inside the page. [nestedSuite] adds an inner scope inside the
/// page (the outer one stays rail).
Widget _app({
  required InteractionSuite suite,
  required ValueNotifier<bool> local,
  required _Surface surface,
  bool scopeAbove = false,
  InteractionSuite? nestedSuite,
}) {
  final data = InteractionData(suite: suite, palette: palette);
  Widget opener = Builder(
    builder: (context) => GestureDetector(
      onTap: () => surface == _Surface.menu
          ? showSuiteContextMenu(
              context,
              position: const Offset(120, 120),
              actions: [SuiteMenuAction(label: '加入', onSelected: () {})],
            )
          : showSuiteDialog<void>(
              context,
              (ctx) => TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('对话框')),
            ),
      child: const Text('open'),
    ),
  );
  if (nestedSuite != null) {
    opener = InteractionScope(data: data.copyWith(suite: nestedSuite), child: opener);
  }
  final page = ValueListenableBuilder(
    valueListenable: local,
    builder: (context, reduce, _) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: Scaffold(body: opener),
    ),
  );
  if (scopeAbove) {
    return InteractionScope(data: data, child: MaterialApp(home: page));
  }
  return MaterialApp(home: InteractionScope(data: data, child: page));
}

String get _label => '加入';

Finder _content(_Surface s) => find.text(s == _Surface.menu ? _label : '对话框');

/// What the open surface reads, from inside the overlay.
InteractionData _overlay(WidgetTester t, _Surface s) => InteractionScope.of(t.element(_content(s)));

/// What the caller reads in place.
InteractionData _caller(WidgetTester t) => InteractionScope.of(t.element(find.text('open')));

Future<void> _settleCheck(WidgetTester t, _Surface s) async {
  // Three frames, as in the recheck probe.
  await t.pump();
  await t.pump();
  await t.pump();
  expect(_caller(t).reduceMotion, isTrue);
  expect(_overlay(t, s).reduceMotion, isTrue, reason: 'overlay must read the caller\'s effective setting');
  if (s == _Surface.dialog) {
    final route = ModalRoute.of(t.element(_content(s)))!;
    expect(route.animation!.status, AnimationStatus.completed);
  }
  expect(t.hasRunningAnimations, isFalse);
}

void main() {
  tearDown(() => expect(InteractionScope.debugLiveLinks, 0, reason: 'every relay released'));

  group('link churn', linkChurnTests);

  for (final surface in _Surface.values) {
    group('R1 ${surface.name}', () {
      for (final suite in _animated) {
        testWidgets('${suite.name}: local reduced motion mid-entrance settles it (scope below navigator)', (t) async {
          final local = ValueNotifier(false);
          addTearDown(local.dispose);
          await t.pumpWidget(_app(suite: suite, local: local, surface: surface));
          await t.tap(find.text('open'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 60));
          expect(t.hasRunningAnimations, isTrue);
          local.value = true;
          await _settleCheck(t, surface);
          await _close(t, surface);
        });

        testWidgets('${suite.name}: local reduced motion before opening opens it static', (t) async {
          final local = ValueNotifier(true);
          addTearDown(local.dispose);
          await t.pumpWidget(_app(suite: suite, local: local, surface: surface));
          await t.tap(find.text('open'));
          await t.pump();
          await t.pump();
          expect(_overlay(t, surface).reduceMotion, isTrue);
          if (surface == _Surface.dialog) {
            expect(ModalRoute.of(t.element(_content(surface)))!.animation!.status, AnimationStatus.completed);
          }
          expect(t.hasRunningAnimations, isFalse);
          await _close(t, surface);
        });

        testWidgets('${suite.name}: local reduced motion mid-exit removes it at once', (t) async {
          final local = ValueNotifier(false);
          addTearDown(local.dispose);
          await t.pumpWidget(_app(suite: suite, local: local, surface: surface));
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
          await _startClose(t, surface);
          await t.pump();
          await t.pump(const Duration(milliseconds: 30));
          expect(_content(surface), findsOneWidget, reason: 'still leaving');
          local.value = true;
          await t.pump();
          await t.pump();
          await t.pump();
          expect(_content(surface), findsNothing);
          expect(t.hasRunningAnimations, isFalse);
        });

        testWidgets('${suite.name}: scope above the navigator, local MediaQuery below it', (t) async {
          final local = ValueNotifier(false);
          addTearDown(local.dispose);
          await t.pumpWidget(_app(suite: suite, local: local, surface: surface, scopeAbove: true));
          await t.tap(find.text('open'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 60));
          local.value = true;
          await _settleCheck(t, surface);
          await _close(t, surface);
        });
      }

      testWidgets('nested scope: the surface follows the inner suite and the local setting', (t) async {
        final local = ValueNotifier(false);
        addTearDown(local.dispose);
        await t.pumpWidget(
          _app(suite: InteractionSuite.rail, local: local, surface: surface, scopeAbove: true, nestedSuite: InteractionSuite.scan),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        expect(_overlay(t, surface).suite, InteractionSuite.scan);
        local.value = true;
        await _settleCheck(t, surface);
        expect(_overlay(t, surface).suite, InteractionSuite.scan);
        await _close(t, surface);
      });

      testWidgets('turning the local setting off again is followed too', (t) async {
        final local = ValueNotifier(true);
        addTearDown(local.dispose);
        await t.pumpWidget(_app(suite: InteractionSuite.glow, local: local, surface: surface));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(_overlay(t, surface).reduceMotion, isTrue);
        local.value = false;
        await t.pump();
        await t.pump();
        expect(_overlay(t, surface).reduceMotion, isFalse);
        await _close(t, surface);
      });

      testWidgets('control: global system reduced motion reaches it', (t) async {
        final local = ValueNotifier(false);
        addTearDown(local.dispose);
        t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await t.pumpWidget(_app(suite: InteractionSuite.scan, local: local, surface: surface));
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump();
        expect(_overlay(t, surface).reduceMotion, isTrue);
        expect(t.hasRunningAnimations, isFalse);
        await _close(t, surface);
      });
    });
  }

  testWidgets('a normal pointer entrance still animates when nothing is reduced', (t) async {
    final local = ValueNotifier(false);
    addTearDown(local.dispose);
    await t.pumpWidget(_app(suite: InteractionSuite.scan, local: local, surface: _Surface.dialog));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(ModalRoute.of(t.element(find.text('对话框')))!.animation!.status, AnimationStatus.forward);
    await t.pumpAndSettle();
    await _close(t, _Surface.dialog);
  });
}

Future<void> _startClose(WidgetTester t, _Surface s) async {
  if (s == _Surface.menu) {
    await t.tapAt(const Offset(700, 500));
  } else {
    await t.tap(find.text('对话框'));
  }
}

Future<void> _close(WidgetTester t, _Surface s) async {
  await _startClose(t, s);
  await t.pumpAndSettle();
  expect(_content(s), findsNothing);
}

// Follow-up to the R1 recheck: a link that is unsubscribed and resubscribed
// before its pending check ran must not stack a second check chain.
/// Draws one frame even when nothing in the tree changed.
Future<void> frame(WidgetTester t) async {
  t.binding.scheduleFrame();
  await t.pump();
}

void linkChurnTests() {
  for (final pumpBetween in [false, true]) {
    testWidgets('resubscribing 20 times keeps one check per frame (pump between: $pumpBetween)', (t) async {
      late BuildContext origin;
      await t.pumpWidget(
        MaterialApp(
          home: InteractionScope(
            data: InteractionData(suite: InteractionSuite.scan, palette: palette),
            child: Builder(builder: (context) {
              origin = context;
              return const SizedBox();
            }),
          ),
        ),
      );
      final link = InteractionScope.linkOf(origin)!;
      void listener() {}
      for (var i = 0; i < 20; i++) {
        link.addListener(listener);
        link.removeListener(listener);
        if (pumpBetween) await frame(t);
      }
      link.addListener(listener);
      await frame(t);
      final before = InteractionScope.debugLinkChecks;
      for (var i = 0; i < 5; i++) {
        await frame(t);
      }
      expect(InteractionScope.debugLinkChecks - before, 5);
      link.removeListener(listener);
      await frame(t);
      final after = InteractionScope.debugLinkChecks;
      await frame(t);
      await frame(t);
      expect(InteractionScope.debugLinkChecks, after, reason: 'no checks once unsubscribed');
      expect(InteractionScope.debugLiveLinks, 0);
    });
  }
}
