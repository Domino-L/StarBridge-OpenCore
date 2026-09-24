#include "flutter_window.h"

#include <commdlg.h>
#include <flutter_windows.h>
#include <optional>
#include <vector>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "application_lifecycle_bridge.h"
#include "native_host_bridge.h"
#include "hangar_browser_bridge.h"
#include "overlay_editor_window.h"
#ifdef STARBRIDGE_ENABLE_MENU_OVERLAY
#include "menu_overlay_bridge.h"
#endif
#include "utils.h"

namespace {

constexpr wchar_t kFlutterWindowOwnerProperty[] =
    L"StarBridge.FlutterWindowOwner";

void PickGameLog(
    HWND owner,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!IsWindow(owner)) {
    result->Error("gameplay_log_picker_unavailable",
                  "The application window is unavailable.");
    return;
  }

  std::vector<wchar_t> file_path(32768, L'\0');
  OPENFILENAMEW dialog{};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.lpstrFilter = L"Game.log\0Game.log\0\0";
  dialog.nFilterIndex = 1;
  dialog.lpstrFile = file_path.data();
  dialog.nMaxFile = static_cast<DWORD>(file_path.size());
  dialog.lpstrTitle = L"Select Game.log";
  dialog.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                 OFN_NOCHANGEDIR | OFN_HIDEREADONLY | OFN_DONTADDTORECENT;
  if (!GetOpenFileNameW(&dialog)) {
    const DWORD error = CommDlgExtendedError();
    if (error == 0) {
      result->Success();
    } else {
      result->Error("gameplay_log_picker_failed",
                    "The Game.log file dialog failed.",
                    flutter::EncodableValue(static_cast<int64_t>(error)));
    }
    return;
  }

  const std::string path = Utf8FromUtf16(file_path.data());
  if (path.empty()) {
    result->Error("gameplay_log_picker_failed",
                  "The selected path could not be encoded.");
    return;
  }
  // Selection only: the Native Host validates the Game.log basename and imports.
  result->Success(flutter::EncodableValue(path));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool startup_launch)
    : project_(project), startup_launch_(startup_launch) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
#ifdef STARBRIDGE_ENABLE_MENU_OVERLAY
  menu_overlay_bridge_ = std::make_unique<MenuOverlayBridge>(
      flutter_controller_->engine()->messenger(), GetHandle());
#endif
  overlay_editor_window_ = std::make_unique<OverlayEditorWindow>(GetHandle());
  window_chrome_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "starbridge/window-chrome",
          &flutter::StandardMethodCodec::GetInstance());
  window_chrome_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "enterOverlayEditor" || method == "exitOverlayEditor") {
          const bool success = method == "enterOverlayEditor"
              ? overlay_editor_window_->Enter() : overlay_editor_window_->Exit();
          if (!success) {
            result->Error("overlay_editor_window_failed",
                          "The editor window mode could not be changed.");
            return;
          }
        } else if (method == "beginDrag") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
        } else if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
        } else if (method == "toggleMaximize") {
          ShowWindow(GetHandle(), IsZoomed(GetHandle()) ? SW_RESTORE
                                                        : SW_MAXIMIZE);
        } else if (method == "getIsMaximized") {
          result->Success(flutter::EncodableValue(
              IsZoomed(GetHandle()) != FALSE));
          return;
        } else if (method == "close") {
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });
  gameplay_files_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "starbridge/gameplay_files",
          &flutter::StandardMethodCodec::GetInstance());
  gameplay_files_channel_->SetMethodCallHandler(
      [owner = GetHandle(), dialog_open = std::make_shared<bool>(false)](
          const auto& call, auto result) {
        if (call.method_name() != "pickGameLog") {
          result->NotImplemented();
          return;
        }
        // The native modal loop can dispatch another platform message.
        if (*dialog_open) {
          result->Error("gameplay_log_picker_busy",
                        "The Game.log file dialog is already open.");
          return;
        }
        *dialog_open = true;
        PickGameLog(owner, std::move(result));
        *dialog_open = false;
      });
  native_host_bridge_ = std::make_unique<NativeHostBridge>(
      GetHandle(), flutter_controller_->engine()->messenger());
  application_lifecycle_bridge_ =
      std::make_unique<ApplicationLifecycleBridge>(
          GetHandle(), flutter_controller_->engine()->messenger(),
          startup_launch_);
  flutter_view_handle_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_handle_);
  hangar_browser_bridge_ = std::make_unique<HangarBrowserBridge>(
      flutter_view_handle_, flutter_controller_->engine()->messenger());

  // Flutter's child HWND fills the entire client area. Without forwarding the
  // resize border, real pointer input is hit-tested as HTCLIENT by FLUTTERVIEW
  // and never reaches the resizable top-level window.
  SetProp(flutter_view_handle_, kFlutterWindowOwnerProperty, this);
  SetLastError(ERROR_SUCCESS);
  flutter_view_window_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      flutter_view_handle_, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(&FlutterWindow::FlutterViewWindowProc)));
  if (!flutter_view_window_proc_ && GetLastError() != ERROR_SUCCESS) {
    RemoveProp(flutter_view_handle_, kFlutterWindowOwnerProperty);
    flutter_view_handle_ = nullptr;
    return false;
  }

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    application_lifecycle_bridge_->OnFirstFrameReady();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
#ifdef STARBRIDGE_ENABLE_MENU_OVERLAY
  menu_overlay_bridge_.reset();
#endif
  overlay_editor_window_.reset();
  hangar_browser_bridge_.reset();
  if (application_lifecycle_bridge_) {
    application_lifecycle_bridge_->Shutdown();
    application_lifecycle_bridge_.reset();
  }
  if (native_host_bridge_) {
    native_host_bridge_->Shutdown();
    native_host_bridge_.reset();
  }
  if (flutter_view_handle_) {
    if (flutter_view_window_proc_) {
      SetWindowLongPtr(flutter_view_handle_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(flutter_view_window_proc_));
    }
    RemoveProp(flutter_view_handle_, kFlutterWindowOwnerProperty);
    flutter_view_handle_ = nullptr;
    flutter_view_window_proc_ = nullptr;
  }

  if (gameplay_files_channel_) {
    gameplay_files_channel_->SetMethodCallHandler(nullptr);
    gameplay_files_channel_.reset();
  }
  window_chrome_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (overlay_editor_window_ && overlay_editor_window_->active()) {
    if (message == WM_ACTIVATE) {
      overlay_editor_window_->OnActivate(LOWORD(wparam) != WA_INACTIVE);
    } else if (message == WM_GETMINMAXINFO) {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize = {1, 1};
      return 0;
    } else if (message == WM_DISPLAYCHANGE) {
      overlay_editor_window_->FitMonitor();
    } else if (message == WM_DPICHANGED) {
      const auto result = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      overlay_editor_window_->FitMonitor();
      return result;
    }
  }
  if (message == WM_CLOSE && application_lifecycle_bridge_ &&
      application_lifecycle_bridge_->HandleCloseRequest()) {
    return 0;
  }
  if (application_lifecycle_bridge_ &&
      application_lifecycle_bridge_->HandleWindowMessage(message, wparam,
                                                          lparam)) {
    return 0;
  }
  if (native_host_bridge_ &&
      native_host_bridge_->HandleWindowMessage(message, lparam)) {
    return 0;
  }
  if (message == WM_SIZE && wparam != SIZE_MINIMIZED) {
    NotifyWindowStateChanged();
  }

  if (message == WM_NCCALCSIZE) {
    RECT* client_rect = nullptr;
    if (wparam == TRUE) {
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      client_rect = &params->rgrc[0];
    } else {
      // Initial window creation commonly uses the simple RECT form. Letting it
      // fall through to DefWindowProc reintroduces a 7 px native frame until a
      // later full NCCALCSIZE pass, which appears as a white startup border.
      client_rect = reinterpret_cast<RECT*>(lparam);
    }

    // Own the complete restored frame instead of retaining the native left,
    // right, and bottom borders. Leaving those borders active allows DWM or a
    // window-capture surface to intermittently paint a system-coloured strip
    // above the Flutter content.
    if (client_rect && IsZoomed(hwnd)) {
      MONITORINFO monitor_info{};
      monitor_info.cbSize = sizeof(monitor_info);
      const HMONITOR monitor =
          MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      if (GetMonitorInfo(monitor, &monitor_info)) {
        // A maximized WS_THICKFRAME window extends beyond the monitor bounds.
        // Keep its client content inside the work area so it does not cover
        // the taskbar while the standard frame remains removed.
        *client_rect = monitor_info.rcWork;
      }
    }
    return 0;
  }

  if (message == WM_NCHITTEST) {
    const std::optional<LRESULT> resize_hit = GetResizeHitTest(lparam);
    if (resize_hit) {
      return *resize_hit;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// static
LRESULT CALLBACK FlutterWindow::FlutterViewWindowProc(
    HWND const window, UINT const message, WPARAM const wparam,
    LPARAM const lparam) noexcept {
  auto* owner = reinterpret_cast<FlutterWindow*>(
      GetProp(window, kFlutterWindowOwnerProperty));
  if (!owner || !owner->flutter_view_window_proc_) {
    return DefWindowProc(window, message, wparam, lparam);
  }

  if (message == WM_NCHITTEST && owner->GetResizeHitTest(lparam)) {
    // Ask Windows to continue hit-testing windows underneath this child. The
    // top-level StarBridge window then returns the standard resize direction.
    return HTTRANSPARENT;
  }

  return CallWindowProc(owner->flutter_view_window_proc_, window, message,
                        wparam, lparam);
}

std::optional<LRESULT> FlutterWindow::GetResizeHitTest(
    LPARAM const lparam) noexcept {
  const HWND window = GetHandle();
  if (!window || IsZoomed(window) ||
      (overlay_editor_window_ && overlay_editor_window_->active())) {
    return std::nullopt;
  }

  RECT window_rect;
  if (!GetWindowRect(window, &window_rect)) {
    return std::nullopt;
  }

  const UINT dpi = FlutterDesktopGetDpiForHWND(window);
  const int resize_border_x =
      GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const LONG pointer_x = GET_X_LPARAM(lparam);
  const LONG pointer_y = GET_Y_LPARAM(lparam);
  const bool on_left = pointer_x >= window_rect.left &&
                       pointer_x < window_rect.left + resize_border_x;
  const bool on_right = pointer_x < window_rect.right &&
                        pointer_x >= window_rect.right - resize_border_x;
  const bool on_top = pointer_y >= window_rect.top &&
                      pointer_y < window_rect.top + resize_border_y;
  const bool on_bottom = pointer_y < window_rect.bottom &&
                         pointer_y >= window_rect.bottom - resize_border_y;

  if (on_top && on_left) {
    return HTTOPLEFT;
  }
  if (on_top && on_right) {
    return HTTOPRIGHT;
  }
  if (on_bottom && on_left) {
    return HTBOTTOMLEFT;
  }
  if (on_bottom && on_right) {
    return HTBOTTOMRIGHT;
  }
  if (on_left) {
    return HTLEFT;
  }
  if (on_right) {
    return HTRIGHT;
  }
  if (on_top) {
    return HTTOP;
  }
  if (on_bottom) {
    return HTBOTTOM;
  }
  return std::nullopt;
}

void FlutterWindow::NotifyWindowStateChanged() {
  if (!window_chrome_channel_ || !GetHandle()) {
    return;
  }

  const bool is_maximized = IsZoomed(GetHandle()) != FALSE;
  if (last_is_maximized_.has_value() &&
      last_is_maximized_.value() == is_maximized) {
    return;
  }
  last_is_maximized_ = is_maximized;
  window_chrome_channel_->InvokeMethod(
      "windowStateChanged",
      std::make_unique<flutter::EncodableValue>(is_maximized));
}
