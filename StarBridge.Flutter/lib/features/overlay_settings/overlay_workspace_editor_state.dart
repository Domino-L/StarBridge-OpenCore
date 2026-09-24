import 'package:flutter/widgets.dart';

/// Editing preferences are shared by the inline and fullscreen workspaces.
/// They are not persisted overlay settings and never create a draft revision.
final class OverlayWorkspaceEditorState extends ChangeNotifier {
  String? selectedKey;
  bool showGrid = true;
  bool snapToGrid = false;
  double gridSize = 16;
  bool smartSnap = true;
  bool layoutLocked = false;
  double nudgePixels = 1;
  bool toolsVisible = true;
  Offset? toolsPosition;
  bool fullscreenOpening = false;
  bool simulateInformation = true;
  Size fullscreenSurfaceSize = const Size(1920, 1080);
  bool _disposed = false;
  bool get disposed => _disposed;

  double get snapPixels => snapToGrid ? gridSize : 0;

  void change(VoidCallback update) {
    if (_disposed) return;
    update();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
