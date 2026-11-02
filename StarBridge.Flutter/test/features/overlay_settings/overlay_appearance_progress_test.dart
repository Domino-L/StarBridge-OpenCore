import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_progress.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_collection_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_appearance_center.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

Map<String, Object?> receipt({
  int? total,
  String state = 'ready',
  String id = 'Fixture',
}) => {
  'schemaVersion': 1,
  'appearanceId': id,
  'state': state,
  'confirmedUsageMs': total,
  'items': [
    {
      'id': 'gift',
      'label': {'zhCN': '初始物件', 'zhTW': '初始物件', 'en': 'Included item'},
      'requiredUsageMs': 0,
      'remainingMs': 0,
      'owned': true,
    },
    {
      'id': 'later',
      'label': {'zhCN': '后续物件', 'zhTW': '後續物件', 'en': 'Later item'},
      'requiredUsageMs': 60000,
      'remainingMs': total == null ? null : (60000 - total).clamp(0, 60000),
      'owned': total != null && total >= 60000,
    },
  ],
};
OverlayAppearanceProgress parse(Map<String, Object?> value) =>
    OverlayAppearanceProgress.fromMap(
      value,
      appearanceId: value['appearanceId'] as String,
    );

final class Port implements OverlayAppearanceProgressPort {
  final owner = StreamController<void>.broadcast(sync: true);
  final requests = <String>[];
  final pending = <Completer<OverlayAppearanceProgress>>[];
  OverlayAppearanceProgress value = parse(receipt(total: 15000));
  bool hold = false, fail = false;
  @override
  bool get supportsAppearanceProgress => true;
  @override
  Stream<void> get appearanceOwnerChanges => owner.stream;
  @override
  Future<OverlayAppearanceProgress> readAppearanceProgress(String id) async {
    requests.add(id);
    if (fail) throw StateError('lost response');
    if (hold) {
      final next = Completer<OverlayAppearanceProgress>();
      pending.add(next);
      return next.future;
    }
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['STARBRIDGE_COLLECTION_CAPTURE'] != null) {
      await loadFonts();
    }
  });
  test(
    'bounded immutable readonly receipt keeps unknown distinct from zero',
    () {
      final input = receipt(state: 'accountSyncPending');
      final value = parse(input);
      (input['items'] as List).clear();
      expect(value.confirmedUsageMs, isNull);
      expect(value.items.length, 2);
      expect(value.items.first.owned, isTrue);
      expect(value.items.last.owned, isFalse);
      expect(value.items.last.remainingMs, isNull);
      expect(() => value.items.clear(), throwsUnsupportedError);
      expect(parse(receipt(total: 0)).confirmedUsageMs, 0);
      expect(parse(receipt(total: 60000)).items.last.owned, isTrue);
      for (final mutate in <void Function(Map<String, Object?>)>[
        (m) => m['schemaVersion'] = 1.0,
        (m) => m['schemaVersion'] = 2,
        (m) => m['state'] = 'bogus',
        (m) => m['accountId'] = 'injected',
        (m) => m['confirmedUsageMs'] = -1,
        (m) => m['confirmedUsageMs'] = 9007199254740992,
        (m) => m['confirmedUsageMs'] = 0.5,
        (m) => (m['items'] as List)[1]['owned'] = true,
        (m) => (m['items'] as List)[1]['remainingMs'] = 0,
        (m) => (m['items'] as List)[1]['id'] = 'gift',
        (m) => (m['items'] as List)[1]['equip'] = 'command',
        (m) => m['items'] = [],
        (m) {
          m['state'] = 'signedOut';
          m['confirmedUsageMs'] = 0;
        },
      ]) {
        final bad = receipt(state: 'accountSyncPending');
        mutate(bad);
        expect(() => parse(bad), throwsFormatException);
      }
      expect(
        () =>
            OverlayAppearanceProgress.fromMap(receipt(), appearanceId: 'Other'),
        throwsFormatException,
      );
    },
  );

  test('real Bridge adapter sends only readonly identity and invalidates on account change', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['overlay.appearanceProgress']);
    final requests = <BridgeEnvelope>[];
    bool hold = false;
    final sub = pair.host.incoming.listen((request) {
      if (request.messageType != 'request') return;
      requests.add(request);
      if (!hold) {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: receipt(total: 15000),
            ),
          ),
        );
      }
    });
    final adapter = BridgeOverlayWorkspaceAdapter(session);
    var changed = 0;
    final owners = adapter.appearanceOwnerChanges.listen((_) => changed++);
    try {
      expect(
        (await adapter.readAppearanceProgress('Fixture')).confirmedUsageMs,
        15000,
      );
      expect(requests.single.name, 'overlay.appearanceProgress.read');
      expect(requests.single.payload, {
        'schemaVersion': 1,
        'appearanceId': 'Fixture',
      });
      expect(requests.single.accountContext, isNull);
      expect(
        () => session.request('overlay.appearanceProgress.report'),
        throwsA(isA<BridgeAccountContextRequiredException>()),
      );
      hold = true;
      final pending = adapter.readAppearanceProgress('Fixture');
      final stale = expectLater(
        pending,
        throwsA(isA<BridgeStaleGenerationException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 2,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await stale;
      await Future<void>.delayed(Duration.zero);
      expect(changed, 1);
      session.acceptHostCapabilities([]);
      expect(adapter.supportsAppearanceProgress, isFalse);
      expect(() => adapter.readAppearanceProgress('Fixture'), throwsStateError);
      expect(requests.every((r) => r.name.endsWith('.read')), isTrue);
    } finally {
      await owners.cancel();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    }
  });

  Future<void> show(
    WidgetTester tester,
    Port port, {
    String id = 'Fixture',
    double width = 420,
  }) async {
    size(tester, Size(width, 800));
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: OverlayAppearanceCollectionPanel(appearanceId: id, port: port),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> remove(WidgetTester tester, Port port) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await port.owner.close();
  }

  testWidgets(
    'unknown has no invented zero or countdown and does not place a gift',
    (tester) async {
      final port = Port()..value = parse(receipt(state: 'accountSyncPending'));
      await show(tester, port);
      expect(find.text('初始拥有'), findsOneWidget);
      expect(find.text('等待进度同步'), findsOneWidget);
      expect(find.text('使用进度尚未同步'), findsOneWidget);
      expect(find.textContaining('0分钟'), findsNothing);
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(port.requests, ['Fixture']);
      expect(tester.takeException(), isNull);
      await remove(tester, port);
    },
  );
  testWidgets(
    'confirmations alone advance unlock status, not elapsed page time',
    (tester) async {
      final port = Port();
      await show(tester, port);
      expect(find.text('还需使用 不足1分钟'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(port.requests.length, 2);
      expect(find.text('已解锁'), findsNothing);
      port.value = parse(receipt(total: 60000));
      await tester.tap(find.byKey(const Key('appearance-collection-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('已解锁'), findsOneWidget);
      expect(find.text('已确认使用：1分钟'), findsOneWidget);
      await remove(tester, port);
    },
  );
  testWidgets(
    'switch account removes old receipt immediately and rejects late replies',
    (tester) async {
      final port = Port()..value = parse(receipt(total: 60000));
      await show(tester, port);
      port.hold = true;
      await tester.tap(find.byKey(const Key('appearance-collection-refresh')));
      await tester.pump();
      port.owner.add(null);
      await tester.pump();
      expect(find.text('已解锁'), findsNothing);
      expect(port.pending.length, 2);
      port.pending[0].complete(parse(receipt(total: 60000)));
      await tester.pumpAndSettle();
      expect(find.text('已解锁'), findsNothing);
      port.pending[1].complete(parse(receipt(state: 'signedOut')));
      await tester.pumpAndSettle();
      expect(find.text('登录后读取账号收藏'), findsOneWidget);
      await remove(tester, port);
    },
  );
  testWidgets(
    'selection change rejects late previous appearance and disposal stops reads',
    (tester) async {
      final port = Port()..hold = true;
      await show(tester, port);
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OverlayAppearanceCollectionPanel(
              appearanceId: 'Other',
              port: port,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(port.pending.length, 2);
      port.pending[0].complete(parse(receipt(total: 60000)));
      await tester.pumpAndSettle();
      expect(find.text('已解锁'), findsNothing);
      port.pending[1].complete(parse(receipt(id: 'Other', total: 0)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('appearance-collection-Other')),
        findsOneWidget,
      );
      final count = port.requests.length;
      await remove(tester, port);
      await tester.pump(const Duration(seconds: 30));
      expect(port.requests.length, count);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'background has no new reads, resumed refreshes, loss clears stale display',
    (tester) async {
      final port = Port()..value = parse(receipt(total: 60000));
      await show(tester, port);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(port.requests.length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(port.requests.length, 2);
      port.fail = true;
      await tester.tap(find.byKey(const Key('appearance-collection-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('已解锁'), findsNothing);
      expect(find.textContaining('未能读取收藏'), findsOneWidget);
      port.fail = false;
      port.value = parse(receipt(total: 0));
      await tester.tap(find.byKey(const Key('appearance-collection-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('已确认使用：0分钟'), findsOneWidget);
      await remove(tester, port);
    },
  );
  testWidgets('disconnect clears collection and stops periodic query', (
    tester,
  ) async {
    final port = Port()..value = parse(receipt(total: 60000));
    await show(tester, port);
    await port.owner.close();
    await tester.pumpAndSettle();
    expect(find.text('已解锁'), findsNothing);
    final before = port.requests.length;
    await tester.pump(const Duration(seconds: 30));
    expect(port.requests.length, before);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  for (final width in [280.0, 420.0, 760.0]) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'collection status remains readable at $width $mode with large text',
        (tester) async {
          size(tester, Size(width, 1000));
          final port = Port();
          for (final state in [
            'ready',
            'signedOut',
            'authenticationRequired',
            'waitingAcknowledgement',
            'anotherSession',
            'resyncRequired',
            'unavailable',
          ]) {
            port.value = parse(
              receipt(
                state: state,
                total: state == 'signedOut' || state == 'authenticationRequired'
                    ? null
                    : 0,
              ),
            );
            await tester.pumpWidget(
              app(
                MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: SingleChildScrollView(
                    child: OverlayAppearanceCollectionPanel(
                      key: ValueKey(state),
                      appearanceId: 'Fixture',
                      port: port,
                    ),
                  ),
                ),
                mode,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('appearance-collection-status')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
          await remove(tester, port);
        },
      );
    }
  }
  testWidgets(
    'actual Native Bridge receipts render with no local acquisition policy',
    (tester) async {
      final report = Platform.environment['STARBRIDGE_COLLECTION_REPORT']!;
      // Widget tests use a fake scheduler; inspect the finished fixture
      // synchronously, then reserve runAsync for raster/image IO below.
      final native = jsonDecode(File(report).readAsStringSync()) as Map;
      expect(native['passed'], isTrue);
      expect(native['finished'], isTrue);
      final rows = (native['stages'] as List)
          .where((row) => (row as Map).containsKey('collection'))
          .toList();
      expect(rows.length, 4);
      for (final row in rows) {
        final source = Map<String, Object?>.from(row['collection'] as Map);
        final port = Port()..value = parse(source);
        final key = GlobalKey();
        size(tester, const Size(420, 800));
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: OverlayAppearanceCollectionPanel(
                  appearanceId: source['appearanceId'] as String,
                  port: port,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(port.value.items.length, 7);
        final output = Platform.environment['STARBRIDGE_COLLECTION_CAPTURE'];
        if (output != null && source['confirmedUsageMs'] == 2700000) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(output).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await remove(tester, port);
      }
    },
    skip: Platform.environment['STARBRIDGE_COLLECTION_REPORT'] == null,
  );
  testWidgets(
    'actual installed metadata wires collection into appearance center without a use grant',
    (tester) async {
      final report = Platform.environment['STARBRIDGE_COLLECTION_REPORT']!;
      final native = jsonDecode(File(report).readAsStringSync()) as Map;
      final stages = native['stages'] as List;
      final workspace = Map<String, Object?>.from(
        stages.singleWhere(
              (s) => s['label'] == 'normal-package-metadata',
            )['workspace']
            as Map,
      );
      final source = Map<String, Object?>.from(
        stages.firstWhere(
              (s) =>
                  s['label'] ==
                      'native-readonly-collection-confirmed-fixture' &&
                  s['syntheticAccountMs'] == 2700000,
            )['collection']
            as Map,
      );
      final id = source['appearanceId'] as String;
      final pair = InMemoryBridgeConnection.createPair();
      final session =
          BridgeClientSession(connection: pair.client, sessionGeneration: 1)
            ..acceptHostCapabilities([
              'overlay.workspace',
              'overlay.appearanceProgress',
            ]);
      final requests = <BridgeEnvelope>[];
      final sub = pair.host.incoming.listen((request) {
        if (request.messageType != 'request') return;
        requests.add(request);
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: request.name == 'overlay.getWorkspace'
                  ? workspace
                  : source,
            ),
          ),
        );
      });
      final module = OverlayWorkspaceModule(
        BridgeOverlayWorkspaceAdapter(session),
      );
      // Close transport in package:test teardown (real async zone), after
      // the widget subtree and its collection subscription have been removed.
      addTearDown(() async {
        module.dispose();
        await sub.cancel();
        await session.close();
        await pair.host.close();
      });
      try {
        // Both in-memory Bridge controllers belong to the widget-test zone;
        // pump its microtasks rather than awaiting them inside runAsync.
        final initialization = module.initialize();
        await tester.pumpAndSettle();
        await initialization;
        expect(module.projection.value.snapshot!.appearanceProgressIds, {id});
        final before = module.projection.value.appearanceOptions;
        size(tester, const Size(1200, 1000));
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: ValueListenableBuilder<OverlayWorkspaceProjection>(
                valueListenable: module.projection,
                builder: (context, value, _) =>
                    OverlayWorkspaceAppearanceCenter(
                      projection: value,
                      module: module,
                      onBack: () {},
                    ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(Key('overlay-appearance-card-$id'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.byKey(Key('appearance-collection-$id')), findsOneWidget);
        expect(find.text('已确认使用：45分钟'), findsOneWidget);
        expect(
          find.byKey(const Key('appearance-config-collection-try-on')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(Key('overlay-appearance-apply-$id')),
              )
              .onPressed,
          isNull,
        );
        expect(module.projection.value.appearanceOptions, before);
        expect(module.projection.value.dirty, isFalse);
        expect(
          requests.every(
            (r) =>
                r.name == 'overlay.getWorkspace' ||
                r.name == 'overlay.appearanceProgress.read',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    },
    skip: Platform.environment['STARBRIDGE_COLLECTION_REPORT'] == null,
  );
}
