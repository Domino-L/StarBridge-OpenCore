import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/settings/notification_audio_test.dart' show AudioFake;
import 'interaction_batch3do_test.dart' as fixture;

const _timeout = Timeout(Duration(seconds: 45));

enum _Result { accepted, rejected, conflict, missingSnapshot }

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Typed, controlled transport; the actual NotificationSettingsModule retains
/// admission, revision handling and its existing queued-refresh policy.
class _Port implements NotificationSettingsPort {
  NotificationSettingsSnapshot current =
      InMemoryNotificationSettingsAdapter.forReview().current;
  final events = StreamController<void>.broadcast();
  final updates = <(NotificationSettingsValue, int)>[];
  int reads = 0;
  _Result result = _Result.accepted;
  Completer<NotificationSettingsWriteResult>? writeGate;
  Completer<NotificationSettingsSnapshot>? readGate;
  bool closed = false;

  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<NotificationSettingsSnapshot> read() async {
    reads++;
    if (readGate != null) {
      return readGate!.future;
    }
    return current;
  }

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  }) async {
    updates.add((settings, expectedRevision));
    if (writeGate != null) return writeGate!.future;
    return _result(settings, expectedRevision);
  }

  NotificationSettingsWriteResult _result(
    NotificationSettingsValue settings,
    int revision,
  ) {
    if (result == _Result.rejected) {
      return const NotificationSettingsWriteResult.failed(
        NotificationSettingsFailure.writeFailed,
      );
    }
    if (result == _Result.conflict) {
      return const NotificationSettingsWriteResult.failed(
        NotificationSettingsFailure.writeConflict,
      );
    }
    if (result == _Result.missingSnapshot) {
      return const NotificationSettingsWriteResult.completed(null);
    }
    if (current.revision != revision) {
      return const NotificationSettingsWriteResult.failed(
        NotificationSettingsFailure.writeConflict,
      );
    }
    current = NotificationSettingsSnapshot.available(
      settings: settings,
      revision: revision + 1,
    );
    return NotificationSettingsWriteResult.completed(current);
  }

  void finishWrite() {
    final gate = writeGate;
    writeGate = null;
    if (gate != null && !gate.isCompleted) {
      final update = updates.last;
      gate.complete(_result(update.$1, update.$2));
    }
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await events.close();
  }
}

Widget _app(
  NotificationSettingsModule module,
  InteractionSuite suite, {
  NotificationAudioController? audio,
}) => fixture.scopedApp(
  NotificationSettingsPage(module: module, audio: audio),
  suite,
);

PrivacyPageDrafts _drafts(WidgetTester t) => NotificationDraftScope.of(
  t.element(find.byKey(const Key('notification-settings-content'))),
)!;

StarBridgeActionButton _button(WidgetTester t, String key) {
  final target = find.byKey(Key(key));
  if (t.widget(target) is StarBridgeActionButton) {
    return t.widget<StarBridgeActionButton>(target);
  }
  return t.widget<StarBridgeActionButton>(
    find
        .ancestor(of: target, matching: find.byType(StarBridgeActionButton))
        .first,
  );
}

Future<void> _tap(WidgetTester t, String key) async {
  final keyed = find.byKey(Key(key));
  var target = keyed;
  final widget = t.widget(keyed);
  if (widget is! StarBridgeSwitch && widget is! StarBridgeActionButton) {
    final switches = find.ancestor(
      of: keyed,
      matching: find.byType(StarBridgeSwitch),
    );
    final buttons = find.ancestor(
      of: keyed,
      matching: find.byType(StarBridgeActionButton),
    );
    if (switches.evaluate().isNotEmpty) {
      target = switches.first;
    } else if (buttons.evaluate().isNotEmpty) {
      target = buttons.first;
    }
  }
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump();
}

Future<void> _mount(
  WidgetTester t,
  NotificationSettingsModule module,
  InteractionSuite suite, {
  NotificationAudioController? audio,
}) async {
  fixture.size(t, const Size(1280, 1100));
  await module.initialize();
  await t.pumpWidget(_app(module, suite, audio: audio));
  await _frames(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t, count: 2);
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite notification failure retry keeps the same focused node across responsive breakpoints and Enter reads once',
      (t) async {
        final port = _Port()..result = _Result.rejected;
        final module = createNotificationSettingsModule(port);
        try {
          await _mount(t, module, suite);
          await _tap(t, 'notification-channel-windows');
          await _tap(t, 'notification-save');
          await _frames(t);
          expect(
            module.projection.value.failure,
            NotificationSettingsFailure.writeFailed,
          );
          expect(port.reads, 1);
          expect(port.updates, hasLength(1));
          expect(module.projection.value.revision, 11);

          FocusNode retryFocus() {
            final control = t.widget(
              find.byKey(const Key('notification-failure-retry')),
            );
            return switch (control) {
              ButtonStyleButton button => button.focusNode!,
              SuitePressable button => button.focusNode!,
              _ => throw StateError(
                'Retry must retain its actual focus target',
              ),
            };
          }

          final focus = retryFocus();
          focus.requestFocus();
          await t.pump();
          expect(focus.hasFocus, isTrue);
          for (final width in [430.0, 1280.0, 430.0, 1280.0]) {
            t.view.physicalSize = Size(width, 1100);
            await _frames(t, count: 2);
            expect(retryFocus(), same(focus));
            expect(focus.hasFocus, isTrue);
            expect(
              port.reads,
              1,
              reason: 'Resizing or focusing must not issue a retry.',
            );
            expect(port.updates, hasLength(1));
            expect(module.projection.value.revision, 11);
            expect(t.takeException(), isNull);
          }

          port.readGate = Completer<NotificationSettingsSnapshot>();
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          expect(port.reads, 2);
          expect(port.updates, hasLength(1));
          expect(
            module.projection.value.availability,
            NotificationSettingsAvailability.loading,
          );
          expect(
            t
                .widget<NotificationLoadingView>(
                  find.byType(NotificationLoadingView),
                )
                .source,
            InteractionSource.keyboard,
          );
          await _frames(t, count: 2);
          expect(port.reads, 2);
          port.readGate!.complete(port.current);
          port.readGate = null;
          await _frames(t);
          expect(port.reads, 2);
          expect(port.updates, hasLength(1));
          expect(module.projection.value.revision, 11);
          expect(t.takeException(), isNull);
        } finally {
          final gate = port.readGate;
          if (gate != null && !gate.isCompleted) {
            gate.complete(port.current);
          }
          await _unmount(t);
          module.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification pending mutation keeps original revision and coalesces queued read only after success',
      (t) async {
        final port = _Port();
        final module = createNotificationSettingsModule(port);
        try {
          await _mount(t, module, suite);
          expect(port.reads, 1);
          expect(port.updates, isEmpty);
          await _tap(t, 'notification-channel-windows');
          final drafts = _drafts(t);
          expect(drafts.dirty, isTrue);
          expect(port.updates, isEmpty);
          final oldSave = _button(t, 'notification-save').onActivate!;
          port.writeGate = Completer<NotificationSettingsWriteResult>();
          await _tap(t, 'notification-save');
          await _frames(t, count: 2);
          expect(port.updates, hasLength(1));
          expect(port.updates.single.$2, 11);
          expect(module.projection.value.revision, 11);
          expect(
            module.projection.value.settings!.channels.windowsDesktopEnabled,
            isTrue,
          );
          expect(
            module.projection.value.operation,
            NotificationSettingsOperation.saving,
          );
          expect(drafts.saving, isTrue);
          expect(_button(t, 'notification-save').onActivate, isNull);
          expect(_button(t, 'notification-discard').onActivate, isNull);
          oldSave(InteractionSource.pointer);
          expect(await confirmNotificationLeave(module), isFalse);
          port.events.add(null);
          port.events.add(null);
          await _frames(t, count: 2);
          expect(port.updates, hasLength(1));
          expect(port.reads, 1);
          port.finishWrite();
          await _frames(t);
          expect(port.updates, hasLength(1));
          expect(port.reads, 2);
          expect(module.projection.value.revision, 12);
          expect(
            module.projection.value.settings!.channels.windowsDesktopEnabled,
            isFalse,
          );
          expect(drafts.dirty, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          port.finishWrite();
          await _unmount(t);
          module.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification rejected conflict and unconfirmed snapshot preserve original accepted values',
      (t) async {
        for (final failure in [
          _Result.rejected,
          _Result.conflict,
          _Result.missingSnapshot,
        ]) {
          final port = _Port()..result = failure;
          final module = createNotificationSettingsModule(port);
          try {
            await _mount(t, module, suite);
            final confirmed = module.projection.value.settings!;
            await _tap(t, 'notification-channel-windows');
            await _tap(t, 'notification-save');
            await _frames(t);
            expect(port.updates, hasLength(1));
            expect(port.reads, 1);
            expect(module.projection.value.settings, same(confirmed));
            expect(module.projection.value.revision, 11);
            expect(module.projection.value.canEdit, isTrue);
            expect(
              module.projection.value.failure,
              failure == _Result.conflict
                  ? NotificationSettingsFailure.writeConflict
                  : NotificationSettingsFailure.writeFailed,
            );
            expect(_drafts(t).dirty, isTrue);
            expect(_drafts(t).failed, isTrue);
            port.result = _Result.accepted;
            await _tap(t, 'notification-save');
            await _frames(t);
            expect(port.updates, hasLength(2));
            expect(port.updates.map((call) => call.$2), [11, 11]);
            expect(port.reads, 1);
            expect(module.projection.value.revision, 12);
            expect(_drafts(t).dirty, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            module.dispose();
          }
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification failed queued refresh preserves the original explicit drain behavior',
      (t) async {
        final port = _Port()..result = _Result.rejected;
        final module = createNotificationSettingsModule(port);
        try {
          await _mount(t, module, suite);
          await _tap(t, 'notification-channel-windows');
          port.writeGate = Completer<NotificationSettingsWriteResult>();
          await _tap(t, 'notification-save');
          await _frames(t, count: 2);
          await module.refresh();
          await module.refresh();
          expect(port.reads, 1);
          port.finishWrite();
          await _frames(t);
          expect(port.updates, hasLength(1));
          expect(
            port.reads,
            1,
            reason: 'The existing owner does not drain its pending read in the failed-write branch.',
          );
          expect(_drafts(t).dirty, isTrue);
          expect(_drafts(t).failed, isTrue);
          await module.refresh();
          await _frames(t);
          expect(
            port.reads,
            3,
            reason: 'One explicit read and the previously queued read follow the original module contract.',
          );
          expect(port.updates, hasLength(1));
          expect(module.projection.value.revision, 11);
          expect(_drafts(t).dirty, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          port.finishWrite();
          await _unmount(t);
          module.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification owner replacement retires old draft queue without cancelling old domain write',
      (t) async {
        final oldPort = _Port();
        final newPort = _Port();
        final oldModule = createNotificationSettingsModule(oldPort);
        final newModule = createNotificationSettingsModule(newPort);
        try {
          await _mount(t, oldModule, suite);
          await _tap(t, 'notification-channel-windows');
          final oldDrafts = _drafts(t);
          var nextOwnerCalls = 0;
          oldDrafts.edit('separate-controlled-owner', false, true, (_) async {
            nextOwnerCalls++;
            return true;
          });
          oldPort.writeGate = Completer<NotificationSettingsWriteResult>();
          await _tap(t, 'notification-save');
          await _frames(t, count: 2);
          expect(oldPort.updates, hasLength(1));
          await newModule.initialize();
          await t.pumpWidget(_app(newModule, suite));
          await _frames(t, count: 2);
          final newDrafts = _drafts(t);
          expect(newDrafts, isNot(same(oldDrafts)));
          expect(newDrafts.dirty, isFalse);
          expect(notificationLeaveGuards[oldModule], isNull);
          expect(notificationLeaveGuards[newModule], isNotNull);
          oldPort.finishWrite();
          await _frames(t);
          expect(nextOwnerCalls, 0);
          expect(oldModule.projection.value.revision, 12);
          expect(newModule.projection.value.revision, 11);
          expect(newPort.updates, isEmpty);
          expect(newPort.reads, 1);
          expect(newDrafts.dirty, isFalse);
          expect(newDrafts.failed, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          oldPort.finishWrite();
          await _unmount(t);
          oldModule.dispose();
          newModule.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification page unmount and owner dispose keep their distinct late-receipt contracts',
      (t) async {
        for (final disposeOwner in [false, true]) {
          final port = _Port();
          final module = createNotificationSettingsModule(port);
          var disposed = false;
          try {
            await _mount(t, module, suite);
            final original = module.projection.value.settings!;
            port.writeGate = Completer<NotificationSettingsWriteResult>();
            final save = module.save(
              original.copyWith(
                channels: original.channels.copyWith(
                  windowsDesktopEnabled: false,
                ),
              ),
            );
            await _frames(t, count: 2);
            expect(port.updates, hasLength(1));
            await _unmount(t);
            if (disposeOwner) {
              module.dispose();
              disposed = true;
            }
            port.finishWrite();
            expect(await save, !disposeOwner);
            await _frames(t);
            if (!disposeOwner) {
              expect(module.projection.value.revision, 12);
              expect(
                module
                    .projection
                    .value
                    .settings!
                    .channels
                    .windowsDesktopEnabled,
                isFalse,
              );
            }
            expect(port.updates, hasLength(1));
            expect(port.reads, 1);
            expect(t.takeException(), isNull);
          } finally {
            port.finishWrite();
            await _unmount(t);
            if (!disposed) module.dispose();
          }
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite notification partial acknowledgement retries only failed audio without replaying accepted settings',
      (t) async {
        final port = _Port();
        final module = createNotificationSettingsModule(port);
        final audioPort = AudioFake()..fail = true;
        final audio = NotificationAudioController(audioPort);
        try {
          await audio.refresh();
          await _mount(t, module, suite, audio: audio);
          await _tap(t, 'notification-channel-windows');
          await _tap(t, 'audio-enabled');
          expect(port.updates, isEmpty);
          expect(audioPort.writes, 0);
          await _tap(t, 'notification-save');
          await _frames(t);
          expect(port.updates, hasLength(1));
          expect(module.projection.value.revision, 12);
          expect(audioPort.writes, 1);
          expect(audio.value!.enabled, isFalse);
          expect(_drafts(t).dirty, isTrue);
          expect(_drafts(t).failed, isTrue);
          audioPort.fail = false;
          await _tap(t, 'notification-save');
          await _frames(t);
          expect(port.updates, hasLength(1));
          expect(port.reads, 1);
          expect(module.projection.value.revision, 12);
          expect(audioPort.writes, 2);
          expect(audio.value!.enabled, isTrue);
          expect(_drafts(t).dirty, isFalse);
          expect(
            audioPort.plays,
            0,
            reason: 'This controlled audio test never invokes preview or real output.',
          );
          expect(t.takeException(), isNull);
        } finally {
          await _unmount(t);
          audio.dispose();
          module.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite local notification Bridge capability keeps account-agnostic minimal read and write behavior',
      (t) async {
        for (final available in [false, true]) {
          final pair = InMemoryBridgeConnection.createPair();
          final session =
              BridgeClientSession(
                connection: pair.client,
                sessionGeneration: 4,
              )..acceptHostCapabilities(
                available
                    ? ['notificationSettings.read', 'notificationSettings.save']
                    : [],
              );
          final requests = <BridgeEnvelope>[];
          var revision = 0;
          var inApp = true;
          final sub = pair.host.incoming.listen((request) {
            if (request.messageType != 'request') return;
            requests.add(request);
            if (request.name == 'notificationSettings.save') {
              revision++;
              inApp = request.payload['inAppEnabled'] as bool;
            }
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: 4,
                  status: 'ok',
                  payload: {
                    'schemaVersion': 1,
                    'revision': revision,
                    'inAppEnabled': inApp,
                    'position': 'bottomRight',
                    'preview': 'sourceOnly',
                  },
                ),
              ),
            );
          });
          final module = createNotificationSettingsModule(
            BridgeNotificationSettingsAdapter(session),
          );
          try {
            await _mount(t, module, suite);
            if (!available) {
              expect(
                module.projection.value.availability,
                NotificationSettingsAvailability.unavailable,
              );
              expect(requests, isEmpty);
            } else {
              expect(module.projection.value.settings!.localInAppOnly, isTrue);
              expect(
                module.projection.value.settings!.desktopDeliveryAvailable,
                isFalse,
              );
              expect(requests.map((r) => r.name), [
                'notificationSettings.read',
              ]);
              await _tap(t, 'notification-channel-in-app');
              expect(requests, hasLength(1));
              await _tap(t, 'notification-save');
              await _frames(t);
              expect(requests.map((r) => r.name), [
                'notificationSettings.read',
                'notificationSettings.save',
              ]);
              expect(requests.every((r) => r.accountContext == null), isTrue);
              expect(requests.last.payload['expectedRevision'], 0);
              expect(requests.last.payload['inAppEnabled'], isFalse);
              expect(module.projection.value.revision, 1);
              expect(
                module.projection.value.settings!.channels.inAppEnabled,
                isFalse,
              );
            }
            expect(t.takeException(), isNull);
          } finally {
            await _unmount(t);
            module.dispose();
            await t.runAsync(() async {
              await sub.cancel();
              await session.close();
              await pair.host.close();
            });
          }
        }
      },
      timeout: _timeout,
    );
  }
}
