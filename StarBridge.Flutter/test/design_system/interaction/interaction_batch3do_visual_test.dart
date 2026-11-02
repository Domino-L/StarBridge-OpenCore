import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/diagnostics_maintenance_panel.dart';
import 'package:starbridge_flutter/features/settings/flutter_installation_panel.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/maintenance_action.dart';

import 'interaction_batch3do_test.dart'
    show BridgeFixture, SupportFixture, scopedApp, size, loadFonts, invoke;

Future<List<int>> pixels(WidgetTester t, Finder target) => t
    .runAsync(() async {
      final render = t.renderObject(target) as RenderRepaintBoundary;
      final image = await render.toImage();
      try {
        return (await image.toByteData())!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    })
    .then((value) => value!);
Future<void> capture(WidgetTester t, GlobalKey key, String name) => t.runAsync(
  () async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final f = File('build/reviews/interaction-batch3do/$name.png');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
    } finally {
      image.dispose();
    }
  },
);

void visibleWaiting(WidgetTester t) {
  final target = find.byType(HelpSupportWaiting);
  expect(target, findsOneWidget);
  expect(t.getTopLeft(target).dy, greaterThanOrEqualTo(0));
  expect(t.getBottomRight(target).dy, lessThanOrEqualTo(800));
}

Future<void> finishDialogExit(WidgetTester t) async {
  // A single long pump starts the route controller on that one frame. Step
  // finite frames so this capture shows pending feedback after actual exit,
  // without pumpAndSettle advancing an indefinite request to its timeout.
  await t.pump();
  for (
    var i = 0;
    i < 12 && find.byType(AlertDialog).evaluate().isNotEmpty;
    i++
  ) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$config actual maintenance controls remain visible in a long narrow scroll page',
          (t) async {
            final semantics = t.ensureSemantics();
            final fixture = BridgeFixture(), support = SupportFixture();
            addTearDown(fixture.close);
            addTearDown(support.dispose);
            try {
              size(t, const Size(390, 800));
              t.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
              final frame = GlobalKey(), scroll = ScrollController();
              addTearDown(scroll.dispose);
              Future<void> bottomClick(String key) async {
                final control = find.byKey(Key(key));
                await t.ensureVisible(control);
                final target = 800 - t.getSize(control).height - 12;
                scroll.jumpTo(
                  (scroll.offset + t.getTopLeft(control).dy - target).clamp(
                    0.0,
                    scroll.position.maxScrollExtent,
                  ),
                );
                await t.pumpAndSettle();
                expect(t.getTopLeft(control).dy, greaterThan(650));
                await t.tap(control);
              }

              Widget host({bool reduce = false}) => RepaintBoundary(
                key: frame,
                child: scopedApp(
                  SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 1400),
                        DiagnosticsMaintenancePanel(
                          support: support,
                          session: fixture.session,
                        ),
                        const SizedBox(height: 24),
                        FlutterInstallationPanel(session: fixture.session),
                      ],
                    ),
                  ),
                  suite,
                  light: light,
                  reduce: reduce,
                ),
              );
              await t.pumpWidget(host());
              await t.pumpAndSettle();
              await bottomClick('maintenance-clear-cache');
              await t.pumpAndSettle();
              await invoke(
                t,
                'maintenance-confirm-execute',
                '清理图片缓存',
                'pointer',
              );
              await finishDialogExit(t);
              visibleWaiting(t);
              await capture(t, frame, '3do-$config-clearing');
              final node = t
                  .getSemantics(find.byType(HelpSupportWaiting))
                  .getSemanticsData();
              expect(node.label, '正在清理图片缓存…');
              expect(node.value, isEmpty);
              await t.pumpWidget(host(reduce: true));
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              visibleWaiting(t);
              final still = await pixels(t, find.byKey(frame));
              await t.pump(const Duration(milliseconds: 300));
              expect(await pixels(t, find.byKey(frame)), orderedEquals(still));
              await capture(t, frame, '3do-$config-clearing-reduced');
              await fixture.reply(0, {'schemaVersion': 1, 'count': 0});
              await t.pumpAndSettle();
              final cleared = find.text('已清理可重新下载的图片缓存，其他图片和数据已保留。');
              expect(t.getTopLeft(cleared).dy, greaterThanOrEqualTo(0));
              expect(t.getBottomRight(cleared).dy, lessThanOrEqualTo(800));
              await capture(t, frame, '3do-$config-cleared');
              await t.pumpWidget(host());
              await t.pumpAndSettle();
              await bottomClick('flutter-installation-scan');
              await t.pump(const Duration(milliseconds: 120));
              visibleWaiting(t);
              await capture(t, frame, '3do-$config-checking');
              await fixture.reply(1, fixture.plan());
              await t.pumpAndSettle();
              await bottomClick('flutter-installation-uninstall');
              await t.pumpAndSettle();
              final dialog = find.byType(AlertDialog);
              expect(t.getTopLeft(dialog).dy, greaterThanOrEqualTo(0));
              expect(t.getBottomRight(dialog).dy, lessThanOrEqualTo(800));
              expect(find.byType(HelpSupportWaiting), findsNothing);
              for (final key in [
                'installation-confirm-cancel',
                'installation-confirm-execute',
              ]) {
                final control = find.byKey(Key(key));
                expect(t.getTopLeft(control).dy, greaterThanOrEqualTo(0));
                expect(t.getBottomRight(control).dy, lessThanOrEqualTo(800));
              }
              await capture(t, frame, '3do-$config-confirming');
              await invoke(
                t,
                'installation-confirm-execute',
                '卸载客户端',
                'pointer',
              );
              await finishDialogExit(t);
              visibleWaiting(t);
              await capture(t, frame, '3do-$config-opening-wizard');
              await fixture.reply(2, {'schemaVersion': 1, 'completed': true});
              await t.pumpAndSettle();
              final started = find.text('卸载向导已启动，请在向导中继续。');
              expect(t.getTopLeft(started).dy, greaterThanOrEqualTo(0));
              expect(t.getBottomRight(started).dy, lessThanOrEqualTo(800));
              await capture(t, frame, '3do-$config-wizard-started');
              // Compare all three plain button variants against original public
              // native geometry using the same production theme and text scale.
              for (final kind in ['quiet', 'secondary', 'primary']) {
                ButtonStyleButton make() => switch (kind) {
                  'quiet' => TextButton(
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                  'primary' => FilledButton(
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                  _ => OutlinedButton(
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                };
                final nativeKey = GlobalKey(), adaptedKey = GlobalKey();
                final original = make();
                final keyed = switch (kind) {
                  'quiet' => TextButton(
                    key: const Key('geometry-action'),
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                  'primary' => FilledButton(
                    key: const Key('geometry-action'),
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                  _ => OutlinedButton(
                    key: const Key('geometry-action'),
                    onPressed: () {},
                    child: const Text('操作'),
                  ),
                };
                await t.pumpWidget(
                  scopedApp(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(key: nativeKey, child: original),
                        SizedBox(
                          key: adaptedKey,
                          child: MaintenanceAction(keyed),
                        ),
                      ],
                    ),
                    suite,
                    light: light,
                  ),
                );
                await t.pumpAndSettle();
                expect(
                  t.getSize(find.byKey(adaptedKey)),
                  t.getSize(find.byKey(nativeKey)),
                  reason: kind,
                );
              }
              await t.pumpWidget(const SizedBox());
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
