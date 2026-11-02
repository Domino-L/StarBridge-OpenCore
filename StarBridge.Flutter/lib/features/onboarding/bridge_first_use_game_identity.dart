import '../../platform/bridge/bridge_client_session.dart';
import '../account/bridge_game_identity_verification.dart';
import '../account/game_identity_verification.dart';

/// The same verification for the staged first-use account. That account is not
/// installed yet, so requests carry no account context; the mode revision and
/// session generation fixed when the flow opens name the owner instead.
final class BridgeFirstUseGameIdentity implements GameIdentityVerificationPort {
  BridgeFirstUseGameIdentity(this._session, this._revision);
  final BridgeClientSession _session;
  final int? Function() _revision;
  int? _flowGeneration, _flowRevision;

  static const capability = 'onboarding.onlineReview.gameIdentity.v1';
  static const _timeout = Duration(seconds: 50);

  @override
  bool get supportsGameIdentityVerification =>
      _session.hostCapabilities.contains(capability);

  @override
  Stream<void> get supportChanges => _session.capabilitiesChanged;

  @override
  void beginFlow() {
    _flowGeneration = _session.activeGeneration;
    _flowRevision = _revision();
  }

  // Checked with no await before the send: a request takes the generation
  // that is active at the moment it is sent.
  bool get _flowCurrent =>
      supportsGameIdentityVerification &&
      _flowRevision != null &&
      _flowRevision == _revision() &&
      _flowGeneration == _session.activeGeneration;

  @override
  Future<GameIdentityResult> requestVerificationCode(String handle) => _send(
    'requestCode',
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
    'verify',
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
    if (!_flowCurrent) return false;
    try {
      final response = await _session.request(
        'onboarding.onlineReview.gameIdentity.openRsiProfile',
        payload: {'schemaVersion': 1, 'revision': _flowRevision},
      );
      return response.payload['schemaVersion'] == 1 &&
          response.payload['opened'] == true;
    } on Object {
      return false;
    }
  }

  Future<GameIdentityResult> _send(
    String action,
    Map<String, Object?> fields,
    Set<GameIdentityOutcome> allowed, {
    GameIdentityOutcome onFailure = GameIdentityOutcome.unavailable,
  }) async {
    if (!_flowCurrent) {
      return const GameIdentityResult(GameIdentityOutcome.unavailable);
    }
    try {
      final response = await _session.request(
        'onboarding.onlineReview.gameIdentity.$action',
        payload: {'schemaVersion': 1, 'revision': _flowRevision, ...fields},
        timeout: _timeout,
      );
      if (response.accountContext != null) return GameIdentityResult(onFailure);
      return decodeGameIdentityResult(response.payload, allowed) ??
          GameIdentityResult(onFailure);
    } on Object {
      return GameIdentityResult(onFailure);
    }
  }
}
