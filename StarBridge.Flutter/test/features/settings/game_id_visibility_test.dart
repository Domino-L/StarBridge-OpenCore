import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_controller.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_setting.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class Fixture {
  Fixture() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(const ['gameIdVisibility.settings']);
    subscription = connection.incoming.listen(
      (request) => unawaited(reply(request)),
    );
  }
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final writes = <BridgeEnvelope>[];
  String subject = 'fixture';
  bool fail = false;
  Completer<void>? readGate;
  final readStarted = Completer<void>();
  Map<String, Object?> snapshot = {
    'schemaVersion': 1,
    'revision': 0,
    'locations': 15,
    'canConfigure': true,
    'identityStamp': 'a' * 64,
  };
  Future<void> reply(BridgeEnvelope request) async {
    final readSnapshot = Map<String, Object?>.of(snapshot);
    if (request.name == 'gameIdVisibility.read' && readGate != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      await readGate!.future;
    }
    if (request.name == 'gameIdVisibility.save') {
      writes.add(request);
      if (!fail) {
        snapshot = {
          ...snapshot,
          'revision': (snapshot['revision'] as int) + 1,
          'locations': request.payload['locations'],
        };
      }
    }
    final failed = fail && request.name == 'gameIdVisibility.save';
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: BridgeAccountContext(
          environment: 'test',
          authority: 'scm',
          subject: subject,
        ),
        status: failed ? 'error' : 'ok',
        error: failed
            ? const BridgeErrorBody(
                code: 'gameId.conflict',
                message: 'fixture',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedIn'}
            : request.name.endsWith('.read')
            ? readSnapshot
            : snapshot,
      ),
    );
  }

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}

Future<void> ready(GameIdVisibilityController c) async {
  for (var i = 0; i < 100 && (c.busy || c.snapshot == null); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(c.snapshot, isNotNull, reason: c.error);
}

void main() {
  test(
    'background refresh allows save and cannot overwrite its receipt',
    () async {
      final h = Fixture();
      final c = GameIdVisibilityController(h.session);
      addTearDown(() async {
        c.dispose();
        await h.close();
      });
      await ready(c);
      h.readGate = Completer<void>();
      final refresh = c.refresh();
      await h.readStarted.future;
      expect(c.canEdit, isTrue);
      await c.change(1, false);
      expect(c.locations, 14);
      h.readGate!.complete();
      await refresh;
      expect(c.locations, 14);
      expect(h.writes, hasLength(1));
    },
  );
  test('four switches save only masks with confirmed revision', () async {
    final h = Fixture();
    final c = GameIdVisibilityController(h.session);
    await ready(c);
    for (final bit in [1, 2, 4, 8]) {
      await c.change(bit, false);
    }
    expect(c.locations, 0);
    expect(h.writes.length, 4);
    expect(
      h.writes.last.payload.keys,
      unorderedEquals([
        'schemaVersion',
        'expectedRevision',
        'identityStamp',
        'locations',
      ]),
    );
    c.dispose();
    await h.close();
  });
  test(
    'uncertain save refreshes without replay and account swap cannot write',
    () async {
      final h = Fixture();
      final c = GameIdVisibilityController(h.session);
      await ready(c);
      h.fail = true;
      await c.change(1, false);
      await ready(c);
      expect(h.writes.length, 1);
      expect(c.locations, 15);
      h.subject = 'other';
      await c.change(2, false);
      await ready(c);
      expect(h.writes.length, 1);
      c.dispose();
      await h.close();
    },
  );
  test('no alternate name keeps all fields visible and invalid states are rejected', () async {
    final h = Fixture();
    h.snapshot['canConfigure'] = false;
    final c = GameIdVisibilityController(h.session);
    await ready(c);
    expect(c.canEdit, isFalse);
    await c.change(1, false);
    expect(h.writes, isEmpty);
    for (final mask in [-1, 16]) {
      expect(
        () => GameIdVisibilityController.validate({
          ...h.snapshot,
          'locations': mask,
        }),
        throwsFormatException,
      );
    }
    c.dispose();
    await h.close();
  });
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ]) {
    testWidgets('compact real game ID switches $locale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Fixture();
      final tokens = StyleRegistry()
          .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
          .tokens;
      await tester.pumpWidget(
        MaterialApp(
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
            body: SingleChildScrollView(
              child: GameIdVisibilitySetting(session: h.session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNWidgets(4));
      h.readGate = Completer<void>();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((tile) => tile.onChanged != null),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('game-id-friends')));
      await tester.pumpAndSettle();
      expect(h.writes.single.payload['locations'], 11);
      h.readGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('game-id-friends')))
            .value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
    });
  }
}
