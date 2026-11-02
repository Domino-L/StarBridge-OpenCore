import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'social_window_test.dart' as fixtures;

class HealthyPort extends fixtures.Port
    implements DirectMessageActivityPort, DirectMessageActivityHealthPort {
  final activity = StreamController<void>.broadcast(sync: true);
  bool healthy = true;
  int directories = 0, histories = 0;
  @override
  Stream<void> get changes => activity.stream;
  @override
  bool get activityHealthy => healthy;
  @override
  Future<List<Conversation>> directory() {
    directories++;
    return super.directory();
  }

  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) {
    histories++;
    return super.history(ref, before: before, after: after);
  }

  @override
  Future<void> close() async {
    await activity.close();
    await super.close();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final mode in ['healthy', 'drop-control', 'health-transition']) {
    testWidgets('$mode primary health reaches the detached messages viewport '
        'without stale suppression or periodic healthy reads', (t) async {
      const primary = MethodChannel('starbridge/messages-primary');
      const surface = MethodChannel('starbridge/messages-surface');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final port = HealthyPort(), inbox = NotificationInboxController(null);
      final healthFrames = <Map>[];
      var snapshotFrames = 0;
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
      );
      messenger.setMockMethodCallHandler(primary, (call) async {
        if (call.method == 'show') return true;
        if (call.method == 'activityHealth') {
          healthFrames.add(Map.of(call.arguments as Map));
          if (mode == 'drop-control') return null;
        }
        if (call.method == 'snapshot') snapshotFrames++;
        return fixtures.native(surface.name, call.method, call.arguments);
      });
      messenger.setMockMethodCallHandler(surface, (call) async {
        if (call.method == 'ready') return binding.snapshot;
        if (call.method == 'rpc') {
          return fixtures.native(primary.name, 'rpc', call.arguments);
        }
        return true;
      });
      var cleaned = false;
      Future<void> cleanup() async {
        if (cleaned) return;
        cleaned = true;
        await t.pumpWidget(const SizedBox());
        binding.dispose();
        inbox.dispose();
        await t.pump();
        messenger.setMockMethodCallHandler(primary, null);
        messenger.setMockMethodCallHandler(surface, null);
      }

      addTearDown(cleanup);
      await binding.open(target: fixtures.row);
      await t.pumpWidget(const SocialWindowApp(kind: 'messages'));
      await t.pumpAndSettle();
      await fixtures.native(primary.name, 'viewportActive', {
        'opening': binding.snapshot['opening'],
        'active': true,
      });
      await fixtures.native(surface.name, 'viewportActive', true);
      await t.pumpAndSettle();
      final directories = port.directories, histories = port.histories;
      int? quietHistory;
      for (var i = 0; i < 60; i++) {
        if (mode == 'health-transition' && i == 20) port.healthy = false;
        if (mode == 'health-transition' && i == 40) port.healthy = true;
        await t.pump(const Duration(seconds: 1));
        await t.pump();
        if (mode == 'health-transition' && i == 45) {
          quietHistory = port.histories;
        }
      }
      debugPrint(
        'WINDOW_HEALTH_COUNTS mode=$mode directory=${port.directories - directories} history=${port.histories - histories} healthFrames=${healthFrames.length} virtualSeconds=60',
      );
      await cleanup();
      expect(healthFrames.length, inInclusiveRange(10, 31));
      expect(
        healthFrames.every(
          (p) =>
              p.length == 6 &&
              p.keys.toSet().containsAll({
                'opening',
                'scope',
                'revision',
                'healthy',
                'leaseMilliseconds',
                'sentAtUtcMilliseconds',
              }),
        ),
        true,
      );
      expect(
        snapshotFrames,
        0,
        reason: 'Health renewal must not masquerade as content or preference updates.',
      );
      if (mode == 'healthy') {
        expect(
          port.directories - directories,
          lessThanOrEqualTo(1),
          reason: 'The child must receive primary health, catch up once, and stop fallback.',
        );
        expect(port.histories - histories, lessThanOrEqualTo(1));
      } else {
        expect(port.directories - directories, inInclusiveRange(2, 12));
        expect(port.histories - histories, port.directories - directories);
        if (mode == 'health-transition') expect(port.histories, quietHistory);
      }
      expect(t.takeException(), isNull);
    });
  }
}
