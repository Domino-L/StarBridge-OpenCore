import 'package:flutter/foundation.dart';

/// Overlay hotkey as the Host reports it; split out of the workspace models
/// to keep that file under the architecture line limit.
@immutable
final class OverlayWorkspaceHotkey {
  const OverlayWorkspaceHotkey({
    required this.binding,
    required this.enabled,
    required this.runtimeState,
    this.registerHotKey,
  });

  final String binding;
  final bool enabled;
  final String runtimeState;

  /// Off by default: shortcuts are read through Raw Input. null: not reported.
  final bool? registerHotKey;

  factory OverlayWorkspaceHotkey.fromMap(Map<String, Object?> source) {
    const fields = <String>{'binding', 'enabled', 'runtimeState'};
    final binding = source['binding'];
    final enabled = source['enabled'];
    final runtimeState = source['runtimeState'];
    final registerHotKey = source['registerHotKey'];
    final keys = source.keys.toSet()..remove('registerHotKey');
    if (!setEquals(keys, fields) ||
        (source.containsKey('registerHotKey') && registerHotKey is! bool) ||
        binding is! String ||
        binding.isEmpty ||
        enabled is! bool ||
        runtimeState is! String ||
        runtimeState.isEmpty) {
      throw const FormatException('Invalid overlay hotkey state.');
    }
    return OverlayWorkspaceHotkey(
      binding: binding,
      enabled: enabled,
      runtimeState: runtimeState,
      registerHotKey: registerHotKey as bool?,
    );
  }

  Map<String, Object?> toUpdateMap() => {
    'binding': binding,
    'enabled': enabled,
    if (registerHotKey != null) 'registerHotKey': registerHotKey,
  };
}
