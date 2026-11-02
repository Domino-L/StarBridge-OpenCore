import '../../platform/bridge/bridge_client_session.dart';
import '../account/game_identity_verification.dart';
import 'bridge_first_use_game_identity.dart';
import 'online_review_port.dart';

// A narrow native route, not the complete firstUse capability or entry policy.
final class BridgeOnlineReviewAdapter
    implements OnlineReviewPort, OnlineReviewGameIdentitySource {
  BridgeOnlineReviewAdapter(this.session, {this.onModeChanged});
  final Future<void> Function()? onModeChanged;
  static const capability = 'onboarding.onlineReview.v1';
  static const retainedCapability = 'onboarding.onlineReview.v2';
  static const reauthorizationCapability =
      'onboarding.onlineReauthorization.v1';
  bool get _v2 => session.hostCapabilities.contains(retainedCapability);
  bool get _available => _v2 || session.hostCapabilities.contains(capability);
  final BridgeClientSession session;
  @override
  late final GameIdentityVerificationPort gameIdentity =
      BridgeFirstUseGameIdentity(session, () => _current?.revision);
  OnlineReviewSnapshot? _current;
  String? _key;
  int? _generation;
  bool? _observedV2;
  _OnlineAuthCancellation? _authWait;
  int _epoch = 0;
  void _invalidate() {
    _epoch++;
    _current = null;
    _key = null;
    _generation = null;
    _observedV2 = null;
  }

  @override
  Stream<void> get invalidations => session.events
      .where(
        (e) => const {
          'account.changed',
          'bootstrap.invalidated',
          'onboarding.changed',
          'gameLog.changed',
        }.contains(e.name),
      )
      .map((_) {
        _invalidate();
      });
  @override
  Future<OnlineReviewSnapshot> read() async {
    if (!_available) {
      _invalidate();
      return const OnlineReviewSnapshot();
    }
    return _request('read', const {});
  }

  @override
  Future<OnlineReviewSnapshot> execute(
    OnlineReviewAction action,
    int revision, {
    String? confirmationKey,
  }) {
    final waiting = _authWait;
    if (action == OnlineReviewAction.cancel && waiting != null) {
      // A same-generation notification revokes review facts, not the original
      // outstanding authentication request's narrow cancellation provenance.
      if (!_available ||
          waiting.generation != session.activeGeneration ||
          waiting.v2 != _v2 ||
          waiting.revision != revision ||
          waiting.cancelling) {
        throw StateError('Authentication cancellation is no longer current.');
      }
      waiting.cancelling = true;
      _key = null;
      return _cancelAuthentication(waiting);
    }
    final current = _current;
    if (!_available ||
        current == null ||
        _generation != session.activeGeneration ||
        _observedV2 != _v2 ||
        current.revision != revision ||
        !(switch (action) {
          OnlineReviewAction.begin => current.canBegin,
          OnlineReviewAction.login => current.canLogin,
          OnlineReviewAction.resume => _v2 && current.canResume,
          OnlineReviewAction.reauthorize =>
            _v2 &&
                current.canReauthorize &&
                session.hostCapabilities.contains(reauthorizationCapability),
          OnlineReviewAction.review => current.canReview,
          OnlineReviewAction.confirm =>
            current.canConfirm && confirmationKey == _key && _key != null,
          OnlineReviewAction.cancel => current.canCancel,
        })) {
      throw StateError('Online review observation is no longer current.');
    }
    // Keep only the observed mode revision for cancelling an in-flight login;
    // the confirmation key is consumed before any asynchronous write starts.
    _key = null;
    if (action == OnlineReviewAction.login ||
        action == OnlineReviewAction.resume ||
        action == OnlineReviewAction.reauthorize) {
      if (waiting != null) {
        throw StateError('Authentication is already pending.');
      }
      final receipt = _OnlineAuthCancellation(
        session.activeGeneration,
        _v2,
        revision,
      );
      _authWait = receipt;
      return _authenticate(action, receipt);
    }
    return _request(action.name, {
      'revision': revision,
      if (action == OnlineReviewAction.confirm)
        'confirmationKey': confirmationKey,
    });
  }

  Future<OnlineReviewSnapshot> _authenticate(
    OnlineReviewAction action,
    _OnlineAuthCancellation receipt,
  ) async {
    try {
      return await _request(action.name, {'revision': receipt.revision});
    } finally {
      // An original cancellation already in flight still owns its real ack.
      if (identical(_authWait, receipt) && !receipt.cancelling) {
        _authWait = null;
      }
    }
  }

  Future<OnlineReviewSnapshot> _cancelAuthentication(
    _OnlineAuthCancellation receipt,
  ) async {
    try {
      return await _request('cancel', {'revision': receipt.revision});
    } finally {
      if (identical(_authWait, receipt)) _authWait = null;
    }
  }

  Future<OnlineReviewSnapshot> _request(
    String action,
    Map<String, Object?> payload,
  ) async {
    final epoch = ++_epoch;
    final generation = session.activeGeneration;
    final v2 = _v2;
    try {
      final response = await session.request(
        'onboarding.onlineReview.${v2 ? 'v2.' : ''}$action',
        payload: {'schemaVersion': v2 ? 2 : 1, ...payload},
        // Browser authorization and actual cleanup can exceed ordinary reads.
        timeout: const Duration(minutes: 5),
      );
      if (epoch != _epoch ||
          generation != session.activeGeneration ||
          response.sessionGeneration != generation ||
          response.accountContext != null ||
          v2 != _v2 ||
          action == 'reauthorize' &&
              !session.hostCapabilities.contains(reauthorizationCapability) ||
          !_available ||
          response.status != 'ok' ||
          response.error != null) {
        throw StateError('Online review request was not confirmed.');
      }
      final value = OnlineReviewWire.parse(
        response.payload,
        retainedProtocol: v2,
        reauthorizationSupported:
            v2 && session.hostCapabilities.contains(reauthorizationCapability),
      );
      _current = value;
      _key = value.confirmationKey;
      _generation = generation;
      _observedV2 = v2;
      if (action == 'begin' || action == 'cancel') {
        await onModeChanged?.call();
        if (epoch != _epoch || generation != session.activeGeneration) {
          throw StateError('Online review changed during mode refresh.');
        }
      }
      return value;
    } on Object {
      if (epoch == _epoch) _invalidate();
      rethrow;
    }
  }
}

// UI transport provenance only, never a Native physical-exit/installation proof.
final class _OnlineAuthCancellation {
  _OnlineAuthCancellation(this.generation, this.v2, this.revision);
  final int generation, revision;
  final bool v2;
  bool cancelling = false;
}

abstract final class OnlineReviewWire {
  static OnlineReviewSnapshot parse(
    Map<String, Object?> raw, {
    bool retainedProtocol = false,
    bool reauthorizationSupported = false,
  }) {
    _shape(raw, {
      'schemaVersion',
      'revision',
      'modeState',
      'identity',
      if (retainedProtocol) 'retainsSession',
    });
    if (raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != (retainedProtocol ? 2 : 1) ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        (raw['revision'] as int) > 9223372036854775807) {
      _bad();
    }
    final mode = _enum(raw['modeState'], OnlineReviewModeState.values);
    final retained = retainedProtocol ? raw['retainsSession'] : false;
    if (retained is! bool ||
        mode == OnlineReviewModeState.offline && !retained ||
        retained &&
            (mode == OnlineReviewModeState.local ||
                mode == OnlineReviewModeState.online)) {
      _bad();
    }
    final value = raw['identity'];
    if (value is! Map<String, Object?>) _bad();
    _shape(value, const {
      'state',
      'localHandle',
      'authoritativeHandle',
      'accountDisplayName',
      'confirmationKey',
    });
    final state = _enum(value['state'], OnlineReviewState.values);
    final local = _handle(value['localHandle']),
        remote = _handle(value['authoritativeHandle']);
    final display = value['accountDisplayName'], key = value['confirmationKey'];
    if (display != null &&
            (display is! String ||
                display.trim().isEmpty ||
                display.length > 128 ||
                RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(display)) ||
        key != null &&
            (key is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(key))) {
      _bad();
    }
    final reviewed = state == OnlineReviewState.reviewRequired;
    final accountReviewed = state == OnlineReviewState.accountReviewRequired;
    final installedReviewed =
        state == OnlineReviewState.installedReviewRequired;
    if ((reviewed || accountReviewed || installedReviewed) != (key != null) ||
        (accountReviewed ||
                state == OnlineReviewState.accountConfirmedForHandoff) &&
            (!retained ||
                mode != OnlineReviewModeState.signInRequired ||
                local != null) ||
        (installedReviewed || state == OnlineReviewState.boundOnlineIdentity) &&
            (mode != OnlineReviewModeState.online ||
                local == null ||
                remote == null ||
                local.toLowerCase() != remote.toLowerCase()) ||
        (reviewed || state == OnlineReviewState.confirmedForHandoff) &&
            (mode != OnlineReviewModeState.signInRequired ||
                local == null ||
                remote == null ||
                local.toLowerCase() != remote.toLowerCase()) ||
        (mode == OnlineReviewModeState.local ||
                mode == OnlineReviewModeState.offline) &&
            state != OnlineReviewState.notStarted) {
      _bad();
    }
    return OnlineReviewSnapshot(
      revision: raw['revision'] as int,
      modeState: mode,
      state: state,
      localHandle: local,
      authoritativeHandle: remote,
      accountDisplayName: display as String?,
      confirmationKey: key as String?,
      retainsSession: retained,
      reauthorizationSupported: retainedProtocol && reauthorizationSupported,
    );
  }

  static T _enum<T extends Enum>(Object? value, List<T> values) =>
      values.where((s) => s.name == value).singleOrNull ?? _bad();
  static void _shape(Map<String, Object?> raw, Set<String> fields) {
    if (raw.length != fields.length || !fields.every(raw.containsKey)) _bad();
  }

  static String? _handle(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(r'^[\p{L}\p{N}_.-]{2,64}$', unicode: true).hasMatch(value)) {
      _bad();
    }
    return value;
  }

  static Never _bad() =>
      throw const FormatException('Invalid online review projection.');
}
