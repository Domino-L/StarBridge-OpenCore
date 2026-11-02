import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';

AccountFailure mapAccountBridgeFailure(Object error) {
  if (error is BridgeClientException) {
    return AccountFailure(
      code: error.code,
      messageKey: _messageKeyForCode(error.code),
      retryable: error.retryable,
    );
  }
  if (error is BridgeFormatException) {
    return const AccountFailure(
      code: 'bridge.invalid_envelope',
      messageKey: 'account.error.invalidResponse',
      retryable: false,
    );
  }
  return const AccountFailure(
    code: 'account.unexpected',
    messageKey: 'account.error.unavailable',
    retryable: true,
  );
}

String _messageKeyForCode(String code) => switch (code) {
  'bridge.disconnected' => 'account.error.hostUnavailable',
  'bridge.timeout' || 'account.login_timeout' => 'account.error.timeout',
  'bridge.cancelled' || 'account.login_cancelled' => 'account.login.cancelled',
  'bridge.stale_generation' => 'account.error.sessionChanged',
  'account.environment_not_enabled' => 'account.error.environmentNotEnabled',
  'account.reauthorization_required' => 'account.error.reauthorizationRequired',
  'account.logout_incomplete' => 'account.error.logoutIncomplete',
  'profile.write_forbidden' => 'account.error.writeForbidden',
  'profile.read_forbidden' => 'account.error.profileReadForbidden',
  'profile.data_invalid' => 'account.error.invalidResponse',
  'bridge.capability_unavailable' => 'account.action.unavailable',
  'profile.cache_clear_unavailable' => 'account.cache.failed',
  'profile.write_conflict' => 'account.error.writeConflict',
  'profile.directory_unavailable' => 'account.error.directoryUnavailable',
  'account.compatibility_read_unavailable' =>
    'account.error.compatibilityUnavailable',
  'account.compatibility_write_unavailable' =>
    'account.error.compatibilityWriteUnavailable',
  'account.legacy_proof_unavailable' => 'account.error.legacyProofUnavailable',
  'account.compatibility_conflict' => 'account.error.compatibilityConflict',
  'account.compatibility_proof_rejected' =>
    'account.error.compatibilityProofRejected',
  'account.compatibility_existing_link_mismatch' =>
    'account.error.compatibilityExistingLinkMismatch',
  'account.legacy_credentials_required' =>
    'account.error.legacyCredentialsRequired',
  'account.legacy_credentials_rejected' =>
    'account.error.legacyCredentialsRejected',
  'bridge.invalid_envelope' ||
  'bridge.protocol_incompatible' => 'account.error.invalidResponse',
  _ => 'account.error.unavailable',
};
