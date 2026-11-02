import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
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

// Regression contracts for stable notification/audio editor composition.
// Both paths retain the real editor queue, module and controller. These gates
// replace transport only; there is no native playback, storage or extra owner.
class _AudioGate implements NotificationAudioPort {
  AudioPreferences stored = const AudioPreferences(
    3,
    true,
    .65,
    true,
    doNotDisturb: true,
  );
  final receipt = Completer<AudioPreferences>();
  int reads = 0, writes = 0, previews = 0, stops = 0;
  AudioPreferences? submittedFrom;
  bool? submittedEnabled;
  double? submittedVolume;
  bool? submittedDnd;

  @override
  Future<AudioPreferences> read() async {
    reads++;
    return stored;
  }

  @override
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  }) {
    writes++;
    submittedFrom = current;
    submittedEnabled = enabled;
    submittedVolume = volume;
    submittedDnd = doNotDisturb;
    return receipt.future;
  }

  void accept() {
    if (receipt.isCompleted) {
      return;
    }
    final from = submittedFrom;
    if (from != null) {
      stored = AudioPreferences(
        from.revision + 1,
        submittedEnabled!,
        submittedVolume!,
        true,
        doNotDisturb: submittedDnd ?? from.doNotDisturb,
      );
    }
    receipt.complete(stored);
  }

  @override
  Future<String> preview() async {
    previews++;
    return 'played';
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

/// The real production connected panels supply the lower scroll content.
/// Reply to their existing typed reads, rather than padding the product tree
/// with test boxes or creating a second notification/audio business owner.
class _ConnectedHost {
  _ConnectedHost() {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 1)
      ..acceptHostCapabilities(['playerActivity.read', 'playReminder.read']);
    subscription = host.incoming.listen((request) {
      reads.add(request.name);
      final payload = switch (request.name) {
        'account.getCurrent' => <String, Object?>{
          'schemaVersion': 1,
          'state': 'signedOut',
        },
        'playerActivity.read' => <String, Object?>{
          'schemaVersion': 1,
          'revision': 'missing',
          'enabled': false,
          'scope': 0,
          'position': 0,
          'online': false,
          'offline': false,
          'startedGame': false,
          'stoppedGame': false,
          'backgroundOnly': true,
          'reduceInGame': true,
          'writable': true,
        },
        'playReminder.read' => <String, Object?>{
          'schemaVersion': 1,
          'revision': 7,
          'enabled': false,
          'firstReminderMinutes': 60,
          'repeatReminderMinutes': 60,
        },
        _ => null,
      };
      unawaited(
        host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            sessionGeneration: 1,
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
        ),
      );
    });
  }
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final reads = <String>[];

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _stageAndSave(WidgetTester t, _AudioGate port) async {
  final row = find
      .ancestor(
        of: find.byKey(const Key('audio-enabled')),
        matching: find.byType(StarBridgeSwitch),
      )
      .first;
  await t.ensureVisible(row);
  await t.pump();
  await t.tap(row);
  await _frames(t, count: 2);
  expect(port.writes, 0);
  await act(t, find.byKey(const Key('notification-save')), 'pointer', '保存更改');
  await _frames(t, count: 2);
  expect(port.writes, 1);
  expect(port.submittedFrom!.revision, 3);
  expect(port.submittedEnabled, isFalse);
  expect(port.submittedDnd, isTrue);
}

void _accepted(
  _AudioGate port,
  NotificationAudioController audio,
  NotificationMotionPort notifications,
) {
  expect(port.stored.revision, 4);
  expect(port.stored.enabled, isFalse);
  expect(port.stored.volume, .65);
  expect(port.stored.doNotDisturb, isTrue);
  expect(audio.value, same(port.stored));
  expect(audio.error, isNull);
  expect(audio.status, 'saved');
  expect(audio.busy, isFalse);
  expect(port.writes, 1);
  expect(port.reads, 1);
  expect(port.previews, 0);
  expect(notifications.writes, isEmpty);
  expect(notifications.reads, hasLength(2));
}

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'stable audio State and accepted draft survive available loading available during held save',
    (t) async {
      size(t, const Size(1280, 1100));
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = _AudioGate();
      final audio = NotificationAudioController(port);
      final pendingRead = Completer<NotificationSettingsSnapshot>();
      try {
        await module.initialize();
        await audio.refresh();
        await t.pumpWidget(
          scopedApp(
            SizedBox.expand(
              child: NotificationSettingsPage(module: module, audio: audio),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t);
        final panel = find.byType(NotificationAudioPanel);
        final original = t.state(panel);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        await _stageAndSave(t, port);
        expect(drafts.dirty, isTrue);
        expect(drafts.saving, isTrue);
        expect(audio.busy, isTrue);
        expect(audio.value!.revision, 3);
        expect(
          module.projection.value.operation,
          NotificationSettingsOperation.none,
        );
        notifications.pendingRead = pendingRead;
        final refresh = module.refresh();
        await _frames(t, count: 2);
        expect(
          module.projection.value.availability,
          NotificationSettingsAvailability.loading,
        );
        expect(notifications.reads, hasLength(2));
        expect(original.mounted, isTrue);
        expect(
          t.state(panel),
          same(original),
          reason:
              'Notification-only read phases preserve the same audio State.',
        );
        expect(NotificationDraftScope.of(t.element(panel)), same(drafts));
        expect(audio.value!.revision, 3);
        expect(port.writes, 1);
        pendingRead.complete(notifications.stored);
        await refresh;
        await _frames(t);
        expect(
          module.projection.value.availability,
          NotificationSettingsAvailability.available,
        );
        expect(t.state(panel), same(original));
        expect(NotificationDraftScope.of(t.element(panel)), same(drafts));
        port.accept();
        await _frames(t);
        _accepted(port, audio, notifications);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        expect(t.takeException(), isNull);
      } finally {
        if (!pendingRead.isCompleted) {
          pendingRead.complete(notifications.stored);
        }
        port.accept();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'real fallback scroll beyond audio cache retains mounted State and confirms held receipt',
    (t) async {
      size(t, const Size(430, 850));
      final connected = _ConnectedHost();
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = _AudioGate();
      final audio = NotificationAudioController(port);
      final pendingRead = Completer<NotificationSettingsSnapshot>();
      try {
        await module.initialize();
        await audio.refresh();
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: SizedBox.expand(
                  child: NotificationSettingsPage(
                    module: module,
                    audio: audio,
                    session: connected.session,
                  ),
                ),
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t);
        final panel = find.byType(NotificationAudioPanel);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        await _stageAndSave(t, port);
        notifications.pendingRead = pendingRead;
        final refresh = module.refresh();
        await _frames(t);
        expect(
          module.projection.value.availability,
          NotificationSettingsAvailability.loading,
        );
        expect(notifications.reads, hasLength(2));
        FocusManager.instance.primaryFocus?.unfocus();
        await _frames(t, count: 6);
        final fallbackState = t.state(panel);
        expect(fallbackState.mounted, isTrue);
        expect(NotificationDraftScope.of(t.element(panel)), same(drafts));
        final scrollFinder = find
            .ancestor(
              of: find.byType(NotificationLoadingView),
              matching: find.byType(Scrollable),
            )
            .first;
        final scroll = t.state<ScrollableState>(scrollFinder);
        final viewportRect = t.getRect(scrollFinder);
        final audioTrailing =
            t.getRect(panel).bottom - viewportRect.top + scroll.position.pixels;
        final viewports = find.descendant(
          of: scrollFinder,
          matching: find.byType(Viewport),
        );
        expect(viewports, findsOneWidget);
        final cacheSpec = t
            .renderObject<RenderViewport>(viewports.first)
            .scrollCacheExtent;
        final cache =
            cacheSpec.value *
            (cacheSpec.style == CacheExtentStyle.viewport
                ? viewportRect.height
                : 1);
        for (var i = 0; i < 24 && scroll.position.extentAfter > 1; i++) {
          await t.timedDragFrom(
            Offset(viewportRect.right - 8, viewportRect.center.dy),
            const Offset(0, -500),
            const Duration(milliseconds: 350),
          );
          await _frames(t, count: 3);
        }
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
        expect(
          scroll.position.pixels - cache,
          greaterThan(audioTrailing + 1),
          reason: 'Actual production connected content, not a spacer, must put audio wholly behind the lazy cache.',
        );
        expect(
          fallbackState.mounted,
          isTrue,
          reason: 'Scrolling the fallback cannot dispose the editor holding an admitted audio receipt.',
        );
        expect(port.writes, 1);
        expect(audio.busy, isTrue);
        expect(audio.value!.revision, 3);
        expect(connected.reads, contains('playReminder.read'));
        expect(
          connected.reads.where((name) => name.endsWith('.save')),
          isEmpty,
        );
        port.accept();
        await _frames(t);
        _accepted(port, audio, notifications);
        expect(drafts.saving, isFalse);
        expect(drafts.dirty, isFalse);
        expect(drafts.failed, isFalse);
        pendingRead.complete(notifications.stored);
        await refresh;
        await _frames(t);
        expect(t.state(panel), same(fallbackState));
        expect(t.takeException(), isNull);
      } finally {
        if (!pendingRead.isCompleted) {
          pendingRead.complete(notifications.stored);
        }
        port.accept();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await connected.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'actual cached audio page unmount retires State stop and leave lease before late receipt',
    (t) async {
      size(t, const Size(430, 850));
      final connected = _ConnectedHost();
      final notifications = NotificationMotionPort();
      final module = createNotificationSettingsModule(notifications);
      final port = _AudioGate();
      final audio = NotificationAudioController(port);
      final pendingRead = Completer<NotificationSettingsSnapshot>();
      try {
        await module.initialize();
        await audio.refresh();
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: SizedBox.expand(
                  child: NotificationSettingsPage(
                    module: module,
                    audio: audio,
                    session: connected.session,
                  ),
                ),
              ),
            ),
            InteractionSuite.scan,
          ),
        );
        await _frames(t);
        final panel = find.byType(NotificationAudioPanel);
        final drafts = NotificationDraftScope.of(t.element(panel))!;
        await _stageAndSave(t, port);
        notifications.pendingRead = pendingRead;
        final refresh = module.refresh();
        await _frames(t);
        expect(
          module.projection.value.availability,
          NotificationSettingsAvailability.loading,
        );
        expect(notifications.reads, hasLength(2));
        FocusManager.instance.primaryFocus?.unfocus();
        await _frames(t, count: 6);
        final fallbackState = t.state(panel);
        expect(fallbackState.mounted, isTrue);
        expect(NotificationDraftScope.of(t.element(panel)), same(drafts));
        final scrollFinder = find
            .ancestor(
              of: find.byType(NotificationLoadingView),
              matching: find.byType(Scrollable),
            )
            .first;
        final scroll = t.state<ScrollableState>(scrollFinder);
        final viewportRect = t.getRect(scrollFinder);
        final audioTrailing =
            t.getRect(panel).bottom - viewportRect.top + scroll.position.pixels;
        final viewports = find.descendant(
          of: scrollFinder,
          matching: find.byType(Viewport),
        );
        expect(viewports, findsOneWidget);
        final renderViewport = t.renderObject<RenderViewport>(viewports.first);
        final cacheExtent = renderViewport.scrollCacheExtent;
        final cache =
            cacheExtent.value *
            (cacheExtent.style == CacheExtentStyle.viewport
                ? renderViewport.size.height
                : 1);
        for (var i = 0; i < 24 && scroll.position.extentAfter > 1; i++) {
          await t.timedDragFrom(
            Offset(viewportRect.right - 8, viewportRect.center.dy),
            const Offset(0, -500),
            const Duration(milliseconds: 350),
          );
          await _frames(t, count: 3);
        }
        expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
        expect(
          scroll.position.pixels - cache,
          greaterThan(audioTrailing + 1),
          reason: 'Actual production connected content, not a spacer, must put audio wholly behind the lazy cache.',
        );
        expect(
          fallbackState.mounted,
          isTrue,
          reason: 'Scrolling the fallback cannot dispose the editor holding an admitted audio receipt.',
        );
        expect(port.writes, 1);
        expect(audio.busy, isTrue);
        expect(audio.value!.revision, 3);
        expect(connected.reads, contains('playReminder.read'));
        expect(
          connected.reads.where((name) => name.endsWith('.save')),
          isEmpty,
        );
        expect(
          t.state(find.byType(NotificationAudioPanel, skipOffstage: false)),
          same(fallbackState),
        );
        expect(drafts.saving, isTrue);
        expect(port.receipt.isCompleted, isFalse);
        expect(notificationLeaveGuards[module], isNotNull);
        final stopsBeforeUnmount = port.stops;

        // This is a real page retirement from its cached fallback position.
        // Do not first restore availability or scroll the audio child back.
        await t.pumpWidget(const SizedBox.shrink());
        await _frames(t, count: 2);
        expect(fallbackState.mounted, isFalse);
        expect(port.stops, greaterThan(stopsBeforeUnmount));
        expect(notificationLeaveGuards[module], isNull);
        expect(find.byType(NotificationAudioPanel), findsNothing);
        expect(port.receipt.isCompleted, isFalse);
        expect(audio.busy, isTrue);
        expect(audio.value!.revision, 3);
        expect(port.writes, 1);
        expect(port.previews, 0);
        expect(t.takeException(), isNull);

        // The still-owned controller may receive its admitted transport
        // receipt. No retired page/queue is revived or permitted a new write.
        port.accept();
        await _frames(t);
        _accepted(port, audio, notifications);
        expect(notificationLeaveGuards[module], isNull);
        expect(fallbackState.mounted, isFalse);
        expect(find.byType(NotificationAudioPanel), findsNothing);
        pendingRead.complete(notifications.stored);
        await refresh;
        await _frames(t);
        expect(port.writes, 1);
        expect(port.previews, 0);
        expect(notificationLeaveGuards[module], isNull);
        expect(t.takeException(), isNull);
      } finally {
        if (!pendingRead.isCompleted) {
          pendingRead.complete(notifications.stored);
        }
        port.accept();
        await _frames(t, count: 2);
        await t.pumpWidget(const SizedBox.shrink());
        audio.dispose();
        module.dispose();
        await t.runAsync(() async {
          await connected.close();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
