import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/connected_manual_presence.dart';
import 'package:starbridge_flutter/app/runtime/online_restore_flow.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';

import '../../features/onboarding/connection_mode_test.dart' show modeWire;
import '../../features/onboarding/online_review_test_support.dart';
import '../../features/onboarding/retained_online_review_test.dart'
    show retainedWire, retainedReview;
import '../tray_quick_panel_test.dart' show app;

class RetainedAccount implements AccountModule {
  RetainedAccount(this.generation, {bool coldStart = false}) {
    if (coldStart) {
      projection.value = const AccountProjection.loading().copyWith(
        operation: AccountOperation.none,
        sessionState: AccountSessionState.credentialTemporarilyUnavailable,
        failure: const AccountFailure(
          code: 'account.local_mode',
          messageKey: 'account.error.unavailable',
          retryable: false,
        ),
      );
    }
  }
  final int Function() generation;
  int refreshes = 0;
  @override
  final ValueNotifier<AccountProjection> projection = ValueNotifier(
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.signedIn,
      identity: const AccountIdentityProjection(
        state: AccountIdentityState.match,
        sensitiveWritesAllowed: true,
        authoritativeHandle: 'Pilot-Example',
      ),
    ),
  );
  @override
  Future<AccountActionResult> refresh() async {
    refreshes++;
    projection.value = const AccountProjection.loading().copyWith(
      generation: generation(),
      operation: AccountOperation.none,
      sessionState: AccountSessionState.signedIn,
      identity: const AccountIdentityProjection(
        state: AccountIdentityState.match,
        sensitiveWritesAllowed: true,
        authoritativeHandle: 'Pilot-Example',
      ),
    );
    return const AccountActionResult(AccountActionOutcome.completed);
  }

  @override
  void dispose() => projection.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account operation');
}

void main() {
  for (final scenario in ['warm', 'cold', 'pending']) {
    final coldStart = scenario != 'warm';
    final pending = scenario == 'pending';
    testWidgets(
      'actual primary Online action restores without a guide or second login ($scenario)',
      (tester) async {
        final f = OnlineBridgeFixture(retainedProtocol: true);
        f.session.acceptHostCapabilities([
          BridgeOnlineReviewAdapter.retainedCapability,
          BridgeOnlineInstallationAdapter.capability,
          BridgeConnectionModeAdapter.capability,
        ]);
        var online = false;
        var recovered = !pending;
        final reviewRevision = pending ? 9 : 7;
        f.onRequest = (request) async {
          final value = request.name == 'onboarding.mode.read'
              ? modeWire(
                  online
                      ? 'online'
                      : recovered
                      ? 'offline'
                      : 'signInRequired',
                  revision: online
                      ? reviewRevision + 1
                      : pending
                      ? 7
                      : 4,
                )
              : request.name == 'onboarding.onlineInstallation.install'
              ? <String, Object?>{
                  'schemaVersion': 1,
                  'revision': reviewRevision,
                  'phase': 'completed',
                  'controlGeneration': 8,
                  'modeRevision': reviewRevision + 1,
                  'modeState': 'online',
                }
              : switch (request.name.split('.').last) {
                  'read' =>
                    recovered
                        ? retainedWire(
                            mode: 'offline',
                            state: 'notStarted',
                            revision: pending ? 8 : 7,
                          )
                        : retainedWire(state: 'recoveryRequired'),
                  'cancel' => retainedWire(
                    mode: 'offline',
                    state: 'notStarted',
                    revision: 8,
                  ),
                  'begin' => retainedWire(revision: reviewRevision),
                  'resume' => {...retainedReview(), 'revision': reviewRevision},
                  'confirm' => {
                    ...retainedReview(confirmed: true),
                    'revision': reviewRevision,
                  },
                  _ => throw StateError('Unexpected request'),
                };
          if (request.name.endsWith('.install')) online = true;
          if (request.name.endsWith('.cancel')) recovered = true;
          await f.respond(request, value: value);
        };
        final chrome = InMemoryShellChrome();
        final connection = ConnectedManualPresence(
          f.session,
          chrome.projection,
        );
        final account = RetainedAccount(
          () => f.session.activeGeneration,
          coldStart: coldStart,
        );
        BuildContext? context;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final flow = OnlineRestoreFlow(
          connection: connection,
          account: account,
          context: () => context,
          current: () => true,
        );
        final ready = connection.refresh();
        await tester.pumpAndSettle();
        await ready;
        expect(
          f.requests.any(
            (r) =>
                r.name.endsWith('.cancel') ||
                r.name.endsWith('.begin') ||
                r.name.endsWith('.resume') ||
                r.name.endsWith('.install'),
          ),
          false,
          reason: 'observation must never start recovery without an explicit Online click',
        );
        expect(connection.source.controller.canRestoreOnline, true);
        bool? restored;
        final restoring = connection.source.controller.restoreOnline()
          ..then((value) => restored = value);
        // Multiple original Bridge / generation reads schedule zero-delay work.
        // Advance that virtual clock explicitly, even if no UI frame is pending.
        for (var i = 0; i < 100 && restored == null; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(restored, true);
        await restoring;
        expect(find.byType(AlertDialog), findsNothing);
        expect(connection.connectionMode.allowsOnlineTraffic, true);
        expect(account.refreshes, 1);
        expect(
          f.requests.where((r) => r.name.endsWith('.cancel')),
          hasLength(pending ? 1 : 0),
        );
        expect(f.session.activeGeneration, 8);
        expect(
          f.requests.where((r) => r.name.endsWith('.install')),
          hasLength(1),
        );
        expect(
          f.requests.any(
            (r) => r.name.endsWith('.login') || r.name.endsWith('.reauthorize'),
          ),
          false,
        );
        expect(await connection.source.controller.restoreOnline(), false);
        await tester.pumpWidget(const SizedBox());
        flow.dispose();
        connection.dispose();
        account.dispose();
        await tester.runAsync(f.close);
      },
    );
  }
}
