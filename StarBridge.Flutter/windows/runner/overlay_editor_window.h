#ifndef RUNNER_OVERLAY_EDITOR_WINDOW_H_
#define RUNNER_OVERLAY_EDITOR_WINDOW_H_

#include <windows.h>
#include <optional>

// Presentation mode for the Flutter editor, independent of the game HUD.
class OverlayEditorWindow {
 public:
  explicit OverlayEditorWindow(HWND window) : window_(window) {}
  ~OverlayEditorWindow();
  bool Enter();
  bool Exit();
  bool active() const { return snapshot_.has_value(); }
  void OnActivate(bool active);
  void FitMonitor();

 private:
  struct Snapshot {
    WINDOWPLACEMENT placement{};
    LONG_PTR style = 0;
  };
  void MarkFullscreen(bool enabled);
  HWND window_;
  std::optional<Snapshot> snapshot_;
};

#endif
