import '../bridge/bridge_client_session.dart';

final class MenuRecoverySession {
  const MenuRecoverySession(this.token, this.previousInterrupted);
  final String token;
  final bool previousInterrupted;
}

abstract interface class MenuRecoveryPort {
  Future<MenuRecoverySession> begin();
  Future<void> finish(String token);
}

final class BridgeMenuRecovery implements MenuRecoveryPort {
  const BridgeMenuRecovery(this.session);
  final BridgeClientSession session;
  @override
  Future<MenuRecoverySession> begin() async {
    final result = await session.request(
      'applicationPreferences.menu.begin',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 3),
    );
    final raw = result.payload;
    if (raw.length != 3 ||
        raw['schemaVersion'] != 1 ||
        raw['token'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(raw['token'] as String) ||
        raw['previousInterrupted'] is! bool) {
      throw const FormatException('Invalid recovery state');
    }
    return MenuRecoverySession(
      raw['token'] as String,
      raw['previousInterrupted'] as bool,
    );
  }

  @override
  Future<void> finish(String token) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(token)) {
      throw const FormatException('Invalid recovery token');
    }
    final result = await session.request(
      'applicationPreferences.menu.finish',
      payload: {'schemaVersion': 1, 'token': token},
      timeout: const Duration(seconds: 3),
    );
    if (result.payload.length != 2 ||
        result.payload['schemaVersion'] != 1 ||
        result.payload['clean'] != true) {
      throw const FormatException('Invalid recovery confirmation');
    }
  }
}
