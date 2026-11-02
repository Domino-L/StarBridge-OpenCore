import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_event_export.dart';
import 'package:starbridge_flutter/features/settings/local_event_export_action.dart';
import 'package:starbridge_flutter/features/settings/local_event_clear_action.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ac_test.dart' show choose;
import 'interaction_batch3bb_coverage_test.dart' show activate;
import 'interaction_batch3bc_test.dart'
    show HistoryPort, ClearPort, ExportPort, page, action;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite keyboard-opened history load keeps decoration static', (
      t,
    ) async {
      final port = HistoryPort('pending')
        ..pending = Completer<LocalHistoryPage>();
      final controller = LocalHistoryController(port);
      addTearDown(controller.dispose);
      late BuildContext caller;
      await mount(
        t,
        Builder(
          builder: (c) {
            caller = c;
            return const Text('Open');
          },
        ),
        suite,
      );
      final pending = showStarBridgeDialog<void>(
        caller,
        source: InteractionSource.keyboard,
        builder: (_) => LocalEventHistoryDialog(controller: controller),
      );
      await t.pump();
      await t.pump();
      final frameContext = t.element(find.byType(SuiteBusyFrame).first);
      expect(InteractionScope.of(frameContext).reduceMotion, true);
      await t.pumpAndSettle();
      port.pending!.complete(page('pending'));
      await t.pump();
      await t.pumpAndSettle();
      await activate(t, 'history-close', 'keyboard');
      await pending;
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite pending clear follows reduce and confirmation scope live',
      (t) async {
        final port = ClearPort()..pending = Completer<String>();
        final live = await mount(
          t,
          LocalEventClearAction(
            port: port,
            enabled: true,
            refresh: () async {},
          ),
          suite,
        );
        await activate(t, 'history-clear', 'pointer');
        await t.pumpAndSettle();
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(
            t.element(find.byKey(const Key('history-clear-confirm'))),
          ).reduceMotion,
          true,
        );
        await activate(t, 'history-clear-confirm', 'keyboard');
        await t.pumpAndSettle();
        expect(port.calls, 1);
        port.pending!.complete('unknown');
        await t.pump();
        await t.pumpAndSettle();
        expect(find.text('清空结果尚未确认，请查看刷新后的记录。'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final code in [
      'saved',
      'cancelled',
      'fileExists',
      'invalidDestination',
      'dataUnavailable',
      'empty',
      'busy',
      'unavailable',
      'failed',
      'unknown',
    ]) {
      testWidgets('$suite export actual outcome $code', (t) async {
        final port = ExportPort()
          ..result = LocalEventExportResult(
            code,
            count: code == 'saved' ? 5 : 0,
          );
        await mount(
          t,
          LocalEventExportAction(port: port, enabled: true),
          suite,
        );
        await activate(t, 'history-export', 'pointer');
        await t.pumpAndSettle();
        expect(port.calls, 1);
        expect(port.locale, 'zh-CN');
        expect(find.byKey(const Key('history-export-result')), findsOneWidget);
        expect(
          find.text('已导出 5 条记录'),
          code == 'saved' ? findsOneWidget : findsNothing,
        );
        final frame = t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame));
        expect(frame.busy, false);
        expect(frame.doneToken, code == 'cancelled' ? 0 : 1);
        expect(
          frame.doneOutcome,
          code == 'saved' ? TaskOutcome.success : TaskOutcome.failure,
        );
        await t.pumpWidget(const SizedBox());
      });
    }
    for (final code in [
      'cleared',
      'failed',
      'unavailable',
      'busy',
      'unknown',
    ]) {
      testWidgets(
        '$suite clear actual outcome $code refreshes once and never invents empty',
        (t) async {
          final port = ClearPort()..result = code;
          var refreshes = 0;
          await mount(
            t,
            LocalEventClearAction(
              port: port,
              enabled: true,
              refresh: () async {
                refreshes++;
              },
            ),
            suite,
          );
          await activate(t, 'history-clear', 'pointer');
          await t.pumpAndSettle();
          expect(port.calls, 0);
          expect(
            t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame).first).busy,
            false,
          );
          await activate(t, 'history-clear-confirm', 'pointer');
          await t.pumpAndSettle();
          expect(port.calls, 1);
          expect(refreshes, 1);
          expect(find.byKey(const Key('history-clear-result')), findsOneWidget);
          expect(
            find.text('已清空本地事件记录'),
            code == 'cleared' ? findsOneWidget : findsNothing,
          );
          expect(
            t
                .widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame).first)
                .doneOutcome,
            code == 'cleared' ? TaskOutcome.success : TaskOutcome.failure,
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final kind in ['export', 'clear']) {
        testWidgets(
          '$suite $kind $source final activation source is preserved',
          (t) async {
            final semantics = t.ensureSemantics();
            final export = ExportPort(), clear = ClearPort();
            var refreshes = 0;
            await mount(
              t,
              kind == 'export'
                  ? LocalEventExportAction(port: export, enabled: true)
                  : LocalEventClearAction(
                      port: clear,
                      enabled: true,
                      refresh: () async {
                        refreshes++;
                      },
                    ),
              suite,
            );
            await activate(t, 'history-$kind', source);
            await t.pumpAndSettle();
            if (kind == 'clear') {
              final route = ModalRoute.of(t.element(find.byType(AlertDialog)));
              expect(route, isA<StarBridgeDialogRoute>());
              expect(
                (route as StarBridgeDialogRoute).instant,
                source != 'pointer',
              );
              expect(clear.calls, 0);
              await activate(t, 'history-clear-confirm', source);
              await t.pumpAndSettle();
              expect(clear.calls, 1);
              expect(refreshes, 1);
            }
            expect(
              kind == 'export' ? export.source : clear.source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
    testWidgets(
      '$suite clear mixed pointer open keyboard confirm uses final source',
      (t) async {
        final port = ClearPort();
        await mount(
          t,
          LocalEventClearAction(
            port: port,
            enabled: true,
            refresh: () async {},
          ),
          suite,
        );
        await activate(t, 'history-clear', 'pointer');
        await t.pumpAndSettle();
        await activate(t, 'history-clear-confirm', 'keyboard');
        await t.pumpAndSettle();
        expect(port.source, InteractionSource.keyboard);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite confirmation Esc has no destructive command or success flash',
      (t) async {
        final port = ClearPort();
        var refreshes = 0;
        await mount(
          t,
          LocalEventClearAction(
            port: port,
            enabled: true,
            refresh: () async {
              refreshes++;
            },
          ),
          suite,
        );
        await activate(t, 'history-clear', 'keyboard');
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.calls, 0);
        expect(refreshes, 0);
        expect(
          t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame)).doneToken,
          0,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite invalidation retires owned confirmation not unrelated route',
      (t) async {
        final a = ClearPort(), b = ClearPort();
        var current = a;
        late StateSetter update;
        Future<void> refresh() async {}
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return LocalEventClearAction(
                port: current,
                enabled: true,
                refresh: refresh,
              );
            },
          ),
          suite,
        );
        await activate(t, 'history-clear', 'pointer');
        await t.pumpAndSettle();
        final c = t.element(find.byType(AlertDialog));
        final unrelated = showDialog<void>(
          context: c,
          builder: (_) => const AlertDialog(content: Text('Unrelated route')),
        );
        await t.pumpAndSettle();
        update(() => current = b);
        await t.pump();
        await t.pumpAndSettle();
        expect(find.text('Unrelated route'), findsOneWidget);
        expect(find.byKey(const Key('history-clear-confirm')), findsNothing);
        Navigator.of(t.element(find.text('Unrelated route'))).pop();
        await t.pumpAndSettle();
        await unrelated;
        expect(a.calls, 0);
        expect(b.calls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite late clear cannot refresh new owner even with same port',
      (t) async {
        final port = ClearPort()..pending = Completer<String>();
        var aRefreshes = 0, bRefreshes = 0;
        Future<void> aRefresh() async {
          aRefreshes++;
        }

        Future<void> bRefresh() async {
          bRefreshes++;
        }

        var refresh = aRefresh;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return LocalEventClearAction(
                port: port,
                enabled: true,
                refresh: refresh,
              );
            },
          ),
          suite,
        );
        await activate(t, 'history-clear', 'pointer');
        await t.pumpAndSettle();
        await activate(t, 'history-clear-confirm', 'pointer');
        await t.pump(const Duration(seconds: 1));
        expect(port.calls, 1);
        update(() => refresh = bRefresh);
        await t.pump();
        await t.pumpAndSettle();
        port.pending!.complete('cleared');
        await t.pump();
        await t.pumpAndSettle();
        expect(aRefreshes, 0);
        expect(bRefreshes, 0);
        expect(find.byKey(const Key('history-clear-result')), findsNothing);
        expect(port.cancelled, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite disabled confirmation cannot later delete', (t) async {
      final port = ClearPort();
      var enabled = true;
      late StateSetter update;
      Future<void> refresh() async {}
      await mount(
        t,
        StatefulBuilder(
          builder: (_, s) {
            update = s;
            return LocalEventClearAction(
              port: port,
              enabled: enabled,
              refresh: refresh,
            );
          },
        ),
        suite,
      );
      await activate(t, 'history-clear', 'pointer');
      await t.pumpAndSettle();
      final cached = action(t, 'history-clear-confirm').onActivate!;
      update(() => enabled = false);
      await t.pump();
      await t.pumpAndSettle();
      cached(InteractionSource.pointer);
      await t.pumpAndSettle();
      expect(port.calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(action(t, 'history-clear').onActivate, isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite held export stops decoration on reduce and ignores late old port',
      (t) async {
        final a = ExportPort()..pending = Completer<LocalEventExportResult>(),
            b = ExportPort();
        var current = a;
        late StateSetter update;
        final live = await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return LocalEventExportAction(port: current, enabled: true);
            },
          ),
          suite,
        );
        await activate(t, 'history-export', 'pointer');
        await t.pump(const Duration(milliseconds: 100));
        expect(a.calls, 1);
        expect(action(t, 'history-export').onActivate, isNull);
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        update(() => current = b);
        await t.pump();
        await t.pumpAndSettle();
        a.pending!.complete(const LocalEventExportResult('saved', count: 5));
        await t.pump();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('history-export-result')), findsNothing);
        expect(a.cancelled, 1);
        expect(b.calls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite history refresh retains rows on wait and failure then explicit retry',
      (t) async {
        final port = HistoryPort('retained'),
            controller = LocalHistoryController(port);
        addTearDown(controller.dispose);
        await mount(t, LocalEventHistoryDialog(controller: controller), suite);
        port.pending = Completer<LocalHistoryPage>();
        await activate(t, 'history-refresh', 'pointer');
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('retained'), findsOneWidget);
        expect(action(t, 'history-refresh').onActivate, isNull);
        port.pending!.completeError(StateError('fixture failure'));
        await t.pump();
        await t.pumpAndSettle();
        expect(find.text('retained'), findsOneWidget);
        expect(find.byKey(const Key('history-empty')), findsNothing);
        port.pending = null;
        await activate(t, 'history-refresh', 'keyboard');
        await t.pumpAndSettle();
        expect(port.reads.length, 3);
        expect(controller.value.failure, isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite history replaces controller during read and resets category field',
      (t) async {
        final a = HistoryPort('old'), b = HistoryPort('new');
        final ca = LocalHistoryController(a), cb = LocalHistoryController(b);
        addTearDown(ca.dispose);
        addTearDown(cb.dispose);
        var current = ca;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return LocalEventHistoryDialog(controller: current);
            },
          ),
          suite,
        );
        final finder = find.byKey(const Key('history-category'));
        await choose<String>(t, finder, 'life', 'keyboard');
        expect(ca.value.category, 'life');
        final cached = t
            .widget<StarBridgeSelectFormField<String>>(finder)
            .onChanged!;
        a.pending = Completer<LocalHistoryPage>();
        await activate(t, 'history-refresh', 'pointer');
        await t.pump();
        update(() => current = cb);
        await t.pump();
        await t.pumpAndSettle();
        cached('ship');
        await t.pumpAndSettle();
        a.pending!.complete(page('stale'));
        await t.pump();
        await t.pumpAndSettle();
        expect(find.text('new'), findsOneWidget);
        expect(find.text('stale'), findsNothing);
        expect(cb.value.category, 'all');
        expect(b.reads.length, 1);
        expect(t.state<FormFieldState<String>>(finder).value, 'all');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite history rapid active refresh is not coalesced after each reply',
      (t) async {
        final port = HistoryPort('active'),
            controller = LocalHistoryController(port);
        addTearDown(controller.dispose);
        await mount(t, LocalEventHistoryDialog(controller: controller), suite);
        for (var i = 0; i < 3; i++) {
          await t.tap(find.byKey(const Key('history-refresh')));
          await t.pump();
        }
        expect(port.reads.length, 4);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite real history widget review frames', (t) async {
      final port = HistoryPort('合成舰船记录'),
          controller = LocalHistoryController(port);
      final export = ExportPort()
        ..pending = Completer<LocalEventExportResult>();
      final clear = ClearPort();
      addTearDown(controller.dispose);
      final capture = GlobalKey();
      final live = await mount(
        t,
        LocalEventHistoryDialog(
          controller: controller,
          exportPort: export,
          clearPort: clear,
        ),
        suite,
        capture: capture,
      );
      Future<void> save(String phase) async {
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3bc');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await save('ready');
      await activate(t, 'history-export', 'pointer');
      await t.pump(const Duration(milliseconds: 100));
      await save('busy');
      export.pending!.complete(const LocalEventExportResult('unknown'));
      await t.pump();
      await t.pumpAndSettle();
      await save('unknown');
      await activate(t, 'history-clear', 'pointer');
      await t.pumpAndSettle();
      await save('confirm');
      await activate(t, 'history-clear-cancel', 'keyboard');
      await t.pumpAndSettle();
      live.change(() => live.light = true);
      await t.pump();
      await t.pumpAndSettle();
      await save('light');
      expect(clear.calls, 0);
      await t.pumpWidget(const SizedBox());
    });
  }
}
