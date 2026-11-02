import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

bool fleetReadIsTransient(Object error) =>
    error is TimeoutException ||
    error is BridgeDisconnectedException ||
    error is BridgeClientException &&
        (error.code == 'bridge.timeout' ||
            error.code == 'official_fleet.read_transient' && error.retryable);

bool fleetReadLosesContext(Object error) =>
    error is BridgeClientException &&
    const {
      'account.reauthorization_required',
      'official_fleet.read_forbidden',
      'bridge.stale_generation',
      'bridge.account_context_required',
    }.contains(error.code);

String fleetReadFailureKey(Object error, {bool members = false}) {
  if (fleetReadIsTransient(error)) {
    return members
        ? 'officialFleet.members.error.transient'
        : 'officialFleet.error.transient';
  }
  if (error is BridgeClientException) {
    return switch (error.code) {
      'bridge.disconnected' => 'officialFleet.error.hostUnavailable',
      'account.reauthorization_required' =>
        'officialFleet.error.reauthorizationRequired',
      'official_fleet.read_forbidden' => 'officialFleet.error.forbidden',
      'official_fleet.data_invalid' ||
      'bridge.invalid_envelope' ||
      'bridge.protocol_incompatible' => 'officialFleet.error.invalidResponse',
      _ =>
        members
            ? 'officialFleet.members.error.unavailable'
            : 'officialFleet.error.unavailable',
    };
  }
  return error is BridgeFormatException
      ? 'officialFleet.error.invalidResponse'
      : members
      ? 'officialFleet.members.error.unavailable'
      : 'officialFleet.error.unavailable';
}
