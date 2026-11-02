import 'privacy_publication_port.dart';

/// Shared by shell and settings. Only transport evidence names a cause; a
/// missing receipt is not proof of a server outage or an offline computer.
String? sharingStatusIssue(PrivacyPublicationView view, int savedRevision) {
  if (view.state == 'withdrawalPending') return 'withdrawal';
  if (view.state == 'withdrawn') return 'paused';
  if (view.state == 'applied' && view.revision == savedRevision) return null;
  // Temporary session expiry also waits for the Host's existing recovery;
  // reconnecting must never ask the user to sign in or imply a manual pause.
  if (view.state == 'reconnecting' &&
      (view.errorCode == 'privacy_publication.identity_unavailable' ||
          view.errorCode == 'account.reauthorization_required')) {
    return 'reconnecting';
  }
  final reason = switch (view.errorCode) {
    'privacy_publication.consent_required' => 'consent',
    'privacy_publication.identity_pending' => 'identityPending',
    'privacy_publication.identity_required' => 'identity',
    'privacy_publication.identity_unavailable' ||
    'account.reauthorization_required' => 'signIn',
    'privacy_publication.forbidden' => 'permission',
    'privacy_publication.rejected' => 'rejected',
    'privacy_publication.response_invalid' => 'contract',
    'privacy_publication.route_retired' => 'retired',
    'privacy_publication.unavailable' => 'service',
    'privacy_local.owner_unavailable' || 'privacy_local.read_unavailable' => 'localRecovering',
    'privacy_local.read_failed' || 'privacy_local.write_failed' => 'local',
    _ => null,
  };
  if (reason != null) return reason;
  if (view.state == 'reconnecting') {
    return switch (view.errorCode) {
      'privacy_publication.network_unavailable' => 'network',
      'privacy_publication.timeout' ||
      'privacy_publication.server_error' ||
      'privacy_publication.rate_limited' => 'network',
      _ => 'service',
    };
  }
  return switch (view.state) {
    'failed' => 'failed',
    'identityRequired' => 'identity',
    _ => 'waiting',
  };
}

const recoveringSharingIssues = {
  'localRecovering',
  'reconnecting',
  'network',
  'timeout',
  'server',
  'rateLimited',
};

