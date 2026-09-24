import 'package:flutter/foundation.dart';

import 'shell_chrome_projection.dart';

enum SceneSelectionResult { saved, hostUnavailable, rejected }

abstract interface class ShellChromePort {
  ValueListenable<ShellChromeProjection> get projection;

  Future<SceneSelectionResult> selectOverlayScene(String sceneId);
}
