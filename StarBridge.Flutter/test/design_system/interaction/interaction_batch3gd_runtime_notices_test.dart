import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/application_lifecycle_prompts.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/widgets/connection_status_notice.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3gc_profile_media_test.dart' show actKey;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;

final _review = visualOutputDir(
  'interaction_motion_batch3gd_20261017',
  legacySubdirectory: 'review',
);

class _Probe {
  _Probe(this.suite, {this.light = false, this.large = false});
  final InteractionSuite suite;
  bool light, large, reduce = false, externalRetry = false;
  bool retryAvailable = true;
  int retries = 0;
  final saves = <bool>[];
  Completer<void> retry = Completer();
  Completer<bool> save = Completer();
  final capture = GlobalKey();
  SemanticsHandle? semantics;
  late StateSetter update;
  bool? closeResult;
  bool startupReturned = false;
  ConnectionIssueAction action = ConnectionIssueAction.retry;
  ConnectionVisualState tone = ConnectionVisualState.disconnected;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConnectionStatusNotice(
                  issue: ConnectionIssueProjection(
                    domain: ConnectionStatusDomain.host,
                    titleKey: 'connection.host.disconnected.title',
                    detailKey: 'connection.host.disconnected.detail',
                    state: tone,
                    action: action,
                  ),
                  retrying: externalRetry,
                  onRetry: retryAvailable
                      ? () {
                          retries++;
                          return retry.future;
                        }
                      : null,
                ),
                StarBridgeActionButton(
                  controlKey: const Key('open-startup'),
                  onActivate: (_) async {
                    await showFirstStartupChoicePrompt(
                      context,
                      onSave: (selected) {
                        saves.add(selected);
                        return save.future;
                      },
                    );
                    startupReturned = true;
                  },
                  child: const Text('Startup'),
                ),
                StarBridgeActionButton(
                  controlKey: const Key('open-close'),
                  onActivate: (_) async {
                    closeResult = await showFirstCloseBehaviorPrompt(context);
                  },
                  child: const Text('Close prompt'),
                ),
              ],
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: base.home,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
        );
      },
    ),
  );
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    semantics?.dispose();
    semantics = null;
    expect(t.takeException(), isNull);
  }
}

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p) async {
  p.semantics = t.ensureSemantics();
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3gd keyboard connection retry must not loop', (t) async {
    final p = _Probe(InteractionSuite.standard);
    await mount(t, p);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await frames(t);
    expect(p.retries, 1);
    final progress = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, isNotNull);
    p.retry.complete();
    await frames(t);
    await p.clean(t);
  });
  testWidgets('3gd startup uses approved source aware route', (t) async {
    final p = _Probe(InteractionSuite.scan);
    await mount(t, p);
    await actKey(t, const Key('open-startup'), 'keyboard');
    await frames(t);
    final dialog = find.byKey(const Key('first-startup-choice-dialog'));
    expect(dialog, findsOneWidget);
    expect(ModalRoute.of(t.element(dialog)), isA<StarBridgeDialogRoute>());
    await p.clean(t);
  });
  moreCases();
}

Finder marker(String key) => find.byKey(Key(key));
void waiting(WidgetTester t, String key, {required bool animated}) {
  expect(marker(key), findsOneWidget);
  final busy = find.descendant(
    of: marker(key),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

Future<void> toggle(WidgetTester t, String source) =>
    actTarget(t, find.byType(StarBridgeSwitch), source);

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void moreCases() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '3gd $suite startup pointer entry keyboard save exits without animation tail',
      (t) async {
        final p = _Probe(suite);
        await mount(t, p);
        await actKey(t, const Key('open-startup'), 'pointer');
        await frames(t, 40);
        final route = ModalRoute.of(
          t.element(marker('first-startup-choice-dialog')),
        ) as StarBridgeDialogRoute;
        await actKey(t, const Key('first-startup-continue'), 'keyboard');
        await frames(t);
        waiting(t, 'first-startup-save-activity', animated: false);
        expect(p.saves, [true]);
        p.save.complete(true);
        await t.pump();
        expect(route.animation!.value, 0);
        expect(p.startupReturned, isTrue);
        await frames(t);
        await p.clean(t);
      },
    );
    testWidgets(
      '3gd $suite restore-online caption preserves original callback',
      (t) async {
        final p = _Probe(suite)
          ..action = ConnectionIssueAction.restoreOnline
          ..tone = ConnectionVisualState.stale;
        await mount(t, p);
        expect(find.text('继续恢复在线'), findsOneWidget);
        await actKey(t, const Key('connection-status-retry'), 'reader');
        await frames(t);
        expect(p.retries, 1);
        waiting(t, 'connection-status-retry-loading', animated: false);
        p.retry.complete();
        await frames(t);
        expect(find.text('继续恢复在线'), findsOneWidget);
        await p.clean(t);
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3gd $suite $source local retry then external waiting uses no stale source',
        (t) async {
          final p = _Probe(suite);
          await mount(t, p);
          await actKey(t, const Key('connection-status-retry'), source);
          await frames(t);
          expect(p.retries, 1);
          waiting(
            t,
            'connection-status-retry-loading',
            animated: source == 'pointer',
          );
          final wrapper = find
              .ancestor(
                of: marker('connection-status-retry'),
                matching: find.byType(StarBridgeActionButton),
              )
              .first;
          expect(t.widget<StarBridgeActionButton>(wrapper).onActivate, isNull);
          p.update(() => p.reduce = true);
          await frames(t, 2);
          waiting(t, 'connection-status-retry-loading', animated: false);
          p.update(() => p.reduce = false);
          await frames(t, 2);
          waiting(
            t,
            'connection-status-retry-loading',
            animated: source == 'pointer',
          );
          p.update(() => p.externalRetry = true);
          p.retry.complete();
          await frames(t);
          waiting(t, 'connection-status-retry-loading', animated: false);
          expect(p.retries, 1);
          p.update(() => p.externalRetry = false);
          await frames(t);
          expect(marker('connection-status-retry-loading'), findsNothing);
          // The authoritative issue remains until the original owner changes it.
          expect(find.text('客户端连接中断'), findsOneWidget);
          p.retry = Completer();
          await actKey(t, const Key('connection-status-retry'), source);
          await frames(t);
          expect(p.retries, 2);
          p.retry.complete();
          await frames(t);
          await p.clean(t);
        },
      );
      testWidgets(
        '3gd $suite startup $source saved false keeps selection and explicit retry',
        (t) async {
          final p = _Probe(suite);
          await mount(t, p);
          await actKey(t, const Key('open-startup'), source);
          await frames(t, 40);
          expect(
            t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
            isTrue,
          );
          await toggle(t, source);
          await frames(t);
          expect(
            t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
            isFalse,
          );
          await actKey(t, const Key('first-startup-continue'), source);
          await frames(t);
          waiting(
            t,
            'first-startup-save-activity',
            animated: source == 'pointer',
          );
          expect(p.saves, [false]);
          expect(
            t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).onChanged,
            isNull,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await frames(t);
          expect(marker('first-startup-choice-dialog'), findsOneWidget);
          p.update(() => p.reduce = true);
          await frames(t, 2);
          waiting(t, 'first-startup-save-activity', animated: false);
          p.update(() => p.reduce = false);
          await frames(t, 2);
          waiting(
            t,
            'first-startup-save-activity',
            animated: source == 'pointer',
          );
          p.save.complete(false);
          await frames(t);
          expect(p.startupReturned, isFalse);
          expect(marker('first-startup-save-activity'), findsNothing);
          expect(find.text('启动设置未能保存，请检查后台连接后重试。'), findsOneWidget);
          expect(
            t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
            isFalse,
          );
          p.save = Completer();
          await actKey(t, const Key('first-startup-continue'), source);
          await frames(t);
          expect(p.saves, [false, false]);
          p.save.complete(true);
          await frames(t, 40);
          expect(p.startupReturned, isTrue);
          expect(marker('first-startup-choice-dialog'), findsNothing);
          await p.clean(t);
        },
      );
      for (final background in [false, true]) {
        testWidgets(
          '3gd $suite close $source returns exact $background without saving',
          (t) async {
            final p = _Probe(suite);
            await mount(t, p);
            await actKey(t, const Key('open-close'), source);
            await frames(t, 40);
            expect(
              ModalRoute.of(t.element(marker('first-close-behavior-dialog'))),
              isA<StarBridgeDialogRoute>(),
            );
            await actKey(
              t,
              Key(background ? 'first-close-background' : 'first-close-exit'),
              source,
            );
            await frames(t, 40);
            expect(p.closeResult, background);
            expect(p.saves, isEmpty);
            expect(p.retries, 0);
            await p.clean(t);
          },
        );
      }
    }
    for (final dismissal in ['escape', 'barrier']) {
      testWidgets('3gd $suite close $dismissal returns null not exit', (
        t,
      ) async {
        final p = _Probe(suite);
        await mount(t, p);
        await actKey(t, const Key('open-close'), 'pointer');
        await frames(t, 40);
        if (dismissal == 'escape') {
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await t.tapAt(const Offset(10, 10));
        }
        await frames(t, 40);
        expect(p.closeResult, isNull);
        expect(marker('first-close-behavior-dialog'), findsNothing);
        expect(p.saves, isEmpty);
        await p.clean(t);
      });
    }
    testWidgets(
      '3gd $suite external wait alone stays static and no retry callback',
      (t) async {
        final p = _Probe(suite)..externalRetry = true;
        await mount(t, p);
        waiting(t, 'connection-status-retry-loading', animated: false);
        expect(p.retries, 0);
        p.update(() => p.retryAvailable = false);
        await frames(t);
        expect(marker('connection-status-retry'), findsNothing);
        expect(marker('connection-status-retry-loading'), findsNothing);
        await p.clean(t);
      },
    );
    for (final phase in ['retry', 'startup']) {
      testWidgets('3gd $suite $phase late completion after unmount', (t) async {
        final p = _Probe(suite);
        await mount(t, p);
        if (phase == 'retry') {
          await actKey(t, const Key('connection-status-retry'), 'pointer');
        } else {
          await actKey(t, const Key('open-startup'), 'pointer');
          await frames(t, 40);
          await actKey(t, const Key('first-startup-continue'), 'pointer');
        }
        await frames(t);
        await t.pumpWidget(const SizedBox());
        if (phase == 'retry') {
          p.retry.complete();
        } else {
          p.save.complete(true);
        }
        await frames(t);
        expect(p.retries, phase == 'retry' ? 1 : 0);
        expect(p.saves, phase == 'startup' ? [true] : isEmpty);
        p.semantics?.dispose();
        p.semantics = null;
        expect(t.takeException(), isNull);
      });
      testWidgets(
        '3gd review $suite $phase original geometry feedback and reduced settle',
        (t) async {
          final p = _Probe(
            suite,
            large: true,
            light:
                suite == InteractionSuite.rail ||
                suite == InteractionSuite.glow,
          );
          await mount(t, p);
          if (phase == 'retry') {
            await actKey(t, const Key('connection-status-retry'), 'pointer');
          } else {
            await actKey(t, const Key('open-startup'), 'pointer');
            await frames(t, 40);
            await actKey(t, const Key('first-startup-continue'), 'pointer');
          }
          await frames(t);
          final target = marker(
            phase == 'retry'
                ? 'connection-status-retry-loading'
                : 'first-startup-save-activity',
          );
          final rect = t.getRect(target);
          if (phase == 'retry') {
            expect(
              rect.size,
              Size(16, suite == InteractionSuite.standard ? 16 : 2),
            );
          }
          final a = await pixels(t, p, rect, png: '$phase-${suite.name}');
          var maxChange = 0;
          for (final interval in [80, 128, 256]) {
            await t.pump(Duration(milliseconds: interval));
            final b = await pixels(t, p, rect);
            final count = changed(a, b);
            if (count > maxChange) maxChange = count;
          }
          expect(maxChange, greaterThan(0));
          p.update(() => p.reduce = true);
          await frames(t, 2);
          final c = await pixels(t, p, rect);
          await frames(t, 38);
          final d = await pixels(t, p, rect);
          expect(changed(c, d), 0);
          expect(t.getRect(target), rect);
          File('$_review/$phase-${suite.name}.json').writeAsStringSync(
            jsonEncode({
              'movingPixels': maxChange,
              'staticPixels': changed(c, d),
              'rect': [rect.left, rect.top, rect.width, rect.height],
            }),
          );
          await p.clean(t);
        },
      );
    }
  }
}
