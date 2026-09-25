import 'dart:async';

import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/shell_review_configuration.dart';
import 'package:starbridge_flutter/app/runtime/starbridge_runtime_host.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/lifecycle/in_memory_application_lifecycle.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'normal product entry automatically announces an available update without downloading',
    (tester) async {
      _startupViewport(tester);
      final requests = <BridgeEnvelope>[];
      final lease = _createSignedOutLease(
        startupChoiceMade: true,
        updateRequests: requests,
      );
      lease.session.acceptHostCapabilities(const [
        'applicationUpdates.check',
        'applicationUpdates.prepare',
        'applicationUpdates.handoff',
      ]);
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: _CallbackNativeHostConnector(() async => lease),
          reconnectDelay: const Duration(hours: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests.map((r) => r.name), ['applicationUpdates.check']);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('下载更新'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('发现新版本'), findsNothing);
      expect(requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final failFirst in [false, true]) {
    testWidgets(
      'storage migration result retries transient failures $failFirst',
      (tester) async {
        _startupViewport(tester);
        final requests = <BridgeEnvelope>[];
        final lease = _createSignedOutLease(
          startupChoiceMade: true,
          migrationRequests: requests,
          failMigrationOnce: failFirst,
        );
        lease.session.acceptHostCapabilities(const [
          'dataLocation.getMigrationResult',
          'dataLocation.acknowledgeMigrationResult',
        ]);
        await tester.pumpWidget(
          StarBridgeRuntimeHost(
            environment: const {},
            windowChrome: InMemoryWindowChrome(),
            nativeHostConnector: _CallbackNativeHostConnector(
              () async => lease,
            ),
            reconnectDelay: const Duration(hours: 1),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        if (failFirst) {
          await tester.pump(const Duration(seconds: 5));
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 250));
        }

        expect(requests.map((request) => request.name), [
          if (failFirst) 'dataLocation.getMigrationResult',
          'dataLocation.getMigrationResult',
          'dataLocation.acknowledgeMigrationResult',
        ]);
        expect(
          requests.every((request) => request.accountContext == null),
          isTrue,
        );
        expect(find.textContaining('本机数据已迁移'), findsOneWidget);
        if (failFirst) {
          await tester.pump(const Duration(seconds: 5));
          expect(
            requests
                .where(
                  (r) => r.name == 'dataLocation.acknowledgeMigrationResult',
                )
                .length,
            2,
          );
          expect(
            requests
                .where((r) => r.name == 'dataLocation.getMigrationResult')
                .length,
            2,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final ready in [false, true]) {
    testWidgets('update handoff only exits after preparation succeeds $ready', (
      tester,
    ) async {
      _startupViewport(tester);
      final connector = _ConnectedNativeHostConnector();
      final lifecycle = InMemoryApplicationLifecycle();
      addTearDown(lifecycle.dispose);
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: connector,
          applicationLifecycle: lifecycle,
          reconnectDelay: const Duration(hours: 1),
        ),
      );
      await tester.pumpAndSettle();
      final prepared = Completer<bool>();
      var attempts = 0;
      Actions.invoke(
        tester.element(find.byKey(const Key('application-window-frame'))),
        ExitApplicationIntent(
          beforeExit: () {
            attempts++;
            return prepared.future;
          },
        ),
      );
      await tester.pump();
      expect(lifecycle.exitCount, 0);
      prepared.complete(ready);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(lifecycle.exitCount, ready ? 1 : 0);
      expect(lifecycle.hideCount, 0);
    });
  }
  testWidgets('explicit exit bypasses tray preference without rewriting it', (
    tester,
  ) async {
    _startupViewport(tester);
    final connector = _ConnectedNativeHostConnector();
    final lifecycle = InMemoryApplicationLifecycle();
    addTearDown(lifecycle.dispose);
    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: connector,
        applicationLifecycle: lifecycle,
        reconnectDelay: const Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();
    final before = connector.firstLease.preferencesUpdateCount;
    Actions.invoke(
      tester.element(find.byKey(const Key('application-window-frame'))),
      const ExitApplicationIntent(),
    );
    await tester.pumpAndSettle();
    expect(lifecycle.exitCount, 1);
    expect(lifecycle.hideCount, 0);
    expect(connector.firstLease.preferencesUpdateCount, before);
    expect(find.byKey(const Key('first-close-behavior-dialog')), findsNothing);
  });

  for (final enabled in [false, true]) {
    testWidgets(
      'signed-out reminder entry requires complete Host capability $enabled',
      (tester) async {
        _startupViewport(tester);
        final requests = <BridgeEnvelope>[];
        final lease = _createSignedOutLease(
          startupChoiceMade: true,
          reminderRequests: requests,
        );
        lease.session.acceptHostCapabilities([
          'playReminder.read',
          if (enabled) 'playReminder.save',
        ]);
        await tester.pumpWidget(
          StarBridgeRuntimeHost(
            environment: const {},
            windowChrome: InMemoryWindowChrome(),
            nativeHostConnector: _CallbackNativeHostConnector(
              () async => lease,
            ),
            reconnectDelay: const Duration(hours: 1),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-command')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-menu-login')));
        await tester.pumpAndSettle();
        final overrides = find.byType(SettingsEntryOverrides).first;
        final opener = tester
            .widget<SettingsEntryOverrides>(overrides)
            .openers['continuous-play'];
        expect(opener != null, enabled);
        if (enabled) {
          unawaited(opener!(tester.element(overrides)));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('notification-play-enabled')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('notification-play-enabled')));
          await tester.pumpAndSettle();
          expect(requests.map((r) => r.name), [
            'playReminder.read',
            'playReminder.save',
          ]);
          expect(requests.every((r) => r.accountContext == null), isTrue);
          expect(requests.last.payload['expectedRevision'], 0);
          await tester.tap(find.byKey(const Key('settings-entry-close')));
          await tester.pumpAndSettle();
        } else {
          expect(requests, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed Host start offers retry and can enter after recovery', (
    tester,
  ) async {
    _startupViewport(tester);
    var attempts = 0;
    final lease = _createSignedOutLease(startupChoiceMade: true);
    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        reconnectDelay: const Duration(hours: 1),
        nativeHostConnector: _CallbackNativeHostConnector(() async {
          if (++attempts == 1) {
            throw const NativeHostConnectionException('host.start_failed');
          }
          return lease;
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startup-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const Key('startup-loading-page')), findsNothing);
    expect(find.byKey(const Key('account-command')), findsOneWidget);
  });

  testWidgets(
    'preference failure retries the same Host without rewriting settings',
    (tester) async {
      _startupViewport(tester);
      var reject = true;
      var opens = 0;
      final lease = _createSignedOutLease(
        startupChoiceMade: true,
        rejectPreferencesRead: () => reject,
      );
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: _CallbackNativeHostConnector(() async {
            opens++;
            return lease;
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法读取应用设置'), findsOneWidget);
      reject = false;
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(lease.preferencesUpdateCount, 0);
      expect(find.byKey(const Key('startup-loading-page')), findsNothing);
    },
  );

  testWidgets(
    'startup and first-choice prompt wait for the initial account check',
    (tester) async {
      _startupViewport(tester);
      final settings = Completer<void>();
      final account = Completer<void>();
      final lease = _createSignedOutLease(
        startupChoiceMade: false,
        preferencesGate: settings.future,
        accountGate: account.future,
      );
      final lifecycle = InMemoryApplicationLifecycle();
      addTearDown(lifecycle.dispose);
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          applicationLifecycle: lifecycle,
          nativeHostConnector: _CallbackNativeHostConnector(() async => lease),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在读取应用设置'), findsOneWidget);
      expect(
        find.byKey(const Key('first-startup-choice-dialog')),
        findsNothing,
      );
      expect(lease.preferencesUpdateCount, 0);
      settings.complete();
      await tester.pump();
      expect(
        lifecycle.behavior,
        isNotNull,
      ); // Configure Runner before animation exits.
      // Longest approved turn + assembly + handoff + first-choice transition.
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('startup-loading-page')), findsOneWidget);
      expect(find.text('正在读取账号状态'), findsOneWidget);
      expect(find.byKey(const Key('first-startup-continue')), findsNothing);
      expect(find.byKey(const Key('account-command')), findsNothing);
      account.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-loading-page')), findsNothing);
      expect(find.byKey(const Key('first-startup-continue')), findsOneWidget);
      expect(lease.preferencesUpdateCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account failure retries in place without reopening Host or saving settings',
    (tester) async {
      _startupViewport(tester);
      var state = 'credentialTemporarilyUnavailable';
      var opens = 0;
      final gate = Completer<void>();
      final lease = _createSignedOutLease(
        startupChoiceMade: true,
        accountState: () => state,
        retryAccountGate: gate.future,
      );
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: _CallbackNativeHostConnector(() async {
            opens++;
            return lease;
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法确认账号状态'), findsOneWidget);
      state = 'signedOut';
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pump();
      expect(find.text('正在重试…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('startup-retry')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('account-command')), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-loading-page')), findsNothing);
      expect(opens, 1);
      expect(lease.preferencesUpdateCount, 0);
    },
  );

  testWidgets(
    'actual account timeout allows entry while retaining unknown account state',
    (tester) async {
      _startupViewport(tester);
      final lease = _createSignedOutLease(
        startupChoiceMade: true,
        stallAccount: true,
      );
      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: _CallbackNativeHostConnector(() async => lease),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法确认账号状态'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-enter')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-loading-page')), findsNothing);
      expect(find.byKey(const Key('account-command')), findsOneWidget);
      expect(lease.preferencesUpdateCount, 0);
    },
  );

  testWidgets('close request during a stalled first startup can exit', (
    tester,
  ) async {
    _startupViewport(tester);
    final lifecycle = InMemoryApplicationLifecycle();
    addTearDown(lifecycle.dispose);
    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        applicationLifecycle: lifecycle,
        nativeHostConnector: _PendingNativeHostConnector(),
      ),
    );
    await tester.pumpAndSettle();
    lifecycle.requestClose();
    await tester.pump();
    expect(lifecycle.exitCount, 1);
    expect(lifecycle.hideCount, 0);
  });

  testWidgets('product startup never exposes the example scene switch', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('zh', 'CN'),
    ];
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {
          ShellReviewConfiguration.stateEnvironmentKey: 'healthy',
          ShellReviewConfiguration.accountEnvironmentKey: 'signedin',
        },
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: _PendingNativeHostConnector(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-loading-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('startup-enter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('example-scene-open')), findsNothing);
    expect(find.byKey(const Key('example-scene-exit')), findsNothing);
    expect(find.byKey(const Key('example-scene-notice')), findsNothing);
    expect(find.byKey(const Key('connection-status-notice')), findsOneWidget);
    expect(find.byKey(const Key('connection-status-retry')), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('Aster Lin'), findsNothing);

    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-login')));
    await tester.pumpAndSettle();
    expect(find.text('Aster Lin'), findsNothing);
    expect(find.byKey(const Key('example-scene-open')), findsNothing);
    expect(find.byKey(const Key('example-scene-exit')), findsNothing);
    expect(find.byKey(const Key('example-scene-notice')), findsNothing);
    expect(find.text('Aster Lin'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('/rooms')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rooms-example-directory')), findsNothing);
    expect(find.text('示例 · 货运护航'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product swaps to the real Host lease and fails closed on exit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final connector = _ConnectedNativeHostConnector();

    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: connector,
        reconnectDelay: const Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(connector.openCount, 1);
    expect(find.byKey(const Key('connection-status-notice')), findsNothing);
    expect(find.text('未登录'), findsOneWidget);

    await tester.runAsync(() async {
      connector.firstLease.completeTermination(
        const NativeHostTermination(code: 'host.process_exited', exitCode: 4),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('connection-status-notice')), findsOneWidget);
    expect(find.text('客户端连接中断'), findsOneWidget);
    expect(find.byKey(const Key('startup-loading-page')), findsNothing);
    expect(find.text('Native Host 暂时不可用，应用正在自动重连。'), findsOneWidget);
    expect(find.text('Aster Lin'), findsNothing);
  });

  testWidgets('first close persists the choice before hiding to tray', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final connector = _ConnectedNativeHostConnector();
    final lifecycle = InMemoryApplicationLifecycle();
    addTearDown(lifecycle.dispose);

    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: connector,
        applicationLifecycle: lifecycle,
        reconnectDelay: const Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(lifecycle.behavior, isNotNull);
    expect(lifecycle.behavior!.keepRunningInBackground, isTrue);

    lifecycle.requestClose();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('first-close-behavior-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('first-close-background')));
    await tester.pumpAndSettle();

    expect(lifecycle.hideCount, 1);
    expect(lifecycle.lastShowHint, isTrue);
    expect(lifecycle.exitCount, 0);
    expect(lifecycle.behavior!.keepRunningInBackground, isTrue);
  });

  testWidgets('dismissing the first close prompt keeps the window open', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final connector = _ConnectedNativeHostConnector();
    final lifecycle = InMemoryApplicationLifecycle();
    addTearDown(lifecycle.dispose);

    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: connector,
        applicationLifecycle: lifecycle,
        reconnectDelay: const Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();

    lifecycle.requestClose();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('first-close-behavior-dialog')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(lifecycle.cancelledCloseCount, 1);
    expect(lifecycle.hideCount, 0);
    expect(lifecycle.exitCount, 0);
    expect(connector.firstLease.preferencesUpdateCount, 0);
  });

  testWidgets(
    'first visible entry recommends startup without writing before continue',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final connector = _ConnectedNativeHostConnector(startupChoiceMade: false);
      final lifecycle = InMemoryApplicationLifecycle();
      addTearDown(lifecycle.dispose);

      await tester.pumpWidget(
        StarBridgeRuntimeHost(
          environment: const {},
          windowChrome: InMemoryWindowChrome(),
          nativeHostConnector: connector,
          applicationLifecycle: lifecycle,
          reconnectDelay: const Duration(hours: 1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('first-startup-choice-dialog')),
        findsOneWidget,
      );
      expect(connector.firstLease.preferencesUpdateCount, 0);
      Actions.invoke(
        tester.element(find.byKey(const Key('application-window-frame'))),
        const ExitApplicationIntent(),
      );
      await tester.pumpAndSettle();
      expect(lifecycle.exitCount, 0);
      expect(lifecycle.cancelledCloseCount, 1);
      lifecycle.requestClose();
      await tester.pumpAndSettle();
      expect(lifecycle.cancelledCloseCount, 2);
      expect(
        find.byKey(const Key('first-close-behavior-dialog')),
        findsNothing,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('first-startup-enabled')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('first-startup-continue')));
      await tester.pumpAndSettle();

      expect(connector.firstLease.preferencesUpdateCount, 1);
      expect(connector.firstLease.applicationBehavior['launchAtStartup'], true);
      expect(connector.firstLease.applicationBehavior['startMinimized'], true);
      expect(
        connector.firstLease.applicationBehavior['startupChoiceMade'],
        true,
      );
      expect(
        find.byKey(const Key('first-startup-choice-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets('first startup choice can be explicitly declined', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final connector = _ConnectedNativeHostConnector(startupChoiceMade: false);
    final lifecycle = InMemoryApplicationLifecycle();
    addTearDown(lifecycle.dispose);

    await tester.pumpWidget(
      StarBridgeRuntimeHost(
        environment: const {},
        windowChrome: InMemoryWindowChrome(),
        nativeHostConnector: connector,
        applicationLifecycle: lifecycle,
        reconnectDelay: const Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-startup-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('first-startup-continue')));
    await tester.pumpAndSettle();

    expect(connector.firstLease.applicationBehavior['launchAtStartup'], false);
    expect(connector.firstLease.applicationBehavior['startMinimized'], false);
    expect(connector.firstLease.applicationBehavior['startupChoiceMade'], true);
  });
}

void _startupViewport(WidgetTester tester) {
  tester.binding.platformDispatcher.localesTestValue = const [
    Locale('zh', 'CN'),
  ];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final class _CallbackNativeHostConnector implements NativeHostConnector {
  _CallbackNativeHostConnector(this._open);
  final Future<NativeHostLease> Function() _open;
  @override
  Future<NativeHostLease> open() => _open();
}

final class _PendingNativeHostConnector implements NativeHostConnector {
  final Completer<NativeHostLease> _pending = Completer();

  @override
  Future<NativeHostLease> open() => _pending.future;
}

final class _ConnectedNativeHostConnector implements NativeHostConnector {
  _ConnectedNativeHostConnector({bool startupChoiceMade = true})
    : firstLease = _createSignedOutLease(startupChoiceMade: startupChoiceMade);

  final _TestNativeHostLease firstLease;
  final Completer<NativeHostLease> _later = Completer();
  int openCount = 0;

  @override
  Future<NativeHostLease> open() async {
    openCount++;
    return openCount == 1 ? firstLease : _later.future;
  }
}

_TestNativeHostLease _createSignedOutLease({
  required bool startupChoiceMade,
  Future<void>? preferencesGate,
  Future<void>? accountGate,
  Future<void>? retryAccountGate,
  String Function()? accountState,
  bool Function()? rejectPreferencesRead,
  bool stallAccount = false,
  List<BridgeEnvelope>? reminderRequests,
  List<BridgeEnvelope>? migrationRequests,
  List<BridgeEnvelope>? updateRequests,
  bool failMigrationOnce = false,
}) {
  final pair = InMemoryBridgeConnection.createPair();
  final preferenceState = _TestPreferenceState(
    applicationBehavior: {
      'launchAtStartup': false,
      'keepRunningInBackground': true,
      'startMinimized': false,
      'startupChoiceMade': startupChoiceMade,
      'closeBehaviorChoiceMade': false,
      'backgroundHintShown': false,
    },
  );
  var preferencesRevision = 0;
  var accountReads = 0;
  var migrationReads = 0;
  var migrationAcks = 0;
  unawaited(
    pair.host.incoming.forEach((request) async {
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'applicationUpdates.check' &&
          updateRequests != null) {
        updateRequests.add(request);
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {
              'schemaVersion': 1,
              'state': 'available',
              'currentVersion': '0.7.0.1',
              'availableVersion': '0.7.0.2',
              'notes': '## 修复\n- 更新弹窗',
            },
          ),
        );
        return;
      }
      if (request.name == 'dataLocation.getMigrationResult') {
        migrationRequests?.add(request);
        if (failMigrationOnce && migrationReads++ == 0) {
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              payload: const {},
              status: 'error',
              error: const BridgeErrorBody(
                code: 'dataLocation.migration_unavailable',
                message: 'Retry',
                retryable: true,
              ),
            ),
          );
          return;
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {
              'schemaVersion': 1,
              'state': 'migrated',
              'nonce': '0123456789abcdef0123456789abcdef',
              'source': r'G:\StarBridge\data',
              'destination': r'D:\StarBridge\data',
              'completedAt': '2026-09-13T18:00:00Z',
            },
          ),
        );
        return;
      }
      if (request.name == 'dataLocation.acknowledgeMigrationResult') {
        migrationRequests?.add(request);
        if (failMigrationOnce && migrationAcks++ == 0) {
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              payload: const {},
              status: 'error',
              error: const BridgeErrorBody(
                code: 'dataLocation.migration_unavailable',
                message: 'Retry',
                retryable: true,
              ),
            ),
          );
          return;
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {'schemaVersion': 1, 'acknowledged': true},
          ),
        );
        return;
      }
      if (request.name.startsWith('playReminder.')) {
        reminderRequests?.add(request);
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: {
              'schemaVersion': 1,
              'enabled': request.name.endsWith('read'),
              'firstReminderMinutes': 120,
              'repeatReminderMinutes': 120,
              'revision': request.name.endsWith('read') ? 0 : 1,
            },
          ),
        );
        return;
      }
      if (request.name == 'applicationPreferences.get') {
        if (preferencesGate != null) await preferencesGate;
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: {
              'schemaVersion': rejectPreferencesRead?.call() == true ? 0 : 1,
              'revision': preferencesRevision,
              'storageState': 'defaulted',
              'preferences': {
                'localeOverride': 'zh-CN',
                'appearanceMode': 'dark',
                'motionPreference': 'followSystem',
                'applicationBehavior': preferenceState.applicationBehavior,
              },
            },
            status: 'ok',
          ),
        );
        return;
      }
      if (request.name == 'applicationPreferences.update') {
        final patch = request.payload['patch'];
        if (patch is Map && patch['applicationBehavior'] is Map) {
          preferenceState.applicationBehavior = Map<String, Object?>.from(
            patch['applicationBehavior'] as Map,
          );
          preferenceState.updateCount++;
        }
        preferencesRevision++;
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: {
              'schemaVersion': 1,
              'revision': preferencesRevision,
              'storageState': 'ready',
              'preferences': {
                'localeOverride': 'zh-CN',
                'appearanceMode': 'dark',
                'motionPreference': 'followSystem',
                'applicationBehavior': preferenceState.applicationBehavior,
              },
            },
            status: 'ok',
          ),
        );
        return;
      }
      if (request.name == 'account.getCurrent') {
        if (stallAccount) return;
        accountReads++;
        if (accountGate != null) await accountGate;
        if (accountReads > 1 && retryAccountGate != null) {
          await retryAccountGate;
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: {
              'schemaVersion': 1,
              'state': accountState?.call() ?? 'signedOut',
            },
            status: 'ok',
          ),
        );
        return;
      }
      throw StateError('Unexpected request ${request.name}');
    }),
  );
  return _TestNativeHostLease(
    BridgeClientSession(connection: pair.client, sessionGeneration: 0),
    pair.host,
    preferenceState,
  );
}

final class _TestNativeHostLease implements NativeHostLease {
  _TestNativeHostLease(
    this.session,
    this._hostConnection,
    this._preferenceState,
  );

  @override
  final BridgeClientSession session;
  final BridgeConnection _hostConnection;
  final _TestPreferenceState _preferenceState;
  final Completer<NativeHostTermination> _termination = Completer();
  bool _closed = false;

  int get preferencesUpdateCount => _preferenceState.updateCount;
  Map<String, Object?> get applicationBehavior =>
      _preferenceState.applicationBehavior;

  @override
  Future<NativeHostTermination> get terminated => _termination.future;

  void completeTermination(NativeHostTermination termination) {
    if (!_termination.isCompleted) {
      _termination.complete(termination);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await session.close();
    await _hostConnection.close();
  }
}

final class _TestPreferenceState {
  _TestPreferenceState({required this.applicationBehavior});

  Map<String, Object?> applicationBehavior;
  int updateCount = 0;
}
