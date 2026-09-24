import 'bridge_envelope.dart';

/// Existing Relay and local domains accept a real legacy login independently
/// of SCM. SCM-only adapters must continue checking their own signedIn state.
bool hasRelayAccount(BridgeEnvelope account) =>
    account.payload['schemaVersion'] == 1 &&
    account.accountContext != null &&
    (account.payload['state'] == 'signedIn' ||
        (account.payload['state'] == 'legacySignedIn' &&
            account.accountContext!.authority.startsWith('starbridge-relay-')));
