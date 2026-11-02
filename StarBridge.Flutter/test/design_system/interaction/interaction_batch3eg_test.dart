import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/bridge_continuous_play.dart';
import 'package:starbridge_flutter/features/settings/notification_connected_panels.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;
import 'interaction_batch3dw_test.dart' show NotificationMotionPort;
import '../../features/settings/player_activity_test.dart' as player show data;

/// Controlled wire transport only. The actual page constructs the connected
/// group and its one real ContinuousPlayController/BridgeContinuousPlay.
class _Peer {
  _Peer() {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 1)
      ..acceptHostCapabilities([
        'playerActivity.read',
        'playerActivity.save',
        'playerActivity.test',
        'playReminder.read',
        'playReminder.save',
        'account.getCurrent',
        'notificationPolicies.read',
      ]);
    subscription = host.incoming.listen((request) {
      if (request.messageType != 'request') {
        return;
      }
      requests.add(request);
      if (request.name == 'playReminder.save') {
        held.add(request);
        return;
      }
      final payload = switch (request.name) {
        'playReminder.read' => _play(4, true),
        'playerActivity.read' => player.data(),
        // The local play/activity domains do not need an account. The source
        // panel may independently show its original signed-out read failure.
        'account.getCurrent' => <String, Object?>{
          'schemaVersion': 1,
          'state': 'signedOut',
        },
        _ => null,
      };
      unawaited(_reply(request, payload));
    });
  }

  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final held = <BridgeEnvelope>[];
  final answered = <String>{};

  static Map<String, Object?> _play(int revision, bool enabled) => {
    'schemaVersion': 1,
    'revision': revision,
    'enabled': enabled,
    'firstReminderMinutes': 120,
    'repeatReminderMinutes': 120,
  };

  Future<void> _reply(BridgeEnvelope request, Map<String, Object?>? payload) =>
      host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          sessionGeneration: request.sessionGeneration,
          correlationId: request.correlationId,
          status: payload == null ? 'error' : 'ok',
          payload: payload ?? const {},
          error: payload == null
              ? const BridgeErrorBody(
                  code: 'unsupported',
                  message: 'read-only fixture',
                  retryable: false,
                )
              : null,
        ),
      );

  Future<void> acknowledgeHeld() async {
    for (final request in held) {
      final id = request.correlationId!;
      if (answered.add(id)) {
        await _reply(request, _play(5, false));
      }
    }
  }

  Future<void> rejectHeld() async {
    for (final request in held) {
      final id = request.correlationId!;
      if (answered.add(id)) {
        await host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            sessionGeneration: request.sessionGeneration,
            correlationId: request.correlationId,
            status: 'error',
            payload: const {},
            error: const BridgeErrorBody(
              code: 'playReminder.save_failed',
              message: 'synthetic rejected save',
              retryable: false,
            ),
          ),
        );
      }
    }
  }

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

NotificationMotionPort _notifications() {
  final port = NotificationMotionPort();
  final saved = port.stored.settings!;
  // This is the actual available-page branch that creates connected owners.
  // localInAppOnly:false would exercise different module-owned static panels.
  port.stored = NotificationSettingsSnapshot.available(
    revision: 11,
    settings: NotificationSettingsValue(
      localInAppOnly: true,
      desktopDeliveryAvailable: true,
      directMessageDeliveryAvailable: true,
      overlayDeliveryAvailable: true,
      channels: saved.channels,
      sourceRules: const [],
      previewMode: saved.previewMode,
      playerActivity: saved.playerActivity,
      continuousPlay: saved.continuousPlay,
    ),
  );
  return port;
}

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _keyboardStage(WidgetTester t, Finder row) async {
  await t.ensureVisible(row);
  await t.pump();
  final detectors = find.descendant(
    of: row,
    matching: find.byWidgetPredicate(
      (w) =>
          w is FocusableActionDetector && w.focusNode?.canRequestFocus == true,
    ),
  );
  expect(
    detectors,
    findsOneWidget,
    reason: 'Observe the public row focus owner, not its excluded decorative switch.',
  );
  final node = t.widget<FocusableActionDetector>(detectors).focusNode!;
  for (var i = 0; i < 80 && !node.hasPrimaryFocus; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
  }
  expect(
    FocusManager.instance.primaryFocus,
    same(node),
    reason:
        'Actual Tab must reach the original play row without direct callbacks.',
  );
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'connected Play forced keyed page replacement retires old held save without touching new owner draft',
    (t) async {
      size(t, const Size(1280, 1100));
      final peer = _Peer();
      final oldNotifications = _notifications();
      final newNotifications = _notifications();
      final oldModule = createNotificationSettingsModule(oldNotifications);
      final newModule = createNotificationSettingsModule(newNotifications);
      const oldKey = Key('play-forced-old-page');
      const newKey = Key('play-forced-new-page');
      try {
        await oldModule.initialize();
        await newModule.initialize();
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(
                key: oldKey,
                module: oldModule,
                session: peer.session,
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t, count: 6);
        final panel = find.byType(ContinuousPlayConnectedPanel);
        expect(panel, findsOneWidget);
        expect(find.byType(NotificationConnectedPanels), findsOneWidget);
        expect(find.byType(NotificationEditorFrame), findsOneWidget);
        final oldPanelState = t.state(panel);
        final oldConnectedState = t.state(
          find.byType(NotificationConnectedPanels),
        );
        final oldFrameState = t.state(find.byType(NotificationEditorFrame));
        final oldController = t
            .widget<ContinuousPlayConnectedPanel>(panel)
            .controller;
        final oldConfirmed = oldController.value.settings!;
        final oldDrafts = NotificationDraftScope.of(t.element(panel))!;
        final oldEpoch = oldDrafts.epoch;
        expect(oldConfirmed.revision, 4);
        expect(oldConfirmed.enabled, isTrue);
        expect(notificationLeaveGuards[oldModule], isNotNull);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );

        final row = find
            .ancestor(
              of: find.byKey(const Key('notification-play-enabled')),
              matching: find.byType(StarBridgeSwitch),
            )
            .first;
        await t.ensureVisible(row);
        await t.pump();
        await t.pump();
        await t.tap(row);
        await _frames(t, count: 2);
        expect(oldDrafts.dirty, isTrue);
        expect(oldDrafts.saving, isFalse);
        expect(oldController.value.settings, same(oldConfirmed));
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(peer.held, isEmpty);
        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await _frames(t, count: 2);
        expect(peer.held, hasLength(1));
        expect(peer.answered, isEmpty);
        final request = peer.held.single;
        expect(request.payload, {
          'schemaVersion': 1,
          'expectedRevision': 4,
          'enabled': false,
          'firstReminderMinutes': 120,
          'repeatReminderMinutes': 120,
        });
        expect(request.accountContext, isNull);
        expect(oldController.value.busy, isTrue);
        expect(oldController.value.settings, same(oldConfirmed));
        expect(oldDrafts.saving, isTrue);
        expect(oldDrafts.dirty, isTrue);
        expect(oldNotifications.writes, isEmpty);

        // Deliberately force an unmount while save is held. This does NOT
        // exercise or bypass the normal user-navigation leave-confirm flow:
        // the two explicit Page keys must destroy the old Frame and owners.
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(
                key: newKey,
                module: newModule,
                session: peer.session,
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t, count: 6);
        expect(find.byKey(oldKey), findsNothing);
        expect(find.byKey(newKey), findsOneWidget);
        expect(oldPanelState.mounted, isFalse);
        expect(oldConnectedState.mounted, isFalse);
        expect(oldFrameState.mounted, isFalse);
        // The real group owns Controller.dispose; debug ChangeNotifier rejects
        // adding a listener after disposal. Do not require its busy bit to clear.
        expect(() => oldController.addListener(() {}), throwsFlutterError);
        expect(oldDrafts.epoch, oldEpoch + 1);
        expect(notificationLeaveGuards[oldModule], isNull);
        expect(notificationLeaveGuards[newModule], isNotNull);
        expect(panel, findsOneWidget);
        expect(find.byType(NotificationConnectedPanels), findsOneWidget);
        expect(find.byType(NotificationEditorFrame), findsOneWidget);
        final newPanelState = t.state(panel);
        final newConnectedState = t.state(
          find.byType(NotificationConnectedPanels),
        );
        final newFrameState = t.state(find.byType(NotificationEditorFrame));
        final newController = t
            .widget<ContinuousPlayConnectedPanel>(panel)
            .controller;
        final newConfirmed = newController.value.settings!;
        final newDrafts = NotificationDraftScope.of(t.element(panel))!;
        final newEpoch = newDrafts.epoch;
        expect(newController, isNot(same(oldController)));
        expect(newDrafts, isNot(same(oldDrafts)));
        expect(newController.value.busy, isFalse);
        expect(newController.value.failed, isFalse);
        expect(newConfirmed.revision, 4);
        expect(newConfirmed.enabled, isTrue);
        expect(newConfirmed.firstMinutes, 120);
        expect(newConfirmed.repeatMinutes, 120);
        expect(newDrafts.dirty, isFalse);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(2),
        );
        expect(peer.held, hasLength(1));
        expect(peer.answered, isEmpty);

        // Stage a genuinely new dirty editor by actual pointer input, without
        // mutating the Controller/projection or sending a second save.
        await t.ensureVisible(row);
        await t.pump();
        await t.pump();
        expect(t.widget<StarBridgeSwitch>(row).value, isTrue);
        await t.tap(row);
        await _frames(t, count: 2);
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(newController.value.settings, same(newConfirmed));
        expect(newDrafts.dirty, isTrue);
        expect(newDrafts.saving, isFalse);
        expect(newDrafts.failed, isFalse);
        expect(newDrafts.value('notification-play', (true, 120, 120)), (
          false,
          120,
          120,
        ));
        final newProjection = newModule.projection.value;
        final newSavedSettings = newProjection.settings;
        final newSavedRevision = newProjection.revision;
        final requestsBeforeAck = List<BridgeEnvelope>.of(peer.requests);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );

        // _Peer intentionally returns fixed rev4 on reads. This checks that
        // an OLD late rev5 receipt cannot contaminate a NEW already-read
        // snapshot; it does not claim authoritative Host read-after-write
        // consistency or account-change reconciliation.
        await peer.acknowledgeHeld();
        await _frames(t, count: 8);
        expect(peer.held, hasLength(1));
        expect(peer.answered, {request.correlationId!});
        expect(
          peer.requests,
          requestsBeforeAck,
          reason: 'A late receipt must not trigger auto-read or auto-save.',
        );
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );
        expect(oldNotifications.writes, isEmpty);
        expect(newNotifications.writes, isEmpty);
        expect(find.byKey(oldKey), findsNothing);
        expect(find.byKey(newKey), findsOneWidget);
        expect(panel, findsOneWidget);
        expect(t.state(panel), same(newPanelState));
        expect(
          t.state(find.byType(NotificationConnectedPanels)),
          same(newConnectedState),
        );
        expect(
          t.state(find.byType(NotificationEditorFrame)),
          same(newFrameState),
        );
        expect(
          t.widget<ContinuousPlayConnectedPanel>(panel).controller,
          same(newController),
        );
        expect(NotificationDraftScope.of(t.element(panel)), same(newDrafts));
        expect(newDrafts.epoch, newEpoch);
        expect(newDrafts.dirty, isTrue);
        expect(newDrafts.saving, isFalse);
        expect(newDrafts.failed, isFalse);
        expect(newDrafts.value('notification-play', (true, 120, 120)), (
          false,
          120,
          120,
        ));
        expect(newController.value.settings, same(newConfirmed));
        expect(newController.value.settings!.revision, 4);
        expect(newController.value.settings!.enabled, isTrue);
        expect(newController.value.busy, isFalse);
        expect(newController.value.failed, isFalse);
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(t.widget<StarBridgeSwitch>(row).onChanged, isNotNull);
        expect(newModule.projection.value, same(newProjection));
        expect(newModule.projection.value.settings, same(newSavedSettings));
        expect(newModule.projection.value.revision, newSavedRevision);
        expect(
          newModule.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        expect(notificationLeaveGuards[oldModule], isNull);
        expect(notificationLeaveGuards[newModule], isNotNull);
        expect(t.takeException(), isNull);

        // Keep the same original session alive. Only AFTER the zero-extra-IO
        // checkpoint, make one explicit typed read to prove caller usability.
        final explicitRead = BridgeContinuousPlay(peer.session).read();
        await _frames(t, count: 2);
        final alive = await explicitRead;
        expect(alive.revision, 4);
        expect(alive.enabled, isTrue);
        expect(peer.session.activeGeneration, 1);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(3),
        );
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );
        expect(peer.held, hasLength(1));
        expect(newController.value.settings, same(newConfirmed));
        expect(newDrafts.dirty, isTrue);
        expect(newDrafts.value('notification-play', (true, 120, 120)), (
          false,
          120,
          120,
        ));
        expect(newModule.projection.value, same(newProjection));
        expect(oldNotifications.writes, isEmpty);
        expect(newNotifications.writes, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await peer.acknowledgeHeld();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        oldModule.dispose();
        newModule.dispose();
        await t.runAsync(() async {
          await peer.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'connected Play Scan real pointer stage keyboard commit keeps held wire receipt and local wait static',
    (t) async {
      size(t, const Size(1280, 1100));
      final peer = _Peer();
      final notifications = _notifications();
      final module = createNotificationSettingsModule(notifications);
      ContinuousPlayController? actual;
      VoidCallback? observed;
      final risingSources = <InteractionSource>[];
      try {
        await module.initialize();
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(
                module: module,
                session: peer.session,
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t, count: 6);
        final panel = find.byType(ContinuousPlayConnectedPanel);
        expect(panel, findsOneWidget);
        final controller = t
            .widget<ContinuousPlayConnectedPanel>(panel)
            .controller;
        actual = controller;
        final confirmed = controller.value.settings!;
        expect(confirmed.revision, 4);
        expect(confirmed.enabled, isTrue);
        expect(confirmed.firstMinutes, 120);
        expect(confirmed.repeatMinutes, 120);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(peer.held, isEmpty);
        var wasBusy = controller.value.busy;
        observed = () {
          final busy = controller.value.busy;
          if (busy && !wasBusy) {
            // Observe the real synchronous owner notification's zone. The
            // asynchronous host incoming listener is not a UI-source witness.
            risingSources.add(captureStarBridgeActivationSource()());
          }
          wasBusy = busy;
        };
        controller.addListener(observed);

        final row = find
            .ancestor(
              of: find.byKey(const Key('notification-play-enabled')),
              matching: find.byType(StarBridgeSwitch),
            )
            .first;
        await t.ensureVisible(row);
        await t.pump();
        await t.pump();
        await t.tap(row);
        await _frames(t, count: 2);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        expect(drafts.dirty, isTrue);
        expect(drafts.saving, isFalse);
        expect(peer.held, isEmpty);
        expect(risingSources, isEmpty);
        expect(controller.value.settings, same(confirmed));
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(notifications.writes, isEmpty);

        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await _frames(t, count: 2);
        expect(
          peer.held,
          hasLength(1),
          reason:
              'The actual save callback must reach the original Bridge port.',
        );
        expect(peer.answered, isEmpty);
        expect(risingSources, [InteractionSource.keyboard]);
        expect(
          t.widget<ContinuousPlayConnectedPanel>(panel).controller,
          same(controller),
        );
        final request = peer.held.single;
        expect(request.payload, {
          'schemaVersion': 1,
          'expectedRevision': 4,
          'enabled': false,
          'firstReminderMinutes': 120,
          'repeatReminderMinutes': 120,
        });
        expect(request.accountContext, isNull);
        expect(controller.value.settings, same(confirmed));
        expect(controller.value.settings!.revision, 4);
        expect(controller.value.settings!.enabled, isTrue);
        expect(controller.value.busy, isTrue);
        expect(drafts.saving, isTrue);
        expect(drafts.dirty, isTrue);
        expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
        expect(
          module.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        expect(notifications.writes, isEmpty);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );

        // This is the proven regression checkpoint, after real owner provenance,
        // payload and unchanged-confirmed facts. Do not inspect only Frame's
        // outer save wait, which already receives the keyboard source.
        final frames = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        final labels = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyLabel),
        );
        expect(frames, findsOneWidget);
        expect(labels, findsOneWidget);
        for (final element in [...frames.evaluate(), ...labels.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isTrue,
            reason: 'The real Play owner began under keyboard commit, not the earlier pointer stage; its local wait must be static.',
          );
        }

        await peer.acknowledgeHeld();
        await _frames(t, count: 6);
        expect(controller.value.settings!.revision, 5);
        expect(controller.value.settings!.enabled, isFalse);
        expect(controller.value.settings!.firstMinutes, 120);
        expect(controller.value.settings!.repeatMinutes, 120);
        expect(controller.value.busy, isFalse);
        expect(controller.value.failed, isFalse);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        expect(peer.held, hasLength(1));
        expect(peer.answered, hasLength(1));
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );
        expect(notifications.writes, isEmpty);
        expect(risingSources, [InteractionSource.keyboard]);
        expect(t.takeException(), isNull);
      } finally {
        final listener = observed;
        if (listener != null) {
          actual?.removeListener(listener);
        }
        // Only cleanup releases a held receipt after a red assertion; there
        // is no early ack to make the local waiting checkpoint pass.
        await peer.acknowledgeHeld();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        module.dispose();
        await t.runAsync(() async {
          await peer.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'connected Play Scan real keyboard stage pointer commit keeps held wire receipt and local wait dynamic',
    (t) async {
      size(t, const Size(1280, 1100));
      final peer = _Peer();
      final notifications = _notifications();
      final module = createNotificationSettingsModule(notifications);
      ContinuousPlayController? actual;
      VoidCallback? observed;
      final risingSources = <InteractionSource>[];
      try {
        await module.initialize();
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(
                module: module,
                session: peer.session,
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t, count: 6);
        final panel = find.byType(ContinuousPlayConnectedPanel);
        expect(panel, findsOneWidget);
        final controller = t
            .widget<ContinuousPlayConnectedPanel>(panel)
            .controller;
        actual = controller;
        final confirmed = controller.value.settings!;
        expect(confirmed.revision, 4);
        expect(confirmed.enabled, isTrue);
        expect(confirmed.firstMinutes, 120);
        expect(confirmed.repeatMinutes, 120);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(peer.held, isEmpty);
        var wasBusy = controller.value.busy;
        observed = () {
          final busy = controller.value.busy;
          if (busy && !wasBusy) {
            // Observe the real synchronous owner notification's zone. The
            // asynchronous host incoming listener is not a UI-source witness.
            risingSources.add(captureStarBridgeActivationSource()());
          }
          wasBusy = busy;
        };
        controller.addListener(observed);

        final row = find
            .ancestor(
              of: find.byKey(const Key('notification-play-enabled')),
              matching: find.byType(StarBridgeSwitch),
            )
            .first;
        await t.ensureVisible(row);
        await t.pump();
        await t.pump();
        await _keyboardStage(t, row);
        await _frames(t, count: 2);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        expect(drafts.dirty, isTrue);
        expect(drafts.saving, isFalse);
        expect(peer.held, isEmpty);
        expect(risingSources, isEmpty);
        expect(controller.value.settings, same(confirmed));
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(notifications.writes, isEmpty);

        await act(
          t,
          find.byKey(const Key('notification-save')),
          'pointer',
          '保存更改',
        );
        await _frames(t, count: 2);
        expect(
          peer.held,
          hasLength(1),
          reason:
              'The actual save callback must reach the original Bridge port.',
        );
        expect(peer.answered, isEmpty);
        expect(risingSources, [InteractionSource.pointer]);
        expect(
          t.widget<ContinuousPlayConnectedPanel>(panel).controller,
          same(controller),
        );
        final request = peer.held.single;
        expect(request.payload, {
          'schemaVersion': 1,
          'expectedRevision': 4,
          'enabled': false,
          'firstReminderMinutes': 120,
          'repeatReminderMinutes': 120,
        });
        expect(request.accountContext, isNull);
        expect(controller.value.settings, same(confirmed));
        expect(controller.value.settings!.revision, 4);
        expect(controller.value.settings!.enabled, isTrue);
        expect(controller.value.busy, isTrue);
        expect(drafts.saving, isTrue);
        expect(drafts.dirty, isTrue);
        expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
        expect(
          module.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        expect(notifications.writes, isEmpty);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );

        // This inverse regression retains real pointer waiting feedback,
        // rather than making every request static to fix keyboard submission.
        final frames = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        final labels = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyLabel),
        );
        expect(frames, findsOneWidget);
        expect(labels, findsOneWidget);
        for (final element in [...frames.evaluate(), ...labels.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isFalse,
            reason: 'The real Play owner began under pointer commit, not the earlier keyboard stage; its local wait must retain motion.',
          );
        }

        expect(t.widget<SuiteBusyFrame>(frames).busy, isTrue);
        expect(InteractionScope.of(t.element(frames)).animates, isTrue);

        await peer.acknowledgeHeld();
        await _frames(t, count: 6);
        expect(controller.value.settings!.revision, 5);
        expect(controller.value.settings!.enabled, isFalse);
        expect(controller.value.settings!.firstMinutes, 120);
        expect(controller.value.settings!.repeatMinutes, 120);
        expect(controller.value.busy, isFalse);
        expect(controller.value.failed, isFalse);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        expect(peer.held, hasLength(1));
        expect(peer.answered, hasLength(1));
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );
        expect(notifications.writes, isEmpty);
        expect(risingSources, [InteractionSource.pointer]);
        expect(t.takeException(), isNull);
      } finally {
        final listener = observed;
        if (listener != null) {
          actual?.removeListener(listener);
        }
        // Only cleanup releases a held receipt after a red assertion; there
        // is no early ack to make the local waiting checkpoint pass.
        await peer.acknowledgeHeld();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        module.dispose();
        await t.runAsync(() async {
          await peer.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'connected Play Scan keyboard save rejection retains draft and explicit pointer retry owns dynamic wait',
    (t) async {
      size(t, const Size(1280, 1100));
      final peer = _Peer();
      final notifications = _notifications();
      final module = createNotificationSettingsModule(notifications);
      ContinuousPlayController? actual;
      VoidCallback? observed;
      final risingSources = <InteractionSource>[];
      try {
        await module.initialize();
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(
                module: module,
                session: peer.session,
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t, count: 6);
        final panel = find.byType(ContinuousPlayConnectedPanel);
        expect(panel, findsOneWidget);
        final controller = t
            .widget<ContinuousPlayConnectedPanel>(panel)
            .controller;
        actual = controller;
        final confirmed = controller.value.settings!;
        expect(confirmed.revision, 4);
        expect(confirmed.enabled, isTrue);
        expect(confirmed.firstMinutes, 120);
        expect(confirmed.repeatMinutes, 120);
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(peer.held, isEmpty);
        var wasBusy = controller.value.busy;
        observed = () {
          final busy = controller.value.busy;
          if (busy && !wasBusy) {
            // Observe the real synchronous owner notification's zone. The
            // asynchronous host incoming listener is not a UI-source witness.
            risingSources.add(captureStarBridgeActivationSource()());
          }
          wasBusy = busy;
        };
        controller.addListener(observed);

        final row = find
            .ancestor(
              of: find.byKey(const Key('notification-play-enabled')),
              matching: find.byType(StarBridgeSwitch),
            )
            .first;
        await t.ensureVisible(row);
        await t.pump();
        await t.pump();
        await t.tap(row);
        await _frames(t, count: 2);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        expect(drafts.dirty, isTrue);
        expect(drafts.saving, isFalse);
        expect(peer.held, isEmpty);
        expect(risingSources, isEmpty);
        expect(controller.value.settings, same(confirmed));
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(notifications.writes, isEmpty);

        await act(
          t,
          find.byKey(const Key('notification-save')),
          'keyboard',
          '保存更改',
        );
        await _frames(t, count: 2);
        expect(
          peer.held,
          hasLength(1),
          reason:
              'The actual save callback must reach the original Bridge port.',
        );
        expect(peer.answered, isEmpty);
        expect(risingSources, [InteractionSource.keyboard]);
        expect(
          t.widget<ContinuousPlayConnectedPanel>(panel).controller,
          same(controller),
        );
        final request = peer.held.single;
        expect(request.payload, {
          'schemaVersion': 1,
          'expectedRevision': 4,
          'enabled': false,
          'firstReminderMinutes': 120,
          'repeatReminderMinutes': 120,
        });
        expect(request.accountContext, isNull);
        expect(controller.value.settings, same(confirmed));
        expect(controller.value.settings!.revision, 4);
        expect(controller.value.settings!.enabled, isTrue);
        expect(controller.value.busy, isTrue);
        expect(drafts.saving, isTrue);
        expect(drafts.dirty, isTrue);
        expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
        expect(
          module.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        expect(notifications.writes, isEmpty);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );

        // This is the proven regression checkpoint, after real owner provenance,
        // payload and unchanged-confirmed facts. Do not inspect only Frame's
        // outer save wait, which already receives the keyboard source.
        final frames = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyFrame),
        );
        final labels = find.descendant(
          of: panel,
          matching: find.byType(SuiteBusyLabel),
        );
        expect(frames, findsOneWidget);
        expect(labels, findsOneWidget);
        for (final element in [...frames.evaluate(), ...labels.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isTrue,
            reason: 'The real Play owner began under keyboard commit, not the earlier pointer stage; its local wait must be static.',
          );
        }

        await peer.rejectHeld();
        await _frames(t, count: 6);
        expect(peer.held, hasLength(1));
        expect(peer.answered, hasLength(1));
        expect(controller.value.settings, same(confirmed));
        expect(controller.value.settings!.revision, 4);
        expect(controller.value.settings!.enabled, isTrue);
        expect(controller.value.busy, isFalse);
        expect(controller.value.failed, isTrue);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isTrue);
        expect(drafts.failed, isTrue);
        expect(
          find.byKey(const Key('continuous-play-failure')),
          findsOneWidget,
        );
        expect(t.widget<StarBridgeSwitch>(row).value, isFalse);
        expect(
          t.widget<StarBridgeSwitch>(row).onChanged,
          isNotNull,
          reason: 'The original editor is enabled again; the rejected draft remains editable.',
        );
        // No timer or presentation listener may retry the rejected request.
        await _frames(t, count: 3);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(1),
        );
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(notifications.writes, isEmpty);

        // Only this actual pointer activation submits the retained draft.
        await act(
          t,
          find.byKey(const Key('notification-save')),
          'pointer',
          '保存更改',
        );
        await _frames(t, count: 2);
        expect(peer.held, hasLength(2));
        expect(peer.answered, hasLength(1));
        expect(risingSources, [
          InteractionSource.keyboard,
          InteractionSource.pointer,
        ]);
        final retried = peer.held.last;
        expect(retried.correlationId, isNot(request.correlationId));
        expect(retried.payload, request.payload);
        expect(retried.payload['expectedRevision'], 4);
        expect(retried.accountContext, isNull);
        expect(controller.value.settings, same(confirmed));
        expect(controller.value.settings!.revision, 4);
        expect(controller.value.settings!.enabled, isTrue);
        expect(controller.value.busy, isTrue);
        expect(drafts.saving, isTrue);
        expect(drafts.dirty, isTrue);
        expect(drafts.failed, isFalse);
        expect(t.widget<StarBridgeSwitch>(row).onChanged, isNull);
        expect(
          module.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        expect(notifications.writes, isEmpty);
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(2),
        );
        for (final element in [...frames.evaluate(), ...labels.evaluate()]) {
          expect(
            InteractionScope.of(element).reduceMotion ||
                !TickerMode.valuesOf(element).enabled,
            isFalse,
            reason: 'The explicit pointer retry is a new active task, not the prior static keyboard failure.',
          );
        }
        expect(t.widget<SuiteBusyFrame>(frames).busy, isTrue);
        expect(InteractionScope.of(t.element(frames)).animates, isTrue);

        await peer.acknowledgeHeld();
        await _frames(t, count: 6);
        expect(controller.value.settings!.revision, 5);
        expect(controller.value.settings!.enabled, isFalse);
        expect(controller.value.settings!.firstMinutes, 120);
        expect(controller.value.settings!.repeatMinutes, 120);
        expect(controller.value.busy, isFalse);
        expect(controller.value.failed, isFalse);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        expect(peer.held, hasLength(2));
        expect(peer.answered, hasLength(2));
        expect(
          peer.requests.where((r) => r.name == 'playReminder.read'),
          hasLength(1),
        );
        expect(
          peer.requests.where((r) => r.name.endsWith('.save')),
          hasLength(2),
        );
        expect(notifications.writes, isEmpty);
        expect(risingSources, [
          InteractionSource.keyboard,
          InteractionSource.pointer,
        ]);
        expect(t.takeException(), isNull);
      } finally {
        final listener = observed;
        if (listener != null) {
          actual?.removeListener(listener);
        }
        // Only cleanup releases a held receipt after a red assertion; there
        // is no early ack to make the local waiting checkpoint pass.
        await peer.acknowledgeHeld();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        module.dispose();
        await t.runAsync(() async {
          await peer.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
