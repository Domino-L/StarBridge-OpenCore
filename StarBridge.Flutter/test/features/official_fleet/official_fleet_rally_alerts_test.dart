import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/official_fleet_rally_banner.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally_views.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../settings/desktop_notification_test.dart' show DesktopFake;

final _now = DateTime.utc(2026, 10, 24, 12);
final _id = 'a' * 32;

final class _Port implements OfficialFleetRallyPort {
  final answers = <OfficialFleetRallyAnswer>[];
  bool failEligibility = false;
  OfficialFleetRallyAnswer? answer;
  @override
  bool get available => true;
  OfficialFleetRallySnapshot get _state => OfficialFleetRallySnapshot(
    onlineCount: 5,
    rally: OfficialFleetRally(
      rallyId: _id,
      text: '新巴贝奇集合',
      minutes: 30,
      startedAt: _now,
      expiresAt: _now.add(const Duration(minutes: 30)),
      state: 'active',
      coming: 1,
      cannot: 0,
      pending: 4,
      answer: answer,
    ),
  );
  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) async => _state;
  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async =>
      failEligibility
      ? throw const OfficialFleetRallyFailure('unavailable')
      : const OfficialFleetRallyEligibility(
          canStart: false,
          onlineCount: 5,
          remainingThisHour: 0,
        );
  @override
  Future<OfficialFleetRallySnapshot> start(
    String sourceRef, {
    required String operationId,
    required String text,
    required int minutes,
  }) => throw UnimplementedError();
  @override
  Future<OfficialFleetRallySnapshot> respond(
    String sourceRef,
    String rallyId,
    OfficialFleetRallyAnswer answer,
  ) async {
    answers.add(answer);
    this.answer = answer;
    return _state;
  }

  @override
  Future<OfficialFleetRallySnapshot> end(String sourceRef, String rallyId) =>
      throw UnimplementedError();
}

Future<OfficialFleetRallyController> _bound(
  _Port port, {
  Stream<OfficialFleetRallyHotkey>? hotkeys,
  bool Function()? online,
}) async {
  final controller = OfficialFleetRallyController(
    port,
    countedOnline: online,
    now: () => _now.add(const Duration(minutes: 2)),
    interval: const Duration(days: 1),
    hotkeys: hotkeys,
  );
  controller.bind('officialFleet:7', fleetName: 'Test Squadron');
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return controller;
}

void main() {
  test('a hotkey answers only the rally this member is asked about', () async {
    final port = _Port();
    final keys = StreamController<OfficialFleetRallyHotkey>();
    final member = await _bound(port, hotkeys: keys.stream);
    expect(
      await member.respondFromHotkey('b' * 32, OfficialFleetRallyAnswer.cannot),
      'conflict',
      reason: 'a stale or foreign rally id is ignored',
    );
    expect(port.answers, isEmpty);
    keys.add((rallyId: _id, answer: OfficialFleetRallyAnswer.coming));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(port.answers, [OfficialFleetRallyAnswer.coming]);
    expect(member.prompt, isNull);
    expect(
      await member.respondFromHotkey(_id, OfficialFleetRallyAnswer.cannot),
      'conflict',
      reason: 'once answered the prompt is gone',
    );
    member.dispose();
    await keys.close();
  });

  test('Host hotkey events are validated before reaching the rally', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final seen = <OfficialFleetRallyHotkey>[];
    var sequence = 0;
    final sub = officialFleetRallyHotkeys(session).listen(seen.add);
    Future<void> send(
      Map<String, Object?> payload, [
      String name = 'officialFleet.rallyHotkey',
    ]) => pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: name,
        sessionGeneration: 1,
        sequence: ++sequence,
        payload: payload,
      ),
    );
    await send({'schemaVersion': 1, 'rallyId': _id, 'answer': 'cannot'});
    await send({'schemaVersion': 1, 'rallyId': 'nothex', 'answer': 'coming'});
    await send({'schemaVersion': 1, 'rallyId': _id, 'answer': 'maybe'});
    await send({'schemaVersion': 2, 'rallyId': _id, 'answer': 'coming'});
    await send({
      'schemaVersion': 1,
      'rallyId': _id,
      'answer': 'coming',
    }, 'other');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen, [(rallyId: _id, answer: OfficialFleetRallyAnswer.cannot)]);
    await sub.cancel();
    await session.close();
  });

  test(
    'a rally first read while invisible stays quiet after coming back',
    () async {
      var online = false;
      final member = await _bound(_Port(), online: () => online);
      expect(member.prompt, isNotNull, reason: 'the page may still show it');
      expect(member.alertPrompt, isNull);
      expect(member.takeAnnouncement(), isNull);
      online = true;
      await member.refresh();
      expect(member.alertPrompt, isNull, reason: 'no replay after coming back');
      expect(member.takeAnnouncement(), isNull);
      member.dispose();

      final visible = await _bound(_Port());
      expect(visible.alertPrompt, isNotNull);
      visible.dispose();
    },
  );

  test(
    'a quiet sighting sticks even when the eligibility read fails',
    () async {
      var online = false;
      final port = _Port()..failEligibility = true;
      final member = await _bound(port, online: () => online);
      port.failEligibility = false;
      online = true;
      await member.refresh(eligibility: true);
      expect(member.prompt, isNotNull);
      expect(member.alertPrompt, isNull, reason: 'first read while invisible');
      member.dispose();
    },
  );

  test(
    'settings that cannot be read stay unknown unless the Host lacks them',
    () {
      NotificationSettingsProjection of(NotificationSettingsSnapshot s) =>
          NotificationSettingsProjection.fromSnapshot(s);
      const disconnected = NotificationSettingsSnapshot.unavailable();
      expect(
        rallyAlertsDecision(of(disconnected), hostHasSettings: true),
        isNull,
      );
      expect(
        rallyAlertsDecision(of(disconnected), hostHasSettings: false),
        isTrue,
      );
      expect(
        rallyAlertsDecision(
          of(
            const NotificationSettingsSnapshot.unavailable(
              failure: NotificationSettingsFailure.readFailed,
            ),
          ),
          hostHasSettings: true,
        ),
        isNull,
      );
      expect(
        rallyAlertsDecision(
          const NotificationSettingsProjection.loading(),
          hostHasSettings: true,
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'unknown settings wait; the decision then shows or consumes once',
    (tester) async {
      for (final decided in [true, false]) {
        final member = (await tester.runAsync(() => _bound(_Port())))!;
        final desktop = DesktopFake();
        final known = ValueNotifier<bool?>(null);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              const Locale('zh', 'CN'),
            ),
            home: Scaffold(
              body: OfficialFleetRallyNotice(
                key: ValueKey(decided),
                controller: member,
                desktop: desktop,
                alertsEnabled: () => known.value,
                alertsChanged: known,
              ),
            ),
          ),
        );
        await tester.runAsync(member.refresh);
        await tester.pumpAndSettle();
        expect(desktop.shown, isEmpty, reason: 'settings not known yet');
        known.value = decided;
        await tester.pumpAndSettle();
        expect(desktop.shown.length, decided ? 1 : 0);
        known.value = !decided;
        await tester.pumpAndSettle();
        expect(desktop.shown.length, decided ? 1 : 0, reason: 'never twice');
        member.dispose();
      }
    },
  );

  testWidgets('with rally alerts off the Windows notification is not shown', (
    tester,
  ) async {
    for (final on in [false, true]) {
      final member = (await tester.runAsync(() => _bound(_Port())))!;
      final desktop = DesktopFake();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: OfficialFleetRallyNotice(
              key: ValueKey(on),
              controller: member,
              desktop: desktop,
              alertsEnabled: () => on,
            ),
          ),
        ),
      );
      await tester.runAsync(member.refresh);
      await tester.pumpAndSettle();
      expect(desktop.shown.length, on ? 1 : 0);
      member.dispose();
    }
  });
}
