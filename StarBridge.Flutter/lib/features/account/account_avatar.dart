import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../communities/community_logo_port.dart';

/// One image-selection transaction is pinned to one account and generation.
/// The existing native image boundary owns file access and image decoding.
final class AccountAvatarPort implements CommunityLogoPort {
  AccountAvatarPort(this.session);
  final BridgeClientSession session;
  BridgeAccountContext? _owner;
  int? _generation;

  @override
  bool get canPickLogo =>
      session.hostCapabilities.contains('account.avatar') &&
      session.hostCapabilities.contains('account.avatarImages');

  void _current() {
    if (_owner == null || _generation != session.activeGeneration) {
      throw const FormatException('Account changed');
    }
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> body,
  ) async {
    _current();
    final response = await session.request(
      name,
      payload: {'schemaVersion': 1, ...body},
      accountContext: _owner,
      timeout: name == 'account.pickAvatar'
          ? const Duration(minutes: 5)
          : const Duration(seconds: 45),
    );
    _current();
    if (response.payload['schemaVersion'] != 1) throw const FormatException();
    return response.payload;
  }

  @override
  Future<CommunityLogoSource?> pickLogo() async {
    if (!canPickLogo) throw const FormatException();
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (account.payload['state'] != 'legacySignedIn' ||
        account.accountContext == null ||
        account.sessionGeneration != session.activeGeneration) {
      throw const FormatException();
    }
    _owner = account.accountContext;
    _generation = session.activeGeneration;
    final response = await _request('account.pickAvatar', const {});
    if (response['status'] == 'cancelled') return null;
    final source = (response['source'] as Map).cast<String, Object?>();
    return CommunityLogoSource(
      source['sourceRef'] as String,
      source['previewImageData'] as String,
      source['width'] as int,
      source['height'] as int,
    );
  }

  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async =>
      (await _request('account.cropAvatar', {
            'sourceRef': sourceRef,
            'x': x,
            'y': y,
            'size': size,
          }))['imageData']
          as String;

  Future<void> save(String imageData) async {
    final result = await _request('account.updateAvatar', {
      'imageData': imageData,
    });
    if (result['imageData'] != imageData) throw const FormatException();
  }

  @override
  Future<void> clearLogo() async {
    if (_owner == null) return;
    try {
      await _request('account.clearAvatarDraft', const {});
    } finally {
      _owner = null;
      _generation = null;
    }
  }
}
