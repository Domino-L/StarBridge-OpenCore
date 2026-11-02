import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace, flush;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;

final _review = visualOutputDir(
  'interaction_motion_batch3ge_20261017',
  legacySubdirectory: 'review',
);

class _Probe {
  _Probe(this.suite, {this.large = false});
  final InteractionSuite suite;
  bool reduce = false, large;
  final native = BrowserFake();
  final work = workspace();
  final capture = GlobalKey();
  Completer<Object?>? opening;
  late StateSetter update;
  SemanticsHandle? semantics;
  Future<Object?> call(String action, Map<String, Object?> args) {
    if (action == 'browserOpen' && opening != null) {
      native.calls.add((action, {...args}));
      return opening!.future;
    }
    return native.call(action, args);
  }

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          MenuBrowserTool(call: call, workspace: work),
          suite,
          reduce: reduce,
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
    for (final pending in [
      opening,
      native.pendingAction,
      native.pendingState,
      native.pendingConfiguration,
    ]) {
      if (pending != null && !pending.isCompleted) pending.complete(null);
    }
    await flush(t);
    work.dispose();
    semantics?.dispose();
    semantics = null;
    expect(t.takeException(), isNull);
  }
}

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p) async {
  p.semantics = t.ensureSemantics();
  size(t, const Size(1200, 1000));
  await t.pumpWidget(p.app());
  await frames(t);
}

Finder marker(String phase) =>
    find.byKey(ValueKey('menu-browser-$phase-activity'));
void waiting(WidgetTester t, String phase, {required bool animated}) {
  expect(marker(phase), findsOneWidget);
  final busy = find.descendant(
    of: marker(phase),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

Future<void> press(WidgetTester t, String label, String source) async {
  await actTarget(
    t,
    find.byWidgetPredicate((w) => w is BridgeMenuAction && w.label == label),
    source,
  );
  await frames(t);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3ge native startup unknown wait has a static marker', (t) async {
    final p = _Probe(InteractionSuite.standard)..opening = Completer();
    await mount(t, p);
    waiting(t, 'starting', animated: false);
    expect(p.native.calls.where((c) => c.$1 == 'browserOpen'), hasLength(1));
    await p.clean(t);
  });
  testWidgets('3ge actual visit held command keeps mouse feedback', (t) async {
    final p = _Probe(InteractionSuite.rail);
    await mount(t, p);
    p.native.pendingAction = Completer();
    await t.enterText(
      find.byKey(const ValueKey('browser-address')),
      'https://example.test/next',
    );
    await press(t, '访问', 'pointer');
    waiting(t, 'command', animated: true);
    await p.clean(t);
  });
  moreCases();
}

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
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
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
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3ge $suite native new-tab button $source keeps actual source',
        (t) async {
          final p = _Probe(suite);
          await mount(t, p);
          p.native.pendingAction = Completer();
          final target = find.byKey(const ValueKey('browser-new-tab'));
          if (source == 'pointer') {
            await t.tap(target);
          } else if (source == 'keyboard') {
            t.widget<IconButton>(target).focusNode!.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            final node = t.getSemantics(target);
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              node.id,
              ui.SemanticsAction.tap,
            );
          }
          await frames(t);
          waiting(t, 'command', animated: source == 'pointer');
          expect(
            p.native.calls
                .where((c) => c.$1 == 'browserNewTab')
                .map((c) => c.$2)
                .toList(),
            [
              {
                'url': p.native.calls
                    .firstWhere((c) => c.$1 == 'browserOpen')
                    .$2['url'],
              },
            ],
          );
          await p.clean(t);
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3ge $suite $source visit held then native loading stays unknown',
        (t) async {
          final p = _Probe(suite);
          await mount(t, p);
          p.native.pendingAction = Completer();
          final field = find.byKey(const ValueKey('browser-address'));
          await t.enterText(field, 'https://example.test/next');
          await press(t, '访问', source);
          waiting(t, 'command', animated: source == 'pointer');
          expect(
            p.native.calls
                .where((c) => c.$1 == 'browserNavigate')
                .map((c) => c.$2)
                .toList(),
            [
              {'tabId': 't1', 'url': 'https://example.test/next'},
            ],
          );
          p.update(() => p.reduce = true);
          await frames(t, 2);
          waiting(t, 'command', animated: false);
          p.update(() => p.reduce = false);
          await frames(t, 2);
          waiting(t, 'command', animated: source == 'pointer');
          // Editing remains live under the original native request.
          await t.enterText(field, 'keep-this-draft');
          p.native.tabs.first['loading'] = true;
          p.native.pendingAction!.complete(null);
          p.native.pendingAction = null;
          await frames(t);
          expect(marker('command'), findsNothing);
          waiting(t, 'page', animated: false);
          expect(
            t.widget<SocialReadActivity>(marker('page')).source,
            InteractionSource.programmatic,
          );
          expect(
            t.widget<TextField>(field).controller!.text,
            'keep-this-draft',
          );
          p.native.tabs.first['loading'] = false;
          await t.pump(const Duration(seconds: 1));
          await flush(t);
          expect(marker('page'), findsNothing);
          expect(
            p.native.calls.where((c) => c.$1 == 'browserNavigate'),
            hasLength(1),
          );
          await p.clean(t);
        },
      );
      testWidgets('3ge $suite native startup failure explicit $source retry', (
        t,
      ) async {
        final p = _Probe(suite)..opening = Completer();
        await mount(t, p);
        waiting(t, 'starting', animated: false);
        p.opening!.completeError(StateError('synthetic open failure'));
        await frames(t);
        expect(marker('starting'), findsNothing);
        expect(find.textContaining('浏览器无法启动'), findsOneWidget);
        p.opening = Completer();
        await press(t, '重试', source);
        waiting(t, 'starting', animated: source == 'pointer');
        expect(
          p.native.calls.where((c) => c.$1 == 'browserOpen'),
          hasLength(2),
        );
        p.opening!.complete(null);
        p.opening = null;
        await frames(t);
        expect(marker('starting'), findsNothing);
        expect(
          p.native.calls.where((c) => c.$1 == 'browserConfigure'),
          hasLength(1),
        );
        await p.clean(t);
      });
      testWidgets(
        '3ge $suite $source command failure keeps draft until explicit retry',
        (t) async {
          final p = _Probe(suite);
          await mount(t, p);
          p.native.pendingAction = Completer();
          final field = find.byKey(const ValueKey('browser-address'));
          await t.enterText(field, 'https://example.test/failed');
          await press(t, '访问', source);
          p.native.pendingAction!.completeError(
            StateError('synthetic command failure'),
          );
          p.native.pendingAction = null;
          await frames(t);
          expect(marker('command'), findsNothing);
          expect(
            t.widget<TextField>(field).controller!.text,
            'https://example.test/failed',
          );
          expect(find.text('操作未完成，请检查当前标签页后重试。'), findsOneWidget);
          expect(
            p.native.calls.where((c) => c.$1 == 'browserNavigate'),
            hasLength(1),
          );
          p.native.pendingAction = Completer();
          await press(t, '访问', source);
          waiting(t, 'command', animated: source == 'pointer');
          expect(
            p.native.calls.where((c) => c.$1 == 'browserNavigate'),
            hasLength(2),
          );
          p.native.pendingAction!.complete(null);
          p.native.pendingAction = null;
          await frames(t);
          await p.clean(t);
        },
      );
    }
    testWidgets('3ge $suite address submit Enter is explicitly keyboard', (
      t,
    ) async {
      final p = _Probe(suite);
      await mount(t, p);
      p.native.pendingAction = Completer();
      await t.enterText(
        find.byKey(const ValueKey('browser-address')),
        'https://example.test/enter',
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await frames(t);
      waiting(t, 'command', animated: false);
      expect(
        t.widget<SocialReadActivity>(marker('command')).source,
        InteractionSource.keyboard,
      );
      expect(p.native.calls.where((c) => c.$1 == 'browserNavigate').last.$2, {
        'tabId': 't1',
        'url': 'https://example.test/enter',
      });
      await p.clean(t);
    });
    testWidgets(
      '3ge $suite passive native loading never dispatches a navigation',
      (t) async {
        final p = _Probe(suite);
        p.native.tabs.first['loading'] = true;
        await mount(t, p);
        waiting(t, 'page', animated: false);
        final calls = p.native.calls
            .where((c) => c.$1 == 'browserNavigate')
            .length;
        await t.pump(const Duration(seconds: 2));
        await flush(t);
        waiting(t, 'page', animated: false);
        expect(
          p.native.calls.where((c) => c.$1 == 'browserNavigate'),
          hasLength(calls),
        );
        p.native.tabs.first['loading'] = false;
        p.native.tabs.first['failed'] = true;
        await t.pump(const Duration(seconds: 1));
        await flush(t);
        expect(marker('page'), findsNothing);
        expect(find.text('网页未能打开，请检查地址或刷新重试。'), findsOneWidget);
        await p.clean(t);
      },
    );
    for (final phase in ['starting', 'command']) {
      testWidgets('3ge $suite $phase late reply after disposal cannot reopen', (
        t,
      ) async {
        final p = _Probe(suite);
        if (phase == 'starting') p.opening = Completer();
        await mount(t, p);
        if (phase == 'command') {
          p.native.pendingAction = Completer();
          await press(t, '刷新', 'pointer');
        }
        final opens = p.native.calls.where((c) => c.$1 == 'browserOpen').length;
        await p.clean(t);
        expect(find.byType(MenuBrowserTool), findsNothing);
        expect(
          p.native.calls.where((c) => c.$1 == 'browserOpen'),
          hasLength(opens),
        );
        expect(p.native.calls.last.$1, 'browserBounds');
        expect(p.native.calls.last.$2, {'visible': false});
      });
    }
    for (final phase in ['command', 'page', 'starting']) {
      testWidgets(
        '3ge review $suite $phase local feedback stable and reduced',
        (t) async {
          final p = _Probe(suite, large: true);
          if (phase == 'starting') p.opening = Completer();
          if (phase == 'page') p.native.tabs.first['loading'] = true;
          await mount(t, p);
          if (phase == 'command') {
            p.native.pendingAction = Completer();
            await press(t, '刷新', 'pointer');
          }
          await frames(t);
          final rect = t.getRect(marker(phase));
          expect(rect.height, 2);
          final a = await pixels(t, p, rect, png: '$phase-${suite.name}');
          var maxChange = 0;
          for (final interval in [80, 128, 256]) {
            await t.pump(Duration(milliseconds: interval));
            final b = await pixels(t, p, rect);
            final count = changed(a, b);
            if (count > maxChange) maxChange = count;
          }
          if (phase == 'command') {
            expect(maxChange, greaterThan(0));
          } else {
            expect(maxChange, 0);
          }
          p.update(() => p.reduce = true);
          await frames(t, 2);
          final c = await pixels(t, p, rect);
          await frames(t, 38);
          final d = await pixels(t, p, rect);
          expect(changed(c, d), 0);
          expect(t.getRect(marker(phase)), rect);
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
