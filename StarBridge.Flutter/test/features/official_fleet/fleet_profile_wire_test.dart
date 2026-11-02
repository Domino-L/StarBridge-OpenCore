import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_profile_identity_source.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show loadFonts, size;

void main() {
  setUpAll(loadFonts);
  const path = String.fromEnvironment('STARBRIDGE_FLEET_PROFILE_WIRE');
  final skip = path.isEmpty
      ? 'Requires the explicitly generated synthetic Native optional-profile fixture.'
      : false;
  test('actual Native optional transient read keeps old profile and accepts new identity time', () async {
    final host = await _Host.create(path);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    final loaded = module.projection.value;
    expect(loaded.profileReadState, OfficialFleetProfileReadState.available);
    expect(loaded.profileObservedAtUtc, isNotNull);
    expect(loaded.fleet?.profile?.rsiDescription, 'Explore & build');
    host.phase = 'transient';
    await module.refresh();
    expect(
      module.projection.value.availability,
      OfficialFleetAvailability.available,
    );
    expect(module.projection.value.fleet?.profile, same(loaded.fleet?.profile));
    expect(
      module.projection.value.profileObservedAtUtc,
      loaded.profileObservedAtUtc,
    );
    expect(module.projection.value.profileRetained, isTrue);
    expect(module.projection.value.profileRefreshFailed, isTrue);
    expect(module.projection.value.refreshFailed, isFalse);
    await module.refresh();
    expect(
      module.projection.value.profileObservedAtUtc,
      loaded.profileObservedAtUtc,
    );
    expect(
      module.projection.value.observedAtUtc,
      DateTime.parse(
        ((host.fixture['transient'] as Map)['payload'] as Map)['observedAtUtc']
            as String,
      ).toUtc(),
    );
  }, skip: skip);
  for (final phase in ['forbidden', 'invalid']) {
    test('Native optional $phase drops only the old profile', () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      host.phase = phase;
      await module.refresh();
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.available,
      );
      expect(module.projection.value.fleet?.profile, isNull);
      expect(module.projection.value.profileObservedAtUtc, isNull);
      expect(module.projection.value.fleet?.officialRankValue, 4);
    }, skip: skip);
  }
  test(
    'legacy missing profile metadata must not make null mean temporary failure',
    () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      host.legacy = true;
      await module.initialize();
      expect(module.projection.value.fleet?.profile, isNotNull);
      expect(module.projection.value.profileObservedAtUtc, isNull);
      host.phase = 'transient';
      await module.refresh();
      expect(module.projection.value.fleet?.profile, isNull);
    },
    skip: skip,
  );
  test(
    'a changed source descriptor cannot retain the old public profile',
    () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      host.phase = 'transient';
      host.sid = 'RENAMED';
      await module.refresh();
      expect(module.projection.value.fleet?.profile, isNull);
      expect(module.projection.value.profileObservedAtUtc, isNull);
    },
    skip: skip,
  );
  test(
    'a hard account generation change cannot restore the previous profile',
    () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      host.phase = 'transient';
      await host.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 2,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await module.refresh();
      expect(module.contextRevision, 1);
      expect(module.projection.value.fleet?.profile, isNull);
      expect(module.projection.value.profileObservedAtUtc, isNull);
    },
    skip: skip,
  );
  test(
    'a newly confirmed profile advances only its successful read time',
    () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      final original = module.projection.value.profileObservedAtUtc!;
      host.phase = 'transient';
      await module.refresh();
      host.phase = 'success';
      host.metadata = {
        'state': 'available',
        'observedAtUtc': original
            .add(const Duration(seconds: 1))
            .toIso8601String(),
      };
      await module.refresh();
      expect(
        module.projection.value.profileObservedAtUtc,
        original.add(const Duration(seconds: 1)),
      );
      expect(module.projection.value.profileRefreshFailed, isFalse);
    },
    skip: skip,
  );
  for (final metadata in <Map<String, Object?>>[
    {'state': 'available'},
    {'state': 'transientFailure', 'observedAtUtc': '2026-10-15T12:00:00Z'},
    {'state': 'not-supported'},
    {'state': 'invalid'},
  ]) {
    test('malformed optional metadata $metadata fails closed', () async {
      final host = await _Host.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      host.metadata = metadata;
      await module.refresh();
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.unavailable,
      );
      expect(module.projection.value.fleet, isNull);
    }, skip: skip);
  }
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [1280.0, 480.0]) {
      testWidgets(
        '$locale details stay live through optional failure at $width',
        (tester) async {
          size(tester, Size(width, 900));
          final contents = await tester.runAsync(
            () => File(path).readAsString(),
          );
          final host = _Host.fromFixture(
            jsonDecode(contents!) as Map<String, dynamic>,
          );
          final module = host.module();
          addTearDown(() async {
            module.dispose();
            await host.close();
          });
          await module.initialize();
          final readTime = module.projection.value.profileObservedAtUtc;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStringsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              theme: buildStarBridgeTheme(
                FutureRestraintStyle.resolve(AppearanceMode.dark),
                locale,
              ),
              home: Scaffold(body: OfficialFleetPage(module: module)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('official-fleet-open-details')),
          );
          await tester.pumpAndSettle();
          final dialog = find.byKey(const Key('official-fleet-details-dialog'));
          final element = tester.element(dialog);
          final scroll = find.descendant(
            of: find.byKey(const Key('official-fleet-profile-scroll')),
            matching: find.byType(Scrollable),
          );
          final position = tester.state<ScrollableState>(scroll.first).position;
          expect(position.axis, Axis.vertical);
          if (position.maxScrollExtent > 0) {
            position.jumpTo(position.maxScrollExtent.clamp(0, 80));
          }
          await tester.pumpAndSettle();
          final pixels = position.pixels;
          host.phase = 'transient';
          await module.refresh();
          await tester.pumpAndSettle();
          expect(identical(tester.element(dialog), element), isTrue);
          expect(position.pixels, closeTo(pixels, 1));
          final source = tester.widget<OfficialFleetProfileIdentitySource>(
            find.byType(OfficialFleetProfileIdentitySource),
          );
          expect(source.profileObservedAtUtc, readTime);
          final prefix = AppStrings.resolve(locale)
              .text('officialFleet.profile.syncFailedAt')
              .split('{time}')
              .first;
          expect(
            find.descendant(of: dialog, matching: find.textContaining(prefix)),
            findsOneWidget,
          );
          expect(find.text('Explore & build'), findsOneWidget);
          expect(tester.takeException(), isNull);
          host.phase = 'forbidden';
          await module.refresh();
          await tester.pumpAndSettle();
          expect(find.text('Explore & build'), findsNothing);
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(
                AppStrings.resolve(locale)
                    .text('officialFleet.profile.readFailed'),
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('official-fleet-details-close')),
          );
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        },
        skip: path.isEmpty,
      );
    }
  }
}

final class _Host {
  _Host(this.fixture, this.pair, this.session) {
    incoming = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'account.getCurrent') {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              accountContext: owner,
              status: 'ok',
              payload: const {'schemaVersion': 1, 'state': 'signedIn'},
            ),
          ),
        );
        return;
      }
      final captured = BridgeEnvelope.fromJson(
        (fixture[phase] as Map).cast<String, Object?>(),
      );
      final payload = <String, Object?>{...captured.payload};
      if (legacy) payload.remove('profileRead');
      if (metadata != null) payload['profileRead'] = metadata;
      if (sid != null) {
        payload['fleet'] = {
          ...(payload['fleet'] as Map).cast<String, Object?>(),
          'sid': sid,
        };
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope.fromJson({
            ...captured.toJson(),
            'correlationId': request.correlationId,
            'sessionGeneration': request.sessionGeneration,
            'payload': payload,
          }),
        ),
      );
    });
  }
  static Future<_Host> create(String path) async {
    final fixture =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    return fromFixture(fixture);
  }

  static _Host fromFixture(Map<String, dynamic> fixture) {
    final success = BridgeEnvelope.fromJson(
      (fixture['success'] as Map).cast<String, Object?>(),
    );
    final pair = InMemoryBridgeConnection.createPair();
    return _Host(
      fixture,
      pair,
      BridgeClientSession(
        connection: pair.client,
        sessionGeneration: success.sessionGeneration,
      ),
    );
  }

  OfficialFleetModule module() => createOfficialFleetModule(
    BridgeOfficialFleetAdapter(session),
    UnavailableOfficialFleetOverviewAdapter(),
    UnavailableOfficialFleetMembersAdapter(),
    UnavailableOfficialFleetShipsAdapter(),
  );
  final Map<String, dynamic> fixture;
  final InMemoryBridgePair pair;
  final BridgeClientSession session;
  BridgeAccountContext get owner => BridgeEnvelope.fromJson(
    (fixture['success'] as Map).cast<String, Object?>(),
  ).accountContext!;
  late final StreamSubscription<BridgeEnvelope> incoming;
  String phase = 'success';
  bool legacy = false;
  String? sid;
  Map<String, Object?>? metadata;
  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
