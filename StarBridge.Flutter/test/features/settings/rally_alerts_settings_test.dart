import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

/// A Host that may or may not know the rally switch.
class _Host {
  _Host({required this.rally});
  final bool rally;
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 3,
  );
  late final adapter = BridgeNotificationSettingsAdapter(session);
  late final module = createNotificationSettingsModule(adapter);
  late StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  late Map<String, Object?> value = {
    'schemaVersion': 1,
    'revision': 0,
    'inAppEnabled': true,
    'windowsEnabled': true,
    'position': 'topRight',
    'preview': 'sourceOnly',
    if (rally) 'rallyAlerts': true,
  };
  Future<void> start() async {
    session.acceptHostCapabilities([
      'notificationSettings.read',
      'notificationSettings.save',
    ]);
    subscription = pair.host.incoming.listen((r) {
      requests.add(r);
      if (r.name == 'notificationSettings.save') {
        value = {
          ...value,
          'revision': (value['revision']! as int) + 1,
          if (r.payload.containsKey('rallyAlerts'))
            'rallyAlerts': r.payload['rallyAlerts'],
        };
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            correlationId: r.correlationId,
            sessionGeneration: 3,
            status: 'ok',
            payload: value,
          ),
        ),
      );
    });
    await module.refresh();
  }

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test(
    'the rally switch round trips; an older Host never receives it',
    () async {
      final old = _Host(rally: false);
      await old.start();
      final before = old.module.projection.value.settings!;
      expect(before.rallyAlertsAvailable, isFalse);
      expect(before.channels.rallyAlertsEnabled, isTrue, reason: 'default on');
      await old.module.save(before);
      expect(old.requests.last.payload.containsKey('rallyAlerts'), isFalse);
      await old.close();

      final host = _Host(rally: true);
      await host.start();
      final value = host.module.projection.value.settings!;
      expect(value.rallyAlertsAvailable, isTrue);
      expect(value.channels.rallyAlertsEnabled, isTrue);
      expect(
        await host.module.save(
          value.copyWith(
            channels: value.channels.copyWith(rallyAlertsEnabled: false),
          ),
        ),
        isTrue,
      );
      expect(host.requests.last.payload['rallyAlerts'], false);
      expect(
        host.module.projection.value.settings!.channels.rallyAlertsEnabled,
        isFalse,
      );
      host.value['rallyAlerts'] = 'yes';
      expect((await host.adapter.read()).settings, isNull, reason: 'malformed');
      await host.close();
    },
  );

  testWidgets('the switch and the preview button follow Host support', (
    tester,
  ) async {
    size(tester, const Size(1200, 900));
    final host = (await tester.runAsync(() async {
      final h = _Host(rally: true);
      await h.start();
      return h;
    }))!;
    var previews = 0;
    Future<void> show({bool preview = true, bool on = true}) async {
      final settings = host.module.projection.value.settings!;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: settings.copyWith(
                channels: settings.channels.copyWith(rallyAlertsEnabled: on),
              ),
              enabled: true,
              showSound: false,
              onSave: (_) async => true,
              onPreviewRally: preview ? () async => previews++ : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.byKey(const Key('notification-channel-rally')), findsOneWidget);
    expect(find.text('主舰队召集提醒'), findsOneWidget);
    expect(find.text('试听召集提醒'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is StarBridgeTooltip && w.message == '播放一次召集提示音和提醒，不会真的发起召集',
      ),
      findsOneWidget,
    );
    // Inside the rally row, under its description: not at the panel's far end.
    final title = tester.getRect(find.text('主舰队召集提醒'));
    final button = tester.getRect(
      find.byKey(const Key('notification-rally-preview')),
    );
    expect(button.left, closeTo(title.left, 24));
    expect(button.top, greaterThan(title.bottom));
    await tester.tap(find.byKey(const Key('notification-rally-preview')));
    await tester.pump();
    expect(previews, 1);

    await show(on: false);
    await tester.tap(
      find.byKey(const Key('notification-rally-preview')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(previews, 1, reason: 'no sample while the switch is off');

    await show(preview: false);
    expect(find.byKey(const Key('notification-rally-preview')), findsNothing);
    await tester.runAsync(host.close);
  });
}
