import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_sources_connected_panel.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart'
    as history;
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';

import '../../features/settings/player_activity_test.dart' as player;
import '../../features/settings/notification_audio_test.dart' show AudioFake;
import '../../features/settings/notification_sources_test.dart' as sources;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bc_test.dart' show page;

class ReadGate<T> {
  ReadGate(this.value);
  final T value;
  int reads = 0;
  Completer<T> pending = Completer<T>();
  Future<T> read() {
    reads++;
    return pending.future;
  }

  void finish({bool fail = false}) {
    if (pending.isCompleted) return;
    if (fail) {
      pending.completeError(StateError('synthetic read failure'));
    } else {
      pending.complete(value);
    }
  }

  void renew() {
    pending = Completer<T>();
  }
}

class HeldAudio extends AudioFake {
  final gate = ReadGate(const AudioPreferences(0, true, .65, true));
  @override
  Future<AudioPreferences> read() => gate.read();
}

class HeldPlay implements ContinuousPlayPort {
  final gate = ReadGate(
    const ContinuousPlayValue(
      enabled: true,
      firstMinutes: 120,
      repeatMinutes: 60,
      revision: 0,
    ),
  );
  int writes = 0;
  @override
  Future<ContinuousPlayValue> read() => gate.read();
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue value) async {
    writes++;
    return value;
  }
}

class HeldSources extends sources.Fake {
  late final gate = ReadGate(value);
  @override
  Future<NotificationSourcesValue> read() => gate.read();
}

class HeldHistory implements history.LocalHistoryPort {
  final gate = ReadGate(page('synthetic history'));
  @override
  Future<history.LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) => gate.read();
}

class Fixture {
  Fixture(String kind) {
    switch (kind) {
      case 'player':
        final gate = ReadGate(player.data());
        final c = PlayerActivityController(
          (_, _) => gate.read(),
          generation: () => 1,
        );
        child = PlayerActivityConnectedPanel(controller: c, showClose: false);
        finish = gate.finish;
        renew = gate.renew;
        reads = () => gate.reads;
        dispose = c.dispose;
        reload = 'player-activity-reload';
      case 'audio':
        final port = HeldAudio(), c = NotificationAudioController(port);
        child = NotificationAudioPanel(controller: c);
        finish = port.gate.finish;
        renew = port.gate.renew;
        reads = () => port.gate.reads;
        dispose = c.dispose;
        reload = 'audio-retry';
      case 'play':
        final port = HeldPlay(), c = ContinuousPlayController(port);
        child = ContinuousPlayConnectedPanel(controller: c);
        finish = port.gate.finish;
        renew = port.gate.renew;
        reads = () => port.gate.reads;
        dispose = c.dispose;
        reload = 'continuous-play-reload';
      case 'sources':
        final port = HeldSources();
        child = NotificationSourcesConnectedPanel(port: port);
        finish = port.gate.finish;
        renew = port.gate.renew;
        reads = () => port.gate.reads;
        dispose = port.dispose;
        reload = 'notification-sources-reload';
      case 'history':
        final port = HeldHistory(), c = history.LocalHistoryController(port);
        child = LocalEventHistoryDialog(controller: c);
        finish = port.gate.finish;
        renew = port.gate.renew;
        reads = () => port.gate.reads;
        dispose = c.dispose;
        reload = 'history-refresh';
      default:
        throw ArgumentError(kind);
    }
  }
  late final Widget child;
  late final void Function({bool fail}) finish;
  late final VoidCallback renew, dispose;
  late final int Function() reads;
  late final String reload;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['player', 'audio', 'play', 'sources', 'history']) {
      testWidgets('$suite $kind initial keyboard read decoration is static', (
        t,
      ) async {
        final fixture = Fixture(kind);
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
          builder: (_) =>
              Dialog(child: SizedBox(width: 700, child: fixture.child)),
        );
        try {
          await t.pump();
          await t.pump();
          expect(fixture.reads(), 1);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame).first))
                .reduceMotion,
            true,
          );
          await t.pumpAndSettle();
          expect(t.binding.hasScheduledFrame, false);
        } finally {
          fixture.finish();
          await t.pump();
          await t.pumpAndSettle();
          Navigator.of(caller).pop();
          await t.pumpAndSettle();
          await pending;
          await t.pumpWidget(const SizedBox());
          fixture.dispose();
        }
      });
    }
  }
}
