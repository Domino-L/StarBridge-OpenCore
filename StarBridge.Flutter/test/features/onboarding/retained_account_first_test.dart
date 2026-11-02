import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_installation_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';

import 'online_review_test_support.dart';

Map<String, Object?> accountWire(
  String state, {
  String mode = 'signInRequired',
  int revision = 8,
}) => {
  'schemaVersion': 2,
  'revision': revision,
  'modeState': mode,
  'retainsSession': mode != 'online',
  'identity': {
    'state': state,
    'localHandle': null,
    'authoritativeHandle': 'Pilot-Example',
    'accountDisplayName': 'Synthetic Pilot',
    'confirmationKey': state == 'accountReviewRequired' ? 'a' * 32 : null,
  },
};

void main() {
  test(
    'owner refresh failure retries refresh without installing twice',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          accountWire('accountConfirmedForHandoff'),
          retainedProtocol: true,
        );
      final installation = SuccessfulInstall(port);
      var refreshes = 0;
      final controller = OnlineReviewController(
        port,
        installation: installation,
        onInstalled: () async {
          if (++refreshes == 1) {
            throw StateError('Synthetic owner refresh failure');
          }
        },
      );
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.value.error, true);
      await controller.refresh();
      expect(controller.value.error, false);
      expect(refreshes, 2);
      expect(installation.installs, 1);
    },
  );
  test(
    'lost confirmation response resumes its confirmed installation once',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          accountWire('accountReviewRequired'),
          retainedProtocol: true,
        );
      port.onAction = (_) async {
        port.snapshot = OnlineReviewWire.parse(
          accountWire('accountConfirmedForHandoff'),
          retainedProtocol: true,
        );
        throw StateError('Synthetic lost confirmation response');
      };
      final installation = SuccessfulInstall(port);
      final controller = OnlineReviewController(
        port,
        installation: installation,
      );
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.execute(OnlineReviewAction.confirm);
      expect(controller.value.error, true);
      expect(installation.installs, 0);
      await controller.refresh();
      expect(controller.value.error, false);
      expect(controller.value.snapshot.modeState, OnlineReviewModeState.online);
      await controller.refresh();
      expect(installation.installs, 1);
      expect(port.actions, [OnlineReviewAction.confirm]);
    },
  );
  for (final completed in [true, false]) {
    test(
      'lost install result is observed without replay: online=$completed',
      () async {
        final port = FakeOnlinePort()
          ..snapshot = OnlineReviewWire.parse(
            accountWire('accountReviewRequired'),
            retainedProtocol: true,
          )
          ..onAction = (_) async => OnlineReviewWire.parse(
            accountWire('accountConfirmedForHandoff'),
            retainedProtocol: true,
          );
        final installation = LostInstallResult(completed);
        final controller = OnlineReviewController(
          port,
          installation: installation,
        );
        addTearDown(port.close);
        addTearDown(controller.dispose);
        await controller.refresh();
        await controller.execute(OnlineReviewAction.confirm);
        expect(controller.value.error, true);
        expect(controller.value.snapshot.retainsSession, true);
        port.snapshot = OnlineReviewWire.parse(
          accountWire(
            completed ? 'needsLocalIdentity' : 'accountReviewRequired',
            mode: completed ? 'online' : 'signInRequired',
            revision: completed ? 9 : 8,
          ),
          retainedProtocol: true,
        );
        await controller.refresh();
        expect(controller.value.error, false);
        expect(installation.installs, 1);
        expect(installation.reads, 1);
        expect(controller.value.snapshot.canCancel, !completed);
        await controller.refresh();
        expect(installation.reads, 1);
      },
    );
  }
  test(
    'actual adapters restore account before any local Handle is available',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
        BridgeOnlineInstallationAdapter.capability,
      ]);
      var installed = false;
      var ownerRefreshes = 0;
      final controller = OnlineReviewController(
        f.adapter,
        installation: BridgeOnlineInstallationAdapter(f.session),
        onInstalled: () async {
          ownerRefreshes++;
        },
      );
      addTearDown(controller.dispose);
      f.onRequest = (request) async {
        final action = request.name.split('.').last;
        if (action == 'install') {
          installed = true;
          await f.respond(
            request,
            value: {
              'schemaVersion': 1,
              'revision': 8,
              'phase': 'completed',
              'controlGeneration': request.sessionGeneration,
              'modeRevision': 9,
              'modeState': 'online',
            },
          );
          return;
        }
        await f.respond(
          request,
          value: switch (action) {
            'read' =>
              installed
                  ? accountWire(
                      'needsLocalIdentity',
                      mode: 'online',
                      revision: 9,
                    )
                  : accountWire('notStarted', mode: 'offline', revision: 7),
            'begin' => accountWire('signInRequired'),
            'resume' => accountWire('accountReviewRequired'),
            'confirm' => accountWire('accountConfirmedForHandoff'),
            _ => throw StateError('Unexpected command $action'),
          },
        );
      };
      await controller.refresh();
      await controller.signIn();
      expect(controller.value.error, false);
      expect(controller.value.snapshot.modeState, OnlineReviewModeState.online);
      expect(
        controller.value.snapshot.state,
        OnlineReviewState.needsLocalIdentity,
      );
      expect(controller.value.snapshot.identityConfirmed, false);
      expect(ownerRefreshes, 1);
      expect(f.requests.map((r) => r.name.split('.').last), [
        'read',
        'begin',
        'resume',
        'confirm',
        'install',
        'read',
      ]);
    },
  );

  test(
    'account-only receipt cannot masquerade as game identity confirmation',
    () {
      final account = OnlineReviewWire.parse(
        accountWire('accountConfirmedForHandoff'),
        retainedProtocol: true,
      );
      expect(account.identityConfirmed, false);
      expect(
        () => OnlineReviewWire.parse({
          ...accountWire('accountReviewRequired'),
          'retainsSession': false,
        }, retainedProtocol: true),
        throwsFormatException,
      );
      expect(
        () => OnlineReviewWire.parse(
          accountWire('reviewRequired'),
          retainedProtocol: true,
        ),
        throwsFormatException,
      );
    },
  );

  test('post-installation identity review requires exact matching Handles', () {
    final wire = accountWire(
      'installedReviewRequired',
      mode: 'online',
      revision: 9,
    );
    wire['identity'] = {
      'state': 'installedReviewRequired',
      'localHandle': 'Pilot-Example',
      'authoritativeHandle': 'Pilot-Example',
      'accountDisplayName': 'Synthetic Pilot',
      'confirmationKey': 'b' * 32,
    };
    final review = OnlineReviewWire.parse(wire, retainedProtocol: true);
    expect(review.canConfirm, true);
    expect(review.canCancel, false);
    final identity = wire['identity']! as Map<String, Object?>;
    identity['localHandle'] = 'Other-Pilot';
    expect(
      () => OnlineReviewWire.parse(wire, retainedProtocol: true),
      throwsFormatException,
    );
  });
}

final class SuccessfulInstall implements OnlineInstallationPort {
  SuccessfulInstall(this.port);
  final FakeOnlinePort port;
  int installs = 0;
  @override
  bool get supported => true;
  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    installs++;
    port.snapshot = OnlineReviewWire.parse(
      accountWire('needsLocalIdentity', mode: 'online', revision: 9),
      retainedProtocol: true,
    );
    return OnlineInstallationSnapshot(
      revision: revision,
      phase: OnlineInstallationPhase.completed,
      controlGeneration: 7,
      modeRevision: 9,
      modeState: 'online',
    );
  }

  @override
  Future<OnlineInstallationSnapshot> read(int revision) => Future.value(
    OnlineInstallationSnapshot(
      revision: revision,
      phase: OnlineInstallationPhase.completed,
      controlGeneration: 7,
      modeRevision: 9,
      modeState: 'online',
    ),
  );
}

final class LostInstallResult implements OnlineInstallationPort {
  LostInstallResult(this.completed);
  final bool completed;
  int installs = 0, reads = 0;
  @override
  bool get supported => true;
  @override
  Future<OnlineInstallationSnapshot> install(int revision) async {
    installs++;
    throw StateError('Synthetic lost response');
  }

  @override
  Future<OnlineInstallationSnapshot> read(int revision) async {
    reads++;
    return OnlineInstallationSnapshot(
      revision: revision,
      phase: completed
          ? OnlineInstallationPhase.completed
          : OnlineInstallationPhase.idle,
      controlGeneration: 7,
      modeRevision: completed ? 9 : 8,
      modeState: completed ? 'online' : 'signInRequired',
    );
  }
}
