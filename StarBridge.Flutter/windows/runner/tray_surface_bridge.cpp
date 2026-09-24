#include "tray_surface_bridge.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <algorithm>
#include <atomic>
#include <optional>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;
using Channel = flutter::MethodChannel<Value>;
constexpr wchar_t kClass[] = L"StarBridge.Flutter.TraySurface.v1";
constexpr UINT kFrameReady = WM_APP + 0x71;
constexpr UINT_PTR kReadyTimeout = 0x5343;
const Value* Field(const Map& map, const char* name) {
  const auto found = map.find(Value(name));
  return found == map.end() ? nullptr : &found->second;
}
}

class TraySurfaceBridge::Impl {
 public:
  Impl(HWND owner, flutter::BinaryMessenger* messenger, std::function<void()> open,
       std::function<void()> exit, std::function<void()> fallback)
      : owner_(owner), open_(std::move(open)), exit_(std::move(exit)),
        fallback_(std::move(fallback)), alive_(std::make_shared<std::atomic_bool>(true)),
        primary_(messenger, "starbridge/tray-primary", &flutter::StandardMethodCodec::GetInstance()) {
    primary_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "configure") {
        const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* schema = map && Field(*map, "schemaVersion")
            ? std::get_if<int32_t>(Field(*map, "schemaVersion")) : nullptr;
        if (!schema || *schema != 1) {
          result->Error("tray.invalid_snapshot", "Invalid tray snapshot."); return;
        }
        snapshot_ = *map;
        configured_ = true;
        Update();
        result->Success();
      } else if (call.method_name() == "detach") {
        configured_ = false; snapshot_.clear(); Hide(); result->Success();
      } else { result->NotImplemented(); }
    });
  }
  ~Impl() {
    *alive_ = false;
    primary_.SetMethodCallHandler(nullptr);
    if (secondary_) secondary_->SetMethodCallHandler(nullptr);
    if (window_) KillTimer(window_, kReadyTimeout);
    secondary_.reset();
    controller_.reset();
    if (window_) { SetWindowLongPtrW(window_, GWLP_USERDATA, 0); DestroyWindow(window_); }
  }
  bool Show(POINT anchor, bool keyboard) {
    if (!configured_) return false;
    if (window_ && IsWindowVisible(window_)) { Hide(); return true; }
    // Recheck facts on opening as well as the shared background watch. This is
    // a state check: it does not activate the main window or replay open/close.
    primary_.InvokeMethod("refresh", nullptr);
    anchor_ = anchor; keyboard_ = keyboard; ++opening_; frame_ready_ = false;
    if (!window_ && !Create()) return false;
    wanted_ = true;
    Position();
    Update();
    SetTimer(window_, kReadyTimeout, 4000, nullptr);
    return true;
  }
  void Hide() {
    wanted_ = false;
    if (window_) { KillTimer(window_, kReadyTimeout); ShowWindow(window_, SW_HIDE); }
  }
 private:
  bool Create() {
    WNDCLASSW wc{};
    wc.lpfnWndProc = WndProc; wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClass; wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc); // Repeated registration is harmless in one process.
    window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClass, L"星海舰桥",
        // Like the WPF quick panel, this is an independent tool window. An
        // owned popup can raise its owner when activated from the shell tray.
        WS_POPUP, 0, 0, 336, 552, nullptr, nullptr, wc.hInstance, this);
    if (!window_) return false;
    const DWORD rounded = 2;
    DwmSetWindowAttribute(window_, 33, &rounded, sizeof(rounded));
    flutter::DartProject project(L"data");
    project.set_dart_entrypoint("trayMain");
    controller_ = std::make_unique<flutter::FlutterViewController>(336, 552, project);
    if (!controller_->engine() || !controller_->view()) {
      controller_.reset(); DestroyWindow(window_); window_ = nullptr; return false;
    }
    HWND child = controller_->view()->GetNativeWindow();
    SetParent(child, window_);
    SetWindowLongPtrW(child, GWL_STYLE, GetWindowLongPtrW(child, GWL_STYLE) | WS_CHILD);
    // SetParent does not lay out Flutter's initially off-screen child. Position
    // may keep the same 336x552 size, so no subsequent WM_SIZE is guaranteed.
    RECT client{};
    GetClientRect(window_, &client);
    MoveWindow(child, 0, 0, client.right, client.bottom, TRUE);
    ShowWindow(child, SW_SHOW);
    secondary_ = std::make_unique<Channel>(controller_->engine()->messenger(),
        "starbridge/tray-surface", &flutter::StandardMethodCodec::GetInstance());
    secondary_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") {
        dart_ready_ = true; result->Success(Value(Snapshot()));
      } else if (call.method_name() == "layout") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* opening = args && Field(*args, "opening")
            ? std::get_if<int32_t>(Field(*args, "opening")) : nullptr;
        const auto* height = args && Field(*args, "height")
            ? std::get_if<int32_t>(Field(*args, "height")) : nullptr;
        if (!opening || !height || *height <= 0 || *height > 4096) {
          result->Error("tray.invalid_layout", "Invalid tray layout."); return;
        }
        if (*opening == opening_ && wanted_ && content_height_ != *height) {
          content_height_ = *height;
          Position();
        }
        result->Success();
      } else if (call.method_name() == "painted") {
        const auto* opening = call.arguments() ? std::get_if<int32_t>(call.arguments()) : nullptr;
        if (opening && *opening == opening_ && wanted_) {
          const auto life = alive_; const auto window = window_; const auto token = opening_;
          controller_->engine()->SetNextFrameCallback([life, window, token]() {
            if (*life) PostMessageW(window, kFrameReady, static_cast<WPARAM>(token), 0);
          });
          controller_->ForceRedraw();
        }
        result->Success();
      } else if (call.method_name() == "dismiss") {
        Hide(); result->Success();
      } else if (call.method_name() == "action") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        const auto* command = args && Field(*args,"action") ? std::get_if<std::string>(Field(*args,"action")) : nullptr;
        if (!configured_ || !wanted_ || !command || busy_) {
          result->Error("tray.unavailable", "Tray action unavailable."); return;
        }
        if (*command == "open") { Hide(); result->Success(); open_(); return; }
        if (*command == "exit") { Hide(); result->Success(); exit_(); return; }
        if (*command != "overlaySettings" && *command != "toggleOverlay" && *command != "presence") {
          result->Error("tray.invalid_action", "Unknown tray action."); return;
        }
        busy_ = true;
        const auto life = alive_;
        const bool close_after = *command == "overlaySettings";
        auto pending = std::shared_ptr<Result>(std::move(result));
        primary_.InvokeMethod("action", std::make_unique<Value>(*args),
          std::make_unique<flutter::MethodResultFunctions<Value>>(
            [this, life, pending, close_after](const Value* value) {
              if (!*life) return;
              busy_ = false;
              if (close_after) { Hide(); open_(); }
              pending->Success(value ? *value : Value());
            },
            [this, life, pending](const std::string& code, const std::string&, const Value*) {
              if (!*life) return;
              busy_ = false; pending->Error(code, "Tray action failed.");
            },
            [this, life, pending]() {
              if (!*life) return;
              busy_ = false; pending->Error("tray.unavailable", "Tray action unavailable.");
            }));
      } else { result->NotImplemented(); }
    });
    return true;
  }
  Map Snapshot() const {
    auto value = snapshot_;
    value[Value("opening")] = Value(opening_);
    value[Value("keyboard")] = Value(keyboard_);
    return value;
  }
  void Update() {
    if (secondary_ && dart_ready_) secondary_->InvokeMethod("snapshot", std::make_unique<Value>(Snapshot()));
  }
  void Reveal() {
    if (!wanted_ || !configured_) return;
    KillTimer(window_, kReadyTimeout);
    ShowWindow(window_, SW_SHOW); SetForegroundWindow(window_);
    if (controller_) SetFocus(controller_->view()->GetNativeWindow());
  }
  void Position() {
    MONITORINFO monitor{sizeof(monitor)};
    if (!GetMonitorInfoW(MonitorFromPoint(anchor_, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    UINT dpi = GetDpiForWindow(window_); if (!dpi) dpi = 96;
    const LONG width = std::min<LONG>(MulDiv(336, dpi, 96), monitor.rcWork.right-monitor.rcWork.left);
    const LONG height = std::min<LONG>(MulDiv(content_height_, dpi, 96), monitor.rcWork.bottom-monitor.rcWork.top);
    const LONG x = std::clamp<LONG>(anchor_.x-width,monitor.rcWork.left,monitor.rcWork.right-width);
    const LONG y = std::clamp<LONG>(anchor_.y-height,monitor.rcWork.top,monitor.rcWork.bottom-height);
    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
  }
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<Impl*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(window,message,wparam,lparam);
    if (message == WM_CLOSE) { self->Hide(); return 0; }
    if (message == WM_ACTIVATE && LOWORD(wparam)==WA_INACTIVE) { self->Hide(); return 0; }
    if (message == kFrameReady) {
      if (wparam == static_cast<WPARAM>(self->opening_)) {
        self->frame_ready_=true; if(self->dart_ready_) self->Reveal();
      }
      return 0;
    }
    if (message == WM_TIMER && wparam == kReadyTimeout) {
      self->Hide(); self->fallback_(); return 0;
    }
    if (message == WM_DPICHANGED) { self->Position(); return 0; }
    if (message == WM_SIZE && self->controller_) {
      RECT rect{}; GetClientRect(window,&rect);
      MoveWindow(self->controller_->view()->GetNativeWindow(),0,0,rect.right,rect.bottom,TRUE);
    }
    if (self->controller_) {
      auto handled=self->controller_->HandleTopLevelWindowProc(window,message,wparam,lparam);
      if(handled) return *handled;
    }
    return DefWindowProcW(window,message,wparam,lparam);
  }
  HWND owner_, window_ = nullptr;
  POINT anchor_{};
  bool configured_=false, wanted_=false, keyboard_=false, frame_ready_=false, dart_ready_=false, busy_=false;
  int opening_=0;
  int content_height_=552;
  Map snapshot_;
  std::function<void()> open_, exit_, fallback_;
  std::shared_ptr<std::atomic_bool> alive_;
  Channel primary_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<Channel> secondary_;
};

TraySurfaceBridge::TraySurfaceBridge(HWND owner, flutter::BinaryMessenger* messenger,
    std::function<void()> open, std::function<void()> exit, std::function<void()> fallback)
    : impl_(std::make_unique<Impl>(owner,messenger,std::move(open),std::move(exit),std::move(fallback))) {}
TraySurfaceBridge::~TraySurfaceBridge()=default;
bool TraySurfaceBridge::Show(POINT anchor,bool keyboard) { return impl_->Show(anchor,keyboard); }
void TraySurfaceBridge::Hide() { impl_->Hide(); }
