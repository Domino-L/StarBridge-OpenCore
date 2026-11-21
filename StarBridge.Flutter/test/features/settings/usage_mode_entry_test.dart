import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/composition/first_use_setup_composition.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_settings_entry.dart';
import 'package:starbridge_flutter/features/settings/usage_mode_page.dart';
import 'package:starbridge_flutter/features/onboarding/first_use_setup_entry.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../onboarding/bridge_onboarding_adapter_test.dart' show wire;
import '../onboarding/online_review_test_support.dart' show onlineWire;
import '../../app/first_use_setup_composition_test.dart' show EditorsFixture;

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStringsDelegate()],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: Scaffold(body: child),
);

void main() {
  for (final (reason, eligibility, completed) in const [
    ('previousUse', 'returning', false),
    ('updateInstallation', 'returning', false),
    ('completedSetup', 'returning', true),
    ('resume', 'firstUse', false),
    ('freshInstallation', 'firstUse', false),
    ('unknown', 'unknown', false),
  ]) {
    final usageMode = completed || eligibility == 'returning';
    for (final online in [false, true]) {
      testWidgets(
        'settings entry reason=$reason eligibility=$eligibility completed=$completed online=$online',
        (tester) async {
          final pair = InMemoryBridgeConnection.createPair();
          final session = BridgeClientSession(
            connection: pair.client,
            sessionGeneration: 7,
          );
          session.acceptHostCapabilities(['onboarding.firstUse.v1']);
          final payload = wire();
          (payload['facts']! as Map<String, Object?>).addAll({
            'activeMode': online ? 'online' : 'local',
            'publicationSuspended': !online,
            'eligibility': eligibility,
          });
          if (reason == 'resume') {
            payload['restored'] = <String, Object?>{
              'step': 'mode',
              'mode': 'local',
              'sourceKey': null,
              'evidenceKey': null,
            };
          }
          payload['completed'] = completed
              ? <String, Object?>{
                  'step': 'summary',
                  'mode': 'local',
                  'sourceKey': null,
                  'evidenceKey': null,
                }
              : null;
          var setupRequests = 0;
          final requests = <String>[];
          final subscription = pair.host.incoming.listen((request) {
            requests.add(request.name);
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: 7,
                  status: 'ok',
                  payload: payload,
                ),
              ),
            );
          });
          await tester.pumpWidget(
            app(
              FirstUseSetupEntry(
                open: (_) async {
                  setupRequests++;
                },
                child: UsageModeSettingsEntry(session: session),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(requests, ['onboarding.read']);
          expect(
            find.byKey(const Key('settings-usage-mode')),
            usageMode ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('settings-first-use')),
            usageMode ? findsNothing : findsOneWidget,
          );
          final editors = EditorsFixture();
          final production = AppComposition.forShellReview(
            windowChrome: InMemoryWindowChrome(),
          );
          final registry = FeatureRegistry([
            ...production.features.all,
            ...createFirstUseSetupFeatures(session, editors.editors),
          ]);
          final menu = registry.inRegion(NavigationRegion.accountMenu);
          expect(menu.map((item) => item.id), [
            'personal-profile',
            'achievements',
            'account-and-identity',
          ]);
          expect(
            menu.map((item) => item.labelKey),
            isNot(contains('settings.firstUse')),
          );
          expect(
            menu.map((item) => item.route),
            isNot(contains('/settings/usage-mode')),
          );
          editors.close();
          if (usageMode) {
            await tester.tap(find.byKey(const Key('settings-usage-mode')));
            await tester.pumpAndSettle();
            expect(find.byType(UsageModePage), findsOneWidget);
            expect(setupRequests, 0);
            Navigator.of(tester.element(find.byType(UsageModePage))).pop();
            await tester.pumpAndSettle();
          }
          if (!usageMode && !online) {
            final future =
                Navigator.of(
                  tester.element(find.byType(UsageModeSettingsEntry)),
                ).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(body: Text('Setup route')),
                  ),
                );
            await tester.pumpAndSettle();
            payload['completed'] = <String, Object?>{
              'step': 'summary',
              'mode': 'local',
              'sourceKey': null,
              'evidenceKey': null,
            };
            (payload['facts']! as Map<String, Object?>)['eligibility'] =
                'returning';
            Navigator.of(tester.element(find.text('Setup route'))).pop();
            await future;
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('settings-first-use')), findsNothing);
            expect(
              find.byKey(const Key('settings-usage-mode')),
              findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await subscription.cancel();
            await session.close();
            await pair.host.close();
          });
        },
      );
    }
  }
  testWidgets('local-mode account button opens usage mode route', (
    tester,
  ) async {
    final module = createAccountModule(_LocalAccount());
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(
      app(
        AccountPage(
          module: module,
          openUsageMode: (context) async => Navigator.of(context).push<void>(
            MaterialPageRoute(
              settings: const RouteSettings(name: '/settings/usage-mode'),
              builder: (_) =>
                  const Scaffold(body: Text('Usage mode destination')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('You are in local mode and cannot sign in.'),
      findsOneWidget,
    );
    final button = find.byKey(const Key('account-local-mode-online'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Usage mode destination'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('Usage mode destination')))!
          .settings
          .name,
      '/settings/usage-mode',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'confirm game identity entry reaches the installed review through the real bridge adapters',
    (tester) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities([
        'onboarding.firstUse.v1',
        'onboarding.onlineReview.v2',
      ]);
      final payload = wire();
      (payload['facts']! as Map<String, Object?>).addAll({
        'activeMode': 'online',
        'publicationSuspended': false,
        'eligibility': 'returning',
      });
      payload['completed'] = <String, Object?>{
        'step': 'summary',
        'mode': 'online',
        'sourceKey': null,
        'evidenceKey': null,
      };
      var identity = 'identityCheckRequired';
      Map<String, Object?> review() => {
        ...onlineWire(
          mode: 'online',
          state: identity,
          local: 'Pilot-Example',
          remote: 'Pilot-Example',
          key: identity == 'installedReviewRequired' ? 'a' * 32 : null,
        ),
        'schemaVersion': 2,
        'retainsSession': false,
      };
      final requests = <String>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request.name);
        if (request.name == 'onboarding.onlineReview.v2.review') {
          identity = 'installedReviewRequired';
        }
        if (request.name == 'onboarding.onlineReview.v2.confirm') {
          identity = 'boundOnlineIdentity';
        }
        final body = request.name == 'onboarding.read'
            ? payload
            : request.name.startsWith('onboarding.onlineReview.v2.')
            ? review()
            : null;
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 7,
              status: body == null ? 'error' : 'ok',
              payload: body ?? const <String, Object?>{},
            ),
          ),
        );
      });
      var reviewed = 0;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              key: const Key('open-identity-review'),
              onPressed: () => unawaited(
                openGameIdentityReview(
                  context,
                  session,
                  afterReview: () async => reviewed++,
                ),
              ),
              child: const Text('Confirm game identity again'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-identity-review')));
      await tester.pumpAndSettle();
      expect(find.byType(UsageModePage), findsOneWidget);
      final panel = find.byKey(const ValueKey('usage-mode-installed-review'));
      expect(panel, findsOneWidget);
      final check = find.byKey(const Key('online-review-check'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('online-review-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(
        requests,
        containsAllInOrder([
          'onboarding.onlineReview.v2.review',
          'onboarding.onlineReview.v2.confirm',
        ]),
      );
      expect(
        requests.where(
          (name) =>
              name != 'onboarding.read' &&
              !name.startsWith('onboarding.onlineReview.v2.'),
        ),
        isEmpty,
      );
      expect(reviewed, 0);
      Navigator.of(tester.element(find.byType(UsageModePage))).pop();
      await tester.pumpAndSettle();
      // Leaving usage mode asks the caller to read the recording state again.
      expect(reviewed, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
    },
  );
}

class _LocalAccount implements AccountPort {
  @override
  Stream<AccountInvalidation> get invalidations => const Stream.empty();
  @override
  Future<AccountPortResult> read() async => const AccountPortResult(
    outcome: AccountActionOutcome.failed,
    snapshot: AccountHostSnapshot(
      generation: 0,
      sessionState: AccountSessionState.signedOut,
      profileFreshness: AccountProfileFreshness.unavailable,
      identity: AccountIdentityProjection.unavailable(),
      compatibility: AccountCompatibilityProjection.unavailable(),
      localeOptions: [],
      timeZoneOptions: [],
    ),
    failure: AccountFailure(
      code: 'account.local_mode',
      messageKey: 'account.error.localMode',
      retryable: false,
    ),
  );
  @override
  Future<AccountPortResult> execute(AccountPortCommand command) => read();
  @override
  Future<void> close() async {}
}
