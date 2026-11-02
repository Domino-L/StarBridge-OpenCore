import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'onboarding_profile_port.dart';

/// Reads and renames the installed SCM account through the existing account
/// requests. The avatar shown is what `account.readAvatar` returns for SCM
/// sessions: the RSI avatar, never a stored upload.
final class BridgeOnboardingProfileAdapter implements OnboardingProfilePort {
  BridgeOnboardingProfileAdapter(this.session) {
    _subscription = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _owner = null;
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  final _invalidations = StreamController<void>.broadcast();
  BridgeAccountContext? _owner;
  int? _generation;

  @override
  Stream<void> get invalidations => _invalidations.stream;

  bool get _canRename => session.hostCapabilities.contains('account.callSign');

  void _current(BridgeEnvelope response) {
    final owner = response.accountContext;
    if (_owner == null ||
        _generation != session.activeGeneration ||
        owner == null ||
        owner.subject != _owner!.subject ||
        owner.authority != _owner!.authority ||
        owner.environment != _owner!.environment ||
        response.payload['schemaVersion'] != 1) {
      throw const FormatException('Account changed');
    }
  }

  @override
  Future<OnboardingProfileSnapshot?> read() async {
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    final context = account.accountContext;
    if (account.payload['state'] != 'signedIn' ||
        context == null ||
        account.sessionGeneration != session.activeGeneration) {
      _owner = null;
      return null;
    }
    _owner = context;
    _generation = session.activeGeneration;
    final avatar = await session.request(
      'account.readAvatar',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      timeout: const Duration(seconds: 45),
    );
    _current(avatar);
    final name = avatar.payload['callSign'] ?? account.payload['displayName'];
    if (name is! String || !validOnboardingCallSign(name)) {
      throw const FormatException('No display name');
    }
    final image = avatar.payload['imageData'];
    return OnboardingProfileSnapshot(
      callSign: name,
      avatarImageData: image is String ? image : null,
      canRename: _canRename,
      canOpenRsi: session.hostCapabilities.contains(
        'helpSupport.openRsiProfileSettings',
      ),
    );
  }

  @override
  Future<String> saveCallSign(String expected, String next) async {
    final owner = _owner;
    if (owner == null ||
        !_canRename ||
        _generation != session.activeGeneration) {
      throw const OnboardingProfileSaveException(
        'profile.save.unavailable',
        conflict: true,
      );
    }
    try {
      // The Host may ask for a one-time write grant in the browser.
      final response = await session.request(
        'account.updateCallSign',
        accountContext: owner,
        timeout: const Duration(minutes: 5),
        payload: {
          'schemaVersion': 1,
          'expectedCallSign': expected,
          'callSign': next,
        },
      );
      _current(response);
      if (response.payload['callSign'] != next) throw const FormatException();
      return next;
    } on OnboardingProfileSaveException {
      rethrow;
    } on Object catch (error) {
      throw switch (error) {
        BridgeRemoteException(code: 'account.callsign_conflict') =>
          const OnboardingProfileSaveException(
            'profile.save.conflict',
            conflict: true,
          ),
        BridgeRemoteException(code: 'account.callsign_invalid') =>
          const OnboardingProfileSaveException('profile.save.invalid'),
        BridgeRemoteException(code: 'personal_profile.write_forbidden') =>
          const OnboardingProfileSaveException('profile.save.forbidden'),
        BridgeCancelledException() => const OnboardingProfileSaveException(
          'profile.save.cancelled',
        ),
        // Unconfirmed: the Host could not prove the result either way.
        BridgeRemoteException(code: 'account.callsign_unconfirmed') =>
          const OnboardingProfileSaveException(
            'profile.save.unconfirmed',
            conflict: true,
          ),
        _ => const OnboardingProfileSaveException('profile.save.failed'),
      };
    }
  }

  @override
  Future<void> openRsiProfile() async {
    final response = await session.request(
      'helpSupport.openRsiProfileSettings',
      payload: const {'schemaVersion': 1},
    );
    if (response.status != 'ok') throw const FormatException();
  }

  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_invalidations.close());
  }
}
