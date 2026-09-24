import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/features/settings/application_update_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  Map<String, dynamic> progress(String phase, int received, int? total) => {
    'schemaVersion': 1,
    'requestId': 'fixture',
    'version': '0.7.1',
    'phase': phase,
    'receivedBytes': received,
    'totalBytes': total,
  };
  Map<String, dynamic> reply(String state) => {
    'schemaVersion': 1,
    'state': state,
    'currentVersion': '0.6.6',
    'availableVersion': null,
    'notes': null,
  };
  testWidgets(
    'Bridge progress belongs to request and handoff waits for exit guard',
    (tester) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'applicationUpdates.check',
        'applicationUpdates.prepare',
        'applicationUpdates.handoff',
      ]);
      final requests = <BridgeEnvelope>[];
      BridgeEnvelope response(
        BridgeEnvelope request,
        Map<String, Object?> payload,
      ) => BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: 1,
        payload: payload,
        status: 'ok',
      );
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'applicationUpdates.check') {
          unawaited(
            pair.host.send(
              response(request, {
                ...reply('available'),
                'availableVersion': '0.7.1',
              }),
            ),
          );
        }
        if (request.name == 'applicationUpdates.handoff') {
          unawaited(
            pair.host.send(
              response(request, {'schemaVersion': 1, 'accepted': false}),
            ),
          );
        }
      });
      addTearDown(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
      ExitApplicationIntent? exit;
      await tester.pumpWidget(
        app(
          Actions(
            actions: {
              ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
                onInvoke: (value) {
                  exit = value;
                  return null;
                },
              ),
            },
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showApplicationUpdateDialog(context, session),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      final prepare = requests.lastWhere(
        (r) => r.name == 'applicationUpdates.prepare',
      );
      var sequence = 0;
      Future<void> emit(String? id, int received, {int generation = 1}) =>
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'applicationUpdates.progress',
              sessionGeneration: generation,
              sequence: ++sequence,
              payload: {
                ...progress('downloading', received, 2097152),
                'requestId': id,
              },
            ),
          );
      await emit('other-request', 1048576);
      await emit(prepare.correlationId, 1048576, generation: 0);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await emit(prepare.correlationId, 1048576);
      await tester.pumpAndSettle();
      expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
      await pair.host.send(
        response(prepare, {
          'schemaVersion': 1,
          'version': '0.7.1',
          'ticket': 'a' * 32,
        }),
      );
      await tester.pumpAndSettle();
      expect(exit, isNull);
      await tester.tap(find.text('重启并安装'));
      await tester.pumpAndSettle();
      expect(exit, isNotNull);
      expect(
        requests.where((r) => r.name == 'applicationUpdates.handoff'),
        isEmpty,
      );
      final handoff = exit!.beforeExit!();
      await tester.pumpAndSettle();
      expect(await handoff, isFalse);
      expect(find.text('更新未能启动，客户端保持打开。'), findsOneWidget);
      expect(find.byKey(const Key('application-update-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('unconfigured channel is not latest and fits narrow $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => reply('channel-unconfigured'),
          ),
          locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('0.6.6'), findsOneWidget);
      expect(find.text('当前已是最新版本。'), findsNothing);
      expect(find.text('You are up to date.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'transient failure retries automatically and disposal stops retries',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async {
              if (++calls == 1) throw StateError('private endpoint');
              return reply('up-to-date');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('自动重试'), findsOneWidget);
      expect(find.textContaining('private endpoint'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('当前已是最新版本。'), findsOneWidget);
      expect(calls, 2);
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            key: const Key('failed'),
            read: () async {
              calls++;
              throw StateError('offline');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final count = calls;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 40));
      expect(calls, count);
    },
  );
  testWidgets('malformed response does not become a successful update', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(ApplicationUpdateDialog(read: () async => {'schemaVersion': 0})),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前客户端暂不支持检查更新。'), findsOneWidget);
  });
  testWidgets('non-retryable Bridge errors do not retry in the background', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      app(
        ApplicationUpdateDialog(
          read: () async {
            reads++;
            throw const BridgeRemoteException('bridge.protocol_incompatible');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(reads, 1);
    expect(find.text('重新检查'), findsOneWidget);
  });
  for (final state in [
    'configuration-invalid',
    'channel-unavailable',
    'verification-failed',
  ]) {
    testWidgets('$state is not latest and does not automatically retry', (
      tester,
    ) async {
      var reads = 0;
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async {
              reads++;
              return reply(state);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      expect(reads, 1);
      expect(find.text('当前已是最新版本。'), findsNothing);
      expect(find.text('下载更新'), findsNothing);
      expect(find.text('重启并安装'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('network retries are bounded and explicit retry can recover', (
    tester,
  ) async {
    var reads = 0;
    var recovered = false;
    await tester.pumpWidget(
      app(
        ApplicationUpdateDialog(
          read: () async {
            reads++;
            if (!recovered) throw StateError('offline');
            return reply('up-to-date');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final delay in [2, 5, 15, 60]) {
      await tester.pump(Duration(seconds: delay));
      await tester.pumpAndSettle();
    }
    expect(reads, 4);
    expect(find.text('重新检查'), findsOneWidget);
    recovered = true;
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();
    expect(reads, 5);
    expect(find.text('当前已是最新版本。'), findsOneWidget);
  });
  testWidgets('closing an active check cancels it and ignores late offer', (
    tester,
  ) async {
    var cancelled = false;
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      app(
        ApplicationUpdateDialog(
          read: () => pending.future,
          cancelCheck: () => cancelled = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在检查更新…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete({...reply('available'), 'availableVersion': '0.7.1'});
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'failure state cannot smuggle an available version or release notes',
    (tester) async {
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => {
              ...reply('verification-failed'),
              'availableVersion': '0.7.1',
              'notes': 'untrusted notes',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前客户端暂不支持检查更新。'), findsOneWidget);
      expect(find.text('untrusted notes'), findsNothing);
    },
  );
  testWidgets(
    'progress is bounded and verified event does not authorize install',
    (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final pending = Completer<Map<String, dynamic>>();
      addTearDown(events.close);
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => {
              ...reply('available'),
              'availableVersion': '0.7.1',
            },
            prepare: (_) => pending.future,
            progress: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      events.add(progress('downloading', 1048576, 2097152));
      await tester.pumpAndSettle();
      expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
      for (final invalid in [
        progress('downloading', -1, 2097152),
        progress('downloading', 2097153, 2097152),
        progress('downloading', 0, 2097152),
        {...progress('downloading', 2097152, 2097152), 'version': '0.8.0'},
        progress('downloading', 2097152, null),
      ]) {
        events.add(invalid);
      }
      await tester.pumpAndSettle();
      expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
      events.add(progress('verified', 2097152, 2097152));
      await tester.pumpAndSettle();
      expect(find.text('下载完成，正在验证更新…'), findsOneWidget);
      expect(find.text('重启并安装'), findsNothing);
      events.add(progress('downloading', 2097152, 2097152));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete({
        'schemaVersion': 1,
        'ticket': 'a' * 32,
        'version': '0.7.1',
      });
      await tester.pumpAndSettle();
      expect(find.text('重启并安装'), findsOneWidget);
    },
  );
  testWidgets('cancel keeps client open and late result cannot replace retry', (
    tester,
  ) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    var calls = 0, cancels = 0;
    addTearDown(events.close);
    await tester.pumpWidget(
      app(
        ApplicationUpdateDialog(
          read: () async => {
            ...reply('available'),
            'availableVersion': '0.7.1',
          },
          prepare: (_) => ++calls == 1 ? first.future : second.future,
          progress: events.stream,
          cancelPreparation: () => cancels++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    events.add(progress('downloading', 1048576, null));
    await tester.pumpAndSettle();
    expect(find.text('1.0 MB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.text('下载已取消，当前版本保持不变。'), findsOneWidget);
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    first.complete({
      'schemaVersion': 1,
      'ticket': 'a' * 32,
      'version': '0.7.1',
    });
    await tester.pumpAndSettle();
    expect(find.text('重启并安装'), findsNothing);
    expect(find.text('取消下载'), findsOneWidget);
    second.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.text('下载更新'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(events.hasListener, isFalse);
  });
  testWidgets(
    'installation requires a prepared matching offer and explicit restart',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var prepares = 0;
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => {
              ...reply('available'),
              'availableVersion': '0.6.7',
            },
            prepare: (version) {
              expect(version, '0.6.7');
              prepares++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重启并安装'), findsNothing);
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(prepares, 1);
      expect(find.text('下载更新'), findsNothing);
      expect(find.text('重启并安装'), findsNothing);
      pending.complete({
        'schemaVersion': 1,
        'ticket': 'a' * 32,
        'version': '0.6.7',
      });
      await tester.pumpAndSettle();
      expect(find.text('重启并安装'), findsOneWidget);
      expect(find.textContaining('请先保存'), findsOneWidget);
    },
  );
  testWidgets(
    'changed prepared version cannot enable installation or auto retry',
    (tester) async {
      var prepares = 0;
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => {
              ...reply('available'),
              'availableVersion': '0.6.7',
            },
            prepare: (_) async {
              prepares++;
              return {
                'schemaVersion': 1,
                'ticket': 'a' * 32,
                'version': '0.6.8',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 40));
      expect(prepares, 1);
      expect(find.text('重启并安装'), findsNothing);
      expect(find.textContaining('当前版本保持不变'), findsOneWidget);
    },
  );
  testWidgets(
    'closing a downloading dialog cancels preparation and ignores late response',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var cancelled = false;
      await tester.pumpWidget(
        app(
          ApplicationUpdateDialog(
            read: () async => {
              ...reply('available'),
              'availableVersion': '0.6.7',
            },
            prepare: (_) => pending.future,
            cancelPreparation: () => cancelled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      pending.complete({
        'schemaVersion': 1,
        'ticket': 'a' * 32,
        'version': '0.6.7',
      });
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget app(Widget child, [Locale locale = const Locale('zh', 'CN')]) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );
