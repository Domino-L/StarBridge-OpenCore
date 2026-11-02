import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;
import 'interaction_batch3dw_test.dart' show NotificationMotionPort;

const _timeout = Timeout(Duration(seconds: 45));

/// A typed transport, not another controller. All sound/storage commands are fake.
class _AudioPort implements NotificationAudioPort {
  AudioPreferences stored = const AudioPreferences(
    3,
    true,
    .65,
    true,
    doNotDisturb: true,
  );
  int reads = 0, previews = 0, stops = 0;
  final writes = <(AudioPreferences, bool, double, bool?)>[];
  Completer<AudioPreferences>? pendingSave;
  final gates = <Completer<AudioPreferences>>[];

  Completer<AudioPreferences> holdSave() {
    final gate = Completer<AudioPreferences>();
    gates.add(gate);
    return pendingSave = gate;
  }

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
    writes.add((current, enabled, volume, doNotDisturb));
    final gate = pendingSave;
    pendingSave = null;
    if (gate != null) {
      return gate.future;
    }
    stored = _receipt();
    return Future.value(stored);
  }

  AudioPreferences _receipt() {
    final request = writes.last;
    return AudioPreferences(
      request.$1.revision + 1,
      request.$2,
      request.$3,
      request.$1.previewAvailable,
      doNotDisturb: request.$4 ?? request.$1.doNotDisturb,
    );
  }

  void accept(Completer<AudioPreferences> gate) {
    stored = _receipt();
    gate.complete(stored);
  }

  void release() {
    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete(stored);
      }
    }
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

Future<void> _frames(WidgetTester t, {int count = 5}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Harness {
  _Harness(this.t, this.suite) {
    module = createNotificationSettingsModule(notifications);
    audio = NotificationAudioController(port);
    modules.add(module);
    audios.add(audio);
    ports.add(port);
  }

  final WidgetTester t;
  final InteractionSuite suite;
  final notifications = NotificationMotionPort();
  final port = _AudioPort();
  late final NotificationSettingsModule module;
  late final NotificationAudioController audio;
  final modules = <NotificationSettingsModule>[];
  final audios = <NotificationAudioController>[];
  final ports = <_AudioPort>[];
  final readGates = <Completer<NotificationSettingsSnapshot>>[];

  Widget app({
    NotificationSettingsModule? nextModule,
    NotificationAudioController? nextAudio,
    BridgeClientSession? session,
    bool omitAudio = false,
  }) => scopedApp(
    SizedBox.expand(
      child: NotificationSettingsPage(
        module: nextModule ?? module,
        audio: omitAudio ? null : nextAudio ?? audio,
        session: session,
      ),
    ),
    suite,
  );

  Future<void> mount({BridgeClientSession? session}) async {
    size(t, const Size(1280, 1100));
    await module.initialize();
    await audio.refresh();
    await t.pumpWidget(app(session: session));
    await _frames(t);
  }

  PrivacyPageDrafts get drafts => NotificationDraftScope.of(
    t.element(find.byType(NotificationAudioPanel)),
  )!;

  Future<void> stageAudio() async {
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
  }

  Future<void> stageWindows() async {
    final row = find
        .ancestor(
          of: find.byKey(const Key('notification-channel-windows')),
          matching: find.byType(StarBridgeSwitch),
        )
        .first;
    await t.ensureVisible(row);
    await t.pump();
    await t.tap(row);
    await _frames(t, count: 2);
  }

  Future<void> save() async {
    await act(t, find.byKey(const Key('notification-save')), 'pointer', '保存更改');
    await _frames(t, count: 2);
  }

  Completer<NotificationSettingsSnapshot> holdRead() {
    final gate = Completer<NotificationSettingsSnapshot>();
    readGates.add(gate);
    notifications.pendingRead = gate;
    return gate;
  }

  Future<void> close() async {
    for (final gate in readGates) {
      if (!gate.isCompleted) {
        gate.complete(notifications.stored);
      }
    }
    for (final audioPort in ports) {
      audioPort.release();
    }
    await _frames(t, count: 2);
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
    for (final controller in audios) {
      controller.dispose();
    }
    for (final owner in modules) {
      owner.dispose();
    }
    await t.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
  }
}

StarBridgeActionButton _button(WidgetTester t, String key) {
  final keyed = find.byKey(Key(key));
  if (t.widget(keyed) is StarBridgeActionButton) {
    return t.widget<StarBridgeActionButton>(keyed);
  }
  return t.widget<StarBridgeActionButton>(
    find
        .ancestor(of: keyed, matching: find.byType(StarBridgeActionButton))
        .first,
  );
}

void _confirmedAudio(_Harness h) {
  expect(h.audio.value, same(h.port.stored));
  expect(h.audio.value!.revision, 4);
  expect(h.audio.value!.enabled, isFalse);
  expect(h.audio.value!.volume, .65);
  expect(h.audio.value!.doNotDisturb, isTrue);
  expect(h.audio.error, isNull);
  expect(h.audio.status, 'saved');
  expect(h.audio.busy, isFalse);
  expect(h.port.reads, 1);
  expect(h.port.previews, 0);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final readFirst in [true, false]) {
      testWidgets(
        '$suite audio same lease read-first=$readFirst confirms one receipt through notification loading',
        (t) async {
          final h = _Harness(t, suite);
          try {
            await h.mount();
            await h.stageAudio();
            final drafts = h.drafts;
            final epoch = drafts.epoch;
            final panel = t.state(find.byType(NotificationAudioPanel));
            final receipt = h.port.holdSave();
            await h.save();
            expect(h.port.writes, hasLength(1));
            expect(h.port.writes.single.$1.revision, 3);
            expect(h.port.writes.single.$4, isTrue);
            expect(drafts.saving, isTrue);
            expect(h.audio.value!.revision, 3);
            final read = h.holdRead();
            final refreshing = h.module.refresh();
            await _frames(t, count: 2);
            expect(
              h.module.projection.value.availability,
              NotificationSettingsAvailability.loading,
            );
            expect(t.state(find.byType(NotificationAudioPanel)), same(panel));
            expect(h.drafts, same(drafts));
            expect(h.drafts.epoch, epoch);
            expect(h.port.stops, 0);
            expect(h.notifications.reads, hasLength(2));
            if (readFirst) {
              read.complete(h.notifications.stored);
              await refreshing;
              await _frames(t);
              expect(drafts.saving, isTrue);
              expect(h.audio.value!.revision, 3);
              h.port.accept(receipt);
              await _frames(t);
            } else {
              h.port.accept(receipt);
              await _frames(t);
              _confirmedAudio(h);
              expect(drafts.dirty, isFalse);
              expect(drafts.failed, isFalse);
              expect(
                h.module.projection.value.availability,
                NotificationSettingsAvailability.loading,
              );
              read.complete(h.notifications.stored);
              await refreshing;
              await _frames(t);
            }
            _confirmedAudio(h);
            expect(t.state(find.byType(NotificationAudioPanel)), same(panel));
            expect(h.drafts, same(drafts));
            expect(drafts.epoch, epoch);
            expect(drafts.saving, isFalse);
            expect(drafts.dirty, isFalse);
            expect(drafts.failed, isFalse);
            expect(h.port.writes, hasLength(1));
            expect(h.port.stops, 0);
            expect(h.notifications.writes, isEmpty);
            expect(_button(t, 'notification-save').onActivate, isNull);
            expect(t.takeException(), isNull);
          } finally {
            await h.close();
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite audio read-unavailable keeps the same local lease and acknowledges only its matching receipt',
      (t) async {
        final h = _Harness(t, suite);
        try {
          await h.mount();
          await h.stageAudio();
          final drafts = h.drafts;
          final panel = t.state(find.byType(NotificationAudioPanel));
          final receipt = h.port.holdSave();
          await h.save();
          final read = h.holdRead();
          final refreshing = h.module.refresh();
          await _frames(t, count: 2);
          read.complete(
            const NotificationSettingsSnapshot.unavailable(
              failure: NotificationSettingsFailure.readFailed,
            ),
          );
          await refreshing;
          await _frames(t);
          expect(
            h.module.projection.value.availability,
            NotificationSettingsAvailability.unavailable,
          );
          expect(
            h.module.projection.value.failure,
            NotificationSettingsFailure.readFailed,
          );
          expect(t.state(find.byType(NotificationAudioPanel)), same(panel));
          expect(h.drafts, same(drafts));
          expect(drafts.saving, isTrue);
          expect(h.audio.value!.revision, 3);
          h.port.accept(receipt);
          await _frames(t);
          _confirmedAudio(h);
          expect(drafts.dirty, isFalse);
          expect(drafts.failed, isFalse);
          expect(drafts.saving, isFalse);
          expect(
            h.module.projection.value.availability,
            NotificationSettingsAvailability.unavailable,
          );
          expect(h.port.writes, hasLength(1));
          expect(h.notifications.writes, isEmpty);
          expect(h.notifications.reads, hasLength(2));
          expect(h.port.stops, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.close();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio failure after refresh keeps only its draft and explicit retry never replays confirmed notifications',
      (t) async {
        final h = _Harness(t, suite);
        try {
          await h.mount();
          // The original queue commits the notification entry first.
          await h.stageWindows();
          await h.stageAudio();
          final drafts = h.drafts;
          final receipt = h.port.holdSave();
          await h.save();
          expect(h.notifications.writes, hasLength(1));
          expect(h.module.projection.value.revision, 12);
          expect(h.port.writes, hasLength(1));
          final read = h.holdRead();
          final refreshing = h.module.refresh();
          await _frames(t, count: 2);
          read.complete(h.notifications.stored);
          await refreshing;
          await _frames(t);
          receipt.completeError(const AudioFailure('conflict'));
          await _frames(t);
          expect(h.audio.value!.revision, 3);
          expect(h.audio.value!.enabled, isTrue);
          expect(h.audio.error, 'conflict');
          expect(drafts.dirty, isTrue);
          expect(drafts.failed, isTrue);
          expect(drafts.saving, isFalse);
          expect(h.port.writes, hasLength(1));
          expect(h.notifications.writes, hasLength(1));
          expect(h.notifications.reads, hasLength(2));
          await _frames(t);
          expect(
            h.port.writes,
            hasLength(1),
            reason: 'No automatic rewrite after rejection or view reparent.',
          );
          await h.save();
          await _frames(t);
          _confirmedAudio(h);
          expect(h.port.writes, hasLength(2));
          expect(h.port.writes.last.$1.revision, 3);
          expect(h.notifications.writes, hasLength(1));
          expect(h.module.projection.value.revision, 12);
          expect(h.notifications.reads, hasLength(2));
          expect(drafts.dirty, isFalse);
          expect(drafts.failed, isFalse);
          expect(h.port.stops, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.close();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio same body controller replacement retires old commit even when panel identity is stable',
      (t) async {
        final h = _Harness(t, suite);
        final nextPort = _AudioPort();
        final nextAudio = NotificationAudioController(nextPort);
        h.ports.add(nextPort);
        h.audios.add(nextAudio);
        try {
          await h.mount();
          await nextAudio.refresh();
          await h.stageAudio();
          final drafts = h.drafts;
          final panel = t.state(find.byType(NotificationAudioPanel));
          final receipt = h.port.holdSave();
          await h.save();
          await t.pumpWidget(h.app(nextAudio: nextAudio));
          await _frames(t);
          expect(t.state(find.byType(NotificationAudioPanel)), same(panel));
          expect(h.drafts, same(drafts));
          expect(h.port.stops, 1);
          expect(nextPort.reads, 1);
          expect(nextPort.writes, isEmpty);
          h.port.accept(receipt);
          await _frames(t);
          expect(h.audio.value!.revision, 4);
          expect(nextAudio.value!.revision, 3);
          expect(nextAudio.value!.enabled, isTrue);
          expect(drafts.dirty, isTrue);
          expect(
            drafts.failed,
            isTrue,
            reason: 'A stable widget key must not acknowledge a replaced controller lease.',
          );
          expect(nextPort.writes, isEmpty);
          expect(h.port.writes, hasLength(1));
          await act(
            t,
            find.byKey(const Key('notification-discard')),
            'pointer',
            '放弃更改',
          );
          await _frames(t, count: 2);
          expect(drafts.dirty, isFalse);
          await h.stageAudio();
          expect(nextPort.writes, isEmpty);
          await h.save();
          await _frames(t);
          expect(nextPort.writes, hasLength(1));
          expect(nextAudio.value!.revision, 4);
          expect(nextAudio.value!.doNotDisturb, isTrue);
          expect(nextAudio.value!.enabled, isFalse);
          expect(drafts.dirty, isFalse);
          expect(drafts.failed, isFalse);
          expect(h.port.previews, 0);
          expect(nextPort.previews, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.close();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio actual page module replacement retires the old frame group without cancelling its local receipt',
      (t) async {
        final h = _Harness(t, suite);
        final nextPort = NotificationMotionPort();
        final nextModule = createNotificationSettingsModule(nextPort);
        h.modules.add(nextModule);
        try {
          await h.mount();
          await nextModule.initialize();
          await h.stageAudio();
          final oldDrafts = h.drafts;
          final oldPanel = t.state(find.byType(NotificationAudioPanel));
          final oldSave = _button(t, 'notification-save').onActivate!;
          final receipt = h.port.holdSave();
          await h.save();
          await t.pumpWidget(h.app(nextModule: nextModule));
          await _frames(t);
          final fresh = h.drafts;
          expect(fresh, isNot(same(oldDrafts)));
          expect(oldPanel.mounted, isFalse);
          expect(fresh.dirty, isFalse);
          expect(fresh.failed, isFalse);
          expect(h.port.stops, greaterThanOrEqualTo(1));
          oldSave(InteractionSource.keyboard);
          expect(h.port.writes, hasLength(1));
          h.port.accept(receipt);
          await _frames(t);
          _confirmedAudio(h);
          expect(fresh.dirty, isFalse);
          expect(fresh.failed, isFalse);
          expect(fresh.saving, isFalse);
          expect(notificationLeaveGuards[h.module], isNull);
          expect(notificationLeaveGuards[nextModule], isNotNull);
          expect(h.notifications.writes, isEmpty);
          expect(nextPort.writes, isEmpty);
          expect(nextPort.reads, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await h.close();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio actual page session replacement retires frame lease rather than carrying a global panel key',
      (t) async {
        final h = _Harness(t, suite);
        final pair1 = InMemoryBridgeConnection.createPair();
        final pair2 = InMemoryBridgeConnection.createPair();
        final first = BridgeClientSession(
          connection: pair1.client,
          sessionGeneration: 1,
        );
        final next = BridgeClientSession(
          connection: pair2.client,
          sessionGeneration: 2,
        );
        try {
          await h.mount(session: first);
          await h.stageAudio();
          final old = h.drafts;
          final panel = t.state(find.byType(NotificationAudioPanel));
          final receipt = h.port.holdSave();
          await h.save();
          await t.pumpWidget(h.app(session: next));
          await _frames(t);
          final fresh = h.drafts;
          expect(fresh, isNot(same(old)));
          expect(panel.mounted, isFalse);
          expect(fresh.dirty, isFalse);
          expect(fresh.saving, isFalse);
          expect(h.port.stops, greaterThanOrEqualTo(1));
          h.port.accept(receipt);
          await _frames(t);
          _confirmedAudio(h);
          expect(fresh.dirty, isFalse);
          expect(fresh.failed, isFalse);
          expect(h.port.writes, hasLength(1));
          expect(h.notifications.writes, isEmpty);
          expect(h.notifications.reads, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await h.close();
          await t.runAsync(() async {
            await first.close();
            await next.close();
            await pair1.host.close();
            await pair2.host.close();
          });
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite audio removal and actual page unmount still stop and never autoack a retired panel closure',
      (t) async {
        for (final removeAudioOnly in [true, false]) {
          final h = _Harness(t, suite);
          try {
            await h.mount();
            await h.stageAudio();
            final drafts = h.drafts;
            final panel = t.state(find.byType(NotificationAudioPanel));
            final receipt = h.port.holdSave();
            await h.save();
            if (removeAudioOnly) {
              await t.pumpWidget(h.app(omitAudio: true));
            } else {
              await t.pumpWidget(const SizedBox.shrink());
            }
            await _frames(t);
            expect(panel.mounted, isFalse);
            expect(find.byType(NotificationAudioPanel), findsNothing);
            expect(h.port.stops, greaterThanOrEqualTo(1));
            expect(h.port.writes, hasLength(1));
            h.port.accept(receipt);
            await _frames(t);
            _confirmedAudio(h);
            expect(h.port.writes, hasLength(1));
            expect(h.notifications.writes, isEmpty);
            expect(h.notifications.reads, hasLength(1));
            if (removeAudioOnly) {
              expect(drafts.dirty, isTrue);
              expect(
                drafts.failed,
                isTrue,
                reason: 'Removing audio is real retirement, not a pure read reparent.',
              );
              expect(drafts.saving, isFalse);
              await act(
                t,
                find.byKey(const Key('notification-discard')),
                'pointer',
                '放弃更改',
              );
              await _frames(t, count: 2);
              expect(drafts.dirty, isFalse);
              expect(h.port.writes, hasLength(1));
            } else {
              expect(notificationLeaveGuards[h.module], isNull);
            }
            expect(t.takeException(), isNull);
          } finally {
            await h.close();
          }
        }
      },
      timeout: _timeout,
    );
  }
}
