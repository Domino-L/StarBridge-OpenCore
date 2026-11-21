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
      'personalProfile.write_invalid' => 'profile.collab.invalid',
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
        'personalProfile.write_invalid',
        'account.reauthorization_required',
      }.contains(error.code)) {
    return profileSaveFailureKey(error);
  }
  // After dispatch, a lost or invalid acknowledgement cannot prove no write.
  return 'profile.error.writeUnconfirmed';
}

String localProfileFailureKey(Object error) => switch (error) {
  BridgeRemoteException(code: 'account.callsign_conflict') =>
    'profile.error.refreshBeforeSave',
  BridgeRemoteException(code: 'account.callsign_invalid') =>
    'profile.collab.invalid',
  BridgeRemoteException(code: 'account.callsign_unconfirmed') =>
    'profile.callsign.unconfirmed',
  BridgeRemoteException(code: 'account.callsign_unavailable') =>
    'profile.callsign.unavailable',
  BridgeRemoteException(code: 'personal_profile.write_forbidden') =>
    'profile.callsign.forbidden',
  BridgeCancelledException() => 'profile.callsign.cancelled',
  BridgeRemoteException(code: 'profile_local.conflict') =>
    'profile.error.refreshBeforeSave',
  BridgeRemoteException(code: 'profile_local.account_changed') ||
  BridgeStaleGenerationException() => 'profile.error.refreshBeforeSave',
  BridgeRemoteException(code: 'profile_local.hangar_changed') =>
    'profile.local.hangarChanged',
  BridgeRemoteException(code: 'profile_local.read_failed') =>
    'profile.local.readFailed',
  BridgeRemoteException(code: 'profile_local.invalid_request') =>
    'profile.collab.invalid',
  _ => 'profile.local.failed',
};
