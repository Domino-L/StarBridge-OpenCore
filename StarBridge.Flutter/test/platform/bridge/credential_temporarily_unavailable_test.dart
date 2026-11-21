import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_read_failure.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_account_access.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

BridgeEnvelope _account(String state) => BridgeEnvelope(
  protocolVersion: 1,
  messageType: 'response',
  name: 'account.getCurrent',
  sessionGeneration: 1,
  payload: {'schemaVersion': 1, 'state': state},
);

void main() {
  test('only the temporary session state counts as temporarily unavailable', () {
    expect(
      accountTemporarilyUnavailable(_account('credentialTemporarilyUnavailable')),
      isTrue,
    );
    for (final state in ['signedOut', 'reauthorizationRequired', 'signedIn']) {
      expect(accountTemporarilyUnavailable(_account(state)), isFalse);
    }
  });

  test('the temporary credential code is never a lost identity', () {
    const temporary = BridgeRemoteException(
      'account.credential_temporarily_unavailable',
      retryable: true,
    );
    expect(isCredentialTemporarilyUnavailable(temporary), isTrue);
    expect(
      isCredentialTemporarilyUnavailable(
        const BridgeRemoteException('account.reauthorization_required'),
      ),
      isFalse,
    );
    expect(fleetReadIsTransient(temporary), isTrue);
    expect(fleetReadLosesContext(temporary), isFalse);
    expect(fleetReadFailureKey(temporary), 'officialFleet.error.transient');
    expect(
      fleetReadFailureKey(temporary, members: true),
      'officialFleet.members.error.transient',
    );
  });
}
