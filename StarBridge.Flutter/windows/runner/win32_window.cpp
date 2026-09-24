#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"
#include "small_application_icon.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr int kMinimumWindowWidth = 900;
constexpr int kMinimumWindowHeight = 620;

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  constexpr DWORD kWindowStyle =
      WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
  HWND window = CreateWindow(
      window_class, title.c_str(), kWindowStyle,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  UpdateTaskbarIcon(dpi);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    // Restart Manager uses session messages, not the user's close-to-tray
    // gesture. Handle these before Flutter/plugins can consume them. A query
    // or a cancelled shutdown must not destroy the window; only the confirmed
    // update shutdown runs normal OnDestroy cleanup and exits the message loop.
    if ((lparam & ENDSESSION_CLOSEAPP) != 0) {
      if (message == WM_QUERYENDSESSION) return TRUE;
      if (message == WM_ENDSESSION) {
        if (wparam != FALSE) DestroyWindow(window);
        return 0;
      }
    }
    // Handle small-icon requests before any plugin can short-circuit them.
    // Queries never WM_SETICON or destroy another consumer's borrowed HICON.
    if (message == WM_GETICON && (wparam == ICON_SMALL || wparam == ICON_SMALL2)) {
      if (const HICON icon = that->TaskbarIconForDpi(lparam)) {
        return reinterpret_cast<LRESULT>(icon);
      }
    }
    // Refresh before plugin dispatch; Flutter still receives theme messages.
    if (IsSmallIconThemeMessage(message)) {
      UpdateTheme(window);
      that->UpdateTaskbarIcon(0);
    } else if (message == WM_DPICHANGED) {
      that->UpdateTaskbarIcon(HIWORD(wparam));
    } else if (message == WM_DISPLAYCHANGE ||
               (message == WM_SIZE && wparam != SIZE_MINIMIZED) ||
               (message == WM_WINDOWPOSCHANGED &&
                MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST) !=
                    that->taskbar_icon_monitor_)) {
      that->UpdateTaskbarIcon(0);
    }
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_GETMINMAXINFO: {
      const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
      const double scale = dpi / 96.0;
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      // NCCALCSIZE removes the native frame. Its usual maximized overscan
      // must be removed from the OUTER bounds as well, or the invisible
      // window/frame can occupy the taskbar despite rcWork-clipped content.
      MONITORINFO monitor_info{};
      monitor_info.cbSize = sizeof(monitor_info);
      if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                         &monitor_info)) {
        const RECT& work = monitor_info.rcWork;
        const RECT& monitor = monitor_info.rcMonitor;
        info->ptMaxPosition.x = work.left - monitor.left;
        info->ptMaxPosition.y = work.top - monitor.top;
        info->ptMaxSize.x = work.right - work.left;
        info->ptMaxSize.y = work.bottom - work.top;
      }
      // Leave ptMaxTrackSize alone: restored resizing and Snap stay native.
      info->ptMinTrackSize.x =
          static_cast<LONG>(kMinimumWindowWidth * scale);
      info->ptMinTrackSize.y =
          static_cast<LONG>(kMinimumWindowHeight * scale);
      return 0;
    }

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      // Deactivation belongs to the new foreground window (including the tray
      // surface). Refocusing our child here can activate the main window again.
      if (LOWORD(wparam) != WA_INACTIVE && child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  ReleaseTaskbarIcon();
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  const COLORREF border_color = DWMWA_COLOR_NONE;
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                        sizeof(border_color));

  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}

UINT Win32Window::TaskbarIconDpi(LPARAM requested) const noexcept {
  if (IsSmallIconDpi(requested)) return static_cast<UINT>(requested);
  // MonitorFromWindow uses the pre-minimize rectangle. Prefer a current Shell
  // window on that monitor, since our minimized HWND may retain its old DPI.
  const HMONITOR monitor = MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  const auto shell_dpi = [monitor](HWND shell) -> UINT {
    return shell && MonitorFromWindow(shell, MONITOR_DEFAULTTONEAREST) == monitor
        ? GetDpiForWindow(shell) : 0;
  };
  UINT dpi = shell_dpi(FindWindowW(L"Shell_TrayWnd", nullptr));
  if (!IsSmallIconDpi(dpi)) {
    HWND shell = nullptr;
    while ((shell = FindWindowExW(nullptr, shell, L"Shell_SecondaryTrayWnd", nullptr))) {
      dpi = shell_dpi(shell);
      if (IsSmallIconDpi(dpi)) break;
    }
  }
  if (IsSmallIconDpi(dpi)) return dpi;
  return ResolveSmallIconDpi(0, 0,
      monitor ? FlutterDesktopGetDpiForMonitor(monitor) : 0,
      window_handle_ ? GetDpiForWindow(window_handle_) : 0);
}

HICON Win32Window::TaskbarIconForDpi(LPARAM requested) noexcept {
  return taskbar_icons_.Get(TaskbarIconDpi(requested), SmallIconUsesDarkForeground());
}

void Win32Window::UpdateTaskbarIcon(UINT dpi) {
  if (window_handle_ == nullptr) {
    return;
  }

  auto next_icon = TaskbarIconForDpi(dpi);
  taskbar_icon_monitor_ = MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  if (next_icon == nullptr || next_icon == taskbar_icon_) {
    return;
  }

  taskbar_icon_ = next_icon;
  SendMessageW(window_handle_, WM_SETICON, ICON_SMALL,
               reinterpret_cast<LPARAM>(taskbar_icon_));
}

void Win32Window::ReleaseTaskbarIcon() {
  taskbar_icon_ = nullptr;
  taskbar_icon_monitor_ = nullptr;
  taskbar_icons_.Clear();
}
