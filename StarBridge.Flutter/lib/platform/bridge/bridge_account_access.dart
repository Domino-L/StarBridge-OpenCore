import 'bridge_envelope.dart';
import 'bridge_request_operation.dart';

/// Existing Relay and local domains accept a real legacy login independently
/// of SCM. SCM-only adapters must continue checking their own signedIn state.
bool hasRelayAccount(BridgeEnvelope account) =>
    account.payload['schemaVersion'] == 1 &&
    account.accountContext != null &&
    (account.payload['state'] == 'signedIn' ||
        (account.payload['state'] == 'legacySignedIn' &&
            account.accountContext!.authority.startsWith('starbridge-relay-')));

/// The Host still holds the account, but session recovery failed for a
/// temporary reason (network or server) and is waiting before retrying.
/// This is never a sign-in request.
bool accountTemporarilyUnavailable(BridgeEnvelope account) =>
    account.payload['schemaVersion'] == 1 &&
    account.payload['state'] == 'credentialTemporarilyUnavailable';

const credentialTemporarilyUnavailableCode =
    'account.credential_temporarily_unavailable';

/// Same temporary state, reported by a business request instead of
/// `account.getCurrent`. Treat like a connection problem, not lost identity.
bool isCredentialTemporarilyUnavailable(Object error) =>
    error is BridgeClientException &&
    error.code == credentialTemporarilyUnavailableCode;
