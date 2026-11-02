import 'package:flutter/material.dart';

import 'overlay_appearance_live_session.dart';
import 'overlay_appearance_preview_page.dart';
import 'overlay_workspace_module.dart';

final _opening = Expando<bool>('appearance-preview-route');

/// Uses the primary fullscreen mechanism; no extra HWND or saved skin change.
Future<void> showOverlayAppearancePreviewPage(
  BuildContext context, {
  required OverlayWorkspaceModule module,
  required OverlayAppearanceLivePort port,
  required String appearanceId,
  bool readOnly = false,
}) async {
  if (_opening[module] == true) return;
  if (port is! OverlayAppearanceLiveControlsPort ||
      !module.projection.value.available) {
    throw StateError('Live preview unavailable.');
  }
  _opening[module] = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  var entered = false;
  try {
    await module.editorWindow.enter();
    entered = true;
    if (!navigator.mounted || !module.projection.value.available) return;
    await navigator.push<void>(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => OverlayAppearancePreviewPage(
          module: module,
          port: port,
          appearanceId: appearanceId,
          readOnly: readOnly,
        ),
      ),
    );
  } finally {
    try {
      if (entered) await module.editorWindow.exit();
    } finally {
      _opening[module] = false;
    }
  }
}
