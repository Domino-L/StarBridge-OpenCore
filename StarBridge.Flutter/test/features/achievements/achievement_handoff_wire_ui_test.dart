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
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../onboarding/connection_mode_test.dart' show modeWire;

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  for (final hasModeOwner in [false, true]) {
    testWidgets(
      'actual restore wire keeps achievement page, scroll and inspector until its own fresh read; mode owner: $hasModeOwner',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1080, 420);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        BridgeEnvelope native(String key) =>
            BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
        final prepared = native('prepared'), completed = native('completed');
        late InMemoryBridgePair pair;
        late BridgeClientSession bridge;
        late AccountModule account;
        ConnectionModeController? mode;
        late BridgeAchievementCollection port;
        late AchievementCollectionSession feature;
        late Future<AccountActionResult> pending;
        late StreamSubscription<BridgeEnvelope> subscription;
        final requests = <BridgeEnvelope>[],
            metadata = <BridgeEnvelope>[],
            fresh = <BridgeEnvelope>[],
            modeReads = <BridgeEnvelope>[];
        var signedOut = false;
        Future<void> reply(
          BridgeEnvelope request,
          Map<String, Object?> payload, {
          bool public = false,
        }) => pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: public ? null : completed.accountContext,
            status: 'ok',
            payload: payload,
          ),
        );
        Future<void> drain() async {
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            await tester.pump();
          }
        }

        await tester.runAsync(() async {
          pair = InMemoryBridgeConnection.createPair();
          var index = 0;
          bridge = BridgeClientSession(
            connection: pair.client,
            sessionGeneration: 0,
            correlationIdFactory: () => index++ == 0
                ? completed.correlationId!
                : 'achievement-ui-$index',
          );
          bridge.acceptHostCapabilities([
            'account.restoreDisplay',
            'profile.stagedRead',
            'achievements.read',
            if (hasModeOwner) 'onboarding.mode.v1',
          ]);
          account = createAccountModule(BridgeAccountAdapter(bridge));
          if (hasModeOwner) {
            mode = ConnectionModeController(
              BridgeConnectionModeAdapter(bridge),
            );
          }
          port = BridgeAchievementCollection(
            bridge,
            mode: mode,
            retainedReadId: () =>
                account.projection.value.hasRetainedDisplayRead
                ? account.projection.value.retainedReadId
                : null,
            displayHandoff: () => account.projection.value.hasDisplayHandoff
                ? account.projection.value.displayHandoff
                : null,
          );
          feature = AchievementCollectionSession(
            account: account.projection,
            port: port,
            mode: mode,
          );
          var first = true;
          subscription = pair.host.incoming.listen((request) {
            requests.add(request);
            switch (request.name) {
              case 'account.getCurrent':
                if (first) {
                  first = false;
                  break;
                }
                final payload = {...completed.payload}
                  ..remove('restoreDisplayReadId');
                unawaited(
                  reply(
                    request,
                    signedOut
                        ? const {'schemaVersion': 1, 'state': 'signedOut'}
                        : payload,
                    public: signedOut,
                  ),
                );
              case 'account.offlineData.read':
                // The actual Native artifact contains only profile data. Awards are
                // explicit synthetic domain fixtures, never claimed as Native output.
                unawaited(
                  reply(request, const {
                    'schemaVersion': 1,
                    'cachedAtUtc': '2026-10-01T00:00:00Z',
                    'collection': {
                      'schemaVersion': 1,
                      'earnedAt': {'first-entry': '2026-09-01T00:00:00Z'},
                    },
                  }, public: true),
                );
              case 'profile.readDisplayCache':
                metadata.add(request);
              case 'achievements.read':
                fresh.add(request);
              case 'onboarding.mode.read':
                if (request.sessionGeneration == 0) {
                  unawaited(reply(request, modeWire('online'), public: true));
                } else {
                  modeReads.add(request);
                }
            }
          });
          pending = account.initialize();
          await Future<void>.delayed(Duration.zero);
          await mode?.refresh();
        });
        try {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStringsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: buildStarBridgeTheme(
                FutureRestraintStyle.resolve(AppearanceMode.dark),
                const Locale('en'),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: Scaffold(
                body: AchievementsPage(
                  account: account.projection,
                  port: port,
                  session: feature,
                  mode: mode,
                ),
              ),
            ),
          );
          await tester.runAsync(() => pair.host.send(prepared));
          await drain();
          expect(feature.collection.value.isEarned('first-entry'), isTrue);
          expect(account.projection.value.isSignedIn, isFalse);
          final element = tester.element(find.byType(AchievementsPage));
          final entry = find.byKey(const Key('achievement-entry-first-entry'));
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          final inspector = tester.element(find.byType(AchievementDetail));
          final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const Key('achievement-collection-scroll')),
          );
          final position = scroll.controller!.offset;
          expect(position, greaterThan(0));
          final readonlyRequests = requests
              .where((r) => r.name == 'account.offlineData.read')
              .length;
          await tester.runAsync(() async {
            await pair.host.send(completed);
            await Future<void>.delayed(Duration.zero);
          });
          await drain();
          expect(account.projection.value.isSignedIn, isFalse);
          expect(metadata, isEmpty);
          expect(
            tester.element(find.byType(AchievementDetail)),
            same(inspector),
          );
          await tester.runAsync(
            () => pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'account.changed',
                sessionGeneration: 1,
                sequence: prepared.sequence! + 1,
                payload: const {'schemaVersion': 1},
              ),
            ),
          );
          await drain();
          expect(account.projection.value.retainedReadId, isNull);
          expect(feature.collection.value.isEarned('first-entry'), isTrue);
          expect(
            tester.element(find.byType(AchievementDetail)),
            same(inspector),
          );
          expect(scroll.controller!.offset, position);
          expect(metadata, isNotEmpty);
          if (hasModeOwner) {
            expect(mode!.allowsOnlineTraffic, isFalse);
            expect(modeReads, hasLength(1));
            await tester.runAsync(
              () => reply(modeReads.single, modeWire('online'), public: true),
            );
            await drain();
            expect(feature.collection.value.isEarned('first-entry'), isTrue);
          }
          await tester.runAsync(() async {
            for (final request in metadata) {
              await reply(request, const {
                'schemaVersion': 1,
                'source': 'unavailable',
                'preferencesPolicy': {
                  'locales': [],
                  'timeZones': [],
                  'availableActions': [],
                },
              });
            }
          });
          await drain();
          expect(account.projection.value.isSignedIn, isTrue);
          expect(fresh, hasLength(1));
          expect(feature.collection.value.isEarned('first-entry'), isTrue);
          await tester.runAsync(
            () =>
                reply(fresh.single, const {'schemaVersion': 1, 'earnedAt': {}}),
          );
          await drain();
          expect(feature.collection.value.isReady, isTrue);
          expect(feature.collection.value.cachedAtUtc, isNull);
          expect(feature.collection.value.isEarned('first-entry'), isTrue);
          expect(tester.element(find.byType(AchievementsPage)), same(element));
          expect(
            tester.element(find.byType(AchievementDetail)),
            same(inspector),
          );
          expect(
            tester
                .widget<AchievementDetail>(find.byType(AchievementDetail))
                .collection
                .isEarned('first-entry'),
            isTrue,
          );
          expect(
            scroll.controller!.offset,
            position.clamp(0.0, scroll.controller!.position.maxScrollExtent),
            reason:
                'Removing sync notices may shrink the bottom extent; '
                'retain the viewport without resetting or overscrolling.',
          );
          expect(
            requests.where((r) => r.name == 'account.offlineData.read'),
            hasLength(readonlyRequests),
          );
          expect(
            requests
                .where((r) => r.name == 'achievements.read')
                .single
                .sessionGeneration,
            1,
          );
          await tester.tap(find.byKey(const Key('achievement-detail-close')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            signedOut = true;
            await pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'account.changed',
                sessionGeneration: 2,
                sequence: prepared.sequence! + 2,
                payload: const {'schemaVersion': 1},
              ),
            );
          });
          await drain();
          expect(find.byType(AchievementDetail), findsNothing);
          expect(feature.collection.value.isReady, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            feature.dispose();
            account.dispose();
            mode?.dispose();
            await bridge.close();
            await pending;
            await subscription.cancel();
            await pair.host.close();
          });
        }
      },
      skip: _path.isEmpty,
    );
  }
}
