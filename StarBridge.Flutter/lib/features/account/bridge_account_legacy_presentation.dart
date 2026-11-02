import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_payload_decoder.dart';

/// Compatibility reads for Hosts without the phased account presentation path.
Future<AccountProfile> readLegacyAccountAvatar(
  BridgeClientSession session,
  BridgeAccountContext context,
  BridgeEnvelope account,
  AccountProfile profile,
  Duration timeout,
) async {
  if (!session.hostCapabilities.contains('account.avatar.read')) return profile;
  final fallback = profile.copyWith(
    displayName: AccountPayloadDecoder.displayCallSign(
      account.payload['displayName'],
    ),
    avatarImageData: account.payload['avatarImageData'] as String?,
  );
  try {
    final response = await session.request(
      'account.readAvatar',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      timeout: timeout,
    );
    AccountPayloadDecoder.requireSchema(response.payload);
    return profile.copyWith(
      displayName: AccountPayloadDecoder.displayCallSign(
        response.payload['callSign'],
      ),
      avatarImageData: response.payload['imageData'] as String?,
    );
  } on BridgeRemoteException {
    return fallback;
  } on BridgeTimeoutException {
    return fallback;
  }
}

Future<AccountCompatibilityProjection> readLegacyAccountCompatibility(
  BridgeClientSession session,
  BridgeAccountContext context,
  Duration timeout,
) async {
  if (!session.hostCapabilities.contains('account.compatibility.read')) {
    return const AccountCompatibilityProjection.retired();
  }
  try {
    final response = await session.request(
      'account.getCompatibilityState',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      timeout: timeout,
    );
    return AccountPayloadDecoder.compatibility(
      response.payload,
      canLinkExisting: session.hostCapabilities.contains(
        'account.compatibility.linkExisting',
      ),
    );
  } on BridgeRemoteException catch (error) {
    if (error.code != 'account.compatibility_read_unavailable' &&
        error.code != 'bridge.capability_unavailable') {
      rethrow;
    }
    return const AccountCompatibilityProjection.unavailable();
  }
}

Future<void> waitForAccountGenerationAdvance(
  BridgeClientSession session,
  int previousGeneration,
) async {
  if (session.activeGeneration > previousGeneration) {
    return;
  }

  final completion = Completer<void>();
  final subscription = session.events.listen((_) {
    if (session.activeGeneration > previousGeneration &&
        !completion.isCompleted) {
      completion.complete();
    }
  });
  try {
    if (session.activeGeneration > previousGeneration) return;
    await completion.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw const BridgeTimeoutException('account.changed'),
    );
  } finally {
    await subscription.cancel();
  }
}
