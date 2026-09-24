import 'dart:async';

import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_activity.dart';

Map<String, Object?> data() => {
  'schemaVersion': 1,
  'revision': 'missing',
  'writable': true,
  'enabled': true,
  'scope': 2,
  'position': 3,
  'online': true,
  'offline': false,
  'startedGame': true,
  'stoppedGame': false,
  'backgroundOnly': true,
  'reduceInGame': true,
};
void main() {
  test('test notification failure does not lock valid settings', () async {
    var reads = 0;
    final c = PlayerActivityController((name, payload) async {
      if (name == 'playerActivity.test') throw StateError('test unavailable');
      reads++;
      return data();
    }, generation: () => 1);
    addTearDown(c.dispose);
    expect(await c.refresh(), isTrue);
    expect(await c.test(), isFalse);
    expect(c.canEdit, isTrue);
    expect(c.failed, isFalse);
    expect(c.testResult, 'unavailable');
    expect(reads, 1);
  });
  test('transient read recovers without manual reload', () async {
    var reads = 0;
    final c = PlayerActivityController((name, payload) async {
      expect(name, 'playerActivity.read');
      if (++reads == 1) {
        throw const BridgeTimeoutException('playerActivity.read');
      }
      return data();
    }, generation: () => 1);
    addTearDown(c.dispose);
    expect(await c.refresh(), isTrue);
    expect(reads, 2);
    expect(c.canEdit, isTrue);
    expect(c.failed, isFalse);
  });
  test('read recovery is bounded and does not retry invalid data', () async {
    var reads = 0;
    final c = PlayerActivityController((name, payload) async {
      reads++;
      throw const BridgeTimeoutException('playerActivity.read');
    }, generation: () => 1);
    addTearDown(c.dispose);
    expect(await c.refresh(), isFalse);
    expect(reads, 3);
    expect(c.failed, isTrue);
    var malformedReads = 0;
    final malformed = PlayerActivityController((name, payload) async {
      malformedReads++;
      return {};
    }, generation: () => 1);
    addTearDown(malformed.dispose);
    expect(await malformed.refresh(), isFalse);
    expect(malformedReads, 1);
  });
  test(
    'generation change stops read recovery and rejects old test state',
    () async {
      var generation = 1, calls = 0;
      final c = PlayerActivityController((name, payload) async {
        calls++;
        generation++;
        throw const BridgeTimeoutException('playerActivity.read');
      }, generation: () => generation);
      addTearDown(c.dispose);
      expect(await c.refresh(), isFalse);
      expect(calls, 1);
      expect(c.canEdit, isFalse);
    },
  );
  test(
    'device player activity traverses the real bridge without an account',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      session.acceptHostCapabilities([
        'playerActivity.read',
        'playerActivity.save',
        'playerActivity.test',
      ]);
      final requests = <BridgeEnvelope>[];
      final sub = pair.host.incoming.listen((request) {
        requests.add(request);
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 3,
            status: 'ok',
            payload: request.name.endsWith('test')
                ? {'schemaVersion': 1, 'submitted': true, 'reason': 'submitted'}
                : data(),
          ),
        );
      });
      final c = PlayerActivityController.bridge(session);
      addTearDown(() async {
        c.dispose();
        await sub.cancel();
        await session.close();
        await pair.host.close();
      });
      expect(await c.refresh(), isTrue);
      expect(await c.save(c.current!.settings, 0), isTrue);
      expect(await c.test(), isTrue);
      expect(requests.map((r) => r.name), [
        'playerActivity.read',
        'playerActivity.save',
        'playerActivity.test',
      ]);
      expect(requests.every((r) => r.accountContext == null), isTrue);
    },
  );
  test('strict parsing and original community scope', () {
    final v = PlayerActivityValue.parse(data());
    expect(v.position, 3);
    expect(v.settings.includeOfficialFleet, true);
    expect(v.settings.includeFriends, false);
    for (final invalid in [
      {...data(), 'extra': true},
      {...data(), 'position': 4},
      {...data(), 'scope': 8},
      {...data(), 'revision': 'bad'},
      {...data(), 'enabled': 1},
    ]) {
      expect(() => PlayerActivityValue.parse(invalid), throwsFormatException);
    }
  });
  test('no default writes; exact narrow save and server readback', () async {
    final calls = <String>[];
    Map<String, Object?>? sent;
    final c = PlayerActivityController((n, p) async {
      calls.add(n);
      if (n.endsWith('save')) {
        sent = p;
        return {...data(), 'position': 1};
      }
      return data();
    }, generation: () => 1);
    addTearDown(c.dispose);
    await c.refresh();
    expect(calls, ['playerActivity.read']);
    await c.save(c.current!.settings.copyWith(includeFriends: true), 0);
    expect(sent!['scope'], 6);
    expect(sent!['expectedRevision'], 'missing');
    expect(sent!.length, 11);
    expect(c.current!.position, 1);
  });
  test('conflict locks writes until explicit read, no retry', () async {
    var writes = 0;
    final c = PlayerActivityController((n, p) async {
      if (n.endsWith('save')) {
        writes++;
        throw StateError('private');
      }
      return data();
    }, generation: () => 1);
    addTearDown(c.dispose);
    await c.refresh();
    await c.save(c.current!.settings, 0);
    expect(c.failed, true);
    expect(c.canEdit, false);
    await c.save(c.current!.settings, 1);
    expect(writes, 1);
    await c.refresh();
    expect(c.canEdit, true);
  });
  test('late response after generation change is discarded', () async {
    var generation = 1;
    final pending = Completer<Map<String, Object?>>();
    final c = PlayerActivityController(
      (n, p) => pending.future,
      generation: () => generation,
    );
    addTearDown(c.dispose);
    final load = c.refresh();
    generation++;
    pending.complete(data());
    await load;
    expect(c.current, isNull);
    expect(c.canEdit, false);
  });
  test('disposed controller ignores late responses', () async {
    final pending = Completer<Map<String, Object?>>();
    final c = PlayerActivityController(
      (n, p) => pending.future,
      generation: () => 1,
    );
    final load = c.refresh();
    c.dispose();
    pending.complete(data());
    expect(await load, false);
  });
  test('test respects real submission result', () async {
    final c = PlayerActivityController(
      (n, p) async => n.endsWith('test')
          ? {'schemaVersion': 1, 'submitted': false, 'reason': 'quietTime'}
          : data(),
      generation: () => 1,
    );
    addTearDown(c.dispose);
    await c.refresh();
    expect(await c.test(), true);
    expect(c.testResult, 'suppressed');
  });
  testWidgets(
    'controls wait for read and correctly label community membership',
    (t) async {
      final pending = Completer<Map<String, Object?>>();
      final c = PlayerActivityController(
        (n, p) => pending.future,
        generation: () => 1,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(app(c));
      await t.pump();
      expect(find.byType(PlayerActivityNotificationPanel), findsNothing);
      pending.complete(data());
      await t.pumpAndSettle();
      expect(find.text('社区组织成员'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('failed read has retry and no fake settings', (t) async {
    final c = PlayerActivityController(
      (n, p) async => throw StateError('private error'),
      generation: () => 1,
    );
    addTearDown(c.dispose);
    await t.pumpWidget(app(c));
    await t.pumpAndSettle();
    expect(find.text('重新读取'), findsOneWidget);
    expect(find.byType(PlayerActivityNotificationPanel), findsNothing);
    expect(find.textContaining('private'), findsNothing);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('narrow player settings $locale $mode', (t) async {
        t.view.physicalSize = const Size(390, 700);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = PlayerActivityController(
          (n, p) async => data(),
          generation: () => 1,
        );
        addTearDown(c.dispose);
        await t.pumpWidget(app(c, locale: locale, mode: mode));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(c.canEdit, true);
      });
    }
  }
}

Widget app(
  PlayerActivityController c, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(
      body: Dialog(
        child: SizedBox(
          width: 760,
          child: PlayerActivityConnectedPanel(controller: c),
        ),
      ),
    ),
  );
}
