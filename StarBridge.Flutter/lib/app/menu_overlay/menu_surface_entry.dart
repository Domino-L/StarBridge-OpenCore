import 'dart:io';

import 'package:flutter/widgets.dart';

import '../diagnostics/loading_diagnostics.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'menu_overlay_surface_app.dart';

// No account/bootstrap, plugins or Host. Only the existing explicit diagnostic
// opt-in may write a bounded trace, just as for the other auxiliary engines.
void runMenuOverlaySurface({bool workspacePreview = false}) {
  LoadingDiagnostics.runAuxiliary(
    Platform.environment,
    LoadingAuxiliarySurface.menu,
    () => runApp(MenuOverlaySurfaceApp(workspacePreview: workspacePreview)),
  );
}
