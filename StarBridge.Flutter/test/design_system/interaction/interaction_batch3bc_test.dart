import 'dart:async';

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_event_export.dart';
import 'package:starbridge_flutter/features/settings/local_event_export_action.dart';
import 'package:starbridge_flutter/features/settings/local_event_clear.dart';
import 'package:starbridge_flutter/features/settings/local_event_clear_action.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bb_coverage_test.dart' show activate;

class HistoryPort implements LocalHistoryPort {
  HistoryPort(this.label);
  final String label;
  final reads = <(String, int)>[];
  Completer<LocalHistoryPage>? pending;
  bool failed = false;
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async {
    reads.add((category, offset));
    if (failed) throw StateError('synthetic read failure');
    return pending?.future ?? page(label, offset: offset);
  }
}

LocalHistoryPage page(String label, {int offset = 0}) => LocalHistoryPage(
  state: 'ready',
  totalCount: 100,
  filteredCount: 100,
  offset: offset,
  pageSize: 50,
  hasMore: offset == 0,
  revision: 'fixture',
  entries: [
    LocalHistoryEntry(
      id: label,
      at: DateTime.utc(2026),
      category: 'ship',
      eventType: 'fixture',
      title: label,
      detail: 'Synthetic detail',
    ),
  ],
);

class ExportPort implements LocalEventExportPort {
  int calls = 0, cancelled = 0;
  String? locale;
  InteractionSource? source;
  LocalEventExportResult result = const LocalEventExportResult(
    'saved',
    count: 5,
  );
  Completer<LocalEventExportResult>? pending;
  @override
  Future<LocalEventExportResult> export(String language) async {
    calls++;
    locale = language;
    source = currentStarBridgeActivationSource;
    return pending?.future ?? result;
  }

  @override
  void cancel() {
    cancelled++;
  }
}

class ClearPort implements LocalEventClearPort {
  int calls = 0, cancelled = 0;
  String result = 'cleared';
  InteractionSource? source;
  Completer<String>? pending;
  @override
  Future<String> clear() async {
    calls++;
    source = currentStarBridgeActivationSource;
    return pending?.future ?? result;
  }

  @override
  void cancel() {
    cancelled++;
  }
}

StarBridgeActionButton action(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(
      find
          .ancestor(
            of: find.byKey(Key(key)),
            matching: find.byType(StarBridgeActionButton),
          )
          .first,
    );

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite history rebind refreshes new controller and rejects cached old action',
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
              return LocalEventHistoryDialog(
                controller: current,
                embedded: true,
              );
            },
          ),
          suite,
        );
        final cached = action(t, 'history-refresh').onActivate!;
        update(() => current = cb);
        await t.pump();
        await t.pumpAndSettle();
        expect(b.reads.length, 1);
        expect(find.text('new'), findsOneWidget);
        cached(InteractionSource.pointer);
        await t.pumpAndSettle();
        expect(a.reads.length, 1);
        expect(b.reads.length, 1);
        await t.pumpWidget(const SizedBox());
        ca.dispose();
        cb.dispose();
      },
    );
    testWidgets('$suite keyboard history factory is immediate live route', (
      t,
    ) async {
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
      final pending = runStarBridgeActivation<void>(
        InteractionSource.keyboard,
        () => showLocalEventHistory(caller),
      );
      await t.pump();
      await t.pumpAndSettle();
      final context = t.element(find.byType(LocalEventHistoryDialog));
      final route = ModalRoute.of(context);
      Navigator.of(context).pop();
      await t.pumpAndSettle();
      await pending;
      expect(route, isA<StarBridgeDialogRoute>());
      expect((route as StarBridgeDialogRoute).instant, true);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite replaced export rejects cached command and preserves keyboard source',
      (t) async {
        final a = ExportPort(), b = ExportPort();
        var current = a;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return LocalEventExportAction(port: current, enabled: true);
            },
          ),
          suite,
        );
        final cached = action(t, 'history-export').onActivate!;
        update(() => current = b);
        await t.pump();
        await t.pumpAndSettle();
        cached(InteractionSource.pointer);
        await t.pumpAndSettle();
        expect(a.calls, 0);
        expect(b.calls, 0);
        await activate(t, 'history-export', 'keyboard');
        await t.pumpAndSettle();
        expect(b.calls, 1);
        expect(b.source, InteractionSource.keyboard);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite invalidated clear retires only its confirmation and rejects cached command',
      (t) async {
        final a = ClearPort(), b = ClearPort();
        var current = a;
        late StateSetter update;
        var refreshes = 0;
        Future<void> refresh() async {
          refreshes++;
        }

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
        final cached = action(t, 'history-clear').onActivate!;
        await activate(t, 'history-clear', 'pointer');
        await t.pumpAndSettle();
        expect(find.byKey(const Key('history-clear-confirm')), findsOneWidget);
        update(() => current = b);
        await t.pump();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('history-clear-confirm')), findsNothing);
        cached(InteractionSource.pointer);
        await t.pumpAndSettle();
        expect(a.calls, 0);
        expect(b.calls, 0);
        expect(refreshes, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
