import '../../platform/bridge/bridge_client_session.dart';
import 'personal_profile_public_header.dart';
import 'profile_read_scope.dart';

const visitorAccountFactsCapability = 'personalProfile.visitorAccountFacts.v1';

/// Host has already applied lastOnlineVisible and resolved the UTC offset.
/// Malformed optional decoration must never fail the authorized page.
PersonalProfilePublicFacts? parseAccountFacts(Object? value) {
  try {
    return value is Map<String, Object?>
        ? PersonalProfilePublicFacts.parse(value)
        : null;
  } on Object {
    return null;
  }
}

Future<PersonalProfilePublicFacts?> readProfileAccountFacts(
  BridgeClientSession session,
) async {
  const capability = 'personalProfile.accountFacts.read.v1';
  if (!session.hostCapabilities.contains(capability)) return null;
  final generation = session.activeGeneration;
  final mode = session.connectionModeRevision;
  try {
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    ProfileReadScope.requireSchema(account.payload);
    if (account.payload['state'] != 'signedIn' ||
        account.accountContext == null ||
        account.sessionGeneration != generation ||
        session.activeGeneration != generation ||
        session.connectionModeRevision != mode ||
        !session.hostCapabilities.contains(capability)) {
      return null;
    }
    final response = await session.request(
      'personalProfile.readAccountFacts',
      payload: const {'schemaVersion': 1},
      accountContext: account.accountContext,
    );
    ProfileReadScope.fromAccountFactsResponse(
      account,
      response,
      session.activeGeneration,
    );
    ProfileReadScope.requireSchema(response.payload);
    if (session.activeGeneration != generation ||
        session.connectionModeRevision != mode ||
        !session.hostCapabilities.contains(capability) ||
        response.payload.length != 2 ||
        !response.payload.containsKey('facts')) {
      return null;
    }
    final facts = response.payload['facts'];
    return parseAccountFacts(facts);
  } on Object {
    // This optional projection must never fail the personal page.
    return null;
  }
}
