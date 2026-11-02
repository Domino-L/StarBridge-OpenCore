import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_payload_decoder.dart';

/// The verified transitional Relay path stays independent of SCM profile IO.
Future<AccountHostSnapshot> readLegacyAccountSnapshot(
  BridgeClientSession session,
  BridgeEnvelope envelope,
  AccountSessionState state,
  void Function(BridgeAccountContext) acceptContext,
) async {
  final context = envelope.accountContext;
  if (context == null || !context.authority.startsWith('starbridge-relay-')) {
    throw const BridgeFormatException(
      'Legacy account requires a distinct Relay authority.',
    );
  }
  acceptContext(context);
  var identity = const AccountIdentityProjection.unavailable();
  if (session.hostCapabilities.contains('account.read')) {
    try {
      final policy = await session.request(
        'gameIdentity.getPolicy',
        payload: const {'schemaVersion': 1},
        accountContext: context,
        timeout: const Duration(seconds: 60),
      );
      identity = AccountPayloadDecoder.identity(policy.payload);
    } on BridgeRemoteException {
      // Optional local identity cannot invalidate a restored Relay session.
    }
  }
  if (session.activeGeneration != envelope.sessionGeneration) {
    throw BridgeStaleGenerationException(
      envelope.sessionGeneration,
      session.activeGeneration,
    );
  }
  return AccountHostSnapshot(
    generation: envelope.sessionGeneration,
    sessionState: state,
    route: AccountRoute(
      environment: context.environment,
      authority: context.authority,
      subject: context.subject,
    ),
    profile: AccountProfile(
      displayName: envelope.payload['displayName'] as String?,
      maskedAccount: envelope.payload['maskedAccount'] as String?,
      avatarImageData: envelope.payload['avatarImageData'] as String?,
    ),
    profileFreshness: state == AccountSessionState.legacySignedIn
        ? AccountProfileFreshness.live
        : AccountProfileFreshness.cached,
    identity: identity,
    compatibility: const AccountCompatibilityProjection.unavailable(),
    localeOptions: const [],
    timeZoneOptions: const [],
  );
}
