#include "friends_window_bridge.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <windowsx.h>
#include <algorithm>
#include <atomic>

#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Channel = flutter::MethodChannel<Value>;
using Result = flutter::MethodResult<Value>;
#ifdef STARBRIDGE_FRIENDS_TEST
constexpr wchar_t kClass[] = L"StarBridge.Flutter.Friends.Fixture";
#else
constexpr wchar_t kClass[] = L"StarBridge.Flutter.Friends.v1";
#endif
constexpr wchar_t kChildOwner[] = L"StarBridge.Friends.ChromeOwner";
constexpr UINT kFrameReady = WM_APP + 0x73;
constexpr UINT kViewportChanged = WM_APP + 0x74;
constexpr UINT_PTR kReadyTimeout = 0x5346;
const Value* Field(const Map& map, const char* name) {
  const auto it = map.find(Value(name));
  return it == map.end() ? nullptr : &it->second;
}
int Number(const Map& map, const char* name) {
  const auto* value = Field(map, name);
  const auto* number = value ? std::get_if<int32_t>(value) : nullptr;
  return number ? *number : -1;
}
}

class FriendsWindowBridge::Impl {
 public:
  Impl(HWND owner, flutter::BinaryMessenger* messenger, std::wstring data_path, std::string kind)
      : owner_(owner), data_path_(std::move(data_path)), kind_(std::move(kind)), alive_(std::make_shared<std::atomic_bool>(true)),
        primary_(messenger, "starbridge/" + kind_ + "-primary", &flutter::StandardMethodCodec::GetInstance()) {
    primary_.SetMethodCallHandler([this](const auto& call, auto result) {
#ifdef STARBRIDGE_FRIENDS_TEST
      if (call.method_name() == "fixtureStatus") {
        result->Success(Value(Map{{Value("dartReady"), Value(dart_ready_)}})); return;
      }
#endif
      if (call.method_name() == "detach") {
        Hide(); snapshot_.clear(); result->Success(); return;
      }
      if (call.method_name() != "show" && call.method_name() != "snapshot") {
        result->NotImplemented(); return;
      }
      const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const auto* view = map && Field(*map, "view") ? std::get_if<std::string>(Field(*map, "view")) : nullptr;
      if (!map || !view || view->size() > 1048576 || Number(*map, "opening") < 1 ||
          Number(*map, "revision") < 0) {
        result->Error("friends.invalid_snapshot", "Invalid friends snapshot."); return;
      }
      if (call.method_name() == "show") {
        const bool reopening = !wanted_;
        snapshot_ = *map;
        if (!window_ && !Create()) { result->Success(Value(false)); return; }
        if (reopening) painted_opening_ = -1;
        show_result_ = std::move(result);
        SetTimer(window_, kReadyTimeout, 8000, nullptr);
        wanted_ = true; Update(); Reveal();
      } else {
        if (Number(*map, "opening") == Number(snapshot_, "opening") &&
            Number(*map, "revision") >= Number(snapshot_, "revision")) {
          snapshot_ = *map; Update();
        }
        result->Success();
      }
    });
  }
  ~Impl() {
    *alive_ = false;
    if (show_result_) show_result_->Success(Value(false));
    if (window_) KillTimer(window_, kReadyTimeout);
    primary_.SetMethodCallHandler(nullptr);
    if (secondary_) secondary_->SetMethodCallHandler(nullptr);
    if (controller_ && controller_->view() && child_proc_) {
      const HWND child = controller_->view()->GetNativeWindow();
      SetWindowLongPtrW(child, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(child_proc_));
      RemovePropW(child, kChildOwner);
    }
    secondary_.reset(); controller_.reset();
    if (window_) {
      SetWindowLongPtrW(window_, GWLP_USERDATA, 0); DestroyWindow(window_);
    }
  }
 private:
  bool Create() {
    WNDCLASSEXW cls{sizeof(cls)};
    cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpfnWndProc = WndProc; cls.lpszClassName = kClass;
    cls.hCursor = LoadCursor(nullptr, IDC_ARROW);
    cls.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    RegisterClassExW(&cls);
    // Unowned and not topmost: minimizing the main window or changing focus
    // must not hide friends. WM_CLOSE hides; primary shutdown destroys.
    const wchar_t* title = kind_ == "messages" ? L"聊天 · 星海舰桥" : kind_ == "notifications" ? L"通知 · 星海舰桥" : L"好友 · 星海舰桥";
    const int width = kind_ == "messages" ? 920 : kind_ == "notifications" ? 560 : 408;
    window_ = CreateWindowExW(WS_EX_APPWINDOW, kClass, title,
        WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_DISABLED,
        CW_USEDEFAULT, CW_USEDEFAULT, width, 700,
        nullptr, nullptr, cls.hInstance, this);
    if (!window_) return false;
    BOOL dark = TRUE;
    DwmSetWindowAttribute(window_, 20, &dark, sizeof(dark));
    const COLORREF border_color = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(window_, DWMWA_BORDER_COLOR, &border_color,
                          sizeof(border_color));
    SendMessageW(window_, WM_SETICON, ICON_SMALL, SendMessageW(owner_, WM_GETICON, ICON_SMALL, 0));
    flutter::DartProject project(data_path_);
    project.set_dart_entrypoint(kind_ + "Main");
    controller_ = std::make_unique<flutter::FlutterViewController>(width, 660, project);
    if (!controller_->engine() || !controller_->view()) {
      controller_.reset(); SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
      DestroyWindow(window_); window_ = nullptr; return false;
    }
    const HWND child = controller_->view()->GetNativeWindow();
    SetParent(child, window_);
    SetWindowLongPtrW(child, GWL_STYLE, GetWindowLongPtrW(child, GWL_STYLE) | WS_CHILD);
    SetPropW(child, kChildOwner, this);
    child_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
        child, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ChildProc)));
    // Preparing a hidden auxiliary engine must not activate its parent. Only
    // Reveal, after an explicit show and a rendered snapshot, may take focus.
    Resize(); ShowWindow(child, SW_SHOWNOACTIVATE);
    secondary_ = std::make_unique<Channel>(controller_->engine()->messenger(),
        "starbridge/" + kind_ + "-surface", &flutter::StandardMethodCodec::GetInstance());
    secondary_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") {
        dart_ready_ = true; result->Success(Value(snapshot_)); WindowState(); Reveal(); return;
      }
      if (call.method_name() == "windowControl") {
        const auto* command = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
        if (!wanted_ || !command) { result->Success(); return; }
        if (*command == "close") Hide();
        else if (*command == "minimize") ShowWindow(window_, SW_MINIMIZE);
        else if (*command == "toggleMaximize") ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
        else { result->NotImplemented(); return; }
        result->Success(); return;
      }
      const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (call.method_name() == "rpc" && kind_ != "friends") {
        if (!wanted_ || !map || Number(*map, "opening") != Number(snapshot_, "opening")) {
          result->Error("window.closed", "Window is not current."); return;
        }
        const auto* op = Field(*map, "op") ? std::get_if<std::string>(Field(*map, "op")) : nullptr;
        if (op && (*op == "navigate" || *op == "openInvite" || *op == "sendInvite" || *op == "profile")) {
          ShowWindow(owner_, IsIconic(owner_) ? SW_RESTORE : SW_SHOW);
          SetForegroundWindow(owner_);
        }
        if (op && *op == "markRead" &&
            (IsIconic(window_) || !IsWindowVisible(window_) || GetForegroundWindow() != window_)) {
          result->Error("window.inactive", "Read viewport is not active."); return;
        }
        auto completion = std::shared_ptr<Result>(std::move(result));
        const auto alive = alive_;
        primary_.InvokeMethod("rpc", std::make_unique<Value>(*map),
            std::make_unique<flutter::MethodResultFunctions<Value>>(
              [alive, completion](const Value* value) { if (*alive) completion->Success(value ? *value : Value()); },
              [alive, completion](const std::string& code, const std::string&, const Value*) {
                if (*alive) completion->Error(code, "Window request failed.");
              },
              [alive, completion]() { if (*alive) completion->NotImplemented(); }));
        return;
      }
      if (call.method_name() == "painted") {
        if (map && Number(*map, "opening") == Number(snapshot_, "opening")) {
          dart_ready_ = true;
          if (wanted_) { painted_opening_ = Number(*map, "opening"); Reveal(); }
        }
        result->Success(); return;
      }
      if (call.method_name() != "action" || !wanted_ || !map ||
          Number(*map, "opening") != Number(snapshot_, "opening") ||
          Number(*map, "revision") != Number(snapshot_, "revision")) {
        result->Success(Value(false)); return;
      }
      const auto* action = Field(*map, "action") ? std::get_if<std::string>(Field(*map, "action")) : nullptr;
      if (action && (*action == "chat" || *action == "profile" || *action == "messages")) {
        ShowWindow(owner_, IsIconic(owner_) ? SW_RESTORE : SW_SHOW);
        SetForegroundWindow(owner_);
      }
      auto completion = std::shared_ptr<Result>(std::move(result));
      const auto alive = alive_;
      primary_.InvokeMethod("action", std::make_unique<Value>(*map),
          std::make_unique<flutter::MethodResultFunctions<Value>>(
            [alive, completion](const Value* value) {
              if (*alive) completion->Success(value ? *value : Value(false));
            },
            [alive, completion](const std::string&, const std::string&, const Value*) {
              if (*alive) completion->Success(Value(false));
            },
            [alive, completion]() { if (*alive) completion->Success(Value(false)); }));
    });
    const HWND window = window_; const auto alive = alive_;
    controller_->engine()->SetNextFrameCallback([alive, window]() {
      if (*alive) PostMessageW(window, kFrameReady, 0, 0);
    });
    controller_->ForceRedraw(); return true;
  }
  void Resize() {
    if (!controller_) return;
    RECT rect{}; GetClientRect(window_, &rect);
    MoveWindow(controller_->view()->GetNativeWindow(), 0, 0, rect.right, rect.bottom, TRUE);
  }
  void WindowState(bool inactive = false) {
    const bool active = !inactive && wanted_ && IsWindowVisible(window_) && !IsIconic(window_) && GetForegroundWindow() == window_;
    if (secondary_) secondary_->InvokeMethod("windowState",
        std::make_unique<Value>(IsZoomed(window_) != FALSE));
    if (secondary_) secondary_->InvokeMethod("viewportActive", std::make_unique<Value>(
        active));
    if (kind_ != "friends") primary_.InvokeMethod("viewportActive", std::make_unique<Value>(Map{
      {Value("opening"), Value(Number(snapshot_, "opening"))}, {Value("active"), Value(active)}}));
  }
  LRESULT HitTest(HWND window, LPARAM point) const {
    RECT rect{}; GetWindowRect(window, &rect);
    const int x = GET_X_LPARAM(point), y = GET_Y_LPARAM(point);
    if (x < rect.left || x >= rect.right || y < rect.top || y >= rect.bottom) return HTCLIENT;
    UINT dpi = GetDpiForWindow(window); if (!dpi) dpi = 96;
    if (!IsZoomed(window)) {
      const int border = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
      const bool left = x < rect.left + border, right = x >= rect.right - border;
      const bool top = y < rect.top + border, bottom = y >= rect.bottom - border;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
    }
    // Keep this geometry paired with the 34-high header and three 44-wide
    // Flutter buttons. Native caption handling preserves drag, Snap and double-click.
    if (y < rect.top + MulDiv(34, dpi, 96) &&
        x < rect.right - MulDiv(132, dpi, 96)) return HTCAPTION;
    return HTCLIENT;
  }
  static LRESULT CALLBACK ChildProc(HWND child, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<Impl*>(GetPropW(child, kChildOwner));
    if (!self || !self->child_proc_) return DefWindowProcW(child, message, wparam, lparam);
    if (message == WM_NCHITTEST && self->HitTest(self->window_, lparam) != HTCLIENT) return HTTRANSPARENT;
    return CallWindowProcW(self->child_proc_, child, message, wparam, lparam);
  }
  void Reveal() {
    if (!wanted_ || !dart_ready_ || !frame_ready_ ||
        painted_opening_ != Number(snapshot_, "opening") || !show_result_) return;
    KillTimer(window_, kReadyTimeout);
    RECT rect{}; GetWindowRect(window_, &rect);
    MONITORINFO monitor{sizeof(monitor)};
    if (!IsZoomed(window_) && !IsIconic(window_) &&
        GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor)) {
      const LONG width = std::min(rect.right - rect.left, monitor.rcWork.right - monitor.rcWork.left);
      const LONG height = std::min(rect.bottom - rect.top, monitor.rcWork.bottom - monitor.rcWork.top);
      SetWindowPos(window_, nullptr,
          std::clamp(rect.left, monitor.rcWork.left, monitor.rcWork.right - width),
          std::clamp(rect.top, monitor.rcWork.top, monitor.rcWork.bottom - height),
          width, height, SWP_NOACTIVATE | SWP_NOZORDER);
    }
    EnableWindow(window_, TRUE);
    ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(window_); SetFocus(controller_->view()->GetNativeWindow());
    WindowState();
    show_result_->Success(Value(true)); show_result_.reset();
  }
  void Update() {
    // Native creation can finish after Dart's first ready request. Push the
    // snapshot as well: Flutter buffers it until the presentation handler is
    // registered, and the painted acknowledgement proves readiness either way.
    if (secondary_) secondary_->InvokeMethod("snapshot", std::make_unique<Value>(snapshot_));
  }
  void Hide() {
    wanted_ = false;
    if (window_) KillTimer(window_, kReadyTimeout);
    if (show_result_) { show_result_->Success(Value(false)); show_result_.reset(); }
    if (window_) {
      ShowWindow(window_, SW_HIDE);
      EnableWindow(window_, FALSE);
    }
    primary_.InvokeMethod("hidden", std::make_unique<Value>(Map{
      {Value("opening"), Value(Number(snapshot_, "opening"))}}));
    WindowState();
  }
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<Impl*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(window, message, wparam, lparam);
    if (message == WM_NCCALCSIZE) {
      auto* rect = wparam ? &reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0]
                          : reinterpret_cast<RECT*>(lparam);
      MONITORINFO monitor{sizeof(monitor)};
      if (rect && IsZoomed(window) && GetMonitorInfoW(
          MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) *rect = monitor.rcWork;
      return 0;
    }
    if (message == WM_NCACTIVATE) {
      // The Flutter surface owns the complete frame; suppress the system's
      // transient activation border, as on the primary window.
      return TRUE;
    }
    if (message == WM_NCHITTEST) return self->HitTest(window, lparam);
    if (message == WM_CLOSE) { self->Hide(); return 0; }
    if (message == WM_TIMER && wparam == kReadyTimeout) {
      if (self->show_result_) self->Hide();
      return 0;
    }
    if (message == kFrameReady) { self->frame_ready_ = true; self->Reveal(); return 0; }
    if (message == WM_GETMINMAXINFO) {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      UINT dpi = GetDpiForWindow(window); if (!dpi) dpi = 96;
      info->ptMinTrackSize = {MulDiv(self->kind_ == "messages" ? 600 : 360, dpi, 96), MulDiv(420, dpi, 96)};
      MONITORINFO monitor{sizeof(monitor)};
      if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
        info->ptMaxPosition = {monitor.rcWork.left - monitor.rcMonitor.left,
                              monitor.rcWork.top - monitor.rcMonitor.top};
        info->ptMaxSize = {monitor.rcWork.right - monitor.rcWork.left,
                          monitor.rcWork.bottom - monitor.rcWork.top};
      }
      return 0;
    }
    if (message == WM_DPICHANGED) {
      const auto* rect = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, rect->left, rect->top,
          rect->right-rect->left, rect->bottom-rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
    }
    if (message == WM_SIZE) {
      if (wparam != SIZE_MINIMIZED) self->Resize();
      self->WindowState();
    }
    if (message == WM_ACTIVATE) {
      self->WindowState(LOWORD(wparam) == WA_INACTIVE);
      if (LOWORD(wparam) != WA_INACTIVE) PostMessageW(window, kViewportChanged, 0, 0);
    }
    if (message == kViewportChanged) { self->WindowState(); return 0; }
    if (message == WM_SETFOCUS && self->controller_ && self->wanted_ && IsWindowVisible(window)) {
      SetFocus(self->controller_->view()->GetNativeWindow());
    }
    if (self->controller_) {
      const auto handled = self->controller_->HandleTopLevelWindowProc(window, message, wparam, lparam);
      if (handled) return *handled;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
  HWND owner_, window_ = nullptr;
  std::wstring data_path_;
  std::string kind_;
  bool wanted_ = false, dart_ready_ = false, frame_ready_ = false;
  int painted_opening_ = -1;
  std::unique_ptr<Result> show_result_;
  Map snapshot_;
  std::shared_ptr<std::atomic_bool> alive_;
  Channel primary_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> secondary_;
  WNDPROC child_proc_ = nullptr;
};

FriendsWindowBridge::FriendsWindowBridge(HWND owner, flutter::BinaryMessenger* messenger, std::wstring data_path, std::string kind)
    : impl_(std::make_unique<Impl>(owner, messenger, std::move(data_path), std::move(kind))) {}
FriendsWindowBridge::~FriendsWindowBridge() = default;
