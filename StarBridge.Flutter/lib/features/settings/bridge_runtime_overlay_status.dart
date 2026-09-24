import '../../platform/bridge/bridge_client_session.dart';

final class RuntimeOverlayStatus {
  const RuntimeOverlayStatus({
    required this.windowState,
    required this.hotkeyState,
    required this.appliedRevision,
    this.hotkeyBinding,
  });
  final String windowState, hotkeyState;
  final String? hotkeyBinding;
  final int appliedRevision;
  bool get available => windowState != 'unavailable';
}

final class BridgeRuntimeOverlayStatus {
  BridgeRuntimeOverlayStatus(this.session);
  final BridgeClientSession session;
  Future<RuntimeOverlayStatus> read() async {
    final p = (await session.request(
      'diagnostics.getOverlayRuntimeStatus',
      payload: const {'schemaVersion': 1},
    )).payload;
    final binding = p['hotkeyBinding'], revision = p['appliedRevision'];
    if (p.length != 5 ||
        p['schemaVersion'] != 1 ||
        !p.containsKey('hotkeyBinding') ||
        !const {
          'open',
          'closed',
          'failed',
          'unavailable',
        }.contains(p['windowState']) ||
        !const {
          'unavailable',
          'disabled',
          'invalid',
          'registered',
          'gameCompatibleOnly',
          'desktopOnly',
          'conflict',
          'failed',
        }.contains(p['hotkeyState']) ||
        revision is! int ||
        revision < 0 ||
        binding != null &&
            (binding is! String ||
                binding.length > 128 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(binding))) {
      throw const FormatException('Incompatible overlay status.');
    }
    return RuntimeOverlayStatus(
      windowState: p['windowState'] as String,
      hotkeyState: p['hotkeyState'] as String,
      hotkeyBinding: binding as String?,
      appliedRevision: revision,
    );
  }
}
