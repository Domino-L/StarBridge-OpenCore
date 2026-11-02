import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_offline_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/offline_personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../hangar/bridge_local_hangar_test.dart' show LocalConnection;
import '../onboarding/connection_mode_test.dart' show ModePort, modeFact;
import '../../app/tray_quick_panel_test.dart' show app;

class ProfileConnection extends LocalConnection {
  Object schemaVersion = 1;
  bool missing = false;
  Map<String, Object?>? remote;
  Completer<void>? held;
  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.name != 'onboarding.mode.profile' &&
        !(request.name == 'account.offlineData.read' &&
            request.payload['kind'] == 'profile')) {
      return super.send(request);
    }
    requests.add(request);
    if (held != null) await held!.future;
    stream.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: 7,
        status: 'ok',
        payload: {
          'schemaVersion': schemaVersion,
          if (remote != null) 'remote': remote,
          'revision': missing ? 0 : 1,
          'savedAt': missing ? null : '2026-10-14T12:00:00Z',
          'content': missing
              ? null
              : {
                  'callSign': 'Synthetic Pilot',
                  'introduction': 'Retained introduction',
                  'avatarStyle': 0,
                  'wallpaperId': 'none',
                  'modules': [],
                  'favoriteShipIds': [],
                },
        },
      ),
    );
  }
}

void main() {
  late ProfileConnection connection;
  late BridgeClientSession session;
  late ModePort modes;
  late ConnectionModeController mode;
  late BridgeOfflinePersonalProfile port;
  setUp(() {
    connection = ProfileConnection();
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    modes = ModePort()
      ..current = ConnectionModeSnapshot(
        scope: 7,
        revision: 22,
        state: ConnectionModeState.offline,
        offlineAccount: OfflineAccountDisplay(
          'Synthetic Pilot',
          DateTime.utc(2026, 10, 14),
        ),
      );
    mode = ConnectionModeController(modes);
  });
  tearDown(() async {
    mode.dispose();
    await modes.events.close();
    await session.close();
  });

  test(
    'offline profile requires integer schema before any derived inventory read',
    () async {
      await mode.refresh();
      connection.schemaVersion = 1.0;
      port = BridgeOfflinePersonalProfile(session, mode);
      expect(
        (await port.read()).availability,
        PersonalProfileAvailability.unavailable,
      );
      expect(connection.requests, hasLength(1));
      await port.close();
    },
  );
  test('network retained profile uses read-only lease and rejects a retired selection', () async {
    var current = true;
    port = BridgeOfflinePersonalProfile.retained(
      session,
      '0123456789abcdef0123456789abcdef',
      isCurrent: () => current,
    );
    final profile = await port.read();
    expect(profile.availability, PersonalProfileAvailability.available);
    expect(profile.callSign, 'Synthetic Pilot');
    expect(profile.allowEditing, isFalse);
    expect(
      connection.requests.every(
        (r) => r.name == 'account.offlineData.read' && r.accountContext == null,
      ),
      isTrue,
    );
    current = false;
    final count = connection.requests.length;
    expect(
      (await port.read()).availability,
      PersonalProfileAvailability.unavailable,
    );
    expect(connection.requests.length, count);
  });

  test('server-confirmed self profile and inline avatar survive without a local profile file', () async {
    connection.missing = true;
    connection.remote = {
      'cachedAtUtc': '2026-09-04T12:00:30Z',
      'payload': {
        'schemaVersion': 1,
        'editable': false,
        'profile': {
          'isPublic': false,
          'visibility': 'private',
          'revision': 3,
          'identity': {
            'callSign': 'Server Pilot',
            'gameHandle': '',
            'avatarAssetId': 'data:image/png;base64,AQID',
          },
          'content': {
            'introduction': 'Server confirmed biography',
            'modules': [],
            'presenceIntent': null,
          },
        },
      },
    };
    await mode.refresh();
    port = BridgeOfflinePersonalProfile(session, mode);
    final result = await port.read();
    expect(result.availability, PersonalProfileAvailability.available);
    expect(result.callSign, 'Server Pilot');
    expect(result.about, 'Server confirmed biography');
    expect(result.avatarImageData, 'data:image/png;base64,AQID');
    expect(result.allowEditing, isFalse);
    expect(result.gameHandle, isEmpty);
    expect(result.local?.savedAt, DateTime.parse('2026-09-04T12:00:30Z'));
    expect(
      connection.requests.every((r) => r.name.startsWith('onboarding.mode.')),
      isTrue,
    );
    (connection.remote!['payload'] as Map)['editable'] = true;
    expect(
      (await port.read()).availability,
      PersonalProfileAvailability.unavailable,
    );
  });

  test('own local profile and inventory remain display-only without account traffic', () async {
    await mode.refresh();
    port = BridgeOfflinePersonalProfile(session, mode);
    final profile = await port.read();
    expect(profile.availability, PersonalProfileAvailability.available);
    expect(profile.callSign, 'Synthetic Pilot');
    expect(profile.about, 'Retained introduction');
    expect(profile.hangarSummary.shipCount, 201);
    expect(profile.allowEditing, isFalse);
    expect(profile.gameHandle, isEmpty);
    expect(profile.affiliations, isEmpty);
    expect(
      connection.requests.every(
        (r) =>
            r.name.startsWith('onboarding.mode.') && r.accountContext == null,
      ),
      isTrue,
    );
    final count = connection.requests.length;
    final result = await port.save(
      const PersonalProfileEdit(
        callSign: 'Changed',
        about: '',
        avatarStyle: 0,
        wallpaperId: 'none',
        visibility: PersonalProfileVisibility.everyone,
        moduleLayout: [],
      ),
    );
    expect(result.outcome, PersonalProfileActionOutcome.rejected);
    expect(connection.requests.length, count);
    await port.close();
  });
  test(
    'missing local profile is unavailable, not a newly created blank profile',
    () async {
      await mode.refresh();
      connection.missing = true;
      port = BridgeOfflinePersonalProfile(session, mode);
      expect(
        (await port.read()).availability,
        PersonalProfileAvailability.unavailable,
      );
      expect(connection.requests, hasLength(1));
      await port.close();
    },
  );
  test('changed mode discards a late original profile response', () async {
    await mode.refresh();
    connection.held = Completer<void>();
    port = BridgeOfflinePersonalProfile(session, mode);
    final read = port.read();
    await Future<void>.delayed(Duration.zero);
    modes.current = modeFact('online');
    await mode.refresh();
    connection.held!.complete();
    expect((await read).availability, PersonalProfileAvailability.unavailable);
    expect(connection.requests, hasLength(1));
    await port.close();
  });
  testWidgets(
    'network outage page clears retained profile on authoritative logout',
    (tester) async {
      modes.current = modeFact('online');
      await tester.runAsync(mode.refresh);
      const id = '0123456789abcdef0123456789abcdef';
      final account = ValueNotifier(
        const AccountProjection(
          sessionState: AccountSessionState.credentialTemporarilyUnavailable,
          retainedReadId: id,
          operation: AccountOperation.none,
          generation: 7,
          profileFreshness: AccountProfileFreshness.cached,
          identity: AccountIdentityProjection.unavailable(),
          compatibility: AccountCompatibilityProjection.unavailable(),
          localeOptions: [],
          timeZoneOptions: [],
        ),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              delegates: const [AppStringsDelegate()],
              child: OfflinePersonalProfilePage(
                mode: mode,
                account: account,
                createPort: () =>
                    throw StateError('manual offline must not be used'),
                createRetainedPort: (readId) =>
                    BridgeOfflinePersonalProfile.retained(
                      session,
                      readId,
                      isCurrent: () => account.value.retainedReadId == readId,
                    ),
                online: const Text('Online owner'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Retained introduction'), findsOneWidget);
      expect(find.byKey(const Key('profile-edit')), findsNothing);
      account.value = account.value.copyWith(
        sessionState: AccountSessionState.signedOut,
        clearProfile: true,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Retained introduction'), findsNothing);
      expect(find.text('Online owner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      account.dispose();
    },
  );
  testWidgets(
    'offline page shows original profile without editing or visibility actions',
    (tester) async {
      await tester.runAsync(mode.refresh);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              delegates: const [AppStringsDelegate()],
              child: OfflinePersonalProfilePage(
                mode: mode,
                createPort: () => BridgeOfflinePersonalProfile(session, mode),
                online: const Text('Online owner'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Retained introduction'), findsOneWidget);
      expect(find.textContaining('正在离线查看本机保存的资料'), findsOneWidget);
      expect(find.byKey(const Key('profile-edit')), findsNothing);
      expect(find.byKey(const Key('profile-visibility')), findsNothing);
      modes.current = modeFact('online');
      await tester.runAsync(mode.refresh);
      await tester.pumpAndSettle();
      expect(find.text('Online owner'), findsOneWidget);
      expect(find.textContaining('Retained introduction'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
