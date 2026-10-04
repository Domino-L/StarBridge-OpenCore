import 'privacy_publication_port.dart';

/// Shared by shell and settings. Only transport evidence names a cause; a
/// missing receipt is not proof of a server outage or an offline computer.
String? sharingStatusIssue(PrivacyPublicationView view, int savedRevision) {
  if (view.state == 'withdrawalPending') return 'withdrawal';
  if (view.state == 'withdrawn') return 'paused';
  if (view.state == 'applied' && view.revision == savedRevision) return null;
  final reason = switch (view.errorCode) {
    'privacy_publication.consent_required' => 'consent',
    'privacy_publication.identity_pending' => 'identityPending',
    'privacy_publication.identity_required' => 'identity',
    'privacy_publication.identity_unavailable' => 'signIn',
    'privacy_publication.forbidden' => 'permission',
    'privacy_publication.response_invalid' ||
    'privacy_publication.route_retired' => 'contract',
    'privacy_local.read_failed' || 'privacy_local.write_failed' => 'local',
    _ => null,
  };
  if (reason != null) return reason;
  if (view.state == 'reconnecting') {
    return switch (view.errorCode) {
      'privacy_publication.network_unavailable' => 'network',
      'privacy_publication.timeout' => 'timeout',
      'privacy_publication.server_error' => 'server',
      'privacy_publication.rate_limited' => 'rateLimited',
      _ => 'reconnecting',
    };
  }
  return switch (view.state) {
    'failed' => 'failed',
    'identityRequired' => 'identity',
    _ => 'waiting',
  };
}

const recoveringSharingIssues = {
  'reconnecting',
  'network',
  'timeout',
  'server',
  'rateLimited',
};
