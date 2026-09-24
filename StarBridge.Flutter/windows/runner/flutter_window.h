#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>

#include "win32_window.h"

class NativeHostBridge;
class ApplicationLifecycleBridge;
class HangarBrowserBridge;
class OverlayEditorWindow;
class MenuOverlayBridge;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  FlutterWindow(const flutter::DartProject& project, bool startup_launch);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static LRESULT CALLBACK FlutterViewWindowProc(HWND window,
                                                UINT const message,
                                                WPARAM const wparam,
                                                LPARAM const lparam) noexcept;

  std::optional<LRESULT> GetResizeHitTest(LPARAM const lparam) noexcept;
  void NotifyWindowStateChanged();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_chrome_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      gameplay_files_channel_;
  std::unique_ptr<NativeHostBridge> native_host_bridge_;
  std::unique_ptr<HangarBrowserBridge> hangar_browser_bridge_;
  std::unique_ptr<OverlayEditorWindow> overlay_editor_window_;
#ifdef STARBRIDGE_ENABLE_MENU_OVERLAY
  std::unique_ptr<MenuOverlayBridge> menu_overlay_bridge_;
#endif
  std::unique_ptr<ApplicationLifecycleBridge> application_lifecycle_bridge_;
  bool startup_launch_ = false;
  std::optional<bool> last_is_maximized_;
  HWND flutter_view_handle_ = nullptr;
  WNDPROC flutter_view_window_proc_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
