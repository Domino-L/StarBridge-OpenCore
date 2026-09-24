import 'dart:async';

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/features/settings/bridge_local_event_history.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  test('background updates retain page and failed refresh retains history', () async {
    final port = _MutableHistoryPort();
    final controller = LocalHistoryController(port);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.next();
    port.revision = 'B' * 64;
    await controller.checkForUpdates();
    expect(controller.value.hasUpdates, isTrue);
    expect(controller.value.page!.offset, 50);
    port.fail = true;
    await controller.refresh();
    expect(controller.value.failure, 'readFailed');
    expect(controller.value.page!.offset, 50);
    port.fail = false;
    await controller.refresh();
    expect(controller.value.page!.offset, 0);
    expect(controller.value.hasUpdates, isFalse);
  });
  testWidgets('embedded history reuses paging without a dialog close action', (
    tester,
  ) async {
    final controller = LocalHistoryController(_Port());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, embedded: true));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('history-close')), findsNothing);
    expect(find.text('1–50 / 75'), findsOneWidget);
    final row = tester.widget<Container>(
      find.byKey(const ValueKey('history-entry-0')),
    );
    expect(((row.decoration as BoxDecoration).border as Border).left.width, 3);
    await tester.ensureVisible(find.byKey(const Key('history-next')));
    await tester.tap(find.byKey(const Key('history-next')));
    await tester.pumpAndSettle();
    expect(find.text('51–75 / 75'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'controller filters and pages; changed revision starts once from page one',
    () async {
      final port = _Port();
      final controller = LocalHistoryController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.value.page!.entries, hasLength(50));
      await controller.next();
      expect(controller.value.page!.offset, 50);
      port.changed = true;
      await controller.previous();
      expect(controller.value.page!.offset, 0);
      expect(controller.value.changed, isTrue);
      port.changed = true;
      await controller.next();
      expect(controller.value.page!.offset, 0);
      expect(controller.value.changed, isTrue);
      await controller.select('life');
      expect(controller.value.page!.filteredCount, 0);
      expect(controller.value.category, 'life');
      expect(port.requests.last.$1, 'life');
      expect(port.requests.last.$2, 0);
    },
  );
  test(
    'busy requests coalesce, close discards late data without another read',
    () async {
      final port = _Port()..pending = Completer();
      final controller = LocalHistoryController(port);
      final reading = controller.refresh();
      await controller.refresh();
      await controller.select('life');
      expect(port.requests, hasLength(1));
      controller.dispose();
      port.pending!.complete(_page());
      await reading;
      await controller.refresh();
      expect(port.requests, hasLength(1));
    },
  );
  test('read timeout does not invent empty history', () async {
    final port = _Port()..pending = Completer();
    final controller = LocalHistoryController(
      port,
      timeout: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.value.failure, 'readFailed');
    expect(controller.value.page, isNull);
  });
  test('bridge sends bounded accountless query and parses strict normalized fields', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 2,
    );
    addTearDown(session.close);
    final result = await BridgeLocalEventHistory(session)
        .read(category: 'all', offset: 0, pageSize: 50);
    expect(result.entries.single.title, 'Event');
    expect(connection.sent.single.accountContext, isNull);
    expect(connection.sent.single.name, 'diagnostics.getLocalEvents');
    expect(connection.sent.single.payload, {
      'schemaVersion': 1,
      'category': 'all',
      'offset': 0,
      'pageSize': 50,
      'revision': null,
    });
  });
  for (final kind in [
    'extra',
    'sourceLine',
    'wrongCount',
    'wrongCategory',
    'badDate',
    'badRevision',
    'wrongPage',
    'missingAsData',
  ]) {
    test('bridge rejects $kind without exposing raw error', () async {
      final connection = _Connection();
      final entry =
          (connection.payload['entries'] as List).single
              as Map<String, Object?>;
      switch (kind) {
        case 'extra':
          connection.payload['path'] = 'private';
        case 'sourceLine':
          entry['sourceLine'] = 'raw secret';
        case 'wrongCount':
          connection.payload['filteredCount'] = 3;
        case 'wrongCategory':
          entry['category'] = 'unknown';
        case 'badDate':
          entry['occurredAt'] = 'not-date';
        case 'badRevision':
          connection.payload['revision'] = 'secret';
        case 'wrongPage':
          connection.payload['offset'] = 50;
        case 'missingAsData':
          connection.payload['state'] = 'missing';
      }
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeLocalEventHistory(session)
            .read(category: 'all', offset: 0, pageSize: 50),
        throwsFormatException,
      );
    });
  }
  testWidgets('actual dialog filters, pages and keeps export/clear disabled', (
    tester,
  ) async {
    final controller = LocalHistoryController(_Port());
    addTearDown(controller.dispose);
    await _open(tester, controller);
    expect(find.text('本机已保存的历史记录'), findsOneWidget);
    expect(find.text('1–50 / 75'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('history-export')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('history-clear')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('history-next')));
    await tester.pumpAndSettle();
    expect(find.text('51–75 / 75'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生命状态').last);
    await tester.pumpAndSettle();
    expect(find.text('此类别没有记录'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-close')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalEventHistoryDialog), findsNothing);
  });
  for (final state in ['missing', 'unavailable', 'recovered']) {
    testWidgets('displays $state distinctly without offering writes', (
      tester,
    ) async {
      final controller = LocalHistoryController(_Port()..state = state);
      addTearDown(controller.dispose);
      await _open(tester, controller);
      expect(
        find.byKey(
          Key(
            state == 'missing'
                ? 'history-empty'
                : state == 'recovered'
                ? 'history-backup'
                : 'history-failure',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('history-close')));
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'closing during load ignores late result; failure text hides internals',
    (tester) async {
      final port = _Port()..pending = Completer();
      final controller = LocalHistoryController(port);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('history-close')));
      await tester.pump(const Duration(milliseconds: 300));
      controller.dispose();
      port.pending!.completeError(
        StateError('private raw log path credentials'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LocalEventHistoryDialog), findsNothing);
      expect(find.textContaining('private'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('390px list wraps long records: $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = LocalHistoryController(
          _Port()
            ..state = 'recovered'
            ..long = true,
        );
        addTearDown(controller.dispose);
        await _open(tester, controller, locale: locale, mode: mode);
        await tester.drag(find.byType(ListView), const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('history-close')));
        await tester.pumpAndSettle();
      });
    }
  }
}

Future<void> _open(
  WidgetTester tester,
  LocalHistoryController controller, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) async {
  await tester.pumpWidget(_app(controller, locale: locale, mode: mode));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Widget _app(
  LocalHistoryController controller, {
  bool embedded = false,
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.runtimeSupportedLocales(),
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    StyleRegistry().resolve(AppPreferences.defaults.designStyleId, mode).tokens,
    locale,
  ),
  home: Scaffold(
    body: embedded
        ? SingleChildScrollView(
            child: LocalEventHistoryDialog(
              controller: controller,
              embedded: true,
            ),
          )
        : Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => LocalEventHistoryDialog(controller: controller),
              ),
              child: const Text('Open'),
            ),
          ),
  ),
);

LocalHistoryPage _page({
  int offset = 0,
  String state = 'ready',
  bool empty = false,
  bool long = false,
}) {
  final total = state == 'missing' || state == 'unavailable' ? 0 : 75;
  final count = empty ? 0 : total;
  return LocalHistoryPage(
    state: state,
    totalCount: total,
    filteredCount: count,
    offset: offset,
    pageSize: 50,
    hasMore: offset + 50 < count,
    revision: 'A' * 64,
    entries: List.generate(
      (count - offset).clamp(0, 50),
      (i) => LocalHistoryEntry(
        id: '${offset + i}',
        at: DateTime.utc(2026, 9, 10, 12),
        category: 'ship',
        eventType: 'Synthetic',
        title: long ? 'Long title ' * 15 : 'Event ${offset + i}',
        detail: long ? 'Long detail ' * 40 : 'detail',
      ),
    ),
  );
}

class _MutableHistoryPort implements LocalHistoryPort {
  bool fail = false;
  String revision = 'A' * 64;
  @override
  Future<LocalHistoryPage> read({required String category, required int offset, required int pageSize, String? revision}) async {
    if (fail) throw const LocalHistoryException('unavailable');
    final page = _page(offset: offset);
    return LocalHistoryPage(state: page.state, totalCount: page.totalCount, filteredCount: page.filteredCount,
      offset: offset, pageSize: pageSize, hasMore: page.hasMore, entries: page.entries, revision: this.revision);
  }
}

class _Port implements LocalHistoryPort {
  String state = 'ready';
  bool changed = false, long = false;
  Completer<LocalHistoryPage>? pending;
  final requests = <(String, int, String?)>[];
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async {
    requests.add((category, offset, revision));
    if (pending != null) return pending!.future;
    if (changed && revision != null) {
      changed = false;
      throw const LocalHistoryException('changed');
    }
    return _page(
      offset: offset,
      state: state,
      empty: category != 'all',
      long: long,
    );
  }
}

class _Connection implements BridgeConnection {
  final _incoming = StreamController<BridgeEnvelope>();
  final sent = <BridgeEnvelope>[];
  final payload = <String, Object?>{
    'schemaVersion': 1,
    'state': 'ready',
    'totalCount': 1,
    'filteredCount': 1,
    'offset': 0,
    'pageSize': 50,
    'hasMore': false,
    'revision': 'A' * 64,
    'entries': [
      <String, Object?>{
        'id': 'one',
        'occurredAt': '2026-09-10T12:00:00+00:00',
        'category': 'ship',
        'eventType': 'Synthetic',
        'title': 'Event',
        'detail': 'Detail',
      },
    ],
  };
  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    sent.add(request);
    _incoming.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: 'ok',
        payload: payload,
      ),
    );
  }

  @override
  Future<void> close() => _incoming.close();
}
