import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../shared/bounded_inline_avatar.dart';
import '../personal_profile/profile_read_failure.dart';
import 'account_models.dart';
import 'account_payload_decoder.dart';

/// Optional independent presentation lane. It never changes authentication,
/// profile freshness, preferences, identity policy or write authorization.
abstract interface class AccountAvatarReadPreparationPort {
  bool get supportsAvatarReadPreparation;
  Future<AccountAvatarReadResult?> prepareAvatarRead({bool retry = false});
  void cancelAvatarReadPreparation();
}

final class AccountAvatarReadResult {
  const AccountAvatarReadResult(
    this.owner,
    this.generation, {
    this.imageData,
    this.callSign,
    this.hasPresentation = false,
    this.retryable = false,
  });
  final BridgeAccountContext owner;
  final int generation;
  final String? imageData, callSign;
  final bool hasPresentation, retryable;
  bool matches(AccountRoute? route, int version) =>
      version == generation &&
      route?.environment == owner.environment &&
      route?.authority == owner.authority &&
      route?.subject == owner.subject;
  AccountProfile apply(AccountProfile? profile) =>
      (profile ?? const AccountProfile()).copyWith(
        displayName: callSign,
        avatarImageData: imageData,
        clearAvatarImageData: imageData == null,
      );
}

final class AccountAvatarReadPreparation {
  AccountAvatarReadPreparation(this.session);
  final BridgeClientSession session;
  BridgeRequestOperation? _operation;
  BridgeAccountContext? _owner;
  int _generation = -1, _epoch = 0;
  bool _attempted = false;
  AccountAvatarReadResult? confirmed;
  void restart() {
    cancel();
    _attempted = false;
  }

  /// A same-account refresh permits one more read, but never cancels the read
  /// already in flight: that read returns the current presentation anyway, and
  /// cancelling it left the shell without a call sign (2026-10-20 traces).
  void allowReread() {
    if (_operation == null) _attempted = false;
  }

  void invalidate() {
    cancel();
    _attempted = false;
    confirmed = null;
  }

  static bool _same(BridgeAccountContext? a, BridgeAccountContext? b) =>
      a != null &&
      b != null &&
      a.environment == b.environment &&
      a.authority == b.authority &&
      a.subject == b.subject;

  void cancel() {
    ++_epoch;
    final operation = _operation;
    _operation = null;
    if (operation != null) {
      _attempted = false;
      unawaited(operation.cancel());
    }
  }

  Future<AccountAvatarReadResult?> read(
    BridgeAccountContext owner,
    int generation, {
    bool retry = false,
  }) async {
    if (!_same(_owner, owner) || _generation != generation) {
      cancel();
      _owner = owner;
      _generation = generation;
      _attempted = false;
      confirmed = null;
    }
    if (_operation != null || _attempted && !retry) return null;
    _attempted = true;
    final epoch = _epoch;
    BridgeRequestOperation? operation;
    bool current() =>
        epoch == _epoch &&
        generation == session.activeGeneration &&
        _same(_owner, owner);
    try {
      operation = _operation = session.beginRequest(
        'account.readAvatar',
        payload: const {'schemaVersion': 1},
        accountContext: owner,
        timeout: const Duration(seconds: 60),
      );
      final response = await operation.future;
      if (!current()) return null;
      if (response.sessionGeneration != generation ||
          !_same(response.accountContext, owner) ||
          response.payload['schemaVersion'] != 1) {
        throw const BridgeFormatException('Invalid avatar owner');
      }
      final image = response.payload['imageData'],
          name = response.payload['callSign'];
      if (image != null && boundedInlineAvatar(image) == null ||
          name != null && AccountPayloadDecoder.displayCallSign(name) == null) {
        throw const BridgeFormatException('Invalid avatar presentation');
      }
      return confirmed = AccountAvatarReadResult(
        owner,
        generation,
        hasPresentation: true,
        imageData: image as String?,
        callSign: name as String?,
      );
    } on Object catch (error) {
      if (!current() || error is BridgeCancelledException) return null;
      if (profileReadIsTransient(error)) {
        return AccountAvatarReadResult(owner, generation, retryable: true);
      }
      // Denied or malformed media cannot remain visible as a current photo.
      return confirmed = AccountAvatarReadResult(
        owner,
        generation,
        hasPresentation: true,
      );
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }
}
