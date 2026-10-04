import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import 'overlay_preset_transfer.dart';

abstract interface class OverlayPresetInspectionPort {
  Future<OverlayPresetTransfer> inspectPreset(String package, int revision);
}

/// Host owns WPF CSV interpretation. UI never reconstructs settings defaults
/// independently, and inspection uses the same parser as the subsequent import.
Future<OverlayPresetTransfer> inspectSharedOverlayPreset(
  BridgeClientSession session,
  String package,
  int revision,
) async {
  if (!session.hostCapabilities.contains('overlay.presetInspection')) {
    throw const FormatException('Preset inspection unavailable.');
  }
  final result = await session.request(
    'overlay.updateWorkspace',
    payload: {
      'schemaVersion': 1,
      'action': 'inspectSharedPreset',
      'package': package,
      'expectedRevision': revision,
    },
  );
  if (result.payload['schemaVersion'] != 1) throw const FormatException();
  return OverlayPresetTransfer.parse(jsonEncode(result.payload['preset']));
}
