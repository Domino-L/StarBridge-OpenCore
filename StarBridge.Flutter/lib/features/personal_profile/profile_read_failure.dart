import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

// Unknown failures, schema errors, cancellations and authorization failures
// must never acquire the display-retention semantics of a transport outage.
bool profileReadIsTransient(Object error) =>
    error is TimeoutException ||
    error is BridgeDisconnectedException ||
    error is BridgeClientException &&
        (error.code == 'bridge.timeout' ||
            error.code == 'personal_profile.read_transient' && error.retryable);

String profileReadFailureKey(Object error) {
  if (error is BridgeClientException) {
    return switch (error.code) {
      'bridge.disconnected' => 'profile.error.hostUnavailable',
      'account.reauthorization_required' =>
        'profile.error.reauthorizationRequired',
      'account.compatibility_existing_link_mismatch' =>
        'profile.error.compatibilityMismatch',
      'bridge.invalid_envelope' ||
      'bridge.protocol_incompatible' ||
      'personal_profile.data_invalid' => 'profile.error.invalidResponse',
      _ => 'profile.error.unavailable',
    };
  }
  return error is BridgeFormatException
      ? 'profile.error.invalidResponse'
      : 'profile.error.unavailable';
}

String profileSaveFailureKey(Object error) {
  if (error is BridgeClientException) {
    return switch (error.code) {
      'personal_profile.write_forbidden' =>
        'profile.error.reauthorizationRequired',
      'personal_profile.write_conflict' => 'profile.error.writeConflict',
      _ => profileReadFailureKey(error),
    };
  }
  return profileReadFailureKey(error);
}

String profilePageSaveFailureKey(Object error) {
  if (error is BridgeClientException &&
      const {
        'personal_profile.write_conflict',
        'personal_profile.write_forbidden',
        'account.reauthorization_required',
      }.contains(error.code)) {
    return profileSaveFailureKey(error);
  }
  // After dispatch, a lost or invalid acknowledgement cannot prove no write.
  return 'profile.error.writeUnconfirmed';
}
