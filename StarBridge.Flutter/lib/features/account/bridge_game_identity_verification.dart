import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'game_identity_verification.dart';

/// Opening a flow fixes its session generation and the first read fixes its
/// account. Later steps only check them again: a verification started for one
/// session can never be submitted for whichever session is current later.
final class BridgeGameIdentityVerification
    implements GameIdentityVerificationPort {
  BridgeGameIdentityVerification(this._session);
  final BridgeClientSession _session;
  int? _flowGeneration;
  BridgeAccountContext? _flowOwner;

  static const capability = 'account.gameIdentity.v1';
  // The Host allows 30 s for the write and 10 s to read the outcome back.
  static const _timeout = Duration(seconds: 50);

  @override
  bool get supportsGameIdentityVerification =>
      _session.hostCapabilities.contains(capability);

  @override
  Stream<void> get supportChanges => _session.capabilitiesChanged;

  @override
  void beginFlow() {
    _flowGeneration = _session.activeGeneration;
    _flowOwner = null;
  }

  // Checked with no await before the send: a request takes the generation
  // that is active at the moment it is sent.
  bool get _flowCurrent => _flowGeneration == _session.activeGeneration;

  @override
  Future<GameIdentityResult> requestVerificationCode(String handle) => _send(
    'account.gameIdentity.requestCode',
    {'gameName': handle.trim()},
    const {
      GameIdentityOutcome.issued,
      GameIdentityOutcome.rejected,
      GameIdentityOutcome.alreadyVerified,
      GameIdentityOutcome.reauthorizationRequired,
      GameIdentityOutcome.unavailable,
    },
  );

  @override
  Future<GameIdentityResult> submitVerification(
    String handle,
    String contact,
  ) => _send(
    'account.gameIdentity.verify',
    {'gameName': handle.trim(), 'contact': contact.trim()},
    const {
      GameIdentityOutcome.verified,
      GameIdentityOutcome.rejected,
      GameIdentityOutcome.alreadyVerified,
      GameIdentityOutcome.reauthorizationRequired,
      GameIdentityOutcome.unavailable,
      GameIdentityOutcome.outcomeUnknown,
    },
    // A lost response may follow a committed write.
    onFailure: GameIdentityOutcome.outcomeUnknown,
  );

  @override
  Future<bool> openRsiProfile() async {
    final owner = await _owner();
    if (owner == null || !_flowCurrent) return false;
    try {
      final response = await _session.request(
        'account.gameIdentity.openRsiProfile',
        accountContext: owner,
        payload: const {'schemaVersion': 1},
      );
      return response.payload['schemaVersion'] == 1 &&
          response.payload['opened'] == true;
    } on Object {
      return false;
    }
  }

  Future<BridgeAccountContext?> _owner() async {
    if (!supportsGameIdentityVerification || !_flowCurrent) return null;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final owner = account.accountContext;
      if (account.payload['schemaVersion'] != 1 ||
          account.payload['state'] != 'signedIn' ||
          owner == null ||
          account.sessionGeneration != _session.activeGeneration) {
        return null;
      }
      final bound = _flowOwner ??= owner;
      return _flowCurrent &&
              bound.environment == owner.environment &&
              bound.authority == owner.authority &&
              bound.subject == owner.subject
          ? owner
          : null;
    } on Object {
      return null;
    }
  }

  Future<GameIdentityResult> _send(
    String name,
    Map<String, Object?> fields,
    Set<GameIdentityOutcome> allowed, {
    GameIdentityOutcome onFailure = GameIdentityOutcome.unavailable,
  }) async {
    final owner = await _owner();
    if (owner == null || !_flowCurrent) {
      return const GameIdentityResult(GameIdentityOutcome.unavailable);
    }
    try {
      final response = await _session.request(
        name,
        accountContext: owner,
        payload: {'schemaVersion': 1, ...fields},
        timeout: _timeout,
      );
      return decodeGameIdentityResult(response.payload, allowed) ??
          GameIdentityResult(onFailure);
    } on Object {
      return GameIdentityResult(onFailure);
    }
  }
}

/// Null when the reply is not one this step may produce.
GameIdentityResult? decodeGameIdentityResult(
  Map<String, Object?> payload,
  Set<GameIdentityOutcome> allowed,
) {
  if (payload['schemaVersion'] != 1) return null;
  final name = payload['outcome'];
  final outcome = GameIdentityOutcome.values
      .where((value) => value.name == name)
      .firstOrNull;
  if (outcome == null || !allowed.contains(outcome)) return null;
  if (outcome == GameIdentityOutcome.issued) {
    final code = payload['verificationCode'],
        expires = payload['expiresInSeconds'];
    if (code is! String || code.isEmpty || code.length > 256) return null;
    if (expires is! int || expires <= 0) return null;
    return GameIdentityResult(
      outcome,
      verificationCode: code,
      expiresInSeconds: expires,
    );
  }
  final message = payload['message'];
  return GameIdentityResult(
    outcome,
    message: outcome == GameIdentityOutcome.rejected && message is String
        ? message
        : null,
  );
}
